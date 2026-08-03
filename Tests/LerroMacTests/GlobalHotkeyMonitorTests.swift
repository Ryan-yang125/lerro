import CoreGraphics
import Foundation
import Testing
import LerroCore
@testable import LerroMac

@Suite("Global hotkey matching")
struct GlobalHotkeyMonitorTests {
    @Test("Fn plus Space requires the exact Fn modifier")
    func fnSpaceMatchesExactly() {
        let monitor = GlobalHotkeyMonitor(definitions: [
            HotkeyDefinition(
                action: .ask,
                keyCode: 49,
                modifiers: CGEventFlags.maskSecondaryFn.rawValue,
                usesFunctionKey: true,
                displayName: "Fn + Space"
            )
        ])

        #expect(monitor.regularKeyAction(keyCode: 49, flags: []) == nil)
        #expect(monitor.regularKeyAction(keyCode: 49, flags: [.maskShift]) == nil)
        #expect(monitor.regularKeyAction(keyCode: 49, flags: [.maskSecondaryFn]) == .ask)
    }

    @Test("A regular shortcut still requires its exact primary modifiers")
    func regularShortcutMatchesExactly() {
        let monitor = GlobalHotkeyMonitor(definitions: [
            HotkeyDefinition(
                action: .pasteLastResult,
                keyCode: 9,
                modifiers: (CGEventFlags.maskControl.union(.maskCommand)).rawValue,
                displayName: "Control + Command + V"
            )
        ])

        #expect(
            monitor.regularKeyAction(
                keyCode: 9,
                flags: [.maskControl, .maskCommand]
            ) == .pasteLastResult
        )
        #expect(monitor.regularKeyAction(keyCode: 9, flags: [.maskCommand]) == nil)
        #expect(
            monitor.regularKeyAction(
                keyCode: 9,
                flags: [.maskControl, .maskCommand, .maskShift]
            ) == nil
        )
    }

    @Test("Modifier-only hold emits one began and one matching ended signal")
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
            modifierHoldDelay: 60
        )

        let down = monitor.process(
            type: .flagsChanged,
            keyCode: 63,
            flags: [.maskSecondaryFn]
        )
        #expect(down.triggers.isEmpty)
        #expect(down.suppressEvent)

        let began = try #require(monitor.activatePendingModifierForTesting())
        #expect(began == HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: definition.id
        ))

        let up = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(up.triggers == [HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .ended,
            definitionID: definition.id
        )])
    }

    @Test("Modifier-only toggle commits on a clean release")
    func modifierOnlyToggleLifecycle() {
        let definition = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskAlternate.rawValue,
            activation: .toggle,
            displayName: "⌥"
        )
        let monitor = GlobalHotkeyMonitor(definitions: [definition])

        let down = monitor.process(
            type: .flagsChanged,
            keyCode: 58,
            flags: [.maskAlternate]
        )
        #expect(down.triggers.isEmpty)

        let up = monitor.process(type: .flagsChanged, keyCode: 58, flags: [])
        #expect(up.triggers == [HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: definition.id
        )])
    }

    @Test("Fn chord cancels the Fn candidate and swallows its ordinary key")
    func fnChordWinsOverFnOnly() {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let ask = HotkeyDefinition(
            action: .ask,
            keyCode: 49,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Space"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn, ask],
            modifierHoldDelay: 60
        )

        let fnDown = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        #expect(fnDown.suppressEvent)
        let spaceDown = monitor.process(
            type: .keyDown,
            keyCode: 49,
            flags: [.maskSecondaryFn]
        )
        #expect(spaceDown.suppressEvent)
        #expect(spaceDown.triggers == [HotkeyTrigger(
            action: .ask,
            activation: .hold,
            phase: .began,
            definitionID: ask.id
        )])
        #expect(monitor.activatePendingModifierForTesting() == nil)

        let repeated = monitor.process(
            type: .keyDown,
            keyCode: 49,
            flags: [.maskSecondaryFn],
            isRepeat: true
        )
        #expect(repeated.suppressEvent)
        #expect(repeated.triggers.isEmpty)

        let spaceUp = monitor.process(type: .keyUp, keyCode: 49, flags: [.maskSecondaryFn])
        #expect(spaceUp.suppressEvent)
        #expect(spaceUp.triggers == [HotkeyTrigger(
            action: .ask,
            activation: .hold,
            phase: .ended,
            definitionID: ask.id
        )])

        let fnUp = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(fnUp.triggers.isEmpty)
    }

    @Test("System chords pass through without activating a single modifier binding")
    func systemChordDisqualifiesModifierCandidate() {
        let commandOnly = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskCommand.rawValue,
            activation: .hold,
            displayName: "⌘"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [commandOnly],
            modifierHoldDelay: 60
        )

        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        let cDown = monitor.process(type: .keyDown, keyCode: 8, flags: [.maskCommand])
        #expect(cDown.triggers.isEmpty)
        #expect(!cDown.suppressEvent)
        #expect(monitor.activatePendingModifierForTesting() == nil)
        let commandUp = monitor.process(type: .flagsChanged, keyCode: 55, flags: [])
        #expect(commandUp.triggers.isEmpty)
    }

    @Test("A chord added after modifier capture starts cancels the capture")
    func activeModifierIsCancelledByChord() throws {
        let commandOnly = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskCommand.rawValue,
            activation: .hold,
            displayName: "⌘"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [commandOnly],
            modifierHoldDelay: 60
        )

        _ = monitor.process(type: .flagsChanged, keyCode: 55, flags: [.maskCommand])
        _ = try #require(monitor.activatePendingModifierForTesting())
        let cDown = monitor.process(type: .keyDown, keyCode: 8, flags: [.maskCommand])
        #expect(cDown.triggers == [HotkeyTrigger(
            action: .cancel,
            activation: .toggle,
            phase: .began
        )])
        #expect(!cDown.suppressEvent)
    }

    @Test("Updating with identical definitions preserves a held gesture")
    func identicalUpdatePreservesGesture() throws {
        let definition = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [definition],
            modifierHoldDelay: 60
        )

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        _ = try #require(monitor.activatePendingModifierForTesting())
        monitor.update(definitions: [definition])
        let up = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(up.triggers.map(\.phase) == [.ended])
    }

    @Test("Changed definitions cancel an active hold and drain its release")
    func changedDefinitionsCancelActiveHoldAndDrainRelease() {
        let active = HotkeyDefinition(
            action: .dictate,
            keyCode: 97,
            activation: .hold,
            displayName: "F6"
        )
        let replacement = HotkeyDefinition(
            action: .dictate,
            keyCode: 98,
            activation: .hold,
            displayName: "F7"
        )
        let recorder = HotkeyTriggerRecorder()
        let monitor = GlobalHotkeyMonitor(definitions: [active])
        monitor.setHandlerForTesting { recorder.append($0) }

        #expect(monitor.processAndEmitForTesting(
            type: .keyDown,
            keyCode: 97,
            flags: []
        ))
        monitor.update(definitions: [replacement])

        #expect(recorder.values() == [
            HotkeyTrigger(
                action: .dictate,
                activation: .hold,
                phase: .began,
                definitionID: active.id
            ),
            HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)
        ])
        let release = monitor.process(type: .keyUp, keyCode: 97, flags: [])
        #expect(release.suppressEvent)
        #expect(release.triggers.isEmpty)
    }

    @Test("Transient reset drains a claimed toggle key through key-up")
    func transientResetDrainsClaimedToggleKey() {
        let definition = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            activation: .toggle,
            displayName: "Space"
        )
        let monitor = GlobalHotkeyMonitor(definitions: [definition])

        let down = monitor.process(type: .keyDown, keyCode: 49, flags: [])
        #expect(down.suppressEvent)
        #expect(down.triggers == [HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: definition.id
        )])

        monitor.resetTransientState()

        let repeatedDown = monitor.process(
            type: .keyDown,
            keyCode: 49,
            flags: [],
            isRepeat: true
        )
        #expect(repeatedDown.suppressEvent)
        #expect(repeatedDown.triggers.isEmpty)

        let up = monitor.process(type: .keyUp, keyCode: 49, flags: [])
        #expect(up.suppressEvent)
        #expect(up.triggers.isEmpty)

        let nextDown = monitor.process(type: .keyDown, keyCode: 49, flags: [])
        #expect(nextDown.suppressEvent)
        #expect(nextDown.triggers.map(\.definitionID) == [definition.id])
    }

    @Test("Transient reset blocks modifier ghosts until every modifier is released")
    func transientResetDrainsModifierSequence() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let fnShift = HotkeyDefinition(
            action: .translate,
            modifiers: CGEventFlags.maskSecondaryFn.union(.maskShift).rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Shift"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn, fnShift],
            modifierHoldDelay: 60
        )

        let fnDown = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        #expect(fnDown.suppressEvent)
        _ = try #require(monitor.activatePendingModifierForTesting())
        monitor.resetTransientState()

        let shiftDown = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn, .maskShift]
        )
        #expect(shiftDown.triggers.isEmpty)
        #expect(shiftDown.suppressEvent)
        let shiftUp = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn]
        )
        #expect(shiftUp.triggers.isEmpty)
        #expect(shiftUp.suppressEvent)
        let fnUp = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(fnUp.triggers.isEmpty)
        #expect(fnUp.suppressEvent)

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        #expect(try #require(monitor.activatePendingModifierForTesting()).definitionID == fn.id)
    }

    @Test("An active modifier prefix atomically upgrades to a regular chord")
    func activeModifierUpgradesToRegularChord() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let ask = HotkeyDefinition(
            action: .ask,
            keyCode: 49,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Space"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn, ask],
            modifierHoldDelay: 60
        )

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        _ = try #require(monitor.activatePendingModifierForTesting())

        let spaceDown = monitor.process(
            type: .keyDown,
            keyCode: 49,
            flags: [.maskSecondaryFn]
        )
        #expect(spaceDown.suppressEvent)
        #expect(spaceDown.triggers == [
            HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began),
            HotkeyTrigger(
                action: .ask,
                activation: .hold,
                phase: .began,
                definitionID: ask.id
            )
        ])

        let spaceUp = monitor.process(
            type: .keyUp,
            keyCode: 49,
            flags: [.maskSecondaryFn]
        )
        #expect(spaceUp.suppressEvent)
        #expect(spaceUp.triggers == [HotkeyTrigger(
            action: .ask,
            activation: .hold,
            phase: .ended,
            definitionID: ask.id
        )])
    }

    @Test("An active modifier prefix atomically upgrades to a modifier chord")
    func activeModifierUpgradesToModifierChord() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let fnShift = HotkeyDefinition(
            action: .translate,
            modifiers: CGEventFlags.maskSecondaryFn.union(.maskShift).rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Shift"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn, fnShift],
            modifierHoldDelay: 60
        )

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        _ = try #require(monitor.activatePendingModifierForTesting())

        let shiftDown = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn, .maskShift]
        )
        #expect(shiftDown.triggers == [
            HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began),
            HotkeyTrigger(
                action: .translate,
                activation: .hold,
                phase: .began,
                definitionID: fnShift.id
            )
        ])

        let shiftUp = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn]
        )
        #expect(shiftUp.triggers == [HotkeyTrigger(
            action: .translate,
            activation: .hold,
            phase: .ended,
            definitionID: fnShift.id
        )])
        let fnUp = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(fnUp.triggers.isEmpty)
    }

    @Test("Regular chord upgrade survives reset from the prefix cancellation handler")
    func regularUpgradeSurvivesCancellationReset() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let ask = HotkeyDefinition(
            action: .ask,
            keyCode: 49,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Space"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn, ask],
            modifierHoldDelay: 60
        )
        monitor.setHandlerForTesting { trigger in
            if trigger.action == .cancel {
                monitor.resetTransientState()
            }
        }

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        _ = try #require(monitor.activatePendingModifierForTesting())
        #expect(monitor.processAndEmitForTesting(
            type: .keyDown,
            keyCode: 49,
            flags: [.maskSecondaryFn]
        ))

        let up = monitor.process(
            type: .keyUp,
            keyCode: 49,
            flags: [.maskSecondaryFn]
        )
        #expect(up.suppressEvent)
        #expect(up.triggers == [HotkeyTrigger(
            action: .ask,
            activation: .hold,
            phase: .ended,
            definitionID: ask.id
        )])
    }

    @Test("Modifier chord upgrade survives reset from the prefix cancellation handler")
    func modifierUpgradeSurvivesCancellationReset() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let fnShift = HotkeyDefinition(
            action: .translate,
            modifiers: CGEventFlags.maskSecondaryFn.union(.maskShift).rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Shift"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn, fnShift],
            modifierHoldDelay: 60
        )
        monitor.setHandlerForTesting { trigger in
            if trigger.action == .cancel {
                monitor.resetTransientState()
            }
        }

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        _ = try #require(monitor.activatePendingModifierForTesting())
        #expect(monitor.processAndEmitForTesting(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn, .maskShift]
        ))

        let shiftUp = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn]
        )
        #expect(shiftUp.triggers == [HotkeyTrigger(
            action: .translate,
            activation: .hold,
            phase: .ended,
            definitionID: fnShift.id
        )])
    }

    @Test("An invalid modifier extension blocks the prefix until full release")
    func invalidModifierExtensionBlocksUntilRelease() {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .toggle,
            displayName: "Fn"
        )
        let monitor = GlobalHotkeyMonitor(definitions: [fn])

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        let shiftDown = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn, .maskShift]
        )
        #expect(shiftDown.triggers.isEmpty)
        let shiftUp = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn]
        )
        #expect(shiftUp.triggers.isEmpty)
        let fnUp = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(fnUp.triggers.isEmpty)

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        let cleanRelease = monitor.process(type: .flagsChanged, keyCode: 63, flags: [])
        #expect(cleanRelease.triggers.map(\.definitionID) == [fn.id])
    }

    @Test("A pending modifier can upgrade to an exact modifier definition")
    func pendingModifierUpgradesToExactDefinition() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let fnShift = HotkeyDefinition(
            action: .translate,
            modifiers: CGEventFlags.maskSecondaryFn.union(.maskShift).rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Shift"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn, fnShift],
            modifierHoldDelay: 60
        )

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        let shiftDown = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn, .maskShift]
        )
        #expect(shiftDown.triggers.isEmpty)
        #expect(try #require(monitor.activatePendingModifierForTesting()).definitionID == fnShift.id)
    }

    @Test("Pointer scroll and system events disqualify modifier gestures and pass through")
    func nonKeyboardEventsInterruptModifierGestures() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let eventTypes: [CGEventType] = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            GlobalHotkeyMonitor.systemDefinedEventType
        ]

        for type in eventTypes {
            let pendingMonitor = GlobalHotkeyMonitor(
                definitions: [fn],
                modifierHoldDelay: 60
            )
            _ = pendingMonitor.process(
                type: .flagsChanged,
                keyCode: 63,
                flags: [.maskSecondaryFn]
            )
            let pendingInterruption = pendingMonitor.process(
                type: type,
                keyCode: 0,
                flags: [.maskSecondaryFn]
            )
            #expect(!pendingInterruption.suppressEvent)
            #expect(pendingInterruption.triggers.isEmpty)
            #expect(pendingMonitor.activatePendingModifierForTesting() == nil)
            let pendingRelease = pendingMonitor.process(
                type: .flagsChanged,
                keyCode: 63,
                flags: []
            )
            #expect(pendingRelease.triggers.isEmpty)

            let activeMonitor = GlobalHotkeyMonitor(
                definitions: [fn],
                modifierHoldDelay: 60
            )
            _ = activeMonitor.process(
                type: .flagsChanged,
                keyCode: 63,
                flags: [.maskSecondaryFn]
            )
            _ = try #require(activeMonitor.activatePendingModifierForTesting())
            let activeInterruption = activeMonitor.process(
                type: type,
                keyCode: 0,
                flags: [.maskSecondaryFn]
            )
            #expect(!activeInterruption.suppressEvent)
            #expect(activeInterruption.triggers == [HotkeyTrigger(
                action: .cancel,
                activation: .toggle,
                phase: .began
            )])
        }
    }

    @Test("Idle pointer events bypass system probes")
    func idlePointerEventsUseFastPath() throws {
        let probe = HotkeySystemCallProbe()
        let monitor = GlobalHotkeyMonitor(
            definitions: [],
            secureInputCheck: { probe.checkSecureInput() },
            physicalModifierFlags: { probe.readModifierFlags() },
            physicalKeyState: { probe.readKeyState($0) }
        )

        for type in [
            CGEventType.leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel
        ] {
            let event = try #require(CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: true
            ))
            event.flags = []
            #expect(!monitor.receive(type: type, event: event))
        }

        #expect(probe.secureInputChecks() == 0)
        #expect(probe.modifierFlagReads() == 0)
        #expect(probe.keyStateReads() == 0)
    }

    @Test("Idle scroll defers Secure Input recovery to the watchdog")
    func idleScrollSkipsPhysicalRecovery() throws {
        let probe = HotkeySystemCallProbe(secureInput: true)
        let monitor = GlobalHotkeyMonitor(
            definitions: [],
            secureInputCheck: { probe.checkSecureInput() },
            physicalModifierFlags: { probe.readModifierFlags() },
            physicalKeyState: { probe.readKeyState($0) }
        )

        #expect(monitor.pollSecureInputForTesting().map(\.action) == [.cancel])
        probe.setSecureInput(false)

        let event = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ))
        event.flags = []
        #expect(!monitor.receive(type: .scrollWheel, event: event))
        #expect(probe.secureInputChecks() == 1)
        #expect(probe.modifierFlagReads() == 0)
        #expect(probe.keyStateReads() == 0)

        #expect(monitor.pollSecureInputForTesting().isEmpty)
        #expect(probe.secureInputChecks() == 2)
        #expect(probe.modifierFlagReads() == 1)
    }

    @Test("Pointer events still cancel pending and active modifier gestures")
    func pointerEventsPreserveModifierInterruption() throws {
        let definition = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )

        let pendingMonitor = GlobalHotkeyMonitor(
            definitions: [definition],
            modifierHoldDelay: 60,
            secureInputCheck: { false }
        )
        _ = pendingMonitor.process(
            type: .flagsChanged,
            keyCode: 63,
            flags: [.maskSecondaryFn]
        )
        let pendingEvent = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ))
        pendingEvent.flags = [.maskSecondaryFn]
        #expect(!pendingMonitor.receive(type: .leftMouseDown, event: pendingEvent))
        #expect(pendingMonitor.activatePendingModifierForTesting() == nil)

        let recorder = HotkeyTriggerRecorder()
        let activeMonitor = GlobalHotkeyMonitor(
            definitions: [definition],
            modifierHoldDelay: 60,
            secureInputCheck: { false }
        )
        activeMonitor.setHandlerForTesting { recorder.append($0) }
        _ = activeMonitor.process(
            type: .flagsChanged,
            keyCode: 63,
            flags: [.maskSecondaryFn]
        )
        _ = try #require(activeMonitor.activatePendingModifierForTesting())
        let activeEvent = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ))
        activeEvent.flags = [.maskSecondaryFn]
        #expect(!activeMonitor.receive(type: .scrollWheel, event: activeEvent))
        #expect(recorder.values() == [HotkeyTrigger(
            action: .cancel,
            activation: .toggle,
            phase: .began
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
        let generatedUp = monitor.process(
            type: .keyUp,
            keyCode: 9,
            flags: [.maskCommand],
            eventSourceUserData: LerroGeneratedEvent.pasteSourceUserData
        )
        #expect(!generatedUp.suppressEvent)
        #expect(generatedUp.triggers.isEmpty)

        let physicalDown = monitor.process(
            type: .keyDown,
            keyCode: 9,
            flags: [.maskCommand]
        )
        #expect(physicalDown.suppressEvent)
        #expect(physicalDown.triggers.map(\.definitionID) == [paste.id])
    }

    @Test("Secure input watchdog cancels logical capture and drains the claimed key")
    func secureInputWatchdogCancelsAndDrains() {
        let definition = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            activation: .hold,
            displayName: "Space"
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [definition],
            secureInputCheck: { true }
        )

        let down = monitor.process(type: .keyDown, keyCode: 49, flags: [])
        #expect(down.suppressEvent)
        let interruption = monitor.pollSecureInputForTesting()
        #expect(interruption == [HotkeyTrigger(
            action: .cancel,
            activation: .toggle,
            phase: .began
        )])
        #expect(monitor.pollSecureInputForTesting().isEmpty)

        let up = monitor.process(type: .keyUp, keyCode: 49, flags: [])
        #expect(up.suppressEvent)
        #expect(up.triggers.isEmpty)
    }

    @Test("Secure input transition emits one cancellation for toggle capture")
    func secureInputWatchdogSignalsToggleCapture() {
        let monitor = GlobalHotkeyMonitor(secureInputCheck: { true })

        #expect(monitor.pollSecureInputForTesting() == [HotkeyTrigger(
            action: .cancel,
            activation: .toggle,
            phase: .began
        )])
        #expect(monitor.pollSecureInputForTesting().isEmpty)
    }

    @Test("Secure input end reconciles lost releases from physical state")
    func secureInputEndReconcilesLostReleases() {
        let fnSpace = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .toggle,
            displayName: "Fn Space"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: true,
            modifierFlags: [.maskSecondaryFn],
            downKeyCodes: [49]
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fnSpace],
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        let firstDown = monitor.process(
            type: .keyDown,
            keyCode: 49,
            flags: [.maskSecondaryFn]
        )
        #expect(firstDown.suppressEvent)
        #expect(monitor.pollSecureInputForTesting().map(\.action) == [.cancel])

        // Secure Event Input can hide both release events from the tap.
        probe.update(secureInput: false, modifierFlags: [], downKeyCodes: [])
        #expect(monitor.pollSecureInputForTesting().isEmpty)

        _ = monitor.process(type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
        let nextDown = monitor.process(
            type: .keyDown,
            keyCode: 49,
            flags: [.maskSecondaryFn]
        )
        #expect(nextDown.suppressEvent)
        #expect(nextDown.triggers.map(\.definitionID) == [fnSpace.id])
    }

    @Test("First non-repeat key down after Secure Input is reprocessed")
    func firstNonRepeatKeyDownAfterSecureInputIsReprocessed() throws {
        let space = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            activation: .toggle,
            displayName: "Space"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: false,
            modifierFlags: [],
            downKeyCodes: []
        )
        let recorder = HotkeyTriggerRecorder()
        let monitor = GlobalHotkeyMonitor(
            definitions: [space],
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )
        monitor.setHandlerForTesting { recorder.append($0) }

        let firstDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 49,
            keyDown: true
        ))
        firstDown.flags = []
        #expect(monitor.receive(type: .keyDown, event: firstDown))

        probe.update(secureInput: true, modifierFlags: [], downKeyCodes: [49])
        #expect(monitor.pollSecureInputForTesting().map(\.action) == [.cancel])

        // Secure Input hid the old release. The key is already down again when
        // the first visible post-secure event arrives.
        probe.update(secureInput: false, modifierFlags: [], downKeyCodes: [49])
        let freshDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 49,
            keyDown: true
        ))
        freshDown.flags = []
        #expect(monitor.receive(type: .keyDown, event: freshDown))
        #expect(recorder.values().map(\.definitionID) == [space.id, space.id])
    }

    @Test("Watchdog-first Secure Input recovery still accepts a fresh same-key down")
    func watchdogFirstRecoveryAcceptsFreshSameKeyDown() throws {
        let space = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            activation: .toggle,
            displayName: "Space"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: false,
            modifierFlags: [],
            downKeyCodes: []
        )
        let recorder = HotkeyTriggerRecorder()
        let monitor = GlobalHotkeyMonitor(
            definitions: [space],
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )
        monitor.setHandlerForTesting { recorder.append($0) }

        let firstDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 49,
            keyDown: true
        ))
        firstDown.flags = []
        #expect(monitor.receive(type: .keyDown, event: firstDown))

        probe.update(secureInput: true, modifierFlags: [], downKeyCodes: [49])
        #expect(monitor.pollSecureInputForTesting().map(\.action) == [.cancel])

        // The watchdog observes Secure Input ending while the same physical key
        // is down again, before its fresh keyDown reaches the event tap.
        probe.update(secureInput: false, modifierFlags: [], downKeyCodes: [49])
        #expect(monitor.pollSecureInputForTesting().isEmpty)
        let freshDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 49,
            keyDown: true
        ))
        freshDown.flags = []
        #expect(monitor.receive(type: .keyDown, event: freshDown))
        #expect(recorder.values().map(\.definitionID) == [space.id, space.id])
    }

    @Test("First modified key down after Secure Input is reprocessed")
    func firstModifiedNonRepeatKeyDownAfterSecureInputIsReprocessed() throws {
        let fnSpace = HotkeyDefinition(
            action: .ask,
            keyCode: 49,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .toggle,
            displayName: "Fn Space"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: false,
            modifierFlags: [.maskSecondaryFn],
            downKeyCodes: [49]
        )
        let recorder = HotkeyTriggerRecorder()
        let monitor = GlobalHotkeyMonitor(
            definitions: [fnSpace],
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )
        monitor.setHandlerForTesting { recorder.append($0) }

        #expect(monitor.processAndEmitForTesting(
            type: .keyDown,
            keyCode: 49,
            flags: [.maskSecondaryFn]
        ))
        probe.update(
            secureInput: true,
            modifierFlags: [.maskSecondaryFn],
            downKeyCodes: [49]
        )
        #expect(monitor.pollSecureInputForTesting().map(\.action) == [.cancel])

        // Both old releases were hidden, and a new Fn-Space is already down
        // when the event tap resumes.
        probe.update(
            secureInput: false,
            modifierFlags: [.maskSecondaryFn],
            downKeyCodes: [49]
        )
        let freshDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 49,
            keyDown: true
        ))
        freshDown.flags = [.maskSecondaryFn]
        #expect(monitor.receive(type: .keyDown, event: freshDown))
        #expect(recorder.values().map(\.definitionID) == [fnSpace.id, fnSpace.id])
    }

    @Test("First modifier down after Secure Input starts a new candidate")
    func firstModifierDownAfterSecureInputStartsNewCandidate() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: false,
            modifierFlags: [.maskSecondaryFn],
            downKeyCodes: []
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn],
            modifierHoldDelay: 60,
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )

        _ = monitor.process(
            type: .flagsChanged,
            keyCode: 63,
            flags: [.maskSecondaryFn]
        )
        _ = try #require(monitor.activatePendingModifierForTesting())
        probe.update(
            secureInput: true,
            modifierFlags: [.maskSecondaryFn],
            downKeyCodes: []
        )
        #expect(monitor.pollSecureInputForTesting().map(\.action) == [.cancel])

        probe.update(
            secureInput: false,
            modifierFlags: [.maskSecondaryFn],
            downKeyCodes: [63]
        )
        let freshFnDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 63,
            keyDown: true
        ))
        freshFnDown.flags = [.maskSecondaryFn]
        #expect(monitor.receive(type: .flagsChanged, event: freshFnDown))
        #expect(monitor.activatePendingModifierForTesting() == HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: fn.id
        ))
    }

    @Test("Releasing one side of a shared modifier after Secure Input keeps draining")
    func sameModifierSideReleaseAfterSecureInputDoesNotStartCandidate() throws {
        let shift = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskShift.rawValue,
            activation: .hold,
            displayName: "Shift"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: false,
            modifierFlags: [.maskShift],
            downKeyCodes: [56, 60]
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [shift],
            modifierHoldDelay: 60,
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )

        _ = monitor.process(type: .flagsChanged, keyCode: 56, flags: [.maskShift])
        _ = try #require(monitor.activatePendingModifierForTesting())
        probe.update(
            secureInput: true,
            modifierFlags: [.maskShift],
            downKeyCodes: [56, 60]
        )
        #expect(monitor.pollSecureInputForTesting().map(\.action) == [.cancel])

        // Left Shift is released while Right Shift remains down. The aggregate
        // Shift flag stays set, so the specific physical key state decides the
        // direction of this flagsChanged event.
        probe.update(
            secureInput: false,
            modifierFlags: [.maskShift],
            downKeyCodes: [60]
        )
        let leftShiftUp = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 56,
            keyDown: false
        ))
        leftShiftUp.flags = [.maskShift]
        #expect(!monitor.receive(type: .flagsChanged, event: leftShiftUp))
        #expect(monitor.activatePendingModifierForTesting() == nil)

        probe.update(secureInput: false, modifierFlags: [], downKeyCodes: [])
        let rightShiftUp = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 60,
            keyDown: false
        ))
        rightShiftUp.flags = []
        #expect(monitor.receive(type: .flagsChanged, event: rightShiftUp))

        probe.update(
            secureInput: false,
            modifierFlags: [.maskShift],
            downKeyCodes: [56]
        )
        let freshLeftShiftDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 56,
            keyDown: true
        ))
        freshLeftShiftDown.flags = [.maskShift]
        #expect(monitor.receive(type: .flagsChanged, event: freshLeftShiftDown))
        #expect(monitor.activatePendingModifierForTesting()?.definitionID == shift.id)
    }

    @Test("Partial modifier release after Secure Input stays in physical drain")
    func partialModifierReleaseAfterSecureInputDoesNotStartCandidate() throws {
        let fn = HotkeyDefinition(
            action: .dictate,
            modifiers: CGEventFlags.maskSecondaryFn.rawValue,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: false,
            modifierFlags: [.maskSecondaryFn, .maskShift],
            downKeyCodes: []
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [fn],
            modifierHoldDelay: 60,
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )

        _ = monitor.process(
            type: .flagsChanged,
            keyCode: 63,
            flags: [.maskSecondaryFn]
        )
        _ = monitor.process(
            type: .flagsChanged,
            keyCode: 56,
            flags: [.maskSecondaryFn, .maskShift]
        )
        probe.update(
            secureInput: true,
            modifierFlags: [.maskSecondaryFn, .maskShift],
            downKeyCodes: []
        )
        #expect(monitor.pollSecureInputForTesting().map(\.action) == [.cancel])

        // Shift was released while Secure Input was active. The first visible
        // event is that partial release, so the older Fn press remains drained.
        probe.update(
            secureInput: false,
            modifierFlags: [.maskSecondaryFn],
            downKeyCodes: []
        )
        let shiftUp = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 56,
            keyDown: false
        ))
        shiftUp.flags = [.maskSecondaryFn]
        #expect(!monitor.receive(type: .flagsChanged, event: shiftUp))
        #expect(monitor.activatePendingModifierForTesting() == nil)

        let fnUp = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 63,
            keyDown: false
        ))
        fnUp.flags = []
        #expect(monitor.receive(type: .flagsChanged, event: fnUp))

        let freshFnDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 63,
            keyDown: true
        ))
        freshFnDown.flags = [.maskSecondaryFn]
        #expect(monitor.receive(type: .flagsChanged, event: freshFnDown))
        #expect(monitor.activatePendingModifierForTesting()?.definitionID == fn.id)
    }

    @Test("Secure Input recovery keeps draining an old repeat")
    func secureInputRecoveryContinuesDrainingOldRepeat() throws {
        let space = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            activation: .toggle,
            displayName: "Space"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: false,
            modifierFlags: [],
            downKeyCodes: []
        )
        let recorder = HotkeyTriggerRecorder()
        let monitor = GlobalHotkeyMonitor(
            definitions: [space],
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )
        monitor.setHandlerForTesting { recorder.append($0) }

        let firstDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 49,
            keyDown: true
        ))
        firstDown.flags = []
        #expect(monitor.receive(type: .keyDown, event: firstDown))
        probe.update(secureInput: true, modifierFlags: [], downKeyCodes: [49])
        _ = monitor.pollSecureInputForTesting()
        probe.update(secureInput: false, modifierFlags: [], downKeyCodes: [49])

        let repeatedDown = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 49,
            keyDown: true
        ))
        repeatedDown.flags = []
        repeatedDown.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(monitor.receive(type: .keyDown, event: repeatedDown))
        #expect(recorder.values().map(\.definitionID) == [space.id])
    }

    @Test("First claimed key-up after secure input still stays swallowed")
    func secureInputRecoverySwallowsClaimedKeyUp() throws {
        let space = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            activation: .toggle,
            displayName: "Space"
        )
        let probe = HotkeyPhysicalStateProbe(
            secureInput: true,
            modifierFlags: [],
            downKeyCodes: [49]
        )
        let monitor = GlobalHotkeyMonitor(
            definitions: [space],
            secureInputCheck: { probe.isSecureInputEnabled() },
            physicalModifierFlags: { probe.modifierFlags() },
            physicalKeyState: { probe.isKeyDown($0) }
        )

        _ = monitor.process(type: .keyDown, keyCode: 49, flags: [])
        _ = monitor.pollSecureInputForTesting()
        probe.update(secureInput: false, modifierFlags: [], downKeyCodes: [])

        let keyUp = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 49,
            keyDown: false
        ))
        #expect(monitor.receive(type: .keyUp, event: keyUp))

        let nextDown = monitor.process(type: .keyDown, keyCode: 49, flags: [])
        #expect(nextDown.suppressEvent)
        #expect(nextDown.triggers.map(\.definitionID) == [space.id])
    }

    @Test("Stop clears physical drain ownership")
    func stopClearsClaimedKeys() {
        let definition = HotkeyDefinition(
            action: .dictate,
            keyCode: 49,
            activation: .toggle,
            displayName: "Space"
        )
        let monitor = GlobalHotkeyMonitor(definitions: [definition])

        _ = monitor.process(type: .keyDown, keyCode: 49, flags: [])
        monitor.resetTransientState()
        monitor.stop()

        let up = monitor.process(type: .keyUp, keyCode: 49, flags: [])
        #expect(!up.suppressEvent)
        #expect(up.triggers.isEmpty)
    }
}

