import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import LerroCore
import OSLog

public actor AccessibilityTextDeliverer: TextDelivering {
    private static let logger = Logger(
        subsystem: "app.lerro.mac",
        category: "text-delivery"
    )

    private let activateTarget: @Sendable (CapturedContext) async -> Bool
    private let focusSnapshot: @Sendable () -> DeliveryFocusSnapshot
    private let activationPollAttempts: Int
    private let activationPollInterval: Duration
    private let pasteOverride: (@Sendable (String, CapturedContext, Bool) async throws -> Void)?
    private let receiptActionOverride: (
        @Sendable (ReceiptAction, TextDeliveryReceipt) async throws -> Void
    )?
    private var activeTransactionIdentifier: UUID?

    public init() {
        activateTarget = activateCapturedApplication
        focusSnapshot = currentDeliveryFocusSnapshot
        activationPollAttempts = 25
        activationPollInterval = .milliseconds(40)
        pasteOverride = nil
        receiptActionOverride = nil
    }

    init(secureFieldCheck: @escaping @Sendable () -> Bool) {
        activateTarget = { _ in true }
        focusSnapshot = {
            DeliveryFocusSnapshot(safety: secureFieldCheck() ? .secure : .safe)
        }
        activationPollAttempts = 1
        activationPollInterval = .zero
        pasteOverride = nil
        receiptActionOverride = nil
    }

    init(
        activateTarget: @escaping @Sendable (CapturedContext) async -> Bool,
        focusSnapshot: @escaping @Sendable () -> DeliveryFocusSnapshot,
        activationPollAttempts: Int = 1,
        activationPollInterval: Duration = .zero,
        pasteOverride: (@Sendable (String, CapturedContext, Bool) async throws -> Void)? = nil,
        receiptActionOverride: (
            @Sendable (ReceiptAction, TextDeliveryReceipt) async throws -> Void
        )? = nil
    ) {
        self.activateTarget = activateTarget
        self.focusSnapshot = focusSnapshot
        self.activationPollAttempts = max(1, activationPollAttempts)
        self.activationPollInterval = activationPollInterval
        self.pasteOverride = pasteOverride
        self.receiptActionOverride = receiptActionOverride
    }

    public func deliver(
        _ text: String,
        to context: CapturedContext,
        replacingSelection: Bool,
        targetPolicy: TextDeliveryTargetPolicy,
        onCommit: @escaping TextDeliveryCommitHandler
    ) async throws -> TextDeliveryReceipt {
        guard activeTransactionIdentifier == nil else {
            throw LerroError.insertionFailed("另一项文本写入仍在进行")
        }
        let transactionIdentifier = UUID()
        activeTransactionIdentifier = transactionIdentifier
        defer {
            if activeTransactionIdentifier == transactionIdentifier {
                activeTransactionIdentifier = nil
            }
        }

        let policyName = targetPolicy == .requireCurrent ? "require-current" : "reactivate-captured"
        let targetBundle = context.bundleIdentifier ?? "unknown"
        var stage = "privacy"
        Self.logger.info(
            "delivery-start policy=\(policyName, privacy: .public) target=\(targetBundle, privacy: .public)"
        )

        do {
            // Plain insertion deliberately targets the keyboard focus that
            // exists when Command-V is posted. AX context remains useful for
            // capture and selection-aware rewrite, while a normal insert has
            // no focused-element, secure-state, selection, PID, or bundle
            // prerequisite.
            if !replacingSelection {
                stage = "paste"
                if targetPolicy == .reactivateCaptured {
                    try await reactivateCapturedApplicationForPlainInsertion(context)
                }
                if let pasteOverride {
                    try await pasteOverride(text, context, false)
                    await onCommit()
                    return makeDeliveryReceipt(fallback: context)
                } else {
                    return try await pasteAtCurrentKeyboardFocus(
                        text,
                        fallbackContext: context,
                        onCommit: onCommit
                    )
                }
            }

            guard CapturePrivacyPolicy.permitsCapture(in: context) else {
                throw LerroError.secureField
            }

            stage = "target"
            let deliveryTarget = try await prepareDeliveryTarget(
                context,
                replacingSelection: replacingSelection,
                policy: targetPolicy
            )
            try Task.checkCancellation()

            stage = "paste"
            if let pasteOverride {
                try await pasteOverride(text, context, replacingSelection)
                await onCommit()
                return makeDeliveryReceipt(fallback: context)
            } else {
                return try await pasteUsingClipboard(
                    text,
                    context: context,
                    replacingSelection: replacingSelection,
                    target: deliveryTarget,
                    onCommit: onCommit
                )
            }
        } catch {
            let errorType = String(reflecting: type(of: error))
            Self.logger.error(
                "delivery-failed stage=\(stage, privacy: .public) type=\(errorType, privacy: .public)"
            )
            throw error
        }
    }

    public func undo(_ receipt: TextDeliveryReceipt) async throws {
        try await performReceiptAction(
            receipt,
            action: .undo,
            keyCode: keyCode(for: "z") ?? CGKeyCode(0x06)
        )
    }

    public func correct(
        _ text: String,
        using receipt: TextDeliveryReceipt
    ) async throws -> TextDeliveryReceipt {
        guard activeTransactionIdentifier == nil else {
            throw LerroError.insertionFailed("另一项文本写入仍在进行")
        }
        guard receipt.canUndo else {
            throw LerroError.insertionFailed("当前输入框无法安全执行该操作")
        }
        let transactionIdentifier = UUID()
        activeTransactionIdentifier = transactionIdentifier
        defer {
            if activeTransactionIdentifier == transactionIdentifier {
                activeTransactionIdentifier = nil
            }
        }

        _ = try await settledReceiptFocus(receipt)
        if let receiptActionOverride {
            try validateReceiptFocus(focusSnapshot(), receipt: receipt)
            try await receiptActionOverride(.correct(text), receipt)
            return makeDeliveryReceipt(
                fallback: receipt.context,
                continuing: receipt
            )
        }
        let snapshotProvider = focusSnapshot
        let transaction = try await MainActor.run {
            try Task.checkCancellation()
            try validateReceiptFocus(snapshotProvider(), receipt: receipt)
            guard CGPreflightPostEventAccess() else {
                throw LerroError.permissionRequired("辅助功能")
            }
            let transaction = try CurrentFocusPasteboardTransaction.begin(text: text)
            do {
                let (undoDown, undoUp) = try makeLerroPasteKeyEvents(
                    keyCode: keyCode(for: "z") ?? CGKeyCode(0x06)
                )
                let (pasteDown, pasteUp) = try makeLerroPasteKeyEvents()
                undoDown.post(tap: .cghidEventTap)
                undoUp.post(tap: .cghidEventTap)
                pasteDown.post(tap: .cghidEventTap)
                pasteUp.post(tap: .cghidEventTap)
                return transaction
            } catch {
                try? transaction.restore()
                throw error
            }
        }
        try await finalizeCommittedPasteDelivery(
            waitForConsumption: {
                try? await Task.sleep(for: .milliseconds(500))
            },
            restorePasteboard: {
                await MainActor.run {
                    try? transaction.restore()
                }
            }
        )
        return makeDeliveryReceipt(
            fallback: receipt.context,
            continuing: receipt
        )
    }

    public func submit(_ receipt: TextDeliveryReceipt) async throws {
        guard VoiceFinishActionResolver.permitsSubmit(in: receipt.context) else {
            throw LerroError.insertionFailed("当前输入框不支持语音发送")
        }
        try await performReceiptAction(
            receipt,
            action: .submit,
            keyCode: CGKeyCode(kVK_Return),
            flags: []
        )
    }

    private func reactivateCapturedApplicationForPlainInsertion(
        _ context: CapturedContext
    ) async throws {
        guard await activateTarget(context) else {
            throw LerroError.insertionFailed("原输入应用已关闭或无法激活")
        }
        for attempt in 0..<activationPollAttempts {
            try Task.checkCancellation()
            if attempt > 0 {
                try await Task.sleep(for: activationPollInterval)
            }
            if focusMatchesTarget(focusSnapshot(), context: context) {
                return
            }
        }
        throw LerroError.insertionFailed("原输入应用已激活，但尚未成为当前键盘目标")
    }

    private func pasteAtCurrentKeyboardFocus(
        _ text: String,
        fallbackContext: CapturedContext,
        onCommit: @escaping TextDeliveryCommitHandler
    ) async throws -> TextDeliveryReceipt {
        let transaction = try await MainActor.run {
            try Task.checkCancellation()
            guard CGPreflightPostEventAccess() else {
                throw LerroError.permissionRequired("辅助功能")
            }
            let transaction = try CurrentFocusPasteboardTransaction.begin(text: text)
            do {
                let (keyDown, keyUp) = try makeLerroPasteKeyEvents()
                try Task.checkCancellation()
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
                onCommit()
                return transaction
            } catch {
                try? transaction.restore()
                throw error
            }
        }
        Self.logger.debug("delivery-paste-event submitted mode=current-focus")

        // Keep transient pasteboard contents alive for 500 ms after posting
        // Command-V, then restore the archived clipboard.
        try await finalizeCommittedPasteDelivery(
            waitForConsumption: {
                try? await Task.sleep(for: .milliseconds(500))
            },
            restorePasteboard: {
                await MainActor.run {
                    try? transaction.restore()
                }
            }
        )
        Self.logger.info("delivery-complete stage=paste mode=current-focus")
        return makeDeliveryReceipt(fallback: fallbackContext)
    }

    private func prepareDeliveryTarget(
        _ context: CapturedContext,
        replacingSelection: Bool,
        policy: TextDeliveryTargetPolicy
    ) async throws -> ResolvedDeliveryTarget {
        var snapshot = focusSnapshot()
        let currentBundle = snapshot.bundleIdentifier ?? "unknown"
        let pidMatches = context.processIdentifier.map {
            snapshot.processIdentifier == $0
        } ?? false
        let bundleMatches = context.bundleIdentifier.map {
            snapshot.bundleIdentifier == $0
        } ?? false
        let safetyName = switch snapshot.safety {
        case .safe: "safe"
        case .secure: "secure"
        case .unavailable: "unavailable"
        }
        Self.logger.info(
            "delivery-target observed current=\(currentBundle, privacy: .public) element=\(snapshot.focusedElementAvailable, privacy: .public) safety=\(safetyName, privacy: .public)"
        )
        Self.logger.info(
            "delivery-target match pid=\(pidMatches, privacy: .public) bundle=\(bundleMatches, privacy: .public)"
        )
        if focusMatchesTarget(snapshot, context: context),
           snapshot.focusedElementAvailable,
           snapshot.selectionState != .unavailable {
            try requireExpectedFocus(snapshot, context: context, replacingSelection: replacingSelection)
            Self.logger.debug("delivery-target already-current")
            return try resolveDeliveryTarget(snapshot, context: context)
        }

        guard policy == .reactivateCaptured else {
            try requireExpectedFocus(snapshot, context: context, replacingSelection: replacingSelection)
            return try resolveDeliveryTarget(snapshot, context: context)
        }

        guard await activateTarget(context) else {
            throw LerroError.insertionFailed("原输入应用已关闭或无法激活")
        }
        Self.logger.debug("delivery-target activation-requested")

        for attempt in 0..<activationPollAttempts {
            try Task.checkCancellation()
            if attempt > 0 {
                try await Task.sleep(for: activationPollInterval)
            }
            snapshot = focusSnapshot()
            guard focusMatchesTarget(snapshot, context: context) else { continue }
            guard snapshot.focusedElementAvailable,
                  snapshot.selectionState != .unavailable else { continue }
            try requireExpectedFocus(snapshot, context: context, replacingSelection: replacingSelection)
            Self.logger.debug("delivery-target activation-settled attempt=\(attempt, privacy: .public)")
            return try resolveDeliveryTarget(snapshot, context: context)
        }

        throw LerroError.insertionFailed("原输入应用已激活，但输入焦点尚未恢复")
    }

    private func pasteUsingClipboard(
        _ text: String,
        context: CapturedContext,
        replacingSelection: Bool,
        target: ResolvedDeliveryTarget,
        onCommit: @escaping TextDeliveryCommitHandler
    ) async throws -> TextDeliveryReceipt {
        let sessionIdentifier = UUID().uuidString
        let transaction = try await MainActor.run {
            try Task.checkCancellation()
            try validateSystemDeliveryFocus(
                context: context,
                replacingSelection: replacingSelection
            )
            return try PasteboardTransaction.begin(
                text: text,
                sessionIdentifier: sessionIdentifier
            )
        }
        Self.logger.debug("delivery-pasteboard prepared")

        do {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(40))
            try await MainActor.run {
                try submitPasteEvent(
                    transaction: transaction,
                    target: target,
                    context: context,
                    replacingSelection: replacingSelection,
                    onCommit: onCommit
                )
            }
        } catch {
            try await restorePasteboard(transaction)
            throw error
        }

        // Posting Command-V is the delivery commit point. Once both events have
        // been submitted, keep the temporary clipboard alive for the target even
        // if the caller's task is cancelled, then restore it exactly once.
        Self.logger.debug("delivery-paste-event submitted")
        try await finalizeCommittedPasteDelivery(
            waitForConsumption: {
                try? await Task.sleep(for: .milliseconds(500))
            },
            restorePasteboard: { [self] in
                try await restorePasteboard(transaction)
            }
        )
        Self.logger.info("delivery-complete stage=paste")
        return makeDeliveryReceipt(fallback: context)
    }

    private func makeDeliveryReceipt(
        fallback: CapturedContext,
        continuing previousReceipt: TextDeliveryReceipt? = nil
    ) -> TextDeliveryReceipt {
        let snapshot = focusSnapshot()
        let identityMatches: Bool
        if let previousReceipt {
            identityMatches = receiptFocusMatches(snapshot, receipt: previousReceipt)
                && snapshot.focusedElementFingerprint
                    == previousReceipt.focusedElementFingerprint
        } else {
            identityMatches = snapshot.processIdentifier != nil
                && snapshot.bundleIdentifier != nil
        }
        let context = if previousReceipt != nil && !identityMatches {
            fallback
        } else {
            CapturedContext(
                applicationName: snapshot.applicationName ?? fallback.applicationName,
                processIdentifier: snapshot.processIdentifier,
                bundleIdentifier: snapshot.bundleIdentifier,
                windowTitle: fallback.windowTitle,
                selectionState: snapshot.selectionState,
                role: snapshot.role ?? fallback.role,
                subrole: snapshot.subrole ?? fallback.subrole,
                isSecureField: snapshot.safety == .secure
            )
        }
        return TextDeliveryReceipt(
            context: context,
            focusedValueFingerprint: identityMatches && snapshot.safety == .safe
                ? snapshot.focusedValueFingerprint
                : nil,
            focusedElementFingerprint: identityMatches && snapshot.safety == .safe
                ? snapshot.focusedElementFingerprint
                : nil
        )
    }

    private func performReceiptAction(
        _ receipt: TextDeliveryReceipt,
        action: ReceiptAction,
        keyCode: CGKeyCode,
        flags: CGEventFlags = .maskCommand
    ) async throws {
        guard activeTransactionIdentifier == nil else {
            throw LerroError.insertionFailed("另一项文本写入仍在进行")
        }
        guard receipt.canUndo else {
            throw LerroError.insertionFailed("当前输入框无法安全执行该操作")
        }
        let transactionIdentifier = UUID()
        activeTransactionIdentifier = transactionIdentifier
        defer {
            if activeTransactionIdentifier == transactionIdentifier {
                activeTransactionIdentifier = nil
            }
        }

        _ = try await settledReceiptFocus(receipt)
        if let receiptActionOverride {
            try validateReceiptFocus(focusSnapshot(), receipt: receipt)
            try await receiptActionOverride(action, receipt)
            return
        }
        try await MainActor.run {
            try Task.checkCancellation()
            guard CGPreflightPostEventAccess() else {
                throw LerroError.permissionRequired("辅助功能")
            }
            guard let keyDown = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: true
            ), let keyUp = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: false
            ) else {
                throw LerroError.insertionFailed("无法生成键盘事件")
            }
            keyDown.flags = flags
            keyUp.flags = flags
            keyDown.setIntegerValueField(
                .eventSourceUserData,
                value: LerroGeneratedEvent.pasteSourceUserData
            )
            keyUp.setIntegerValueField(
                .eventSourceUserData,
                value: LerroGeneratedEvent.pasteSourceUserData
            )
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func settledReceiptFocus(
        _ receipt: TextDeliveryReceipt
    ) async throws -> DeliveryFocusSnapshot {
        var snapshot = focusSnapshot()
        if !receiptFocusMatches(snapshot, receipt: receipt) {
            guard await activateTarget(receipt.context) else {
                throw LerroError.insertionFailed("原输入应用已关闭或无法激活")
            }
            for attempt in 0..<activationPollAttempts {
                try Task.checkCancellation()
                if attempt > 0 { try await Task.sleep(for: activationPollInterval) }
                snapshot = focusSnapshot()
                if receiptFocusMatches(snapshot, receipt: receipt) { break }
            }
        }
        try validateReceiptFocus(snapshot, receipt: receipt)
        return snapshot
    }

    private func restorePasteboard(_ transaction: PasteboardTransaction) async throws {
        let result = try await MainActor.run {
            try transaction.restoreIfOwned()
        }
        if result == .ownershipLost {
            Self.logger.info("delivery-pasteboard restore-skipped ownership-lost")
        } else {
            Self.logger.debug("delivery-pasteboard restored")
        }
    }

    private func requireExpectedFocus(
        _ snapshot: DeliveryFocusSnapshot,
        context: CapturedContext,
        replacingSelection: Bool
    ) throws {
        try validateExpectedFocus(
            snapshot,
            context: context,
            replacingSelection: replacingSelection
        )
    }

    private func focusMatchesTarget(
        _ snapshot: DeliveryFocusSnapshot,
        context: CapturedContext
    ) -> Bool {
        var hasExpectedIdentity = false
        if let expectedPID = context.processIdentifier {
            hasExpectedIdentity = true
            guard snapshot.processIdentifier == expectedPID else { return false }
        }
        if let expectedBundle = context.bundleIdentifier {
            hasExpectedIdentity = true
            guard snapshot.bundleIdentifier == expectedBundle else { return false }
        }
        return hasExpectedIdentity
    }
}

