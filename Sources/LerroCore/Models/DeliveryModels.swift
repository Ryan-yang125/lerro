import Foundation

public struct TextDeliveryReceipt: Equatable, Sendable {
    public var id: UUID
    public var committedAt: Date
    public var context: CapturedContext
    public var focusedValueFingerprint: Int?
    public var focusedElementFingerprint: Int?

    public init(
        id: UUID = UUID(),
        committedAt: Date = .now,
        context: CapturedContext,
        focusedValueFingerprint: Int? = nil,
        focusedElementFingerprint: Int? = nil
    ) {
        self.id = id
        self.committedAt = committedAt
        self.context = context
        self.focusedValueFingerprint = focusedValueFingerprint
        self.focusedElementFingerprint = focusedElementFingerprint
    }
}