private final class HotkeyTriggerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var triggers: [HotkeyTrigger] = []

    func append(_ trigger: HotkeyTrigger) {
        lock.withLock { triggers.append(trigger) }
    }

    func values() -> [HotkeyTrigger] {
        lock.withLock { triggers }
    }
}

private final class HotkeyPhysicalStateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var secureInput: Bool
    private var flags: CGEventFlags
    private var downKeyCodes: Set<CGKeyCode>

    init(
        secureInput: Bool,
        modifierFlags: CGEventFlags,
        downKeyCodes: Set<CGKeyCode>
    ) {
        self.secureInput = secureInput
        flags = modifierFlags
        self.downKeyCodes = downKeyCodes
    }

    func update(
        secureInput: Bool,
        modifierFlags: CGEventFlags,
        downKeyCodes: Set<CGKeyCode>
    ) {
        lock.lock()
        self.secureInput = secureInput
        flags = modifierFlags
        self.downKeyCodes = downKeyCodes
        lock.unlock()
    }

    func isSecureInputEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return secureInput
    }

    func modifierFlags() -> CGEventFlags {
        lock.lock()
        defer { lock.unlock() }
        return flags
    }

    func isKeyDown(_ keyCode: CGKeyCode) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return downKeyCodes.contains(keyCode)
    }
}

private final class HotkeySystemCallProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var secureInput: Bool
    private var secureInputCheckCount = 0
    private var modifierFlagReadCount = 0
    private var keyStateReadCount = 0

    init(secureInput: Bool = false) {
        self.secureInput = secureInput
    }

    func setSecureInput(_ enabled: Bool) {
        lock.lock()
        secureInput = enabled
        lock.unlock()
    }

    func checkSecureInput() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        secureInputCheckCount += 1
        return secureInput
    }

    func readModifierFlags() -> CGEventFlags {
        lock.lock()
        defer { lock.unlock() }
        modifierFlagReadCount += 1
        return []
    }

    func readKeyState(_ keyCode: CGKeyCode) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        keyStateReadCount += 1
        return false
    }

    func secureInputChecks() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return secureInputCheckCount
    }

    func modifierFlagReads() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return modifierFlagReadCount
    }

    func keyStateReads() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return keyStateReadCount
    }
}
