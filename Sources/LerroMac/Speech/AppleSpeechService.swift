import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import OSLog
import Speech
import LerroCore

@available(macOS 26.0, *)
public actor AppleSpeechService: SpeechTranscribing {
    static let quickDictateSilenceDuration: Duration = .milliseconds(1_200)

    private static let logger = Logger(
        subsystem: "app.lerro.mac",
        category: "audio-cleanup"
    )
    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var speechDetector: SpeechDetector?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var eventContinuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var tapInstalled = false
    private var transcriptLedger = TranscriptLedger()
    private var endpointTracker = SpeechEndpointTracker()
    private var endpointEventsEnabled = false
    private var localeIdentifier = "zh_CN"
    private var startedAt: ContinuousClock.Instant?
    private var outputMuteSnapshot: CoreAudioHardware.OutputMuteSnapshot?
    private var audioFileWriter: AudioFileWriter?
    private var audioConverter: AudioBufferConverter?
    private var audioRelativePath: String?
    private var sessionGeneration: UUID?
    private let applicationPaths: ApplicationPaths

    public init(applicationPaths: ApplicationPaths = .live()) {
        self.applicationPaths = applicationPaths
    }

    public func availableInputDevices() async -> [AudioInputDevice] {
        CoreAudioHardware.inputDevices()
    }

    public func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        muteOtherAudio: Bool,
        saveAudio: Bool,
        detectSpeechEndpoint: Bool
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error> {
        await cancel()
        let generation = UUID()
        sessionGeneration = generation

        guard SpeechTranscriber.isAvailable else {
            sessionGeneration = nil
            throw LerroError.speechUnavailable("SpeechTranscriber 在当前系统上不可用")
        }

        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            if sessionGeneration == generation { sessionGeneration = nil }
            throw LerroError.speechUnavailable("不支持语言 \(localeIdentifier)")
        }
        try requireCurrent(generation)

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            _ = try? await AssetInventory.reserve(locale: locale)
        case .supported, .downloading:
            sessionGeneration = nil
            throw LerroError.speechUnavailable("请先在引导或设置中准备语音资源")
        case .unsupported:
            sessionGeneration = nil
            throw LerroError.speechUnavailable("语言资源不受支持")
        @unknown default:
            sessionGeneration = nil
            throw LerroError.speechUnavailable("语言资源状态未知")
        }
        try requireCurrent(generation)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        try selectInputDevice(uid: microphoneDeviceUID, inputNode: inputNode)
        let naturalFormat = inputNode.outputFormat(forBus: 0)
        guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
            throw LerroError.speechUnavailable("没有可用的麦克风输入格式")
        }

        // Apple's VAD gates transcription while installed, so keep it scoped
        // to Quick Dictate sessions that explicitly request endpoint events.
        let speechDetector: SpeechDetector? = detectSpeechEndpoint
            ? SpeechDetector(
                detectionOptions: .init(sensitivityLevel: .medium),
                reportResults: true
            )
            : nil
        var modules: [any SpeechModule] = [transcriber]
        if let speechDetector {
            modules.append(speechDetector)
        }
        guard let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: naturalFormat
        ) else {
            throw LerroError.speechUnavailable("无法协商音频格式")
        }
        try requireCurrent(generation)

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        try await analyzer.prepareToAnalyze(in: analysisFormat)
        try requireCurrent(generation)

        // Audio never drops silently. A bounded queue gives a clear failure if
        // the analyzer cannot keep pace instead of producing a partial transcript.
        let inputPair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(192))
        // UI levels are naturally coalesced by the MainActor. Keep the event
        // stream lossless so partial/final transcript events always arrive.
        let eventPair = AsyncThrowingStream<SpeechEvent, any Error>.makeStream()
        let converter: AudioBufferConverter?
        if formatsMatch(naturalFormat, analysisFormat) {
            converter = nil
        } else {
            guard let preparedConverter = AudioBufferConverter(
                inputFormat: naturalFormat,
                outputFormat: analysisFormat
            ) else {
                sessionGeneration = nil
                throw LerroError.speechUnavailable("无法创建音频格式转换器")
            }
            converter = preparedConverter
        }
        let recording: (writer: AudioFileWriter, relativePath: String)?
        if saveAudio {
            recording = try makeRecordingWriter(format: naturalFormat)
        } else {
            recording = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: naturalFormat) { buffer, _ in
            recording?.writer.write(buffer)
            let converted: AVAudioPCMBuffer
            if let converter {
                guard let output = converter.convert(buffer) else {
                    inputPair.continuation.finish()
                    eventPair.continuation.finish(
                        throwing: LerroError.speechUnavailable("音频格式转换失败")
                    )
                    return
                }
                converted = output
            } else {
                // AVAudioEngine owns the tap buffer only for this callback.
                // SpeechAnalyzer consumes it asynchronously, so pass a copy.
                guard let copied = copyPCMBuffer(buffer) else {
                    inputPair.continuation.finish()
                    eventPair.continuation.finish(
                        throwing: LerroError.speechUnavailable("无法复制麦克风音频")
                    )
                    return
                }
                converted = copied
            }
            if case .dropped = inputPair.continuation.yield(AnalyzerInput(buffer: converted)) {
                inputPair.continuation.finish()
                eventPair.continuation.finish(
                    throwing: LerroError.speechUnavailable("语音处理速度不足，请缩短本次录音后重试")
                )
                return
            }
            eventPair.continuation.yield(.audioLevel(normalizedAudioLevel(buffer)))
        }

        engine.prepare()
        if muteOtherAudio {
            outputMuteSnapshot = CoreAudioHardware.muteDefaultOutput()
        }
        do {
            try engine.start()
        } catch {
            restoreOutputAudioIfNeeded()
            inputNode.removeTap(onBus: 0)
            if let path = recording?.relativePath { deleteRecording(relativePath: path) }
            throw error
        }

        self.audioEngine = engine
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.speechDetector = speechDetector
        self.inputContinuation = inputPair.continuation
        self.eventContinuation = eventPair.continuation
        self.tapInstalled = true
        self.audioFileWriter = recording?.writer
        self.audioConverter = converter
        self.audioRelativePath = recording?.relativePath
        self.sessionGeneration = generation
        self.transcriptLedger = TranscriptLedger()
        self.endpointTracker.reset()
        self.endpointEventsEnabled = speechDetector != nil
        self.localeIdentifier = locale.identifier
        self.startedAt = .now

        self.analysisTask = Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: inputPair.stream)
            } catch {
                await self?.finishWithError(error, generation: generation)
            }
        }

        self.resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    await self?.receive(result: result, generation: generation)
                }
            } catch {
                await self?.finishWithError(error, generation: generation)
            }
        }

        if let speechDetector {
            self.detectionTask = Task { [weak self] in
                do {
                    for try await result in speechDetector.results {
                        await self?.receive(detectorResult: result, generation: generation)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await self?.disableEndpointEvents(generation: generation)
                }
            }
        }

        return eventPair.stream
    }

    public func stop() async throws -> SpeechTranscription {
        guard let generation = sessionGeneration else {
            throw LerroError.emptyTranscription
        }
        guard let engine = audioEngine,
              let analyzer,
              let startedAt else {
            throw LerroError.emptyTranscription
        }
        endEndpointEvents(generation: generation)
        defer { restoreOutputAudioIfNeeded() }

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        var completedAudioRelativePath = audioRelativePath
        do {
            try audioFileWriter?.verifyWritesSucceeded()
        } catch {
            if let completedAudioRelativePath {
                deleteRecording(relativePath: completedAudioRelativePath)
            }
            completedAudioRelativePath = nil
        }
        audioFileWriter = nil
        if let audioConverter {
            guard let tailBuffers = audioConverter.drainTail() else {
                throw LerroError.speechUnavailable("无法完成音频尾部格式转换")
            }
            for tail in tailBuffers {
                if case .some(.dropped) = inputContinuation?.yield(AnalyzerInput(buffer: tail)) {
                    throw LerroError.speechUnavailable("语音处理速度不足，请缩短本次录音后重试")
                }
            }
        }
        inputContinuation?.finish()
        let pendingResults = resultTask
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            await pendingResults?.value
            detectionTask?.cancel()
        } catch {
            guard sessionGeneration == generation else { throw CancellationError() }
            eventContinuation?.finish(throwing: error)
            deleteCurrentRecording()
            clearSession(generation: generation)
            throw error
        }
        try requireCurrent(generation)
        let text = composedText().trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = startedAt.duration(to: .now).timeInterval

        if text.isEmpty {
            eventContinuation?.finish()
            restoreOutputAudioIfNeeded()
            deleteCurrentRecording()
            clearSession(generation: generation)
            throw LerroError.emptyTranscription
        }

        eventContinuation?.yield(.final(text))
        eventContinuation?.finish()
        let result = SpeechTranscription(
            rawText: text,
            localeIdentifier: localeIdentifier,
            duration: duration,
            audioRelativePath: completedAudioRelativePath
        )
        restoreOutputAudioIfNeeded()
        clearSession(generation: generation)
        return result
    }

    public func cancel() async {
        let generation = sessionGeneration
        let analyzerToCancel = analyzer
        endEndpointEvents(generation: generation)
        if let engine = audioEngine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
        }
        inputContinuation?.finish()
        eventContinuation?.finish(throwing: LerroError.cancelled)
        restoreOutputAudioIfNeeded()
        deleteCurrentRecording()
        clearSession(generation: generation)
        await analyzerToCancel?.cancelAndFinishNow()
    }

    private func ensureAssets(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .installed:
            _ = try? await AssetInventory.reserve(locale: locale)
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            _ = try? await AssetInventory.reserve(locale: locale)
        case .unsupported:
            throw LerroError.speechUnavailable("语言资源不受支持")
        @unknown default:
            throw LerroError.speechUnavailable("语言资源状态未知")
        }
    }

    public func resourceStatus(localeIdentifier: String) async -> LanguageResourceStatus {
        guard SpeechTranscriber.isAvailable else {
            return LanguageResourceStatus(
                state: .unsupported,
                sourceLanguageIdentifier: localeIdentifier,
                message: "SpeechTranscriber 在当前系统上不可用"
            )
        }
        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            return LanguageResourceStatus(
                state: .unsupported,
                sourceLanguageIdentifier: localeIdentifier,
                message: "此听写语言暂不支持"
            )
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return LanguageResourceStatus(
                state: .ready,
                sourceLanguageIdentifier: locale.identifier,
                message: "语音资源已准备"
            )
        case .supported:
            return LanguageResourceStatus(
                state: .available,
                sourceLanguageIdentifier: locale.identifier,
                message: "需要准备语音资源"
            )
        case .downloading:
            return LanguageResourceStatus(
                state: .downloading,
                sourceLanguageIdentifier: locale.identifier,
                message: "语音资源下载中"
            )
        case .unsupported:
            return LanguageResourceStatus(
                state: .unsupported,
                sourceLanguageIdentifier: locale.identifier,
                message: "语音资源不受支持"
            )
        @unknown default:
            return LanguageResourceStatus(
                state: .failed,
                sourceLanguageIdentifier: locale.identifier,
                message: "语音资源状态未知"
            )
        }
    }

    public func prepareResources(localeIdentifier: String) async throws -> LanguageResourceStatus {
        guard SpeechTranscriber.isAvailable else {
            throw LerroError.speechUnavailable("SpeechTranscriber 在当前系统上不可用")
        }
        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw LerroError.speechUnavailable("不支持语言 \(localeIdentifier)")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        try await ensureAssets(for: transcriber, locale: locale)
        return await resourceStatus(localeIdentifier: locale.identifier)
    }

    private func receive(result: SpeechTranscriber.Result, generation: UUID) {
        guard sessionGeneration == generation else { return }
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        transcriptLedger.apply(
            text: text,
            start: result.range.start.isNumeric ? result.range.start.seconds : 0,
            duration: result.range.duration.isNumeric ? max(0, result.range.duration.seconds) : 0,
            isFinal: result.isFinal
        )
        eventContinuation?.yield(.partial(composedText()))
    }

    private func receive(detectorResult: SpeechDetector.Result, generation: UUID) {
        guard sessionGeneration == generation, endpointEventsEnabled else { return }
        switch endpointTracker.observe(speechDetected: detectorResult.speechDetected) {
        case .none:
            break
        case .speechStarted:
            eventContinuation?.yield(.speechStarted)
        case .silenceBegan:
            scheduleSilenceEvent(generation: generation)
        case .speechResumed:
            silenceTask?.cancel()
            silenceTask = nil
        }
    }

    private func scheduleSilenceEvent(generation: UUID) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.quickDictateSilenceDuration)
            } catch {
                return
            }
            await self?.emitSilenceElapsed(generation: generation)
        }
    }

    private func emitSilenceElapsed(generation: UUID) {
        guard sessionGeneration == generation,
              endpointEventsEnabled,
              endpointTracker.markSilenceElapsed() else {
            return
        }
        silenceTask = nil
        eventContinuation?.yield(.silenceElapsed)
    }

    private func disableEndpointEvents(generation: UUID) {
        guard sessionGeneration == generation else { return }
        endEndpointEvents(generation: generation)
    }

    private func endEndpointEvents(generation: UUID?) {
        guard generation == nil || sessionGeneration == generation else { return }
        endpointEventsEnabled = false
        silenceTask?.cancel()
        silenceTask = nil
        endpointTracker.reset()
    }

    private func composedText() -> String {
        transcriptLedger.composedText
    }

    private func finishWithError(_ error: any Error, generation: UUID) {
        guard sessionGeneration == generation else { return }
        endEndpointEvents(generation: generation)
        if let engine = audioEngine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
        }
        inputContinuation?.finish()
        eventContinuation?.finish(throwing: error)
        restoreOutputAudioIfNeeded()
        deleteCurrentRecording()
        clearSession(generation: generation)
    }

    private func selectInputDevice(uid: String?, inputNode: AVAudioInputNode) throws {
        guard let uid,
              let deviceID = CoreAudioHardware.inputDeviceID(forUID: uid) else {
            return
        }
        guard let audioUnit = inputNode.audioUnit else {
            throw LerroError.speechUnavailable("无法连接所选麦克风")
        }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw LerroError.speechUnavailable("无法使用所选麦克风（\(status)）")
        }
    }

    private func restoreOutputAudioIfNeeded() {
        guard let outputMuteSnapshot else { return }
        CoreAudioHardware.restoreOutputMute(outputMuteSnapshot)
        self.outputMuteSnapshot = nil
    }

    private func makeRecordingWriter(
        format: AVAudioFormat
    ) throws -> (writer: AudioFileWriter, relativePath: String) {
        try applicationPaths.prepareDirectories()
        let relativePath = "\(UUID().uuidString.lowercased()).caf"
        let url = applicationPaths.audioDirectory.appending(path: relativePath)
        return (try AudioFileWriter(url: url, format: format), relativePath)
    }

    private func deleteCurrentRecording() {
        guard let audioRelativePath else { return }
        deleteRecording(relativePath: audioRelativePath)
        self.audioRelativePath = nil
        audioFileWriter = nil
        audioConverter = nil
    }

    private func deleteRecording(relativePath: String) {
        guard relativePath == URL(fileURLWithPath: relativePath).lastPathComponent else { return }
        let url = applicationPaths.audioDirectory.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error(
                "Recording cleanup will retry during reconciliation: \(relativePath, privacy: .public), \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func requireCurrent(_ generation: UUID) throws {
        guard sessionGeneration == generation, !Task.isCancelled else {
            throw CancellationError()
        }
    }

    private func clearSession(generation: UUID?) {
        guard generation == nil || sessionGeneration == generation else { return }
        analysisTask?.cancel()
        resultTask?.cancel()
        detectionTask?.cancel()
        silenceTask?.cancel()
        analysisTask = nil
        resultTask = nil
        detectionTask = nil
        silenceTask = nil
        audioEngine = nil
        analyzer = nil
        transcriber = nil
        speechDetector = nil
        inputContinuation = nil
        eventContinuation = nil
        tapInstalled = false
        audioFileWriter = nil
        audioConverter = nil
        audioRelativePath = nil
        startedAt = nil
        transcriptLedger = TranscriptLedger()
        endpointTracker.reset()
        endpointEventsEnabled = false
        sessionGeneration = nil
    }
}

