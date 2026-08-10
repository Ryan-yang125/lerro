import Foundation

public protocol ContextCapturing: Sendable {
    func captureCurrentContext() async -> CapturedContext
}

public enum TextDeliveryTargetPolicy: Sendable, Equatable {
    /// Automatic capture results are delivered only while the captured app is
    /// still the current keyboard target. This prevents a late result from
    /// stealing focus or writing into an app the user switched to.
    case requireCurrent

    /// Explicit user actions, such as inserting from the Ask card, may restore
    /// the app captured with that card before delivery.
    case reactivateCaptured
}

public typealias TextDeliveryCommitHandler = @MainActor @Sendable () -> Void

public protocol TextDelivering: Sendable {
    @discardableResult
    func deliver(
        _ text: String,
        to context: CapturedContext,
        replacingSelection: Bool,
        targetPolicy: TextDeliveryTargetPolicy,
        onCommit: @escaping TextDeliveryCommitHandler
    ) async throws -> TextDeliveryReceipt

    func undo(_ receipt: TextDeliveryReceipt) async throws
    @discardableResult
    func correct(
        _ text: String,
        using receipt: TextDeliveryReceipt
    ) async throws -> TextDeliveryReceipt
    func submit(_ receipt: TextDeliveryReceipt) async throws
}

public extension TextDelivering {
    @discardableResult
    func deliver(
        _ text: String,
        to context: CapturedContext,
        replacingSelection: Bool,
        targetPolicy: TextDeliveryTargetPolicy
    ) async throws -> TextDeliveryReceipt {
        try await deliver(
            text,
            to: context,
            replacingSelection: replacingSelection,
            targetPolicy: targetPolicy,
            onCommit: {}
        )
    }
}

public protocol HotkeyMonitoring: AnyObject, Sendable {
    func start(handler: @escaping @Sendable (HotkeyTrigger) -> Void) throws
    func update(definitions: [HotkeyDefinition])
    func resetTransientState()
    func stop()
}

public protocol PermissionChecking: Sendable {
    func microphoneAuthorized() async -> Bool
    func requestMicrophone() async -> Bool
    func accessibilityAuthorized(prompt: Bool) -> Bool
}

public protocol LoginItemManaging: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
    func reconcileAfterIdentityMigration(
        enabled: Bool
    ) throws -> LoginItemIdentityMigrationStatus
}

public extension LoginItemManaging {
    func reconcileAfterIdentityMigration(
        enabled: Bool
    ) throws -> LoginItemIdentityMigrationStatus {
        if isEnabled() != enabled {
            try setEnabled(enabled)
        }
        return .completed
    }
}

public protocol ApplicationIdentityMonitoring: Sendable {
    func legacyApplicationIsRunning() -> Bool
}