func finalizeCommittedPasteDelivery(
    waitForConsumption: @escaping @Sendable () async -> Void,
    restorePasteboard: @escaping @Sendable () async throws -> Void
) async throws {
    try await Task.detached {
        await waitForConsumption()
        try await restorePasteboard()
    }.value
}

enum ReceiptAction: Equatable, Sendable {
    case undo
    case correct(String)
    case submit
}

struct ResolvedDeliveryTarget: Equatable, Sendable {
    var processIdentifier: pid_t
    var bundleIdentifier: String?
}

enum DeliveryFocusSafety: Equatable, Sendable {
    case safe
    case secure
    case unavailable
}

struct DeliveryFocusSnapshot: Equatable, Sendable {
    var safety: DeliveryFocusSafety
    var processIdentifier: Int32?
    var bundleIdentifier: String?
    var applicationName: String?
    var focusedElementAvailable: Bool
    var selectionState: TextSelectionState
    var selectedText: String?
    var selectedTextFingerprint: Int?
    var focusedValueFingerprint: Int?
    var focusedElementFingerprint: Int?
    var role: String?
    var subrole: String?

    init(
        safety: DeliveryFocusSafety,
        processIdentifier: Int32? = nil,
        bundleIdentifier: String? = nil,
        applicationName: String? = nil,
        focusedElementAvailable: Bool = true,
        selectionState: TextSelectionState? = nil,
        selectedText: String? = nil,
        selectedTextFingerprint: Int? = nil,
        focusedValueFingerprint: Int? = nil,
        focusedElementFingerprint: Int? = nil,
        role: String? = nil,
        subrole: String? = nil
    ) {
        self.safety = safety
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.focusedElementAvailable = focusedElementAvailable
        self.selectionState = selectionState
            ?? (selectedText?.isEmpty == false ? .knownSelection : .unavailable)
        self.selectedText = selectedText
        self.selectedTextFingerprint = selectedTextFingerprint
        self.focusedValueFingerprint = focusedValueFingerprint
        self.focusedElementFingerprint = focusedElementFingerprint
        self.role = role
        self.subrole = subrole
    }
}