private func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(
        pcmFormat: buffer.format,
        frameCapacity: buffer.frameLength
    ) else { return nil }
    copy.frameLength = buffer.frameLength
    let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
    guard sourceBuffers.count == destinationBuffers.count else { return nil }
    for index in sourceBuffers.indices {
        guard let source = sourceBuffers[index].mData,
              let destination = destinationBuffers[index].mData else { return nil }
        memcpy(destination, source, Int(sourceBuffers[index].mDataByteSize))
    }
    return copy
}

func transcriptSeparator(after preceding: String, before following: String) -> String {
    guard let last = preceding.last, let first = following.first else { return "" }
    guard !last.isWhitespace, !first.isWhitespace else { return "" }
    if joinsPreviousToken(first) || joinsFollowingToken(last) { return "" }
    return requiresWordSeparator(last) || requiresWordSeparator(first) ? " " : ""
}

private func joinsPreviousToken(_ character: Character) -> Bool {
    ",.;:!?%)]}，。！？；：、）】》」』".contains(character)
}

private func joinsFollowingToken(_ character: Character) -> Bool {
    "([{（【《「『".contains(character)
}

private func requiresWordSeparator(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
            false
        default:
            true
        }
    }
}

private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
    lhs.sampleRate == rhs.sampleRate
        && lhs.channelCount == rhs.channelCount
        && lhs.commonFormat == rhs.commonFormat
        && lhs.isInterleaved == rhs.isInterleaved
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
