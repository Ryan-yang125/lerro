import AppKit
import Testing
@testable import Lerro

@Suite("Shortcut recorder policy")
struct ShortcutRecorderPolicyTests {
    @Test("Single modifiers are accepted")
    func acceptsSingleModifiers() {
        #expect(ShortcutRecorderPolicy.modifierValidationMessage(
            keyCode: 63,
            flags: [.function]
        ) == nil)
        #expect(ShortcutRecorderPolicy.modifierValidationMessage(
            keyCode: 58,
            flags: [.option]
        ) == nil)
        #expect(ShortcutRecorderPolicy.modifierValidationMessage(
            keyCode: 55,
            flags: [.command]
        ) == nil)
    }

    @Test("Caps Lock and combinations longer than three keys are rejected")
    func enforcesModifierLimits() {
        #expect(ShortcutRecorderPolicy.modifierValidationMessage(
            keyCode: 57,
            flags: [.capsLock]
        ) != nil)
        #expect(ShortcutRecorderPolicy.modifierValidationMessage(
            keyCode: 55,
            flags: [.command, .control, .option, .shift]
        ) != nil)
    }

    @Test("Bare typing keys are rejected while modified keys are accepted")
    func protectsOrdinaryTyping() {
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "A",
            keyCode: 0,
            flags: []
        ) != nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "Space",
            keyCode: 49,
            flags: []
        ) != nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "A",
            keyCode: 0,
            flags: [.option]
        ) == nil)
    }

    @Test("Common macOS-reserved shortcuts are rejected")
    func rejectsSystemReservedShortcuts() {
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "Space",
            keyCode: 49,
            flags: [.command]
        ) != nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "⇥",
            keyCode: 48,
            flags: [.command]
        ) != nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "C",
            keyCode: 8,
            flags: [.command]
        ) != nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "Escape",
            keyCode: 53,
            flags: [.command, .option]
        ) != nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "3",
            keyCode: 20,
            flags: [.command, .shift]
        ) != nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "↑",
            keyCode: 126,
            flags: [.control]
        ) != nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "D",
            keyCode: 2,
            flags: [.command, .shift]
        ) == nil)
        #expect(ShortcutRecorderPolicy.keyValidationMessage(
            keyName: "V",
            keyCode: 9,
            flags: [.command, .control]
        ) == nil)
    }
}

@Suite("Shortcut recorder AppKit bridge", .serialized)
struct ShortcutRecorderAppKitTests {
    @Test("Active recorder captures modifier events without taking first responder")
    @MainActor
    func activeRecorderCapturesModifierEventsWithoutTakingFirstResponder() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let content = NSView(frame: window.contentLayoutRect)
        let previous = RecorderTestResponderView(
            frame: NSRect(x: 20, y: 120, width: 120, height: 24)
        )
        let recorder = ShortcutCaptureNSView(frame: NSRect(x: 20, y: 60, width: 1, height: 1))
        content.addSubview(previous)
        content.addSubview(recorder)
        window.contentView = content
        #expect(window.makeFirstResponder(previous))

        var received: [(ShortcutRecorderEvent.Kind, UInt16, NSEvent.ModifierFlags)] = []
        recorder.onEvent = { event in
            received.append((event.kind, event.keyCode, event.modifierFlags))
        }
        recorder.isRecording = true
        #expect(recorder.hasLocalEventMonitor)
        #expect(window.firstResponder === previous)

        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let otherControlDown = try #require(makeRecorderEvent(
            type: .flagsChanged,
            keyCode: 59,
            flags: [.control],
            window: otherWindow
        ))
        NSApplication.shared.sendEvent(otherControlDown)
        #expect(received.isEmpty)

        let controlDown = try #require(makeRecorderEvent(
            type: .flagsChanged,
            keyCode: 59,
            flags: [.control],
            window: window
        ))
        let controlUp = try #require(makeRecorderEvent(
            type: .flagsChanged,
            keyCode: 59,
            flags: [],
            window: window
        ))
        NSApplication.shared.sendEvent(controlDown)
        NSApplication.shared.sendEvent(controlUp)

        #expect(received.count == 2)
        #expect(received[0].0 == .flagsChanged)
        #expect(received[0].1 == 59)
        #expect(received[0].2.contains(.control))
        #expect(received[1].0 == .flagsChanged)
        #expect(received[1].1 == 59)
        #expect(!received[1].2.contains(.control))

        recorder.isRecording = false
        #expect(!recorder.hasLocalEventMonitor)
        NSApplication.shared.sendEvent(controlDown)
        #expect(received.count == 2)

        window.orderOut(nil)
        otherWindow.orderOut(nil)
        RecorderWindowTestLifetime.hold(window)
        RecorderWindowTestLifetime.hold(otherWindow)
    }

    @MainActor
    private func makeRecorderEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        window: NSWindow
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

