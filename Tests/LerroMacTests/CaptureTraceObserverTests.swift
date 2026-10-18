import CoreGraphics
import Foundation
import Testing
import LerroCore
@testable import LerroMac

@Suite("Capture trace observer")
struct CaptureTraceObserverTests {
    private func makeTrace() -> CaptureTrace {
        let origin = ContinuousClock.now
        var trace = CaptureTrace(
            id: UUID(),
            mode: .dictation,
            intelligenceMode: .remote,
            pressedAt: origin,
            handledAt: origin.advanced(by: .milliseconds(121))
        )
        trace.mark(.speechStartRequested, at: origin.advanced(by: .milliseconds(200)))
        trace.mark(.listening, at: origin.advanced(by: .milliseconds(412)))
        trace.mark(.stopRequested, at: origin.advanced(by: .milliseconds(2_000)))
        trace.processingRoute = .remote
        trace.finish(.completed, at: origin.advanced(by: .milliseconds(2_500)))
        return trace
    }

    @Test("Summary line lists reached segments only")
    func summaryLine() {
        let line = OSLogCaptureTraceObserver.summaryLine(for: makeTrace())
        #expect(line.contains("readyToSpeak=412ms"))
        #expect(line.contains("hotkeyDispatch=121ms"))
        #expect(line.contains("outcome=completed"))
        #expect(line.contains("route=remote"))
        #expect(line.contains("mode=dictation"))
        #expect(line.contains("intelligence=remote"))
        #expect(line.contains("error=-"))
        #expect(!line.contains("firstAudio="))
        #expect(!line.contains("firstPartial="))
        #expect(!line.contains("transcription="))
    }

    @Test("Steps line lists adjacent reached milestones")
    func stepsLine() {
        let line = OSLogCaptureTraceObserver.stepsLine(for: makeTrace())
        #expect(line.contains("hotkeyPressed>hotkeyHandled=121ms"))
        #expect(!line.contains("hudArmed>permissionsChecked"))
    }

    @Test("Regular key-down began trigger carries a press time and key-up does not")
    func regularKeyPressedAt() throws {
        let definition = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            modifiers: CGEventFlags.maskCommand.rawValue,
            activation: .hold,
            displayName: "Command Space"
        )
        let monitor = GlobalHotkeyMonitor(definitions: [definition], modifierHoldDelay: 60)
        let down = monitor.process(type: .keyDown, keyCode: 49, flags: [.maskCommand])
        let began = try #require(down.triggers.first)
        #expect(began.phase == .began)
        #expect(began.pressedAt != nil)
        let up = monitor.process(type: .keyUp, keyCode: 49, flags: [.maskCommand])
        let ended = try #require(up.triggers.first)
        #expect(ended.phase == .ended)
        #expect(ended.pressedAt == nil)
    }
}
