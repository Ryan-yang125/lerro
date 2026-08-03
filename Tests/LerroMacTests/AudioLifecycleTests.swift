import AVFoundation
import Foundation
import Testing
@testable import LerroMac

@Suite("Audio lifecycle", .serialized)
struct AudioLifecycleTests {
    @Test("Transcript segments preserve punctuation and CJK boundaries")
    func transcriptSeparatorsRespectLanguageBoundaries() {
        #expect(transcriptSeparator(after: "hello", before: ",") == "")
        #expect(transcriptSeparator(after: "(", before: "hello") == "")
        #expect(transcriptSeparator(after: "hello", before: "world") == " ")
        #expect(transcriptSeparator(after: "你好", before: "世界") == "")
        #expect(transcriptSeparator(after: "你好", before: "world") == " ")
        #expect(transcriptSeparator(after: "world", before: "。") == "")
        #expect(transcriptSeparator(after: "こんにちは", before: "世界") == "")
        #expect(transcriptSeparator(after: "안녕", before: "하세요") == "")
    }

    @Test("Transcript ledger replaces overlapping volatile text and preserves final order")
    func transcriptLedgerReconcilesVolatileAndFinalRanges() {
        var ledger = TranscriptLedger()
        ledger.apply(text: "later", start: 2, duration: 1, isFinal: false)
        ledger.apply(text: "hello", start: 0, duration: 1, isFinal: false)
        #expect(ledger.composedText == "hello later")

        ledger.apply(text: "", start: 2, duration: 1, isFinal: false)
        #expect(ledger.composedText == "hello")

        ledger.apply(text: "hello,", start: 0, duration: 1, isFinal: true)
        ledger.apply(text: "world", start: 1, duration: 1, isFinal: true)
        #expect(ledger.composedText == "hello, world")
    }

    @Test("Normalizes silence and a known signal level")
    func normalizesAudioLevels() throws {
        let silence = try makeBuffer(sampleRate: 16_000, frameCount: 256) { _ in 0 }
        let minusTwentyDecibels = try makeBuffer(sampleRate: 16_000, frameCount: 256) { _ in 0.1 }

        #expect(normalizedAudioLevel(silence) == 0)
        #expect(abs(normalizedAudioLevel(minusTwentyDecibels) - (2.0 / 3.0)) < 0.001)
    }

    @Test("Converts synthetic microphone audio to the analysis format")
    func convertsAudioBuffers() throws {
        let input = try makeBuffer(sampleRate: 48_000, frameCount: 480) { index in
            0.2 * sin(2 * .pi * 440 * Float(index) / 48_000)
        }
        let outputFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let converter = try #require(
            AudioBufferConverter(inputFormat: input.format, outputFormat: outputFormat)
        )

        let output = try #require(converter.convert(input))

        #expect(output.frameLength > 0)
        #expect(output.frameLength <= output.frameCapacity)
        #expect(output.format.sampleRate == 16_000)
        #expect(output.format.channelCount == 1)

        let tail = try #require(converter.drainTail())
        #expect(tail.count <= 32)
        #expect(tail.allSatisfy { $0.frameLength > 0 && $0.frameLength <= $0.frameCapacity })
    }

    @Test("Writes and reopens a synthetic CAF recording")
    func writesAudioFileLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LerroMacAudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "capture.caf")
        let buffer = try makeBuffer(sampleRate: 16_000, frameCount: 512) { index in
            0.15 * sin(2 * .pi * 220 * Float(index) / 16_000)
        }

        var writer: AudioFileWriter? = try AudioFileWriter(url: fileURL, format: buffer.format)
        writer?.write(buffer)
        try writer?.verifyWritesSucceeded()
        writer = nil

        let recording = try AVAudioFile(forReading: fileURL)
        #expect(recording.length == 512)
        #expect(recording.processingFormat.sampleRate == 16_000)
        #expect(recording.processingFormat.channelCount == 1)
    }

    private func makeBuffer(
        sampleRate: Double,
        frameCount: AVAudioFrameCount,
        sample: (Int) -> Float
    ) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let channel = try #require(buffer.floatChannelData?.pointee)
        for index in 0..<Int(frameCount) {
            channel[index] = sample(index)
        }
        return buffer
    }
}
