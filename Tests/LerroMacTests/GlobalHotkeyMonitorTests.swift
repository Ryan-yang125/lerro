import CoreGraphics
import Foundation
import Testing
import LerroCore
@testable import LerroMac

@Suite("Global hotkey matching")
struct GlobalHotkeyMonitorTests {
    @Test("Modifier-only hold emits matching lifecycle triggers")
    func modifierOnlyHoldLifecycle() throws {
        let definition = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [definition],
            modifierHoldDelay: 60,
            pointerPressedWithin: { _ in false }
        )
        let down = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        #expect(down.triggers == [HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .armed,
            definitionID: definition.id
        )])
        #expect(down.suppressEvent)
        #expect(
            try #require(monitor.activatePendingModifierForTesting()) == HotkeyTrigger(
                action: .dictate,
                activation: .hold,
                phase: .began,
                definitionID: definition.id
            )
        )
        let up = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(up.triggers == [HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .ended,
            definitionID: definition.id
        )])
    }

    @Test("Modifier-only toggle commits once on release with its definition ID")
    func modifierOnlyToggleLifecycle() {
        let definition = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskAlternate.rawValue,
            activation: .toggle,
            displayName: "Option"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [definition],
            modifierTapTimeout: 60,
            pointerPressedWithin: { _ in false }
        )
        #expect(monitor.process(type: .flagsChanged, keyCode: 58, flags: [.maskAlternate]).triggers == [HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .armed,
            definitionID: definition.id
        )])
        let up = monitor.process(type: .flagsChanged, keyCode: 58, flags: [])
        #expect(up.triggers == [HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: definition.id
        )])
    }

    @Test("Fn chord upgrades ownership from its prefix")
    func fnChordWinsOverFnOnly() {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let chord = HotkeyDefinition(
            action: .translate,
            keyCode: 49,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Space"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn, chord],
            modifierHoldDelay: 60,
            pointerPressedWithin: { _ in false }
        )
        #expect(monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn]).suppressEvent)
        let spaceDown = monitor.process(type: .keyDown, keyCode: 49, flags: [.maskSecondaryFn])
        #expect(spaceDown.suppressEvent)
        #expect(spaceDown.triggers == [HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .disarmed,
            definitionID: fn.id
        ), HotkeyTrigger(
            action: .translate,
            activation: .hold,
            phase: .began,
            definitionID: chord.id
        )])
        #expect(monitor.activatePendingModifierForTesting() == nil)
        let spaceUp = monitor.process(type: .keyUp, keyCode: 49, flags: [.maskSecondaryFn])
        #expect(spaceUp.triggers == [HotkeyTrigger(
            action: .translate,
            activation: .hold,
            phase: .ended,
            definitionID: chord.id
        )])
    }

    @Test("Lerro generated paste events bypass shortcut matching")
    func generatedPasteEventsPassThrough() {
        let paste = HotkeyDefinition(
            action: .pasteLastResult,
            keyCode: 9,
            modifiers: CGEventFlags.maskCommand.rawValue,
            activation: .toggle,
            displayName: "Command V"
        )
        let monitor = GlobalHotkeyMonitor(definitions: [paste], pointerPressedWithin: { _ in false })
        let generatedDown = monitor.process(
            type: .keyDown,
            keyCode: 9,
            flags: [.maskCommand],
            eventSourceUserData: LerroGeneratedEvent.pasteSourceUserData
        )
        #expect(!generatedDown.suppressEvent)
        #expect(generatedDown.triggers.isEmpty)
        let physicalDown = monitor.process(type: .keyDown, keyCode: 9, flags: [.maskCommand])
        #expect(physicalDown.suppressEvent)
        #expect(physicalDown.triggers.map(\.definitionID) == [paste.id])
    }

    @Test("Secure input cancellation drains an already claimed key")
    func secureInputWatchdogCancelsAndDrains() {
        let definition = HotkeyDefinition(action: .dictate, keyCode: 49, activation: .hold, displayName: "Space")
        let monitor = GlobalHotkeyMonitor(definitions: [definition], secureInputCheck: { true })
        #expect(monitor.process(type: .keyDown, keyCode: 49, flags: []).suppressEvent)
        #expect(monitor.pollSecureInputForTesting() == [HotkeyTrigger(
            action: .cancel,
            activation: .toggle,
            phase: .began
        )])
        let up = monitor.process(type: .keyUp, keyCode: 49, flags: [])
        #expect(up.suppressEvent)
        #expect(up.triggers.isEmpty)
    }

    @Test("Tap reset is coalesced and preserves physical drain")
    func tapDisabledRestartIsCoalescedAndDrainsRelease() throws {
        let definition = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let restartProbe = HotkeyRestartProbe()
        let recorder = HotkeyTriggerRecorder()
        let monitor = GlobalHotkeyMonitor(
            definitions: [definition],
            modifierHoldDelay: 60,
            pointerPressedWithin: { _ in false },
            mainQueueScheduler: { work in restartProbe.schedule(work) },
            eventTapRestartInstaller: { restartProbe.recordInstallAttempt() }
        )
        monitor.setHandlerForTesting { recorder.append($0) }
        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        _ = try #require(monitor.activatePendingModifierForTesting())
        let disabledEvent = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: false))
        #expect(!monitor.receive(type: .tapDisabledByTimeout, event: disabledEvent))
        #expect(!monitor.receive(type: .tapDisabledByUserInput, event: disabledEvent))
        #expect(recorder.values().map(\.action) == [.cancel])
        #expect(monitor.process(type: .flagsChanged, keyCode: 63, flags: []).suppressEvent)
        restartProbe.runAll()
        #expect(restartProbe.installAttempts() == 1)
    }

    // MARK: Arming

    @Test("Command toggle arms on press and commits on release")
    func commandToggleArmsThenBegins() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        let down = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        #expect(down.triggers == [Self.trigger(definition, .armed)])
        let up = monitor.process(type: .flagsChanged, keyCode: 55, flags: [])
        #expect(up.triggers == [Self.trigger(definition, .began)])
        #expect(up.triggers.first?.definitionID == definition.id)
    }

    @Test("A key pressed with the modifier disarms and the release emits nothing")
    func comboKeyDisarms() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        let combo = monitor.process(type: .keyDown, keyCode: 8, flags: [.maskCommand])
        #expect(combo.triggers == [Self.trigger(definition, .disarmed)])
        #expect(!combo.suppressEvent)
        let up = monitor.process(type: .flagsChanged, keyCode: 55, flags: [])
        #expect(up.triggers.isEmpty)
    }

    @Test("Command plus held arrow keys disarms and passes every arrow event through")
    func commandArrowDisarms() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        // Arrow events carry the SecondaryFn and NumericPad flags.
        let arrowFlags: CGEventFlags = [.maskCommand, .maskSecondaryFn, .maskNumericPad]
        let right = monitor.process(type: .keyDown, keyCode: 124, flags: arrowFlags)
        #expect(right.triggers == [Self.trigger(definition, .disarmed)])
        #expect(!right.suppressEvent)
        for keyCode: Int64 in [124, 123, 126, 125] {
            let down = monitor.process(type: .keyDown, keyCode: keyCode, flags: arrowFlags)
            #expect(down.triggers.isEmpty)
            #expect(!down.suppressEvent)
            let up = monitor.process(type: .keyUp, keyCode: keyCode, flags: arrowFlags)
            #expect(up.triggers.isEmpty)
            #expect(!up.suppressEvent)
        }
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: []).triggers.isEmpty)
        // The next plain tap still dictates.
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand]).triggers
            == [Self.trigger(definition, .armed)])
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: []).triggers
            == [Self.trigger(definition, .began)])
    }

    @Test("Adding another modifier without a matching shortcut disarms")
    func extraModifierDisarms() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        let shift = monitor.process(type: .flagsChanged, keyCode: 56, flags: [.maskCommand, .maskShift])
        #expect(shift.triggers == [Self.trigger(definition, .disarmed)])
        #expect(monitor.process(type: .flagsChanged, keyCode: 56, flags: [.maskCommand]).triggers.isEmpty)
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: []).triggers.isEmpty)
    }

    @Test("A larger modifier shortcut replaces the armed prefix once")
    func upgradeDisarmsPrefixAndArmsLongerShortcut() {
        let option = Self.toggleDefinition(.dictate, flags: .maskAlternate)
        let optionShift = Self.toggleDefinition(.translate, flags: [.maskAlternate, .maskShift])
        let monitor = Self.monitor([option, optionShift])
        let optionDown = monitor.process(type: .flagsChanged, keyCode: 58, flags: [.maskAlternate])
        #expect(optionDown.triggers == [Self.trigger(option, .armed)])
        let shiftDown = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskAlternate, .maskShift]
        )
        #expect(shiftDown.triggers == [
            Self.trigger(option, .disarmed),
            Self.trigger(optionShift, .armed)
        ])
        let optionUp = monitor.process(type: .flagsChanged, keyCode: 58, flags: [.maskShift])
        #expect(optionUp.triggers == [Self.trigger(optionShift, .began)])
        let shiftUp = monitor.process(type: .flagsChanged, keyCode: 56, flags: [])
        #expect(shiftUp.triggers.isEmpty)
    }

    @Test("Tap timeout disarms a held toggle and the release emits nothing")
    func tapTimeoutDisarms() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        #expect(monitor.expirePendingModifierForTesting() == [Self.trigger(definition, .disarmed)])
        #expect(monitor.expirePendingModifierForTesting().isEmpty)
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: []).triggers.isEmpty)
    }

    @Test("A pointer press during a toggle press disarms instead of beginning")
    func pointerPressCancelsToggle() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition], pointerPressed: true)
        let down = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        #expect(down.triggers == [Self.trigger(definition, .armed)])
        let up = monitor.process(type: .flagsChanged, keyCode: 55, flags: [])
        #expect(up.triggers == [Self.trigger(definition, .disarmed)])
    }

    @Test("Hold arms on press, begins on activation and ends on release")
    func holdArmBeganEnded() throws {
        let definition = Self.holdDefinition(.dictate)
        let monitor = Self.monitor([definition])
        let down = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        #expect(down.triggers == [Self.trigger(definition, .armed)])
        #expect(try #require(monitor.activatePendingModifierForTesting()) == Self.trigger(definition, .began))
        let up = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(up.triggers == [Self.trigger(definition, .ended)])
    }

    @Test("Hold released before activation disarms")
    func holdReleasedBeforeActivationDisarms() {
        let definition = Self.holdDefinition(.dictate)
        let monitor = Self.monitor([definition])
        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        let up = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(up.triggers == [Self.trigger(definition, .disarmed)])
        #expect(monitor.activatePendingModifierForTesting() == nil)
    }

    @Test("A pointer press during a hold disarms at activation")
    func pointerPressCancelsHoldActivation() {
        let definition = Self.holdDefinition(.dictate)
        let monitor = Self.monitor([definition], pointerPressed: true)
        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        #expect(monitor.activatePendingModifierForTesting() == Self.trigger(definition, .disarmed))
        #expect(monitor.process(type: .flagsChanged, keyCode: 63, flags: []).triggers.isEmpty)
    }

    @Test("Escape while armed disarms and cancels")
    func escapeDisarms() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        let escape = monitor.process(type: .keyDown, keyCode: 53, flags: [.maskCommand])
        #expect(escape.triggers == [
            Self.trigger(definition, .disarmed),
            HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)
        ])
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: []).triggers.isEmpty)
    }

    @Test("Transient state reset while armed emits disarmed")
    func resetTransientStateDisarms() {
        let definition = Self.toggleDefinition(.translate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        let recorder = HotkeyTriggerRecorder()
        monitor.setHandlerForTesting { recorder.append($0) }
        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        monitor.resetTransientState()
        #expect(recorder.values() == [Self.trigger(definition, .disarmed)])
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: []).triggers.isEmpty)
    }

    @Test("Stopping while armed emits disarmed")
    func stopDisarms() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        let recorder = HotkeyTriggerRecorder()
        monitor.setHandlerForTesting { recorder.append($0) }
        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        monitor.stop()
        #expect(recorder.values() == [Self.trigger(definition, .disarmed)])
    }

    @Test("Changing definitions while armed emits disarmed")
    func updateDisarms() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        let recorder = HotkeyTriggerRecorder()
        monitor.setHandlerForTesting { recorder.append($0) }
        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        monitor.update(definitions: [])
        #expect(recorder.values() == [Self.trigger(definition, .disarmed)])
    }

    @Test("Paste-last modifier shortcut never arms")
    func pasteLastNeverArms() {
        let definition = Self.toggleDefinition(.pasteLastResult, flags: .maskCommand)
        let monitor = Self.monitor([definition], pointerPressed: true)
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand]).triggers.isEmpty)
        #expect(monitor.process(type: .flagsChanged, keyCode: 55, flags: []).triggers == [
            Self.trigger(definition, .began)
        ])
    }

    @Test("Lerro generated events never arm")
    func generatedEventsNeverArm() {
        let definition = Self.toggleDefinition(.dictate, flags: .maskCommand)
        let monitor = Self.monitor([definition])
        let generated = monitor.process(
            type: .flagsChanged,
            keyCode: 55,
            flags: [.maskCommand],
            eventSourceUserData: LerroGeneratedEvent.pasteSourceUserData
        )
        #expect(generated.triggers.isEmpty)
        #expect(!generated.suppressEvent)
    }

    // MARK: Helpers

    private static func toggleDefinition(
        _ action: HotkeyAction,
        flags: CGEventFlags
    ) -> HotkeyDefinition {
        HotkeyDefinition(
            action: action,
            modifiers: flags.rawValue,
            activation: .toggle,
            displayName: "Modifier"
        )
    }

    private static func holdDefinition(_ action: HotkeyAction) -> HotkeyDefinition {
        HotkeyDefinition(
            action: action,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
    }

    private static func trigger(
        _ definition: HotkeyDefinition,
        _ phase: HotkeyGesturePhase
    ) -> HotkeyTrigger {
        HotkeyTrigger(
            action: definition.action,
            activation: definition.activation,
            phase: phase,
            definitionID: definition.id
        )
    }

    /// Large delays keep real timers from firing during a test.
    private static func monitor(
        _ definitions: [HotkeyDefinition],
        pointerPressed: Bool = false
    ) -> GlobalHotkeyMonitor {
        GlobalHotkeyMonitor(
            definitions: definitions,
            modifierHoldDelay: 60,
            modifierTapTimeout: 60,
            pointerPressedWithin: { _ in pointerPressed }
        )
    }
}

private final class HotkeyTriggerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var triggers: [HotkeyTrigger] = []
    func append(_ trigger: HotkeyTrigger) { lock.withLock { triggers.append(trigger) } }
    func values() -> [HotkeyTrigger] { lock.withLock { triggers } }
}

private final class HotkeyRestartProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var workItems: [@Sendable () -> Void] = []
    private var installs = 0
    func schedule(_ work: @escaping @Sendable () -> Void) { lock.withLock { workItems.append(work) } }
    func recordInstallAttempt() -> Bool { lock.withLock { installs += 1 }; return true }
    func runAll() {
        let scheduled = lock.withLock { () -> [@Sendable () -> Void] in
            defer { workItems.removeAll() }
            return workItems
        }
        scheduled.forEach { $0() }
    }
    func installAttempts() -> Int { lock.withLock { installs } }
}
