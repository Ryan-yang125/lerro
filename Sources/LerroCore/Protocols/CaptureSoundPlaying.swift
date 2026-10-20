import Foundation

public enum CaptureSound: Sendable {
    case start
    case stop
}

public protocol CaptureSoundPlaying: Sendable {
    /// Loads the sounds once so each `play` starts immediately.
    func prepare() async
    /// Returns after the sound has finished playing.
    func play(_ sound: CaptureSound) async
}
