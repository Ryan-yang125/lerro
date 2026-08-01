import AVFoundation
import AudioToolbox
import Foundation
import OSLog
import Speech
import LerroCore

@available(macOS 26.0, *)
public actor AppleSpeechService: SpeechTranscribing {
    private static let logger = Logger(
        subsystem: "app.lerro.mac",
        category: "audio-cleanup"
    )
    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var eventContinuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var tapInstalled = false
    private var finalSegments: [String] = []
    private var volatileText = ""
    private var localeIdentifier = "zh_CN"
    private var startedAt: ContinuousClock.Instant?
    private var outputMuteSnapshot: CoreAudioHardware.OutputMuteSnapshot?
    private var audioFileWriter: AudioFileWriter?
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
        saveAudio: Bool
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
        try await ensureAssets(for: transcriber, locale: locale)
        try requireCurrent(generation)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        try selectInputDevice(uid: microphoneDeviceUID, inputNode: inputNode)
        let naturalFormat = inputNode.outputFormat(forBus: 0)
        guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
            throw LerroError.speechUnavailable("没有可用的麦克风输入格式")
        }

        let modules: [any SpeechModule] = [transcriber]
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

        let inputPair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(96))
        let eventPair = AsyncThrowingStream<SpeechEvent, any Error>.makeStream(bufferingPolicy: .bufferingNewest(64))
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
                converted = buffer
            }
            inputPair.continuation.yield(AnalyzerInput(buffer: converted))
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
        self.inputContinuation = inputPair.continuation
        self.eventContinuation = eventPair.continuation
        self.tapInstalled = true
        self.audioFileWriter = recording?.writer
        self.audioRelativePath = recording?.relativePath
        self.sessionGeneration = generation
        self.finalSegments = []
        self.volatileText = ""
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
        inputContinuation?.finish()
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

    private func receive(result: SpeechTranscriber.Result, generation: UUID) {
        guard sessionGeneration == generation else { return }
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if result.isFinal {
            finalSegments.append(text)
            volatileText = ""
        } else {
            volatileText = text
        }
        eventContinuation?.yield(.partial(composedText()))
    }

    private func composedText() -> String {
        (finalSegments + (volatileText.isEmpty ? [] : [volatileText])).joined(separator: " ")
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
        analysisTask = nil
        resultTask = nil
        audioEngine = nil
        analyzer = nil
        transcriber = nil
        inputContinuation = nil
        eventContinuation = nil
        tapInstalled = false
        audioFileWriter = nil
        audioRelativePath = nil
        startedAt = nil
        finalSegments = []
        volatileText = ""
        sessionGeneration = nil
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