@MainActor
private enum RecorderWindowTestLifetime {
    private static var windows: [NSWindow] = []

    static func hold(_ window: NSWindow) {
        windows.append(window)
    }
}

private final class RecorderTestResponderView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@Suite("Shortcut recorder reducer")
struct ShortcutRecorderReducerTests {
    @Test("Recorder presentation starts detection immediately")
    func presentationStartsDetectionImmediately() {
        let state = ShortcutRecorderState(startsRecording: true)

        #expect(state.isRecording)
        #expect(state.announcement == "快捷键检测已开始")
    }

    @Test("Fn and Shift retain their peak chord through progressive release")
    func modifierPeakSurvivesProgressiveRelease() {
        var state = ShortcutRecorderState()
        send(.startRecording, to: &state)
        send(.flagsChanged(keyCode: 63, modifiers: raw([.function])), to: &state)
        #expect(state.liveShortcut?.displayName == "Fn")

        send(.flagsChanged(keyCode: 56, modifiers: raw([.function, .shift])), to: &state)
        #expect(state.liveShortcut?.displayName == "Fn ⇧")
        #expect(state.validatedShortcut == nil)

        send(.flagsChanged(keyCode: 56, modifiers: raw([.function])), to: &state)
        #expect(state.liveShortcut?.displayName == "Fn ⇧")
        #expect(state.validatedShortcut == nil)

        send(.flagsChanged(keyCode: 63, modifiers: raw([])), to: &state)
        #expect(state.validatedShortcut?.displayName == "Fn ⇧")
        #expect(state.validatedShortcut?.keyCode == nil)
        #expect(state.isRecording)
        #expect(!state.isPressed)
    }

    @Test("Command Shift D retains the complete chord after every key is released")
    func regularChordPeakSurvivesProgressiveRelease() {
        var state = ShortcutRecorderState()
        send(.startRecording, to: &state)
        send(.flagsChanged(keyCode: 55, modifiers: raw([.command])), to: &state)
        send(.flagsChanged(keyCode: 56, modifiers: raw([.command, .shift])), to: &state)
        send(
            .keyDown(
                keyCode: 2,
                modifiers: raw([.command, .shift]),
                keyName: "D"
            ),
            to: &state
        )
        #expect(state.liveShortcut?.displayName == "⇧⌘D")

        send(.flagsChanged(keyCode: 56, modifiers: raw([.command])), to: &state)
        #expect(state.liveShortcut?.displayName == "⇧⌘D")
        send(.flagsChanged(keyCode: 55, modifiers: raw([])), to: &state)
        #expect(state.liveShortcut?.displayName == "⇧⌘D")
        #expect(state.isPressed)
        send(.keyUp(keyCode: 2, modifiers: raw([])), to: &state)

        #expect(state.validatedShortcut?.displayName == "⇧⌘D")
        #expect(state.validatedShortcut?.keyCode == 2)
        #expect(state.validatedShortcut?.modifiers == raw([.command, .shift]))
    }