func receiptFocusMatches(
    _ snapshot: DeliveryFocusSnapshot,
    receipt: TextDeliveryReceipt
) -> Bool {
    snapshot.processIdentifier == receipt.context.processIdentifier
        && snapshot.bundleIdentifier == receipt.context.bundleIdentifier
}

func validateReceiptFocus(
    _ snapshot: DeliveryFocusSnapshot,
    receipt: TextDeliveryReceipt
) throws {
    guard receiptFocusMatches(snapshot, receipt: receipt) else {
        throw LerroError.insertionFailed("焦点已切换，回执操作已停用")
    }
    guard snapshot.safety == .safe, snapshot.focusedElementAvailable else {
        throw LerroError.insertionFailed("无法确认当前输入框的安全状态")
    }
    guard let expected = receipt.focusedValueFingerprint,
          snapshot.focusedValueFingerprint == expected else {
        throw LerroError.insertionFailed("输入内容已经变化，回执操作已停用")
    }
    guard let expectedElement = receipt.focusedElementFingerprint,
          snapshot.focusedElementFingerprint == expectedElement else {
        throw LerroError.insertionFailed("当前输入框已变化，回执操作已停用")
    }
}

private func validateExpectedFocus(
    _ snapshot: DeliveryFocusSnapshot,
    context: CapturedContext,
    replacingSelection: Bool
) throws {
    switch snapshot.safety {
    case .safe:
        break
    case .secure:
        throw LerroError.secureField
    case .unavailable:
        throw LerroError.insertionFailed("无法确认当前输入框的安全状态")
    }

    var hasExpectedIdentity = false
    if let expectedPID = context.processIdentifier {
        hasExpectedIdentity = true
        guard snapshot.processIdentifier == expectedPID else {
            throw LerroError.insertionFailed("焦点已切换到其他应用，结果已保留在历史记录中")
        }
    }
    if let expectedBundle = context.bundleIdentifier {
        hasExpectedIdentity = true
        guard snapshot.bundleIdentifier == expectedBundle else {
            throw LerroError.insertionFailed("焦点已切换到其他应用，结果已保留在历史记录中")
        }
    }
    guard hasExpectedIdentity else {
        throw LerroError.insertionFailed("捕获上下文缺少输入应用身份")
    }
    guard snapshot.focusedElementAvailable else {
        throw LerroError.insertionFailed("无法确认当前输入框的焦点状态")
    }
    guard snapshot.selectionState != .unavailable else {
        throw LerroError.insertionFailed("无法安全读取当前选区，结果已保留在历史记录中")
    }

    if replacingSelection {
        guard context.selectionState == .knownSelection,
              snapshot.selectionState == .knownSelection,
              let expectedSelection = context.selectedText else {
            throw LerroError.insertionFailed("无法确认原选区，结果已保留在历史记录中")
        }
        let selectionMatches = if let expectedFingerprint = context.selectedTextFingerprint {
            snapshot.selectedTextFingerprint == expectedFingerprint
        } else {
            snapshot.selectedText == expectedSelection
        }
        guard selectionMatches else {
            throw LerroError.insertionFailed("原选区已变化，结果已保留在历史记录中")
        }
    }
}

