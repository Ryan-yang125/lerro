@preconcurrency import AVFoundation
import Foundation

/// One delivery from `CapturedAudioRelay`. `AVAudioPCMBuffer` is not Sendable;
/// each copy has a single owner at a time, moving from the tap to the sink.
enum CapturedAudioEvent: @unchecked Sendable {
    case buffer(AVAudioPCMBuffer, ContinuousClock.Instant)
    case copyFailed
}

/// Receives every input-tap buffer. Before a capture adopts the relay it keeps
/// the newest buffers in memory; afterwards it forwards each buffer to the
/// sink. This lets the microphone open at modifier key-down, so speech right
/// after the release is not lost, while a combo discards the audio unused.
final class CapturedAudioRelay: @unchecked Sendable {
    typealias Sink = @Sendable (CapturedAudioEvent) -> Void

    /// AVAudioEngine delivers about 100 ms per tap buffer, so this exceeds the
    /// 2 s prearm backstop.
    static let maxPendingEvents = 64

    private let lock = NSLock()
    private var pending: [CapturedAudioEvent] = []
    private var sink: Sink?
    private var dropped = false

    /// Called from the audio tap. AVAudioEngine owns the tap buffer only for
    /// this callback, so the relay stores or forwards a copy.
    func receive(_ buffer: AVAudioPCMBuffer, at instant: ContinuousClock.Instant) {
        let event: CapturedAudioEvent
        if let copy = copyPCMBuffer(buffer) {
            event = .buffer(copy, instant)
        } else {
            event = .copyFailed
        }
        lock.lock()
        defer { lock.unlock() }
        guard !dropped else { return }
        if let sink {
            sink(event)
            return
        }
        pending.append(event)
        if pending.count > Self.maxPendingEvents {
            pending.removeFirst(pending.count - Self.maxPendingEvents)
        }
    }

    /// Delivers the buffered events in order, then forwards live events. Both
    /// happen under one lock, so the tap cannot interleave a live buffer
    /// between the buffered ones.
    func attach(_ sink: @escaping Sink) {
        lock.lock()
        defer { lock.unlock() }
        guard !dropped else { return }
        let buffered = pending
        pending = []
        for event in buffered { sink(event) }
        self.sink = sink
    }

    /// Discards buffered audio and ignores later input.
    func drop() {
        lock.lock()
        defer { lock.unlock() }
        dropped = true
        pending = []
        sink = nil
    }
}

func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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
