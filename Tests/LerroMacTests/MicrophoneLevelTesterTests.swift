import AVFoundation
import Foundation
import Testing
@testable import LerroMac

@Test func microphoneLevelTesterForwardsLevelsAndStopsMatchingSession() async throws {
    let engine = FakeMicrophoneLevelEngine(levels: [0.12, 0.68])
    let tester = MicrophoneLevelTester { engine }

    let session = try await tester.start(microphoneDeviceUID: "synthetic-device")
    var iterator = session.levels.makeAsyncIterator()

    #expect(try await iterator.next() == 0.12)
    #expect(try await iterator.next() == 0.68)
    #expect(await engine.requestedDeviceUID() == "synthetic-device")

    await tester.stop(sessionID: session.id)
    #expect(await engine.stopCount() == 1)
}

@Test func staleSessionCannotStopNewMicrophoneTest() async throws {
    let engine = FakeMicrophoneLevelEngine(levels: [0.4])
    let tester = MicrophoneLevelTester { engine }

    let first = try await tester.start(microphoneDeviceUID: nil)
    let second = try await tester.start(microphoneDeviceUID: nil)
    #expect(await engine.stopCount() == 1)

    await tester.stop(sessionID: first.id)
    #expect(await engine.stopCount() == 1)

    await tester.stop(sessionID: second.id)
    #expect(await engine.stopCount() == 2)
}

@Test func normalizedAudioLevelMapsSilenceAndSignalIntoUnitRange() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
    buffer.frameLength = 16

    #expect(normalizedAudioLevel(buffer) == 0)

    let samples = try #require(buffer.floatChannelData?.pointee)
    for index in 0..<16 { samples[index] = 0.5 }
    let level = normalizedAudioLevel(buffer)
    #expect(level > 0.8)
    #expect(level <= 1)
}

private actor FakeMicrophoneLevelEngine: MicrophoneLevelEngine {
    private let scriptedLevels: [Float]
    private var selectedUID: String?
    private var stops = 0

    init(levels: [Float]) {
        scriptedLevels = levels
    }

    func start(microphoneDeviceUID: String?) async throws -> AsyncThrowingStream<Float, any Error> {
        selectedUID = microphoneDeviceUID
        let levels = scriptedLevels
        return AsyncThrowingStream { continuation in
            levels.forEach { continuation.yield($0) }
        }
    }

    func stop() async {
        stops += 1
    }

    func requestedDeviceUID() -> String? { selectedUID }
    func stopCount() -> Int { stops }
}