private func resolveDeliveryTarget(
    _ snapshot: DeliveryFocusSnapshot,
    context: CapturedContext
) throws -> ResolvedDeliveryTarget {
    guard let processIdentifier = snapshot.processIdentifier else {
        throw LerroError.insertionFailed("无法确认当前输入应用的进程身份")
    }
    return ResolvedDeliveryTarget(
        processIdentifier: processIdentifier,
        bundleIdentifier: snapshot.bundleIdentifier ?? context.bundleIdentifier
    )
}

private func validatedFocusedElement(
    context: CapturedContext,
    replacingSelection: Bool
) throws -> AXUIElement {
    let systemWide = AXUIElementCreateSystemWide()
    guard let focusedApplication = axElement(
        from: systemWide,
        attribute: kAXFocusedApplicationAttribute as CFString
    ) else {
        throw LerroError.insertionFailed("无法确认当前输入应用")
    }
    guard axApplication(focusedApplication, matches: context) else {
        throw LerroError.insertionFailed("焦点已切换到其他应用，结果已保留在历史记录中")
    }
    guard !IsSecureEventInputEnabled() else {
        throw LerroError.secureField
    }
    guard let focusedElement = axElement(
        from: focusedApplication,
        attribute: kAXFocusedUIElementAttribute as CFString
    ) else {
        throw LerroError.insertionFailed("无法确认当前输入框的焦点状态")
    }
    guard !axElementIsSecure(focusedElement) else {
        throw LerroError.secureField
    }
    return focusedElement
}

