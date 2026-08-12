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

public protocol RecoveryTextCopying: Sendable {
    func copyForRecovery(_ text: String) async throws
}

public struct DeliveredTextEdit: Equatable, Sendable {
    public var originalSpan: String
    public var correctedSpan: String
    public var contextBefore: String?
    public var contextAfter: String?
    public var applicationName: String
    public var bundleIdentifier: String?

    public init(
        originalSpan: String,
        correctedSpan: String,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        applicationName: String,
        bundleIdentifier: String? = nil
    ) {
        self.originalSpan = originalSpan
        self.correctedSpan = correctedSpan
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
    }
}

public protocol DeliveredTextObserving: Sendable {
    func observe(
        text: String,
        receipt: TextDeliveryReceipt,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<DeliveredTextEdit, any Error>
    func stopObserving() async
}

public struct ApplicationDescriptor: Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public var bundleIdentifier: String
    public var name: String
    public var bundleURL: String?
    public var iconData: Data?
    public var isRunning: Bool

    public init(
        bundleIdentifier: String,
        name: String,
        bundleURL: String? = nil,
        iconData: Data? = nil,
        isRunning: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.bundleURL = bundleURL
        self.iconData = iconData
        self.isRunning = isRunning
    }
}

public protocol ApplicationCataloging: Sendable {
    func applications() async -> [ApplicationDescriptor]
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
