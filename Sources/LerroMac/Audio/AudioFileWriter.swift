@preconcurrency import AVFoundation
import Foundation

final class AudioFileWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let lock = NSLock()
    private var writeError: (any Error)?

    init(url: URL, format: AVAudioFormat) throws {
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard writeError == nil else { return }
        do {
            try file.write(from: buffer)
        } catch {
            writeError = error
        }
    }

    func verifyWritesSucceeded() throws {
        lock.lock()
        defer { lock.unlock() }
        if let writeError {
            throw writeError
        }
    }
}