@MainActor
private func validateSystemDeliveryFocus(
    context: CapturedContext,
    replacingSelection: Bool
) throws {
    try validateExpectedFocus(
        currentDeliveryFocusSnapshot(),
        context: context,
        replacingSelection: replacingSelection
    )
    _ = try validatedFocusedElement(
        context: context,
        replacingSelection: replacingSelection
    )
}

private func axElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
}

private func currentDeliveryFocusSnapshot() -> DeliveryFocusSnapshot {
    let systemWide = AXUIElementCreateSystemWide()
    let secureInputEnabled = IsSecureEventInputEnabled()
    guard let focusedApplication = axElement(
        from: systemWide,
        attribute: kAXFocusedApplicationAttribute as CFString
    ) else {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return DeliveryFocusSnapshot(
                safety: secureInputEnabled ? .secure : .unavailable,
                focusedElementAvailable: false
            )
        }
        return DeliveryFocusSnapshot(
            safety: secureInputEnabled ? .secure : .safe,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            focusedElementAvailable: false
        )
    }
    var processIdentifier: pid_t = 0
    let hasPID = AXUIElementGetPid(focusedApplication, &processIdentifier) == .success
    let bundleIdentifier = hasPID
        ? NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
        : nil
    let applicationName = hasPID
        ? NSRunningApplication(processIdentifier: processIdentifier)?.localizedName
        : nil
    guard let focusedElement = axElement(
        from: focusedApplication,
        attribute: kAXFocusedUIElementAttribute as CFString
    ) else {
        return DeliveryFocusSnapshot(
            safety: secureInputEnabled ? .secure : .safe,
            processIdentifier: hasPID ? processIdentifier : nil,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            focusedElementAvailable: false,
            selectionState: .unavailable
        )
    }
    let selection = deliverySelectionObservation(from: focusedElement)
    let focusedValue = axString(from: focusedElement, attribute: kAXValueAttribute as CFString)
    let role = axString(from: focusedElement, attribute: kAXRoleAttribute as CFString)
    let subrole = axString(from: focusedElement, attribute: kAXSubroleAttribute as CFString)
    let completeSelectedText = selection.text
    let selectedText = completeSelectedText.map { String($0.prefix(4_096)) }
    return DeliveryFocusSnapshot(
        safety: secureInputEnabled || axElementIsSecure(focusedElement) ? .secure : .safe,
        processIdentifier: hasPID ? processIdentifier : nil,
        bundleIdentifier: bundleIdentifier,
        applicationName: applicationName,
        focusedElementAvailable: true,
        selectionState: selection.state,
        selectedText: selectedText?.isEmpty == true ? nil : selectedText,
        selectedTextFingerprint: completeSelectedText?.isEmpty == false
            ? completeSelectedText?.hashValue
            : nil,
        focusedValueFingerprint: focusedValue?.hashValue,
        focusedElementFingerprint: Int(CFHash(focusedElement)),
        role: role,
        subrole: subrole
    )
}

