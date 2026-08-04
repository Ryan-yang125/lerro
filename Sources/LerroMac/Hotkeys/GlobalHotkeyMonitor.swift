import Carbon
import CoreGraphics
import Foundation
import LerroCore

enum LerroGeneratedEvent {
    /// ASCII `LERROPST`. A fixed, process-independent value lets the global
    /// monitor recognize the Command-V pair produced by text delivery.
    static let pasteSourceUserData: Int64 = 0x4C45_5252_4F50_5354
}

public final class GlobalHotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    private struct ProcessingResult {
        enum UpgradeContinuation {
            case regular(keyCode: Int64, definition: HotkeyDefinition)
            case modifier(definition: HotkeyDefinition)
        }

        enum ModifierTimerDirective {
            case none
            case cancel
            case schedule(definitionID: String)
        }

        var triggers: [HotkeyTrigger] = []
        var suppressEvent = false
        var timerDirective: ModifierTimerDirective = .none
        var upgradeContinuation: UpgradeContinuation?
    }

    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapRestartPending = false
    private var eventTapRestartGeneration: UInt64 = 0
    private var secureInputWatchdog: DispatchSourceTimer?
    private var handler: (@Sendable (HotkeyTrigger) -> Void)?
    private var definitions: [HotkeyDefinition]

    // The event tap is installed on the main run loop. AppSession also calls
    // lifecycle methods from MainActor, keeping this gesture state serialized.
    private var currentModifierFlags: CGEventFlags = []
    private var pendingModifierDefinition: HotkeyDefinition?
    private var activeModifierDefinition: HotkeyDefinition?
    private var activeKeyDefinitions: [Int64: HotkeyDefinition] = [:]
    private var claimedKeyCodes: Set<Int64> = []
    /// Exact modifier key codes currently held in the physical event stream.
    /// Aggregate flags remain the shortcut-matching input because left/right
    /// modifier variants share the same semantic flag.
    private var pressedModifierKeyCodes: Set<Int64> = []
    /// Physical modifier keys claimed by an active modifier-only shortcut.
    /// Fn/Globe can produce flagsChanged plus keyboard events for the same
    /// press, so ownership is keyCode-based rather than inferred solely from
    /// aggregate flags.
    private var claimedModifierKeyCodes: Set<Int64> = []
    /// A configured modifier shortcut owns every keyboard event from its first
    /// physical press through the matching final modifier release. This keeps
    /// Fn/Globe from receiving a trailing event after Lerro accepted it.
    private var modifierSequenceOwned = false
    private var modifierSequenceBlocked = false
    private var physicalDrainRequested = false
    private var pendingModifierActivation: DispatchWorkItem?
    private var modifierTimerGeneration: UInt64 = 0
    private var secureInputObserved = false
    private var secureInputRecoveryPending = false

    private let modifierHoldDelay: TimeInterval
    private let secureInputPollInterval: TimeInterval
    private let secureInputCheck: @Sendable () -> Bool
    private let physicalModifierFlags: @Sendable () -> CGEventFlags
    private let physicalKeyState: @Sendable (CGKeyCode) -> Bool
    private let mainQueueScheduler: @Sendable (@escaping @Sendable () -> Void) -> Void
    private let eventTapRestartInstaller: (@Sendable () -> Bool)?

    private static let primaryModifiers: CGEventFlags = [
        .maskCommand,
        .maskControl,
        .maskAlternate,
        .maskShift,
        .maskSecondaryFn
    ]

    /// The active HID tap only observes physical keyboard lifecycle events.
    /// Pointer and system-defined events retain their native routing and never
    /// alter shortcut ownership.
    static let monitoredEventTypes: [CGEventType] = [
        .flagsChanged,
        .keyDown,
        .keyUp
    ]

    public convenience init(
        definitions: [HotkeyDefinition] = UserPreferences.defaultHotkeys,
        modifierHoldDelay: TimeInterval = 0.12,
        secureInputPollInterval: TimeInterval = 0.10,
        secureInputCheck: @escaping @Sendable () -> Bool = {
            IsSecureEventInputEnabled()
        },
        physicalModifierFlags: @escaping @Sendable () -> CGEventFlags = {
            CGEventSource.flagsState(.combinedSessionState)
        },
        physicalKeyState: @escaping @Sendable (CGKeyCode) -> Bool = { keyCode in
            CGEventSource.keyState(.combinedSessionState, key: keyCode)
        }
    ) {
        self.init(
            definitions: definitions,
            modifierHoldDelay: modifierHoldDelay,
            secureInputPollInterval: secureInputPollInterval,
            secureInputCheck: secureInputCheck,
            physicalModifierFlags: physicalModifierFlags,
            physicalKeyState: physicalKeyState,
            mainQueueScheduler: { work in DispatchQueue.main.async(execute: work) },
            eventTapRestartInstaller: nil
        )
    }

    init(
        definitions: [HotkeyDefinition] = UserPreferences.defaultHotkeys,
        modifierHoldDelay: TimeInterval = 0.12,
        secureInputPollInterval: TimeInterval = 0.10,
        secureInputCheck: @escaping @Sendable () -> Bool = {
            IsSecureEventInputEnabled()
        },
        physicalModifierFlags: @escaping @Sendable () -> CGEventFlags = {
            CGEventSource.flagsState(.combinedSessionState)
        },
        physicalKeyState: @escaping @Sendable (CGKeyCode) -> Bool = { keyCode in
            CGEventSource.keyState(.combinedSessionState, key: keyCode)
        },
        mainQueueScheduler: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
        eventTapRestartInstaller: (@Sendable () -> Bool)?
    ) {
        self.definitions = definitions.map(Self.normalized)
        self.modifierHoldDelay = modifierHoldDelay
        self.secureInputPollInterval = secureInputPollInterval
        self.secureInputCheck = secureInputCheck
        self.physicalModifierFlags = physicalModifierFlags
        self.physicalKeyState = physicalKeyState
        self.mainQueueScheduler = mainQueueScheduler
        self.eventTapRestartInstaller = eventTapRestartInstaller
    }

    deinit {
        stop()
    }

    public func start(handler: @escaping @Sendable (HotkeyTrigger) -> Void) throws {
        lock.withLock { self.handler = handler }

        // Permission refreshes happen during capture startup. Keeping an
        // existing tap preserves the key-down state until its matching key-up.
        guard eventTap == nil else { return }

        try installEventTap()
        startSecureInputWatchdog()
    }

    private func installEventTap() throws {
        guard eventTap == nil else { return }

        let eventMask = Self.monitoredEventTypes.reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: globalHotkeyEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw LerroError.permissionRequired("辅助功能")
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func update(definitions: [HotkeyDefinition]) {
        let normalizedDefinitions = definitions.map(Self.normalized)
        let changed = lock.withLock { self.definitions != normalizedDefinitions }
        guard changed else { return }
        let interruption = interruptionTriggers()
        beginPhysicalDrain()
        lock.withLock { self.definitions = normalizedDefinitions }
        interruption.forEach(emit)
    }

    /// Cancels logical gesture ownership while retaining every physical event
    /// already claimed by the active tap. Matching key-up and modifier-release
    /// events continue to drain without reaching the frontmost application.
    public func resetTransientState() {
        beginPhysicalDrain()
    }

    /// Stops dispatch and clears both logical and physical state. Once the tap
    /// is disabled it has no authority to consume the remainder of a gesture.
    public func stop() {
        stopSecureInputWatchdog()
        cancelEventTapRestart()
        clearAllGestureState()
        invalidateEventTap()
        secureInputObserved = false
    }

    private func invalidateEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func scheduleEventTapRestart() {
        guard !eventTapRestartPending else { return }
        eventTapRestartPending = true
        let generation = eventTapRestartGeneration
        mainQueueScheduler { [weak self] in
            guard let self,
                  self.eventTapRestartGeneration == generation else { return }
            self.eventTapRestartPending = false
            self.invalidateEventTap()
            if let eventTapRestartInstaller {
                _ = eventTapRestartInstaller()
                return
            }
            do {
                try self.installEventTap()
            } catch {
                // The tap remains nil. A later normal start() can retry after
                // Accessibility permission or the system event path recovers.
            }
        }
    }

    private func cancelEventTapRestart() {
        eventTapRestartGeneration &+= 1
        eventTapRestartPending = false
    }

    @discardableResult
    func receive(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let interruption = interruptionTriggers()
            beginPhysicalDrain()
            interruption.forEach(emit)
            scheduleEventTapRestart()
            return false
        }

        if event.getIntegerValueField(.eventSourceUserData)
            == LerroGeneratedEvent.pasteSourceUserData {
            return false
        }

        let keyCode = Int64(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let modifierKeyIsDown = Self.modifierFlag(for: keyCode).flatMap { _ in
            CGKeyCode(exactly: keyCode).map(physicalKeyState)
        }
        if secureInputCheck() {
            let interruption = observeSecureInput()
            let suppressEvent = drainPhysicalEvent(
                type: type,
                keyCode: keyCode,
                flags: event.flags,
                modifierKeyIsDown: modifierKeyIsDown
            )
            interruption.forEach(emit)
            return suppressEvent
        }
        let recoveringFromSecureInput = secureInputObserved || secureInputRecoveryPending
        let drainsClaimedKeyUp = recoveringFromSecureInput
            && type == .keyUp
            && claimedKeyCodes.contains(keyCode)
        let startsFreshKeyPress = recoveringFromSecureInput
            && type == .keyDown
            && !isRepeat
        let startsFreshModifierPress: Bool
        if recoveringFromSecureInput,
           type == .flagsChanged,
           let changedModifier = Self.modifierFlag(for: keyCode) {
            let eventStillCarriesModifier = event.flags.contains(changedModifier)
            let changedModifierIsPhysicallyDown = CGKeyCode(exactly: keyCode).map {
                physicalKeyState($0)
            } ?? eventStillCarriesModifier
            startsFreshModifierPress = eventStillCarriesModifier
                && changedModifierIsPhysicallyDown
        } else {
            startsFreshModifierPress = false
        }
        if startsFreshKeyPress {
            // A fresh non-repeat down proves that an earlier physical press
            // ended while Secure Input hid its release from the event tap.
            // Retire that stale claim before reconciling the current state so
            // this new press can enter normal shortcut matching.
            claimedKeyCodes.remove(keyCode)
        }
        reconcileSecureInputEndIfNeeded()
        if (startsFreshKeyPress || startsFreshModifierPress),
           claimedKeyCodes.isEmpty {
            physicalDrainRequested = false
            modifierSequenceBlocked = false
            secureInputRecoveryPending = false
            if startsFreshModifierPress {
                // Reprocess this visible flagsChanged as the beginning of the
                // new modifier sequence instead of treating the reconciled
                // physical flags as an already-observed old gesture.
                currentModifierFlags = []
                pressedModifierKeyCodes.removeAll()
                claimedModifierKeyCodes.removeAll()
                modifierSequenceOwned = false
            }
        }

        let result = processEvent(
            type: type,
            keyCode: keyCode,
            flags: event.flags,
            isRepeat: isRepeat,
            eventSourceUserData: 0,
            modifierKeyIsDown: modifierKeyIsDown
        )
        apply(result)
        return drainsClaimedKeyUp || result.suppressEvent
    }

    @discardableResult
    func process(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        isRepeat: Bool = false,
        eventSourceUserData: Int64 = 0,
        modifierKeyIsDown: Bool? = nil
    ) -> (triggers: [HotkeyTrigger], suppressEvent: Bool) {
        let result = processEvent(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isRepeat: isRepeat,
            eventSourceUserData: eventSourceUserData,
            modifierKeyIsDown: modifierKeyIsDown
        )
        applyTimerDirective(result.timerDirective)
        return (result.triggers, result.suppressEvent)
    }

    func setHandlerForTesting(
        _ handler: @escaping @Sendable (HotkeyTrigger) -> Void
    ) {
        lock.withLock { self.handler = handler }
    }

    @discardableResult
    func processAndEmitForTesting(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        isRepeat: Bool = false
    ) -> Bool {
        let result = processEvent(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isRepeat: isRepeat,
            eventSourceUserData: 0,
            modifierKeyIsDown: nil
        )
        apply(result)
        return result.suppressEvent
    }

    private func processEvent(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        isRepeat: Bool,
        eventSourceUserData: Int64,
        modifierKeyIsDown: Bool?
    ) -> ProcessingResult {
        guard eventSourceUserData != LerroGeneratedEvent.pasteSourceUserData else {
            return ProcessingResult()
        }

        switch type {
        case .flagsChanged:
            return processFlagsChanged(
                keyCode: keyCode,
                flags: flags,
                modifierKeyIsDown: modifierKeyIsDown
            )
        case .keyDown:
            return processKeyDown(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        case .keyUp:
            return processKeyUp(keyCode: keyCode, flags: flags)
        default:
            return ProcessingResult()
        }
    }

    func activatePendingModifierForTesting() -> HotkeyTrigger? {
        activatePendingModifier(expectedDefinitionID: pendingModifierDefinition?.id)
    }

    func pollSecureInputForTesting() -> [HotkeyTrigger] {
        pollSecureInput()
    }

    func eventTapRestartPendingForTesting() -> Bool {
        eventTapRestartPending
    }

    func regularKeyAction(keyCode: Int64, flags: CGEventFlags) -> HotkeyAction? {
        regularKeyDefinition(keyCode: keyCode, flags: flags)?.action
    }

    private func processFlagsChanged(
        keyCode: Int64,
        flags: CGEventFlags,
        modifierKeyIsDown: Bool?,
        releaseConfirmedByKeyUp: Bool = false
    ) -> ProcessingResult {
        let current = flags.intersection(Self.primaryModifiers)
        let previous = currentModifierFlags
        var result = ProcessingResult()
        let isModifierEvent = Self.modifierFlag(for: keyCode) != nil
        let ownedBeforeEvent = modifierSequenceOwned
            || claimedModifierKeyCodes.contains(keyCode)

        // A physical modifier state is kept per keyCode. Aggregate flags can
        // stay unchanged when one side of a shared modifier is released, and
        // Fn/Globe can emit duplicate flagsChanged events for one press.
        if isModifierEvent {
            updatePressedModifierKey(
                keyCode: keyCode,
                currentFlags: current,
                previousFlags: previous,
                modifierKeyIsDown: modifierKeyIsDown
            )
            if modifierSequenceOwned,
               pressedModifierKeyCodes.contains(keyCode) {
                claimedModifierKeyCodes.insert(keyCode)
            }
        }
        guard current != previous else {
            finishModifierOwnershipIfReleased(
                currentFlags: current,
                releaseConfirmedByKeyUp: releaseConfirmedByKeyUp
            )
            return ProcessingResult(suppressEvent: ownedBeforeEvent)
        }
        currentModifierFlags = current

        if physicalDrainRequested {
            finishPhysicalDrainIfPossible()
            return finalizeModifierResult(
                result,
                current: current,
                ownedBeforeEvent: ownedBeforeEvent,
                releaseConfirmedByKeyUp: releaseConfirmedByKeyUp
            )
        }

        let grew = current.rawValue.nonzeroBitCount > previous.rawValue.nonzeroBitCount
            && current.intersection(previous) == previous
        let shrank = current.rawValue.nonzeroBitCount < previous.rawValue.nonzeroBitCount
            && previous.intersection(current) == current

        if let active = activeModifierDefinition,
           requiredFlags(for: active) != current {
            activeModifierDefinition = nil
            if grew,
               let upgraded = modifierOnlyDefinition(flags: current) {
                result.triggers.append(
                    HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)
                )
                activateModifierUpgrade(upgraded, result: &result)
                return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
            }

            if active.activation.resolved == .hold, shrank {
                result.triggers.append(trigger(for: active, phase: .ended))
            } else if active.activation.resolved == .hold {
                result.triggers.append(
                    HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)
                )
            }
            modifierSequenceBlocked = !current.isEmpty
            if current.isEmpty {
                modifierSequenceBlocked = false
            }
            return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
        }

        if let pending = pendingModifierDefinition,
           requiredFlags(for: pending) != current {
            pendingModifierDefinition = nil
            result.timerDirective = .cancel

            if grew,
               let upgraded = modifierOnlyDefinition(flags: current) {
                stageModifierCandidate(upgraded, result: &result)
                return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
            }

            if pending.activation.resolved == .toggle,
               shrank,
               !modifierSequenceBlocked {
                result.triggers.append(trigger(for: pending, phase: .began))
            }
            modifierSequenceBlocked = !current.isEmpty
            if current.isEmpty {
                modifierSequenceBlocked = false
            }
            return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
        }

        if current.isEmpty {
            modifierSequenceBlocked = false
            return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
        }

        guard !modifierSequenceBlocked, previous.isEmpty || grew else {
            return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
        }

        guard let definition = modifierOnlyDefinition(flags: current),
              isModifierEvent else {
            return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
        }

        stageModifierCandidate(definition, result: &result)
        if pressedModifierKeyCodes.contains(keyCode) {
            claimedModifierKeyCodes.insert(keyCode)
        }
        return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
    }

    private func finalizeModifierResult(
        _ result: ProcessingResult,
        current: CGEventFlags,
        ownedBeforeEvent: Bool,
        releaseConfirmedByKeyUp: Bool = false
    ) -> ProcessingResult {
        var finalized = result
        if ownedBeforeEvent || modifierSequenceOwned {
            finalized.suppressEvent = true
        }
        finishModifierOwnershipIfReleased(
            currentFlags: current,
            releaseConfirmedByKeyUp: releaseConfirmedByKeyUp
        )
        return finalized
    }

    private func updatePressedModifierKey(
        keyCode: Int64,
        currentFlags: CGEventFlags,
        previousFlags: CGEventFlags,
        modifierKeyIsDown: Bool?
    ) {
        guard let modifierFlag = Self.modifierFlag(for: keyCode) else { return }
        let isDown: Bool
        // A cleared semantic flag is the definitive modifier release. The
        // global physical-key query can lag one event behind the HID stream.
        if !currentFlags.contains(modifierFlag) {
            isDown = false
        } else if let modifierKeyIsDown {
            isDown = modifierKeyIsDown
        } else if !pressedModifierKeyCodes.contains(keyCode) {
            isDown = true
        } else if currentFlags == previousFlags {
            // Synthetic callers without an injected physical state cannot
            // distinguish a duplicate notification from a shared-modifier
            // release. Retaining the existing state is the safe choice: the
            // event remains owned and the next definitive release drains it.
            isDown = true
        } else {
            isDown = true
        }

        if isDown {
            pressedModifierKeyCodes.insert(keyCode)
        } else {
            pressedModifierKeyCodes.remove(keyCode)
        }
    }

    private func finishModifierOwnershipIfReleased(
        currentFlags: CGEventFlags,
        releaseConfirmedByKeyUp: Bool
    ) {
        guard pressedModifierKeyCodes.isEmpty,
              currentFlags.isEmpty || releaseConfirmedByKeyUp else { return }
        modifierSequenceOwned = false
        claimedModifierKeyCodes.removeAll()
    }

    private func stageModifierCandidate(
        _ definition: HotkeyDefinition,
        result: inout ProcessingResult
    ) {
        pendingModifierDefinition = definition
        modifierSequenceOwned = true
        if definition.activation.resolved == .hold {
            result.timerDirective = .schedule(definitionID: definition.id)
        }
    }

    private func activateModifierUpgrade(
        _ definition: HotkeyDefinition,
        result: inout ProcessingResult
    ) {
        modifierSequenceOwned = true
        result.timerDirective = .cancel
        result.triggers.append(trigger(for: definition, phase: .began))
        result.upgradeContinuation = .modifier(definition: definition)
        if definition.activation.resolved == .hold {
            activeModifierDefinition = definition
        } else {
            modifierSequenceBlocked = true
        }
    }

    private func processKeyDown(
        keyCode: Int64,
        flags: CGEventFlags,
        isRepeat: Bool
    ) -> ProcessingResult {
        // Some keyboards surface Fn/Globe as a keyboard down before their
        // companion flagsChanged event. Claim the physical key immediately;
        // a later same-flags event then remains owned instead of leaking to
        // the system emoji/character-switcher path.
        if Self.modifierFlag(for: keyCode) != nil {
            if claimedModifierKeyCodes.contains(keyCode) {
                return ProcessingResult(suppressEvent: true)
            }
            return processFlagsChanged(
                keyCode: keyCode,
                flags: flags,
                modifierKeyIsDown: true
            )
        }

        currentModifierFlags = flags.intersection(Self.primaryModifiers)

        if keyCode == 53 {
            let interruption = interruptionTriggers()
            beginPhysicalDrain()
            return ProcessingResult(
                triggers: interruption.isEmpty
                    ? [HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)]
                    : interruption
            )
        }

        if claimedModifierKeyCodes.contains(keyCode) {
            return ProcessingResult(suppressEvent: true)
        }

        if claimedKeyCodes.contains(keyCode) {
            return ProcessingResult(suppressEvent: true)
        }

        if physicalDrainRequested {
            return ProcessingResult()
        }

        let definition = isRepeat
            ? nil
            : regularKeyDefinition(keyCode: keyCode, flags: flags)
        var result = ProcessingResult()

        if pendingModifierDefinition != nil {
            pendingModifierDefinition = nil
            modifierSequenceBlocked = !currentModifierFlags.isEmpty
            result.timerDirective = .cancel
            if let definition {
                claimRegularKey(keyCode, definition: definition, result: &result)
            }
            return result
        }

        if activeModifierDefinition != nil {
            result.triggers.append(
                HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)
            )
            activeModifierDefinition = nil
            modifierSequenceBlocked = !currentModifierFlags.isEmpty
            if let definition {
                claimRegularKey(keyCode, definition: definition, result: &result)
                result.upgradeContinuation = .regular(
                    keyCode: keyCode,
                    definition: definition
                )
            }
            return result
        }

        guard let definition else { return result }
        claimRegularKey(keyCode, definition: definition, result: &result)
        return result
    }

    private func claimRegularKey(
        _ keyCode: Int64,
        definition: HotkeyDefinition,
        result: inout ProcessingResult
    ) {
        claimedKeyCodes.insert(keyCode)
        result.suppressEvent = true
        result.triggers.append(trigger(for: definition, phase: .began))
        if definition.activation.resolved == .hold {
            activeKeyDefinitions[keyCode] = definition
        }
    }

    private func processKeyUp(
        keyCode: Int64,
        flags: CGEventFlags
    ) -> ProcessingResult {
        if let modifierFlag = Self.modifierFlag(for: keyCode) {
            let wasOwned = modifierSequenceOwned
                || claimedModifierKeyCodes.contains(keyCode)
            pressedModifierKeyCodes.remove(keyCode)
            var effectiveFlags = flags.intersection(Self.primaryModifiers)
            if !pressedModifierKeyCodes.contains(where: {
                Self.modifierFlag(for: $0) == modifierFlag
            }) {
                effectiveFlags.remove(modifierFlag)
            }
            var result = processFlagsChanged(
                keyCode: keyCode,
                flags: effectiveFlags,
                modifierKeyIsDown: false,
                releaseConfirmedByKeyUp: true
            )
            result.suppressEvent = wasOwned || result.suppressEvent
            return result
        }
        let wasClaimed = claimedKeyCodes.remove(keyCode) != nil
        var result = ProcessingResult(suppressEvent: wasClaimed)
        if let definition = activeKeyDefinitions.removeValue(forKey: keyCode),
           definition.activation.resolved == .hold {
            result.triggers.append(trigger(for: definition, phase: .ended))
        }
        finishPhysicalDrainIfPossible()
        return result
    }

    private func apply(_ result: ProcessingResult) {
        applyTimerDirective(result.timerDirective)
        guard let continuation = result.upgradeContinuation,
              let first = result.triggers.first else {
            result.triggers.forEach(emit)
            return
        }

        emit(first)
        resumePhysicalOwnership(continuation)
        result.triggers.dropFirst().forEach(emit)
    }

    private func resumePhysicalOwnership(
        _ continuation: ProcessingResult.UpgradeContinuation
    ) {
        physicalDrainRequested = false
        modifierSequenceBlocked = !currentModifierFlags.isEmpty
        switch continuation {
        case let .regular(keyCode, definition):
            claimedKeyCodes.insert(keyCode)
            if definition.activation.resolved == .hold {
                activeKeyDefinitions[keyCode] = definition
            }
        case let .modifier(definition):
            if definition.activation.resolved == .hold {
                activeModifierDefinition = definition
            } else {
                modifierSequenceBlocked = true
            }
        }
    }

    private func applyTimerDirective(_ directive: ProcessingResult.ModifierTimerDirective) {
        switch directive {
        case .none:
            break
        case .cancel:
            cancelModifierTimer()
        case let .schedule(definitionID):
            modifierTimerGeneration &+= 1
            let generation = modifierTimerGeneration
            pendingModifierActivation?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      self.modifierTimerGeneration == generation,
                      let trigger = self.activatePendingModifier(
                        expectedDefinitionID: definitionID
                      ) else { return }
                self.emit(trigger)
            }
            pendingModifierActivation = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + modifierHoldDelay,
                execute: workItem
            )
        }
    }

    private func cancelModifierTimer() {
        modifierTimerGeneration &+= 1
        pendingModifierActivation?.cancel()
        pendingModifierActivation = nil
    }

    private func activatePendingModifier(expectedDefinitionID: String?) -> HotkeyTrigger? {
        guard !physicalDrainRequested,
              let expectedDefinitionID,
              let pending = pendingModifierDefinition,
              pending.id == expectedDefinitionID,
              pending.activation.resolved == .hold,
              requiredFlags(for: pending) == currentModifierFlags,
              !modifierSequenceBlocked else {
            return nil
        }
        pendingModifierDefinition = nil
        pendingModifierActivation = nil
        activeModifierDefinition = pending
        return trigger(for: pending, phase: .began)
    }

    private func trigger(
        for definition: HotkeyDefinition,
        phase: HotkeyGesturePhase
    ) -> HotkeyTrigger {
        HotkeyTrigger(
            action: definition.action,
            activation: definition.activation,
            phase: phase,
            definitionID: definition.id
        )
    }

    private func modifierOnlyDefinition(flags: CGEventFlags) -> HotkeyDefinition? {
        lock.withLock {
            definitions.first {
                $0.keyCode == nil
                    && !requiredFlags(for: $0).isEmpty
                    && requiredFlags(for: $0) == flags
            }
        }
    }

    private func regularKeyDefinition(
        keyCode: Int64,
        flags: CGEventFlags
    ) -> HotkeyDefinition? {
        let primary = flags.intersection(Self.primaryModifiers)
        return lock.withLock {
            definitions.first {
                $0.keyCode == keyCode && requiredFlags(for: $0) == primary
            }
        }
    }

    private func requiredFlags(for definition: HotkeyDefinition) -> CGEventFlags {
        CGEventFlags(rawValue: definition.modifiers).intersection(Self.primaryModifiers)
    }

    private func interruptionTriggers() -> [HotkeyTrigger] {
        guard activeModifierDefinition != nil || !activeKeyDefinitions.isEmpty else {
            return []
        }
        return [HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)]
    }

    private func beginPhysicalDrain() {
        cancelModifierTimer()
        pendingModifierDefinition = nil
        activeModifierDefinition = nil
        activeKeyDefinitions.removeAll()
        physicalDrainRequested = !currentModifierFlags.isEmpty
            || !claimedKeyCodes.isEmpty
            || !pressedModifierKeyCodes.isEmpty
            || !claimedModifierKeyCodes.isEmpty
            || modifierSequenceOwned
        modifierSequenceBlocked = !currentModifierFlags.isEmpty
    }

    private func drainPhysicalEvent(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        modifierKeyIsDown: Bool?
    ) -> Bool {
        switch type {
        case .flagsChanged:
            let current = flags.intersection(Self.primaryModifiers)
            let modifierFlag = Self.modifierFlag(for: keyCode)
            let ownsThisEvent = modifierSequenceOwned
                || claimedModifierKeyCodes.contains(keyCode)
            if modifierFlag != nil {
                updatePressedModifierKey(
                    keyCode: keyCode,
                    currentFlags: current,
                    previousFlags: currentModifierFlags,
                    modifierKeyIsDown: modifierKeyIsDown
                )
            }
            if modifierSequenceOwned,
               pressedModifierKeyCodes.contains(keyCode) {
                claimedModifierKeyCodes.insert(keyCode)
            }
            currentModifierFlags = current
            if !currentModifierFlags.isEmpty {
                physicalDrainRequested = true
                modifierSequenceBlocked = true
            }
            finishPhysicalDrainIfPossible()
            return ownsThisEvent
        case .keyUp:
            let wasClaimed = claimedKeyCodes.remove(keyCode) != nil
                || claimedModifierKeyCodes.contains(keyCode)
            if let modifierFlag = Self.modifierFlag(for: keyCode) {
                pressedModifierKeyCodes.remove(keyCode)
                var effectiveCurrent = flags.intersection(Self.primaryModifiers)
                if !pressedModifierKeyCodes.contains(where: {
                    Self.modifierFlag(for: $0) == modifierFlag
                }) {
                    effectiveCurrent.remove(modifierFlag)
                }
                currentModifierFlags = effectiveCurrent
                finishModifierOwnershipIfReleased(
                    currentFlags: effectiveCurrent,
                    releaseConfirmedByKeyUp: true
                )
            }
            finishPhysicalDrainIfPossible()
            return wasClaimed
        case .keyDown:
            if Self.modifierFlag(for: keyCode) != nil {
                pressedModifierKeyCodes.insert(keyCode)
                if modifierSequenceOwned {
                    claimedModifierKeyCodes.insert(keyCode)
                }
            }
            return claimedKeyCodes.contains(keyCode)
                || claimedModifierKeyCodes.contains(keyCode)
        default:
            break
        }
        finishPhysicalDrainIfPossible()
        return false
    }

    private func finishPhysicalDrainIfPossible() {
        finishModifierOwnershipIfReleased(
            currentFlags: currentModifierFlags,
            releaseConfirmedByKeyUp: false
        )
        guard physicalDrainRequested,
              currentModifierFlags.isEmpty,
              claimedKeyCodes.isEmpty,
              pressedModifierKeyCodes.isEmpty else { return }
        physicalDrainRequested = false
        modifierSequenceBlocked = false
        if !secureInputObserved {
            secureInputRecoveryPending = false
        }
    }

    private func clearAllGestureState() {
        cancelModifierTimer()
        pendingModifierDefinition = nil
        activeModifierDefinition = nil
        activeKeyDefinitions.removeAll()
        claimedKeyCodes.removeAll()
        pressedModifierKeyCodes.removeAll()
        claimedModifierKeyCodes.removeAll()
        modifierSequenceOwned = false
        currentModifierFlags = []
        modifierSequenceBlocked = false
        physicalDrainRequested = false
        secureInputRecoveryPending = false
    }

    private func startSecureInputWatchdog() {
        guard secureInputWatchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + secureInputPollInterval,
            repeating: secureInputPollInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.pollSecureInput().forEach(self.emit)
        }
        secureInputWatchdog = timer
        timer.resume()
    }

    private func stopSecureInputWatchdog() {
        secureInputWatchdog?.setEventHandler {}
        secureInputWatchdog?.cancel()
        secureInputWatchdog = nil
    }

    private func pollSecureInput() -> [HotkeyTrigger] {
        guard secureInputCheck() else {
            reconcileSecureInputEndIfNeeded()
            return []
        }
        return observeSecureInput()
    }

    private func observeSecureInput() -> [HotkeyTrigger] {
        guard !secureInputObserved else { return [] }
        secureInputObserved = true
        secureInputRecoveryPending = false
        beginPhysicalDrain()
        // A toggle capture has no active physical definition after key-up, so
        // every secure-input transition emits one logical cancellation signal.
        return [HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)]
    }

    private func reconcileSecureInputEndIfNeeded() {
        guard secureInputObserved else { return }
        secureInputObserved = false
        secureInputRecoveryPending = true
        currentModifierFlags = physicalModifierFlags().intersection(Self.primaryModifiers)
        claimedKeyCodes = Set(claimedKeyCodes.filter { keyCode in
            guard let physicalKeyCode = CGKeyCode(exactly: keyCode) else { return false }
            return physicalKeyState(physicalKeyCode)
        })
        pressedModifierKeyCodes = Set(pressedModifierKeyCodes.filter { keyCode in
            guard let physicalKeyCode = CGKeyCode(exactly: keyCode) else { return false }
            return physicalKeyState(physicalKeyCode)
        })
        modifierSequenceBlocked = !currentModifierFlags.isEmpty
        finishPhysicalDrainIfPossible()
    }

    private func emit(_ trigger: HotkeyTrigger) {
        let callback = lock.withLock { handler }
        callback?(trigger)
    }

    private static func normalized(_ saved: HotkeyDefinition) -> HotkeyDefinition {
        var definition = saved
        if definition.usesFunctionKey {
            definition.modifiers |= CGEventFlags.maskSecondaryFn.rawValue
        }
        if let keyCode = definition.keyCode,
           let flag = modifierFlag(for: keyCode) {
            definition.keyCode = nil
            definition.modifiers |= flag.rawValue
        }
        return definition
    }

    private static func modifierFlag(for keyCode: Int64) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: .maskCommand
        case 56, 60: .maskShift
        case 58, 61: .maskAlternate
        case 59, 62: .maskControl
        // Fn (ANSI) and Globe (the macOS 26 virtual key emitted by newer
        // Apple keyboards) both carry the SecondaryFn semantic.
        case 63, 179: .maskSecondaryFn
        default: nil
        }
    }
}

private func globalHotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.receive(type: type, event: event)
        ? nil
        : Unmanaged.passUnretained(event)
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
