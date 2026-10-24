import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import LerroMac

@Suite("Captured audio relay")
struct CapturedAudioRelayTests {
    /// A 48 kHz mono float buffer whose samples all equal `marker`.
    private func makeBuffer(marker: Float, frames: AVAudioFrameCount = 64) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try #require(buffer.floatChannelData)[0]
        for index in 0..<Int(frames) { samples[index] = marker }
        return buffer
    }

    /// Collects delivered events from the relay sink.
    private final class Recorder: Sendable {
        private let events = Mutex<[CapturedAudioEvent]>([])

        var sink: CapturedAudioRelay.Sink {
            { [self] event in events.withLock { $0.append(event) } }
        }

        var markers: [Float] {
            events.withLock { $0.compactMap { event in
                guard case let .buffer(buffer, _) = event else { return nil }
                return buffer.floatChannelData?[0][0]
            } }
        }

        var count: Int { events.withLock { $0.count } }
    }

    @Test("buffered buffers are delivered in order on attach, then live ones follow")
    func attachDrainsInOrderThenForwards() throws {
        let relay = CapturedAudioRelay()
        let recorder = Recorder()
        let start = ContinuousClock.now
        for value in 1...3 {
            relay.receive(try makeBuffer(marker: Float(value)), at: start)
        }
        #expect(recorder.count == 0)

        relay.attach(recorder.sink)
        relay.receive(try makeBuffer(marker: 4), at: start)
        relay.receive(try makeBuffer(marker: 5), at: start)

        #expect(recorder.markers == [1, 2, 3, 4, 5])
    }

    @Test("buffers after attach go straight to the sink")
    func forwardsAfterAttach() throws {
        let relay = CapturedAudioRelay()
        let recorder = Recorder()
        relay.attach(recorder.sink)
        relay.receive(try makeBuffer(marker: 7), at: .now)
        #expect(recorder.markers == [7])
    }

    @Test("overflow keeps the newest 64 buffers")
    func overflowDropsOldest() throws {
        let relay = CapturedAudioRelay()
        let recorder = Recorder()
        let total = CapturedAudioRelay.maxPendingEvents + 10
        for value in 0..<total {
            relay.receive(try makeBuffer(marker: Float(value)), at: .now)
        }
        relay.attach(recorder.sink)

        let expected = (10..<total).map { Float($0) }
        #expect(CapturedAudioRelay.maxPendingEvents == 64)
        #expect(recorder.markers == expected)
    }

    @Test("drop discards pending buffers and ignores later input")
    func dropDiscards() throws {
        let relay = CapturedAudioRelay()
        let recorder = Recorder()
        relay.receive(try makeBuffer(marker: 1), at: .now)
        relay.drop()
        relay.receive(try makeBuffer(marker: 2), at: .now)
        relay.attach(recorder.sink)
        relay.receive(try makeBuffer(marker: 3), at: .now)

        #expect(recorder.count == 0)
    }

    @Test("drop after attach stops forwarding")
    func dropStopsForwarding() throws {
        let relay = CapturedAudioRelay()
        let recorder = Recorder()
        relay.attach(recorder.sink)
        relay.receive(try makeBuffer(marker: 1), at: .now)
        relay.drop()
        relay.receive(try makeBuffer(marker: 2), at: .now)

        #expect(recorder.markers == [1])
    }

    @Test("delivered buffers are copies of the tap buffer")
    func deliversCopies() throws {
        let relay = CapturedAudioRelay()
        let recorder = Recorder()
        let original = try makeBuffer(marker: 0.5)
        relay.receive(original, at: .now)
        original.floatChannelData?[0][0] = 9

        relay.attach(recorder.sink)
        let live = try makeBuffer(marker: 0.25)
        relay.receive(live, at: .now)
        live.floatChannelData?[0][0] = 9

        #expect(recorder.markers == [0.5, 0.25])
    }

    @Test("events carry the arrival instant of the buffer")
    func carriesArrivalInstant() throws {
        let relay = CapturedAudioRelay()
        let arrival = ContinuousClock.now - .seconds(1)
        relay.receive(try makeBuffer(marker: 1), at: arrival)

        let delivered = Mutex<ContinuousClock.Instant?>(nil)
        relay.attach { event in
            if case let .buffer(_, instant) = event { delivered.withLock { $0 = instant } }
        }
        #expect(delivered.withLock { $0 } == arrival)
    }
}