private func deliverySelectionObservation(
    from element: AXUIElement
) -> (state: TextSelectionState, text: String?) {
    let selectedText = axString(
        from: element,
        attribute: kAXSelectedTextAttribute as CFString
    )
    var selectedRange: CFRange?
    var selectedRangeValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &selectedRangeValue
    ) == .success,
       let selectedRangeValue,
       CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() {
        let axValue = unsafeDowncast(selectedRangeValue, to: AXValue.self)
        var selectionRange = CFRange()
        if AXValueGetType(axValue) == .cfRange,
           AXValueGetValue(axValue, .cfRange, &selectionRange),
           selectionRange.location >= 0,
           selectionRange.length >= 0 {
            selectedRange = selectionRange
        }
    }
    return (
        resolvedTextSelectionState(
            selectedText: selectedText,
            selectedRange: selectedRange
        ),
        selectedText
    )
}

private func frontmostApplicationMatches(_ context: CapturedContext) -> Bool {
    guard let application = NSWorkspace.shared.frontmostApplication else { return false }
    var hasExpectedIdentity = false
    if let expectedPID = context.processIdentifier {
        hasExpectedIdentity = true
        guard application.processIdentifier == expectedPID else { return false }
    }
    if let expectedBundle = context.bundleIdentifier {
        hasExpectedIdentity = true
        guard application.bundleIdentifier == expectedBundle else { return false }
    }
    return hasExpectedIdentity
}

private func axApplication(_ application: AXUIElement, matches context: CapturedContext) -> Bool {
    var processIdentifier: pid_t = 0
    guard AXUIElementGetPid(application, &processIdentifier) == .success else { return false }
    var hasExpectedIdentity = false
    if let expectedPID = context.processIdentifier {
        hasExpectedIdentity = true
        guard processIdentifier == expectedPID else { return false }
    }
    if let expectedBundle = context.bundleIdentifier {
        hasExpectedIdentity = true
        guard NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
                == expectedBundle else { return false }
    }
    return hasExpectedIdentity
}

@MainActor
private func activateCapturedApplication(_ context: CapturedContext) -> Bool {
    let application: NSRunningApplication?
    if let processIdentifier = context.processIdentifier {
        application = NSRunningApplication(processIdentifier: processIdentifier)
    } else if let bundleIdentifier = context.bundleIdentifier {
        application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    } else {
        return true
    }
    guard let application, !application.isTerminated else { return false }
    if let expectedBundle = context.bundleIdentifier,
       application.bundleIdentifier != expectedBundle {
        return false
    }
    return application.activate(options: [.activateAllWindows])
}

private func pasteKeyCode() -> CGKeyCode {
    keyCode(for: "v") ?? CGKeyCode(0x09)
}

func makeLerroPasteKeyEvents(
    keyCode: CGKeyCode = pasteKeyCode()
) throws -> (keyDown: CGEvent, keyUp: CGEvent) {
    guard let keyDown = CGEvent(
        keyboardEventSource: nil,
        virtualKey: keyCode,
        keyDown: true
    ),
    let keyUp = CGEvent(
        keyboardEventSource: nil,
        virtualKey: keyCode,
        keyDown: false
    ) else {
        throw LerroError.insertionFailed("无法生成粘贴事件")
    }
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.setIntegerValueField(
        .eventSourceUserData,
        value: LerroGeneratedEvent.pasteSourceUserData
    )
    keyUp.setIntegerValueField(
        .eventSourceUserData,
        value: LerroGeneratedEvent.pasteSourceUserData
    )
    return (keyDown, keyUp)
}

@MainActor
private func submitPasteEvent(
    transaction: PasteboardTransaction,
    target: ResolvedDeliveryTarget,
    context: CapturedContext,
    replacingSelection: Bool,
    onCommit: @escaping TextDeliveryCommitHandler
) throws {
    try Task.checkCancellation()
    guard CGPreflightPostEventAccess() else {
        throw LerroError.permissionRequired("辅助功能")
    }
    guard targetIsFrontmostAndRunning(target) else {
        throw LerroError.insertionFailed("焦点已切换到其他应用，结果已保留在历史记录中")
    }
    guard !IsSecureEventInputEnabled() else {
        throw LerroError.secureField
    }
    try validateExpectedFocus(
        currentDeliveryFocusSnapshot(),
        context: context,
        replacingSelection: replacingSelection
    )
    let focusedElement = try validatedFocusedElement(
        context: context,
        replacingSelection: replacingSelection
    )

    let (keyDown, keyUp) = try makeLerroPasteKeyEvents()
    try Task.checkCancellation()
    guard targetIsFrontmostAndRunning(target) else {
        throw LerroError.insertionFailed("焦点已切换到其他应用，结果已保留在历史记录中")
    }
    guard !IsSecureEventInputEnabled() else {
        throw LerroError.secureField
    }
    guard transaction.isOwned() else {
        throw LerroError.insertionFailed("临时剪贴板已被其他应用更新")
    }
    try Task.checkCancellation()
    guard CGPreflightPostEventAccess() else {
        throw LerroError.permissionRequired("辅助功能")
    }
    guard targetIsFrontmostAndRunning(target) else {
        throw LerroError.insertionFailed("焦点已切换到其他应用，结果已保留在历史记录中")
    }
    guard !IsSecureEventInputEnabled() else {
        throw LerroError.secureField
    }
    try validateExpectedFocus(
        currentDeliveryFocusSnapshot(),
        context: context,
        replacingSelection: replacingSelection
    )
    let currentFocusedElement = try validatedFocusedElement(
        context: context,
        replacingSelection: replacingSelection
    )
    guard CFEqual(currentFocusedElement, focusedElement) else {
        throw LerroError.insertionFailed("当前输入框已变化，结果已保留在历史记录中")
    }
    guard transaction.isOwned() else {
        throw LerroError.insertionFailed("临时剪贴板已被其他应用更新")
    }
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    onCommit()
}

