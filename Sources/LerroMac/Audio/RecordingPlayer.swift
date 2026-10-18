@preconcurrency import AVFoundation
import Foundation
import Observation

/// Plays one saved recording at a time and reports playback progress.
@MainActor
@Observable
public final class RecordingPlayer {
    /// The recording that is playing now. `nil` while paused or stopped.
    public private(set) var playingURL: URL?
    /// Playback position of the loaded recording, from 0 to 1.
    public private(set) var progress: Double = 0
    /// Length of the loaded recording in seconds. 0 until a recording is loaded.
    public private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var timer: Timer?

    public init() {}

    isolated deinit {
        timer?.invalidate()
        player?.stop()
    }

    /// Starts playback of `url`, pauses it when it is playing, and resumes it when it is paused.
    /// Starting another recording stops the current one.
    public func toggle(url: URL) {
        if loadedURL == url, let player {
            if player.isPlaying {
                pause()
            } else {
                resume(player)
            }
            return
        }

        stop()
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        newPlayer.prepareToPlay()
        player = newPlayer
        loadedURL = url
        duration = newPlayer.duration
        resume(newPlayer)
    }

    public func stop() {
        invalidateTimer()
        player?.stop()
        player = nil
        loadedURL = nil
        playingURL = nil
        progress = 0
        duration = 0
    }

    private func resume(_ player: AVAudioPlayer) {
        guard player.play() else {
            stop()
            return
        }
        playingURL = loadedURL
        startTimer()
    }

    private func pause() {
        player?.pause()
        invalidateTimer()
        playingURL = nil
        updateProgress()
    }

    private func startTimer() {
        invalidateTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let player, player.isPlaying else {
            stop()
            return
        }
        updateProgress()
    }

    private func updateProgress() {
        guard let player, player.duration > 0 else {
            progress = 0
            return
        }
        progress = min(max(player.currentTime / player.duration, 0), 1)
    }
}
