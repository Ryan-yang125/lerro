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
    /// A configured modifier shortcut owns every flagsChanged event from its
    /// first press through the matching final release. This keeps Fn/Globe
    /// from receiving the trailing event after Lerro accepted the shortcut.
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

    private static let primaryModifiers: CGEventFlags = [
        .maskCommand,
        .maskControl,
        .maskAlternate,
        .maskShift,
        .maskSecondaryFn
    ]

    // Quartz exposes this event numerically even though the Swift overlay for
    // the current SDK omits the historical `systemDefined` case.
    static let systemDefinedEventType = CGEventType(rawValue: 14)!

    private static let monitoredEventTypes: [CGEventType] = [
        .flagsChanged,
        .keyDown,
        .keyUp,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .scrollWheel,
        systemDefinedEventType
    ]

    public init(
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
        self.definitions = definitions.map(Self.normalized)
        self.modifierHoldDelay = modifierHoldDelay
        self.secureInputPollInterval = secureInputPollInterval
        self.secureInputCheck = secureInputCheck
        self.physicalModifierFlags = physicalModifierFlags
        self.physicalKeyState = physicalKeyState
    }

    deinit {
        stop()
    }

    public func start(handler: @escaping @Sendable (HotkeyTrigger) -> Void) throws {
        lock.withLock { self.handler = handler }

        // Permission refreshes happen during capture startup. Keeping an
        // existing tap preserves the key-down state until its matching key-up.
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
        startSecureInputWatchdog()
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
        clearAllGestureState()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        secureInputObserved = false
    }

    @discardableResult
    func receive(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let interruption = interruptionTriggers()
            beginPhysicalDrain()
            interruption.forEach(emit)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }

        // Scroll events can arrive in dense bursts. When no modifier sequence
        // exists, they and ordinary pointer clicks have no hotkey work to do.
        // Pass them through before querying Secure Input or physical key state.
        if Self.isPointerInterruptionEvent(type),
           event.flags.intersection(Self.primaryModifiers).isEmpty,
           currentModifierFlags.isEmpty,
           pendingModifierDefinition == nil,
           activeModifierDefinition == nil {
            return false
        }

        if event.getIntegerValueField(.eventSourceUserData)
            == LerroGeneratedEvent.pasteSourceUserData {
            return false
        }

        let keyCode = Int64(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if secureInputCheck() {
            let interruption = observeSecureInput()
            let suppressEvent = drainPhysicalEvent(
                type: type,
                keyCode: keyCode,
                flags: event.flags
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
            let changedModifierIsPhysicallyDown = CGKeyCode(exactly: keyCode).map {
                physicalKeyState($0)
            } ?? event.flags.contains(changedModifier)
            startsFreshModifierPress = changedModifierIsPhysicallyDown
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
            }
        }

        let result = processEvent(
            type: type,
            keyCode: keyCode,
            flags: event.flags,
            isRepeat: isRepeat,
            eventSourceUserData: 0
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
        eventSourceUserData: Int64 = 0
    ) -> (triggers: [HotkeyTrigger], suppressEvent: Bool) {
        let result = processEvent(
            type: type,
            keyCode: keyCode,
            flags: flags,
            isRepeat: isRepeat,
            eventSourceUserData: eventSourceUserData
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
            eventSourceUserData: 0
        )
        apply(result)
        return result.suppressEvent
    }

    private func processEvent(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        isRepeat: Bool,
        eventSourceUserData: Int64
    ) -> ProcessingResult {
        guard eventSourceUserData != LerroGeneratedEvent.pasteSourceUserData else {
            return ProcessingResult()
        }

        if type == Self.systemDefinedEventType {
            return processModifierInterruption(flags: flags)
        }

        switch type {
        case .flagsChanged:
            return processFlagsChanged(flags: flags)
        case .keyDown:
            return processKeyDown(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        case .keyUp:
            return processKeyUp(keyCode: keyCode)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            return processModifierInterruption(flags: flags)
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

    func regularKeyAction(keyCode: Int64, flags: CGEventFlags) -> HotkeyAction? {
        regularKeyDefinition(keyCode: keyCode, flags: flags)?.action
    }

    private func processFlagsChanged(flags: CGEventFlags) -> ProcessingResult {
        let current = flags.intersection(Self.primaryModifiers)
        let previous = currentModifierFlags
        var result = ProcessingResult()
        let ownedBeforeEvent = modifierSequenceOwned
        guard current != previous else { return result }
        currentModifierFlags = current

        if physicalDrainRequested {
            finishPhysicalDrainIfPossible()
            return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
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

        guard let definition = modifierOnlyDefinition(flags: current) else {
            return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
        }

        stageModifierCandidate(definition, result: &result)
        return finalizeModifierResult(result, current: current, ownedBeforeEvent: ownedBeforeEvent)
    }

    private func finalizeModifierResult(
        _ result: ProcessingResult,
        current: CGEventFlags,
        ownedBeforeEvent: Bool
    ) -> ProcessingResult {
        var finalized = result
        if ownedBeforeEvent || modifierSequenceOwned {
            finalized.suppressEvent = true
        }
        if current.isEmpty {
            modifierSequenceOwned = false
        }
        return finalized
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

    private func processKeyUp(keyCode: Int64) -> ProcessingResult {
        let wasClaimed = claimedKeyCodes.remove(keyCode) != nil
        var result = ProcessingResult(suppressEvent: wasClaimed)
        if let definition = activeKeyDefinitions.removeValue(forKey: keyCode),
           definition.activation.resolved == .hold {
            result.triggers.append(trigger(for: definition, phase: .ended))
        }
        finishPhysicalDrainIfPossible()
        return result
    }

    private func processModifierInterruption(flags: CGEventFlags) -> ProcessingResult {
        let observedFlags = flags.intersection(Self.primaryModifiers)
        if !observedFlags.isEmpty || currentModifierFlags.isEmpty {
            currentModifierFlags = observedFlags
        }

        guard !physicalDrainRequested else { return ProcessingResult() }

        var result = ProcessingResult()
        if pendingModifierDefinition != nil {
            pendingModifierDefinition = nil
            result.timerDirective = .cancel
        }
        if activeModifierDefinition != nil {
            activeModifierDefinition = nil
            result.triggers.append(
                HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began)
            )
        }
        if !currentModifierFlags.isEmpty {
            modifierSequenceBlocked = true
        }
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
        physicalDrainRequested = !currentModifierFlags.isEmpty || !claimedKeyCodes.isEmpty
        modifierSequenceBlocked = !currentModifierFlags.isEmpty
    }

    private func drainPhysicalEvent(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags
    ) -> Bool {
        switch type {
        case .flagsChanged:
            let ownsThisEvent = modifierSequenceOwned
            currentModifierFlags = flags.intersection(Self.primaryModifiers)
            if !currentModifierFlags.isEmpty {
                physicalDrainRequested = true
                modifierSequenceBlocked = true
            }
            finishPhysicalDrainIfPossible()
            if currentModifierFlags.isEmpty {
                modifierSequenceOwned = false
            }
            return ownsThisEvent
        case .keyUp:
            let wasClaimed = claimedKeyCodes.remove(keyCode) != nil
            finishPhysicalDrainIfPossible()
            return wasClaimed
        case .keyDown:
            return claimedKeyCodes.contains(keyCode)
        default:
            break
        }
        finishPhysicalDrainIfPossible()
        return false
    }

    private func finishPhysicalDrainIfPossible() {
        guard physicalDrainRequested,
              currentModifierFlags.isEmpty,
              claimedKeyCodes.isEmpty else { return }
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
        case 63: .maskSecondaryFn
        default: nil
        }
    }

    private static func isPointerInterruptionEvent(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            true
        default:
            false
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