@MainActor
private func targetIsFrontmostAndRunning(_ target: ResolvedDeliveryTarget) -> Bool {
    guard let application = NSRunningApplication(
        processIdentifier: target.processIdentifier
    ),
    !application.isTerminated,
    let frontmostApplication = NSWorkspace.shared.frontmostApplication,
    frontmostApplication.processIdentifier == target.processIdentifier else {
        return false
    }
    if let expectedBundle = target.bundleIdentifier {
        return application.bundleIdentifier == expectedBundle
            && frontmostApplication.bundleIdentifier == expectedBundle
    }
    return true
}

private func keyCode(for character: String) -> CGKeyCode? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let layoutData = unsafeBitCast(rawLayout, to: CFData.self)
    guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
    let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

    for keyCode in 0..<128 {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { continue }
        let value = String(utf16CodeUnits: characters, count: length)
        if value.localizedCaseInsensitiveCompare(character) == .orderedSame {
            return CGKeyCode(keyCode)
        }
    }
    return nil
}

private func axElementIsSecure(_ element: AXUIElement) -> Bool {
    let role = axString(from: element, attribute: kAXRoleAttribute as CFString)
    let subrole = axString(from: element, attribute: kAXSubroleAttribute as CFString)
    return role == (kAXSecureTextFieldSubrole as String)
        || subrole == (kAXSecureTextFieldSubrole as String)
}

private func axString(from element: AXUIElement, attribute: CFString) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return decodedAXTextValue(value)
}

enum PasteboardRestoreResult: Equatable, Sendable {
    case restored
    case ownershipLost
}

typealias PasteboardWriter = @MainActor @Sendable (
    NSPasteboard,
    [NSPasteboardItem]
) -> Bool

@MainActor
private func systemPasteboardWrite(
    _ pasteboard: NSPasteboard,
    _ items: [NSPasteboardItem]
) -> Bool {
    pasteboard.writeObjects(items)
}

@MainActor
struct PasteboardSnapshot: Sendable {
    static let sessionType = NSPasteboard.PasteboardType("app.lerro.mac.paste-session")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    struct Representation: Equatable, Sendable {
        var rawType: String
        var data: Data
    }

    struct Item: Sendable {
        var representations: [Representation]
    }

    var items: [Item]

    static func capture(from pasteboard: NSPasteboard) throws -> PasteboardSnapshot {
        guard let pasteboardItems = pasteboard.pasteboardItems else {
            throw LerroError.insertionFailed("无法读取当前剪贴板内容")
        }
        var capturedItems: [Item] = []
        capturedItems.reserveCapacity(pasteboardItems.count)
        for item in pasteboardItems {
            guard !item.types.isEmpty else {
                throw LerroError.insertionFailed("剪贴板包含无法保存的空项目")
            }
            var representations: [Representation] = []
            representations.reserveCapacity(item.types.count)
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    throw LerroError.insertionFailed("剪贴板包含无法完整读取的数据类型")
                }
                representations.append(Representation(rawType: type.rawValue, data: data))
            }
            capturedItems.append(Item(representations: representations))
        }
        return PasteboardSnapshot(items: capturedItems)
    }

    static func captureBestEffort(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let capturedItems = (pasteboard.pasteboardItems ?? []).map { item in
            Item(
                representations: item.types.compactMap { type in
                    item.data(forType: type).map {
                        Representation(rawType: type.rawValue, data: $0)
                    }
                }
            )
        }
        return PasteboardSnapshot(items: capturedItems)
    }

    func makePasteboardItems() throws -> [NSPasteboardItem] {
        try items.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in snapshot.representations {
                guard item.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.rawType)
                ) else {
                    throw LerroError.insertionFailed("无法重建原剪贴板项目")
                }
            }
            return item
        }
    }

    func matches(_ pasteboard: NSPasteboard) -> Bool {
        guard let pasteboardItems = pasteboard.pasteboardItems,
              pasteboardItems.count == items.count else {
            return false
        }
        for (pasteboardItem, snapshotItem) in zip(pasteboardItems, items) {
            let currentTypes = pasteboardItem.types.map(\.rawValue)
            let expectedTypes = snapshotItem.representations.map(\.rawType)
            guard currentTypes == expectedTypes else { return false }
            for representation in snapshotItem.representations {
                let type = NSPasteboard.PasteboardType(representation.rawType)
                guard pasteboardItem.data(forType: type) == representation.data else {
                    return false
                }
            }
        }
        return true
    }

    func restore(
        to pasteboard: NSPasteboard,
        expectedCurrentChangeCount: Int,
        writer: PasteboardWriter = systemPasteboardWrite
    ) throws -> Bool {
        guard pasteboard.changeCount == expectedCurrentChangeCount else {
            return false
        }
        let firstItems = try makePasteboardItems()
        guard pasteboard.changeCount == expectedCurrentChangeCount else {
            return false
        }
        let firstClearedChangeCount = pasteboard.prepareForNewContents(with: [])
        guard pasteboard.changeCount == firstClearedChangeCount else {
            throw restorationFailure()
        }
        let firstSucceeded = firstItems.isEmpty
            ? matches(pasteboard)
            : writer(pasteboard, firstItems)
                && pasteboard.changeCount == firstClearedChangeCount
                && matches(pasteboard)
        if firstSucceeded { return true }
        guard pasteboard.changeCount == firstClearedChangeCount else {
            throw restorationFailure()
        }

        let retryItems = try makePasteboardItems()
        guard pasteboard.changeCount == firstClearedChangeCount else {
            throw restorationFailure()
        }
        let retryClearedChangeCount = pasteboard.prepareForNewContents(with: [])
        guard pasteboard.changeCount == retryClearedChangeCount else {
            throw restorationFailure()
        }
        let retrySucceeded = retryItems.isEmpty
            ? matches(pasteboard)
            : writer(pasteboard, retryItems)
                && pasteboard.changeCount == retryClearedChangeCount
                && matches(pasteboard)
        guard retrySucceeded else { throw restorationFailure() }
        return true
    }

    private func restorationFailure() -> LerroError {
        LerroError.insertionFailed("文本可能已写入，但原剪贴板内容恢复失败")
    }
}