    @Test("Fn Space retains Fn after Space releases first")
    func functionChordPeakSurvivesProgressiveRelease() {
        var state = ShortcutRecorderState()
        send(.startRecording, to: &state)
        send(.flagsChanged(keyCode: 63, modifiers: raw([.function])), to: &state)
        send(
            .keyDown(
                keyCode: 49,
                modifiers: raw([.function]),
                keyName: "Space"
            ),
            to: &state
        )
        send(.keyUp(keyCode: 49, modifiers: raw([.function])), to: &state)
        #expect(state.liveShortcut?.displayName == "Fn Space")
        send(.flagsChanged(keyCode: 63, modifiers: raw([])), to: &state)

        #expect(state.validatedShortcut?.displayName == "Fn Space")
        #expect(state.validatedShortcut?.usesFunctionKey == true)
        #expect(state.validatedShortcut?.keyCode == 49)
    }

    @Test("Rejected Command Space never degrades into a saveable Command")
    func invalidChordDoesNotDegradeToModifier() {
        var state = ShortcutRecorderState()
        send(.startRecording, to: &state)
        send(.flagsChanged(keyCode: 55, modifiers: raw([.command])), to: &state)
        #expect(state.liveShortcut?.displayName == "⌘")
        #expect(state.validatedShortcut == nil)

        send(
            .keyDown(
                keyCode: 49,
                modifiers: raw([.command]),
                keyName: "Space"
            ),
            to: &state
        )
        #expect(!state.validationMessage.isEmpty)
        #expect(state.validatedShortcut == nil)

        send(.keyUp(keyCode: 49, modifiers: raw([.command])), to: &state)
        send(.flagsChanged(keyCode: 55, modifiers: raw([])), to: &state)
        #expect(state.validatedShortcut == nil)
        #expect(state.liveShortcut == nil)
        #expect(!state.validationMessage.isEmpty)
    }

    @Test("Inactive recorder ignores navigation keys and remains active after a successful release")
    func explicitActivationControlsEventHandling() {
        var state = ShortcutRecorderState()
        send(
            .keyDown(keyCode: 48, modifiers: raw([]), keyName: "⇥"),
            to: &state
        )
        send(.keyUp(keyCode: 48, modifiers: raw([])), to: &state)
        #expect(state.validatedShortcut == nil)
        #expect(!state.isRecording)

        send(.startRecording, to: &state)
        send(
            .keyDown(keyCode: 36, modifiers: raw([]), keyName: "↩"),
            to: &state
        )
        #expect(state.isPressed)
        send(.keyUp(keyCode: 36, modifiers: raw([])), to: &state)
        #expect(state.validatedShortcut?.displayName == "↩")
        #expect(state.isRecording)

        send(.stopRecording, to: &state)
        #expect(!state.isRecording)
        #expect(!state.isPressed)
    }

    @Test("Rejected test preserves an existing validated shortcut")
    func invalidTestKeepsPreviousValidatedShortcut() {
        let existing = ShortcutBindingDraft(
            keyCode: nil,
            modifiers: raw([.option]),
            usesFunctionKey: false,
            displayName: "⌥"
        )
        var state = ShortcutRecorderState(validatedShortcut: existing)
        send(.startRecording, to: &state)
        send(.flagsChanged(keyCode: 55, modifiers: raw([.command])), to: &state)
        send(
            .keyDown(
                keyCode: 49,
                modifiers: raw([.command]),
                keyName: "Space"
            ),
            to: &state
        )
        send(.keyUp(keyCode: 49, modifiers: raw([.command])), to: &state)
        send(.flagsChanged(keyCode: 55, modifiers: raw([])), to: &state)

        #expect(state.validatedShortcut == existing)
        #expect(!state.validationMessage.isEmpty)
    }

    private func send(
        _ input: ShortcutRecorderInput,
        to state: inout ShortcutRecorderState
    ) {
        ShortcutRecorderReducer.reduce(state: &state, input: input)
    }

    private func raw(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        UInt64(flags.rawValue)
    }
}
