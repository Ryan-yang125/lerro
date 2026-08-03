import AVFoundation
import Foundation

final class AudioBufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()

    init?(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        let inputProvider = AudioConverterInput(buffer: input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            inputProvider.provide(status: statusPointer)
        }

        guard conversionError == nil, (status == .haveData || status == .inputRanDry) else {
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    /// Drains samples retained by the resampler after the final input buffer.
    /// This preserves the trailing phoneme when input and analysis sample rates
    /// differ.
    func drainTail(maximumBufferCount: Int = 32) -> [AVAudioPCMBuffer]? {
        lock.lock()
        defer { lock.unlock() }

        guard maximumBufferCount > 0 else { return nil }
        let capacity = AVAudioFrameCount(max(32, Int(outputFormat.sampleRate / 50)))
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<maximumBufferCount {
            guard let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else { return nil }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
                statusPointer.pointee = .endOfStream
                return nil
            }
            guard conversionError == nil,
                  (status == .haveData || status == .endOfStream) else { return nil }
            if output.frameLength > 0 { buffers.append(output) }
            if status == .endOfStream { return buffers }
            guard output.frameLength > 0 else { return nil }
        }
        return nil
    }
}

private final class AudioConverterInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provide(
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if didProvideInput {
            status.pointee = .noDataNow
            return nil
        }
        didProvideInput = true
        status.pointee = .haveData
        return buffer
    }
}

func normalizedAudioLevel(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let channel = buffer.floatChannelData?.pointee else { return 0 }
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0 else { return 0 }

    var sum: Float = 0
    for index in 0..<frameCount {
        let sample = channel[index]
        sum += sample * sample
    }
    let rms = sqrt(sum / Float(frameCount))
    let decibels = 20 * log10(max(rms, 0.000_001))
    return min(1, max(0, (decibels + 60) / 60))
}
