import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import OSLog
import Speech
import Synchronization
import LerroCore

@available(macOS 26.0, *)
public actor AppleSpeechService: SpeechTranscribing {
    private static let logger = Logger(
        subsystem: "app.lerro.mac",
        category: "audio-cleanup"
    )
    private var audioEngine: AVAudioEngine?
    private var audioEngineDeviceUID: String?
    private var warmEngine: WarmEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var rawContinuation: AsyncStream<CapturedAudio>.Continuation?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var eventContinuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation?
    private var pipelineTask: Task<Void, any Error>?
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var tapInstalled = false
    private var stopRequested = false
    private var transcriptLedger = TranscriptLedger()
    private var localeIdentifier = "zh_CN"
    private var startedAt: ContinuousClock.Instant?
    private var outputMuteSnapshot: CoreAudioHardware.OutputMuteSnapshot?
    private var audioFileWriter: AudioFileWriter?
    private var audioConverter: AudioBufferConverter?
    private var audioRelativePath: String?
    private var sessionGeneration: UUID?
    private var milestoneReporter: CaptureMilestoneReporter?
    private var reportedFirstPartial = false
    private let applicationPaths: ApplicationPaths

    public init(applicationPaths: ApplicationPaths = .live()) {
        self.applicationPaths = applicationPaths
    }

    public func availableInputDevices() async -> [AudioInputDevice] {
        CoreAudioHardware.inputDevices()
    }

    /// Builds the audio engine for the next capture. The engine stays stopped,
    /// so the microphone and its system indicator remain off while idle.
    public func prewarmAudioInput(microphoneDeviceUID: String?) async {
        guard sessionGeneration == nil, audioEngine == nil else { return }
        if let warmEngine, warmEngine.serves(deviceUID: microphoneDeviceUID) { return }
        let engine = AVAudioEngine()
        do {
            try selectInputDevice(uid: microphoneDeviceUID, inputNode: engine.inputNode)
        } catch {
            dropWarmEngine()
            return
        }
        adoptWarmEngine(engine, deviceUID: microphoneDeviceUID)
    }

    public func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        saveAudio: Bool,
        milestones: @escaping CaptureMilestoneReporter
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error> {
        await cancel()
        let generation = UUID()
        sessionGeneration = generation
        var didStart = false
        defer {
            if !didStart, sessionGeneration == generation { sessionGeneration = nil }
        }

        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw LerroError.speechUnavailable("不支持语言 \(localeIdentifier)")
        }
        try requireCurrent(generation)
        milestones(.speechLocaleResolved, .now)

        // The microphone opens before any speech resource work. The analyzer
        // is prepared afterwards while captured audio waits in memory.
        let engine: AVAudioEngine
        if let warm = takeWarmEngine(deviceUID: microphoneDeviceUID) {
            engine = warm
        } else {
            engine = AVAudioEngine()
            try selectInputDevice(uid: microphoneDeviceUID, inputNode: engine.inputNode)
        }
        let inputNode = engine.inputNode
        milestones(.audioEngineCreated, .now)
        let naturalFormat = inputNode.outputFormat(forBus: 0)
        guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
            throw LerroError.speechUnavailable("没有可用的麦克风输入格式")
        }
        milestones(.audioInputConfigured, .now)

        let recording: (writer: AudioFileWriter, relativePath: String)?
        if saveAudio {
            recording = try makeRecordingWriter(format: naturalFormat)
        } else {
            recording = nil
        }

        // Captured audio never drops silently. Both bounded queues give a clear
        // failure if the analyzer cannot keep pace instead of producing a
        // partial transcript. The raw queue holds the microphone audio captured
        // while the analyzer prepares (512 buffers is about 20 seconds at
        // 48 kHz) and the analyzer queue holds the same backlog once it is
        // forwarded.
        let rawPair = AsyncStream<CapturedAudio>.makeStream(bufferingPolicy: .bufferingOldest(512))
        // UI levels are naturally coalesced by the MainActor. Keep the event
        // stream lossless so partial/final transcript events always arrive.
        let eventPair = AsyncThrowingStream<SpeechEvent, any Error>.makeStream()

        let firstBufferLatch = FirstEventLatch()
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: naturalFormat) { buffer, _ in
            if firstBufferLatch.claim() {
                milestones(.firstAudioBuffer, .now)
            }
            recording?.writer.write(buffer)
            // AVAudioEngine owns the tap buffer only for this callback.
            // The analyzer pipeline consumes it later, so queue a copy.
            guard let copied = copyPCMBuffer(buffer) else {
                rawPair.continuation.finish()
                eventPair.continuation.finish(
                    throwing: LerroError.speechUnavailable("无法复制麦克风音频")
                )
                return
            }
            if case .dropped = rawPair.continuation.yield(CapturedAudio(buffer: copied)) {
                rawPair.continuation.finish()
                eventPair.continuation.finish(
                    throwing: LerroError.speechUnavailable("语音处理速度不足，请缩短本次录音后重试")
                )
                return
            }
            eventPair.continuation.yield(.audioLevel(normalizedAudioLevel(buffer)))
        }

        engine.prepare()
        do {
            try engine.start()
            milestones(.audioEngineStarted, .now)
        } catch {
            inputNode.removeTap(onBus: 0)
            rawPair.continuation.finish()
            if let path = recording?.relativePath { deleteRecording(relativePath: path) }
            throw error
        }

        self.audioEngine = engine
        self.audioEngineDeviceUID = microphoneDeviceUID
        self.rawContinuation = rawPair.continuation
        self.eventContinuation = eventPair.continuation
        self.tapInstalled = true
        self.stopRequested = false
        self.audioFileWriter = recording?.writer
        self.audioRelativePath = recording?.relativePath
        self.sessionGeneration = generation
        self.transcriptLedger = TranscriptLedger()
        self.localeIdentifier = locale.identifier
        self.startedAt = .now
        self.milestoneReporter = milestones
        self.reportedFirstPartial = false

        let pipelineInput = AnalyzerPipelineInput(
            locale: locale,
            naturalFormat: naturalFormat,
            rawStream: rawPair.stream,
            milestones: milestones
        )
        self.pipelineTask = Task { [weak self] in
            try await self?.runAnalyzerPipeline(pipelineInput, generation: generation)
        }

        didStart = true
        return eventPair.stream
    }

    /// Mutes the default output while this session's microphone is running.
    /// Does nothing before the engine starts, after it stops, or when the
    /// output is already lowered.
    public func lowerOtherAudio() async {
        guard sessionGeneration != nil,
              audioEngine != nil,
              !stopRequested,
              outputMuteSnapshot == nil else { return }
        outputMuteSnapshot = CoreAudioHardware.muteDefaultOutput()
    }

    /// Stops the microphone and restores the output audio lowered by `lowerOtherAudio`,
    /// so a sound played afterwards is audible. Transcription keeps running
    /// until `stop` finalizes it.
    public func endAudioCapture() async {
        guard sessionGeneration != nil, let engine = audioEngine else { return }
        stopRequested = true
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        rawContinuation?.finish()
        rawContinuation = nil
        restoreOutputAudioIfNeeded()
    }

    public func stop() async throws -> SpeechTranscription {
        guard let generation = sessionGeneration else {
            throw LerroError.emptyTranscription
        }
        guard let engine = audioEngine,
              let pipelineTask,
              let startedAt else {
            throw LerroError.emptyTranscription
        }
        defer { restoreOutputAudioIfNeeded() }

        await endAudioCapture()
        let deviceUID = audioEngineDeviceUID
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

        // The pipeline finishes preparing the analyzer, forwards every buffered
        // chunk, drains the converter tail and closes the analyzer input.
        do {
            try await pipelineTask.value
        } catch {
            if sessionGeneration == generation {
                eventContinuation?.finish(throwing: error)
                deleteCurrentRecording()
                clearSession(generation: generation)
            }
            throw error
        }
        guard sessionGeneration == generation else { throw CancellationError() }
        guard let analyzer else {
            throw LerroError.emptyTranscription
        }
        let pendingResults = resultTask
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            await pendingResults?.value
        } catch {
            guard sessionGeneration == generation else { throw CancellationError() }
            eventContinuation?.finish(throwing: error)
            deleteCurrentRecording()
            clearSession(generation: generation)
            throw error
        }
        try requireCurrent(generation)
        let text = composedText()
        let duration = startedAt.duration(to: .now).timeInterval

        if text.isEmpty {
            eventContinuation?.finish()
            restoreOutputAudioIfNeeded()
            deleteCurrentRecording()
            clearSession(generation: generation)
            adoptWarmEngine(engine, deviceUID: deviceUID)
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
        adoptWarmEngine(engine, deviceUID: deviceUID)
        return result
    }

    public func cancel() async {
        let generation = sessionGeneration
        let analyzerToCancel = analyzer
        let engine = audioEngine
        let deviceUID = audioEngineDeviceUID
        pipelineTask?.cancel()
        if let engine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
        }
        rawContinuation?.finish()
        inputContinuation?.finish()
        eventContinuation?.finish(throwing: LerroError.cancelled)
        restoreOutputAudioIfNeeded()
        deleteCurrentRecording()
        clearSession(generation: generation)
        if let engine {
            adoptWarmEngine(engine, deviceUID: deviceUID)
        }
        await analyzerToCancel?.cancelAndFinishNow()
    }

    /// Prepares the analyzer while the microphone is already capturing, then
    /// feeds it the buffered audio in order and continues with live audio until
    /// `stop` or `cancel` finishes the raw stream.
    private func runAnalyzerPipeline(
        _ input: AnalyzerPipelineInput,
        generation: UUID
    ) async throws {
        do {
            try await prepareAnalyzerAndForwardAudio(input, generation: generation)
        } catch let error as CancellationError {
            throw error
        } catch {
            finishWithError(error, generation: generation)
            throw error
        }
    }

    private func prepareAnalyzerAndForwardAudio(
        _ input: AnalyzerPipelineInput,
        generation: UUID
    ) async throws {
        let milestones = input.milestones
        let naturalFormat = input.naturalFormat

        let transcriber = SpeechTranscriber(locale: input.locale, preset: .progressiveTranscription)
        try await ensureAssets(for: transcriber, locale: input.locale)
        try requireCurrent(generation)
        milestones(.speechAssetsReserved, .now)

        let modules: [any SpeechModule] = [transcriber]
        guard let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: naturalFormat
        ) else {
            throw LerroError.speechUnavailable("麦克风的音频格式不受支持")
        }
        try requireCurrent(generation)
        milestones(.audioFormatNegotiated, .now)

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        milestones(.analyzerCreated, .now)
        try await analyzer.prepareToAnalyze(in: analysisFormat)
        try requireCurrent(generation)
        milestones(.analyzerPrepared, .now)

        let converter: AudioBufferConverter?
        if formatsMatch(naturalFormat, analysisFormat) {
            converter = nil
        } else {
            guard let preparedConverter = AudioBufferConverter(
                inputFormat: naturalFormat,
                outputFormat: analysisFormat
            ) else {
                throw LerroError.speechUnavailable("无法创建音频格式转换器")
            }
            converter = preparedConverter
        }
        let inputPair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(512))

        self.analyzer = analyzer
        self.transcriber = transcriber
        self.inputContinuation = inputPair.continuation
        self.audioConverter = converter

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

        for await captured in input.rawStream {
            try requireCurrent(generation)
            let buffer: AVAudioPCMBuffer
            if let converter {
                guard let output = converter.convert(captured.buffer) else {
                    throw LerroError.speechUnavailable("音频格式转换失败")
                }
                buffer = output
            } else {
                buffer = captured.buffer
            }
            if case .dropped = inputPair.continuation.yield(AnalyzerInput(buffer: buffer)) {
                throw LerroError.speechUnavailable("语音处理速度不足，请缩短本次录音后重试")
            }
        }
        try requireCurrent(generation)

        if let converter {
            guard let tailBuffers = converter.drainTail() else {
                throw LerroError.speechUnavailable("音频处理失败，请重试")
            }
            for tail in tailBuffers {
                if case .dropped = inputPair.continuation.yield(AnalyzerInput(buffer: tail)) {
                    throw LerroError.speechUnavailable("语音处理速度不足，请缩短本次录音后重试")
                }
            }
        }
        inputPair.continuation.finish()
    }

    private func adoptWarmEngine(_ engine: AVAudioEngine, deviceUID: String?) {
        dropWarmEngine()
        let identifier = ObjectIdentifier(engine)
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.invalidateWarmEngine(identifier) }
        }
        warmEngine = WarmEngine(
            engine: engine,
            deviceUID: deviceUID,
            defaultInputDeviceID: CoreAudioHardware.defaultInputDeviceID(),
            observer: observer
        )
    }

    private func takeWarmEngine(deviceUID: String?) -> AVAudioEngine? {
        guard let warmEngine else { return nil }
        dropWarmEngine()
        return warmEngine.serves(deviceUID: deviceUID) ? warmEngine.engine : nil
    }

    private func invalidateWarmEngine(_ identifier: ObjectIdentifier) {
        guard let warmEngine, ObjectIdentifier(warmEngine.engine) == identifier else { return }
        dropWarmEngine()
    }

    private func dropWarmEngine() {
        guard let warmEngine else { return }
        NotificationCenter.default.removeObserver(warmEngine.observer)
        self.warmEngine = nil
    }

    /// `AssetInventory.status` can report an installed locale as `.supported`
    /// for the rest of the process lifetime (seen after mobileassetd restarts),
    /// and the in-process reinstall then fails. `installedLocales` stays
    /// correct, and transcription works in that state, so it is checked first.
    private func localeIsInstalled(_ locale: Locale) async -> Bool {
        let identifier = locale.identifier(.bcp47)
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == identifier }
    }

    private func ensureAssets(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        try Task.checkCancellation()
        if await localeIsInstalled(locale) {
            _ = try? await AssetInventory.reserve(locale: locale)
            return
        }
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .installed:
            _ = try? await AssetInventory.reserve(locale: locale)
        case .supported, .downloading:
            try await AssetInventory.reserve(locale: locale)
            try Task.checkCancellation()
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            try Task.checkCancellation()
            guard await AssetInventory.status(forModules: modules) == .installed else {
                throw LerroError.speechUnavailable("语音资源暂未就绪，请稍后重试。")
            }
        case .unsupported:
            throw LerroError.speechUnavailable("当前语言不受支持，请在设置中更换听写语言")
        @unknown default:
            throw LerroError.speechUnavailable("语言资源状态未知")
        }
    }

    public func resourceStatus(localeIdentifier: String) async -> LanguageResourceStatus {
        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            return LanguageResourceStatus(
                state: .unsupported,
                sourceLanguageIdentifier: localeIdentifier,
                message: "此听写语言暂不支持"
            )
        }
        if await localeIsInstalled(locale) {
            return LanguageResourceStatus(
                state: .ready,
                sourceLanguageIdentifier: locale.identifier,
                message: "语音资源已就绪"
            )
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return LanguageResourceStatus(
                state: .ready,
                sourceLanguageIdentifier: locale.identifier,
                message: "语音资源已就绪"
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
        let composed = composedText()
        if !reportedFirstPartial, !composed.isEmpty {
            reportedFirstPartial = true
            milestoneReporter?(.firstPartial, .now)
        }
        eventContinuation?.yield(.partial(composed))
    }

    /// The ledger text with SpeechTranscriber's spacing around CJK punctuation removed.
    private func composedText() -> String {
        TranscriptSpacing.normalize(transcriptLedger.composedText)
    }

    private func finishWithError(_ error: any Error, generation: UUID) {
        guard sessionGeneration == generation else { return }
        if let engine = audioEngine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
        }
        // The failure may come from the engine itself, so it does not return
        // to the warm slot.
        rawContinuation?.finish()
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
            throw LerroError.speechUnavailable("无法连接所选麦克风，请检查设备或重新选择")
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
        pipelineTask?.cancel()
        analysisTask?.cancel()
        resultTask?.cancel()
        pipelineTask = nil
        analysisTask = nil
        resultTask = nil
        audioEngine = nil
        audioEngineDeviceUID = nil
        analyzer = nil
        transcriber = nil
        rawContinuation = nil
        inputContinuation = nil
        eventContinuation = nil
        tapInstalled = false
        stopRequested = false
        audioFileWriter = nil
        audioConverter = nil
        audioRelativePath = nil
        startedAt = nil
        milestoneReporter = nil
        reportedFirstPartial = false
        transcriptLedger = TranscriptLedger()
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

/// A copied microphone buffer. `AVAudioPCMBuffer` is not Sendable; the copy
/// has a single owner at a time, moving from the tap to the analyzer pipeline.
private struct CapturedAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Everything the analyzer pipeline needs from `start`, handed over once.
private struct AnalyzerPipelineInput: @unchecked Sendable {
    let locale: Locale
    let naturalFormat: AVAudioFormat
    let rawStream: AsyncStream<CapturedAudio>
    let milestones: CaptureMilestoneReporter
}

/// A built but stopped engine, kept for the next capture on the same device.
private struct WarmEngine {
    let engine: AVAudioEngine
    let deviceUID: String?
    /// The system default input when the engine was kept. A stopped engine may
    /// not report configuration changes, so a default-input engine is reused
    /// only while the default device is unchanged.
    let defaultInputDeviceID: AudioDeviceID?
    let observer: any NSObjectProtocol

    func serves(deviceUID: String?) -> Bool {
        guard self.deviceUID == deviceUID else { return false }
        return deviceUID != nil || defaultInputDeviceID == CoreAudioHardware.defaultInputDeviceID()
    }
}

/// Claims a one-shot event from the real-time audio thread.
private final class FirstEventLatch: Sendable {
    private let claimed = Mutex(false)

    func claim() -> Bool {
        claimed.withLock { value in
            if value { return false }
            value = true
            return true
        }
    }
}
