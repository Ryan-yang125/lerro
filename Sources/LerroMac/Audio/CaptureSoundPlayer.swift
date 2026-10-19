@preconcurrency import AVFoundation
import Foundation
import OSLog
import LerroCore

/// Plays the short start and stop sounds from `Contents/Resources/Sounds`.
/// Both players are loaded once by `prepare`, so `play` starts immediately.
public actor CaptureSoundPlayer: CaptureSoundPlaying {
    private static let logger = Logger(subsystem: "app.lerro.mac", category: "capture-sound")
    private static let volume: Float = 0.6

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
        player.currentTime = 0
        player.play()
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
