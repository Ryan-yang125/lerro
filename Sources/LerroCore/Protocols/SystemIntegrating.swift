import Foundation

public protocol ContextCapturing: Sendable {
    func captureCurrentContext() async -> CapturedContext
}

public typealias TextDeliveryCommitHandler = @MainActor @Sendable () -> Void

public protocol TextDelivering: Sendable {
    @discardableResult
    func deliver(
        _ text: String,
        to context: CapturedContext,
        onCommit: @escaping TextDeliveryCommitHandler
    ) async throws -> TextDeliveryReceipt
}

public extension TextDelivering {
    @discardableResult
    func deliver(
        _ text: String,
        to context: CapturedContext
    ) async throws -> TextDeliveryReceipt {
        try await deliver(
            text,
            to: context,
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
}
