import Foundation
import Testing
import LerroCore
@testable import Lerro

@Suite("Menu bar panel presentation")
struct MenuBarPanelPresentationTests {
    typealias Presentation = MenuBarPanelPresentation

    @Test("Status follows permissions first, then the capture phase", arguments: [
        (CapturePhase.idle, true, true, Presentation.Status.ready),
        (.success, true, true, .ready),
        (.cancelled, true, true, .ready),
        (.listening, true, true, .listening),
        (.transcribing, true, true, .processing),
        (.enhancing, true, true, .processing),
        (.inserting, true, true, .processing),
        (.failed, true, true, .failed),
        (.idle, false, true, .permission),
        (.idle, true, false, .permission),
        (.failed, false, false, .permission)
    ])
    func status(phase: CapturePhase, microphone: Bool, accessibility: Bool, expected: Presentation.Status) {
        #expect(Presentation.status(
            phase: phase,
            microphoneGranted: microphone,
            accessibilityGranted: accessibility
        ) == expected)
    }

    @Test("Missing permissions list the microphone before accessibility")
    func missingPermissions() {
        #expect(Presentation.missingPermissions(microphoneGranted: true, accessibilityGranted: true).isEmpty)
        #expect(Presentation.missingPermissions(microphoneGranted: false, accessibilityGranted: true) == [.microphone])
        #expect(Presentation.missingPermissions(microphoneGranted: true, accessibilityGranted: false) == [.accessibility])
        #expect(Presentation.missingPermissions(microphoneGranted: false, accessibilityGranted: false)
            == [.microphone, .accessibility])
    }

    @Test("Tiles start when idle, finish or cancel while listening, and disable while processing")
    func tiles() {
        func tile(
            _ mode: CaptureMode,
            _ phase: CapturePhase,
            active: CaptureMode = .dictation,
            granted: Bool = true
        ) -> Presentation.Tile {
            Presentation.tile(for: mode, phase: phase, activeMode: active, permissionsGranted: granted)
        }

        #expect(tile(.dictation, .idle) == .start)
        #expect(tile(.translation, .failed) == .start)
        #expect(tile(.dictation, .idle, granted: false) == .disabled)
        #expect(tile(.dictation, .listening) == .finish)
        #expect(tile(.translation, .listening) == .cancel)
        #expect(tile(.dictation, .listening, active: .translation) == .cancel)
        #expect(tile(.translation, .listening, active: .translation) == .finish)
        #expect(tile(.dictation, .listening, active: .ask) == .finish)
        #expect(tile(.translation, .listening, active: .ask) == .cancel)
        #expect(tile(.dictation, .transcribing) == .disabled)
        #expect(tile(.translation, .enhancing) == .disabled)
        #expect(tile(.dictation, .inserting) == .disabled)
    }

    @Test("Elapsed time formats as minutes and zero-padded seconds", arguments: [
        (0.0, "0:00"), (12.9, "0:12"), (65, "1:05"), (600, "10:00"), (-3, "0:00")
    ])
    func elapsed(seconds: TimeInterval, expected: String) {
        #expect(Presentation.elapsedText(seconds) == expected)
    }
}
