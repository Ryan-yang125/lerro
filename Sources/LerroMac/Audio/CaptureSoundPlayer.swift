@preconcurrency import AVFoundation
import Foundation
import OSLog
import LerroCore

/// Plays the short start and stop sounds from `Contents/Resources/Sounds`.
/// Both players are loaded once by `prepare`, so `play` starts immediately and
/// returns when the sound has finished (or after a safety timeout).
public actor CaptureSoundPlayer: CaptureSoundPlaying {
    private static let logger = Logger(subsystem: "app.lerro.mac", category: "capture-sound")
    private static let volume: Float = 0.6
    private static let playbackTimeout: Duration = .milliseconds(1_500)

    private var players: [CaptureSound: AVAudioPlayer] = [:]
    private var isPrepared = false

    public init() {}

    public func prepare() async {
        guard !isPrepared else { return }
        isPrepared = true
        players[.start] = Self.makePlayer(resource: "capture-start")
        players[.stop] = Self.makePlayer(resource: "capture-stop")
    }

    public func play(_ sound: CaptureSound) async {
        await prepare()
        guard let player = players[sound] else { return }
        let finish = PlaybackCompletion()
        player.delegate = finish
        player.currentTime = 0
        guard player.play() else {
            player.delegate = nil
            return
        }
        await finish.wait(timeout: Self.playbackTimeout)
        player.delegate = nil
    }

    private static func makePlayer(resource: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(
            forResource: resource,
            withExtension: "caf",
            subdirectory: "Sounds"
        ) else {
            logger.error("Missing sound resource \(resource, privacy: .public)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            return player
        } catch {
            logger.error("Cannot load sound \(resource, privacy: .public)")
            return nil
        }
    }
}

/// Bridges `AVAudioPlayerDelegate` callbacks to a single awaited completion.
/// The delegate callback and the timeout race; the first one resumes the
/// continuation and the other is ignored.
private final class PlaybackCompletion: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isFinished = false

    func wait(timeout: Duration) async {
        let timeoutTask = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.finish()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyFinished = lock.withLock {
                if isFinished { return true }
                self.continuation = continuation
                return false
            }
            if alreadyFinished { continuation.resume() }
        }
        timeoutTask.cancel()
    }

    private func finish() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            guard !isFinished else { return nil }
            isFinished = true
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        finish()
    }
}