@MainActor
struct CurrentFocusPasteboardTransaction: Sendable {
    var snapshot: PasteboardSnapshot
    var pasteboardName: String

    static func begin(
        text: String,
        pasteboard: NSPasteboard = .general,
        writer: PasteboardWriter = systemPasteboardWrite
    ) throws -> CurrentFocusPasteboardTransaction {
        let temporaryItem = NSPasteboardItem()
        guard temporaryItem.setString(text, forType: .string),
              temporaryItem.setData(Data(), forType: PasteboardSnapshot.transientType) else {
            throw LerroError.insertionFailed("无法准备临时剪贴板内容")
        }

        let transaction = CurrentFocusPasteboardTransaction(
            snapshot: PasteboardSnapshot.captureBestEffort(from: pasteboard),
            pasteboardName: pasteboard.name.rawValue
        )
        _ = pasteboard.prepareForNewContents(with: .currentHostOnly)
        guard writer(pasteboard, [temporaryItem]) else {
            try? transaction.restore(writer: writer)
            throw LerroError.insertionFailed("无法写入临时剪贴板内容")
        }
        return transaction
    }

    func restore(
        writer: PasteboardWriter = systemPasteboardWrite
    ) throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(pasteboardName))
        let items = try snapshot.makePasteboardItems()
        _ = pasteboard.prepareForNewContents(with: [])
        guard items.isEmpty || writer(pasteboard, items) else {
            throw LerroError.insertionFailed("文本可能已写入，但原剪贴板内容恢复失败")
        }
    }
}

@MainActor
struct PasteboardTransaction: Sendable {
    var snapshot: PasteboardSnapshot
    var expectedChangeCount: Int
    var expectedText: String
    var sessionIdentifier: String
    var pasteboardName: String

    static func begin(
        text: String,
        sessionIdentifier: String,
        pasteboard: NSPasteboard = .general,
        writer: PasteboardWriter = systemPasteboardWrite
    ) throws -> PasteboardTransaction {
        let temporaryItem = NSPasteboardItem()
        guard temporaryItem.setString(text, forType: .string),
              temporaryItem.setString(
                sessionIdentifier,
                forType: PasteboardSnapshot.sessionType
              ),
              temporaryItem.setData(Data(), forType: PasteboardSnapshot.transientType) else {
            throw LerroError.insertionFailed("无法准备临时剪贴板内容")
        }

        let initialChangeCount = pasteboard.changeCount
        let snapshot = try PasteboardSnapshot.capture(from: pasteboard)
        guard pasteboard.changeCount == initialChangeCount else {
            throw LerroError.insertionFailed("读取期间剪贴板已被其他应用更新")
        }

        let clearedChangeCount = pasteboard.prepareForNewContents(with: .currentHostOnly)
        guard pasteboard.changeCount == clearedChangeCount else {
            throw LerroError.insertionFailed("剪贴板状态在写入前发生变化")
        }
        guard writer(pasteboard, [temporaryItem]) else {
            guard pasteboard.changeCount == clearedChangeCount else {
                throw LerroError.insertionFailed(
                    "临时剪贴板写入失败，原剪贴板内容可能未恢复"
                )
            }
            guard try snapshot.restore(
                    to: pasteboard,
                    expectedCurrentChangeCount: clearedChangeCount,
                    writer: writer
            ) else {
                throw LerroError.insertionFailed(
                    "临时剪贴板写入失败，原剪贴板内容可能未恢复"
                )
            }
            throw LerroError.insertionFailed("无法写入临时剪贴板内容")
        }
        guard pasteboard.changeCount == clearedChangeCount else {
            throw LerroError.insertionFailed(
                "临时剪贴板写入后所有权发生变化，原剪贴板内容可能未恢复"
            )
        }

        let transaction = PasteboardTransaction(
            snapshot: snapshot,
            expectedChangeCount: pasteboard.changeCount,
            expectedText: text,
            sessionIdentifier: sessionIdentifier,
            pasteboardName: pasteboard.name.rawValue
        )
        guard transaction.isOwned() else {
            guard pasteboard.changeCount == transaction.expectedChangeCount else {
                throw LerroError.insertionFailed(
                    "临时剪贴板验证期间所有权发生变化，原剪贴板内容可能未恢复"
                )
            }
            guard try snapshot.restore(
                    to: pasteboard,
                    expectedCurrentChangeCount: transaction.expectedChangeCount,
                    writer: writer
            ) else {
                throw LerroError.insertionFailed(
                    "临时剪贴板验证失败，原剪贴板内容可能未恢复"
                )
            }
            throw LerroError.insertionFailed("无法验证临时剪贴板内容")
        }
        return transaction
    }

    func isOwned() -> Bool {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(pasteboardName)
        )
        guard pasteboard.changeCount == expectedChangeCount,
              pasteboard.string(forType: .string) == expectedText,
              pasteboard.string(forType: PasteboardSnapshot.sessionType)
                == sessionIdentifier,
              let items = pasteboard.pasteboardItems,
              items.count == 1,
              let item = items.first else {
            return false
        }
        return item.data(forType: PasteboardSnapshot.transientType) == Data()
    }

    func restoreIfOwned(
        writer: PasteboardWriter = systemPasteboardWrite
    ) throws -> PasteboardRestoreResult {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name(pasteboardName)
        )
        guard isOwned() else { return .ownershipLost }
        guard try snapshot.restore(
            to: pasteboard,
            expectedCurrentChangeCount: expectedChangeCount,
            writer: writer
        ) else { return .ownershipLost }
        return .restored
    }
}
