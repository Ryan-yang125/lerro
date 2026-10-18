import AppKit
import Observation
import LerroCore

@MainActor
@Observable
final class LerroMenuBarAnimator {
    private(set) var assetName = LerroMenuBarAnimator.idle

    @ObservationIgnored private var phase = CapturePhase.idle
    @ObservationIgnored private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @ObservationIgnored private var animation: Task<Void, Never>?

    private static let idle = "LerroMenuIdleTemplate"
    private static let listening = "LerroMenuListeningTemplate"
    private static let listeningDim = "LerroMenuListeningDimTemplate"
    private static let error = "LerroMenuErrorTemplate"
    private static let processing = (1...4).map { "LerroMenuProcessing\($0)Template" }

    private static let listeningInterval = Duration.milliseconds(525)
    private static let processingFrameInterval = Duration.milliseconds(150)
    private static let processingHold = Duration.milliseconds(300)

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reduceMotionDidChange() }
        }
    }

    func update(phase: CapturePhase) {
        self.phase = phase
        restart()
    }

    private func reduceMotionDidChange() {
        let current = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard current != reduceMotion else { return }
        reduceMotion = current
        restart()
    }

    private func restart() {
        animation?.cancel()
        animation = nil

        switch phase {
        case .idle, .success, .cancelled:
            assetName = Self.idle
        case .failed:
            assetName = Self.error
        case .listening:
            assetName = Self.listening
            if !reduceMotion {
                animation = Task { [weak self] in await self?.runListening() }
            }
        case .transcribing, .enhancing, .inserting:
            assetName = Self.processing[3]
            if !reduceMotion {
                animation = Task { [weak self] in await self?.runProcessing() }
            }
        }
    }

    private func runListening() async {
        var dimmed = false
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.listeningInterval)
            guard !Task.isCancelled else { return }
            dimmed.toggle()
            assetName = dimmed ? Self.listeningDim : Self.listening
        }
    }

    private func runProcessing() async {
        while !Task.isCancelled {
            for frame in Self.processing {
                guard !Task.isCancelled else { return }
                assetName = frame
                let isLast = frame == Self.processing.last
                try? await Task.sleep(
                    for: isLast ? Self.processingFrameInterval + Self.processingHold : Self.processingFrameInterval
                )
            }
        }
    }
}
