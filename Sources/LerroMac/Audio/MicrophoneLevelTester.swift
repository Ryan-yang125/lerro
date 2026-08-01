@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import LerroCore

public struct MicrophoneLevelTestSession: Sendable {
    public let id: UUID
    public let levels: AsyncThrowingStream<Float, any Error>

    public init(id: UUID, levels: AsyncThrowingStream<Float, any Error>) {
        self.id = id
        self.levels = levels
    }
}

/// A microphone-only input meter used by onboarding.  It owns no speech
/// recognizer, model, repository, or text-delivery dependency.
public protocol MicrophoneLevelTesting: Sendable {
    func availableInputDevices() async -> [AudioInputDevice]
    func start(microphoneDeviceUID: String?) async throws -> MicrophoneLevelTestSession
    func stop(sessionID: UUID) async
}

public actor MicrophoneLevelTester: MicrophoneLevelTesting {
    private let makeEngine: @Sendable () -> any MicrophoneLevelEngine
    private var active: (id: UUID, engine: any MicrophoneLevelEngine)?

    public init() {
        makeEngine = { AVAudioMicrophoneLevelEngine() }
    }

    init(makeEngine: @escaping @Sendable () -> any MicrophoneLevelEngine) {
        self.makeEngine = makeEngine
    }

    public func availableInputDevices() async -> [AudioInputDevice] {
        CoreAudioHardware.inputDevices()
    }

    public func start(microphoneDeviceUID: String?) async throws -> MicrophoneLevelTestSession {
        if let active {
            self.active = nil
            await active.engine.stop()
        }

        let engine = makeEngine()
        let levels = try await engine.start(microphoneDeviceUID: microphoneDeviceUID)
        let id = UUID()
        active = (id, engine)
        return MicrophoneLevelTestSession(id: id, levels: levels)
    }

    public func stop(sessionID: UUID) async {
        guard let active, active.id == sessionID else { return }
        self.active = nil
        await active.engine.stop()
    }
}

protocol MicrophoneLevelEngine: Sendable {
    func start(microphoneDeviceUID: String?) async throws -> AsyncThrowingStream<Float, any Error>
    func stop() async
}

private actor AVAudioMicrophoneLevelEngine: MicrophoneLevelEngine {
    private var engine: AVAudioEngine?
    private var continuation: AsyncThrowingStream<Float, any Error>.Continuation?
    private var tapInstalled = false
    private var generation: UUID?

    func start(microphoneDeviceUID: String?) async throws -> AsyncThrowingStream<Float, any Error> {
        stopCurrent()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        try selectInputDevice(uid: microphoneDeviceUID, inputNode: inputNode)
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneLevelTestError.inputUnavailable
        }

        let streamPair = AsyncThrowingStream<Float, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        let generation = UUID()
        streamPair.continuation.onTermination = { [weak self] _ in
            Task { await self?.stop(generation: generation) }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            streamPair.continuation.yield(normalizedAudioLevel(buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            streamPair.continuation.finish(throwing: error)
            throw error
        }

        self.engine = engine
        self.continuation = streamPair.continuation
        self.tapInstalled = true
        self.generation = generation
        return streamPair.stream
    }

    func stop() async {
        stopCurrent()
    }

    private func stop(generation: UUID) {
        guard self.generation == generation else { return }
        stopCurrent()
    }

    private func stopCurrent() {
        let engine = self.engine
        let continuation = self.continuation
        self.engine = nil
        self.continuation = nil
        generation = nil

        if tapInstalled, let engine {
            engine.inputNode.removeTap(onBus: 0)
        }
        tapInstalled = false
        engine?.stop()
        continuation?.finish()
    }

    private func selectInputDevice(uid: String?, inputNode: AVAudioInputNode) throws {
        guard let uid else { return }
        guard let deviceID = CoreAudioHardware.inputDeviceID(forUID: uid),
              let audioUnit = inputNode.audioUnit else {
            throw MicrophoneLevelTestError.deviceUnavailable
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
            throw MicrophoneLevelTestError.cannotSelectDevice(status)
        }
    }
}

public enum MicrophoneLevelTestError: LocalizedError, Sendable {
    case inputUnavailable
    case deviceUnavailable
    case cannotSelectDevice(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            "没有可用的麦克风输入格式"
        case .deviceUnavailable:
            "所选麦克风当前不可用"
        case .cannotSelectDevice(let status):
            "无法使用所选麦克风（\(status)）"
        }
    }
}
