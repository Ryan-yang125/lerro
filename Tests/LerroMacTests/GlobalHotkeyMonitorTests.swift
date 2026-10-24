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
        let monitor = GlobalHotkeyMonitor(definitions: [definition], modifierHoldDelay: 60)
        let down = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        #expect(down.triggers.isEmpty)
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
        let monitor = GlobalHotkeyMonitor(definitions: [definition])
        #expect(monitor.process(type: .flagsChanged, keyCode: 58, flags: [.maskAlternate]).triggers.isEmpty)
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
        let monitor = GlobalHotkeyMonitor(definitions: [fn, chord], modifierHoldDelay: 60)
        #expect(monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn]).suppressEvent)
        let spaceDown = monitor.process(type: .keyDown, keyCode: 49, flags: [.maskSecondaryFn])
        #expect(spaceDown.suppressEvent)
        #expect(spaceDown.triggers == [HotkeyTrigger(
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
        let monitor = GlobalHotkeyMonitor(definitions: [paste])
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
