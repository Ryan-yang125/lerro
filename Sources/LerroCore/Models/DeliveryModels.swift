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

    public var canUndo: Bool {
        context.processIdentifier != nil
            && context.bundleIdentifier != nil
            && focusedValueFingerprint != nil
            && focusedElementFingerprint != nil
            && !context.isSecureField
    }
}

public struct VoiceFinishApplication: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var bundleIdentifier: String
    public var applicationName: String

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, applicationName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
    }
}

public struct VoiceFinishResolution: Equatable, Sendable {
    public var text: String
    public var requestsSubmit: Bool

    public init(text: String, requestsSubmit: Bool) {
        self.text = text
        self.requestsSubmit = requestsSubmit
    }
}

public enum VoiceFinishActionResolver {
    private static let suffixes = [
        "send it",
        "发送",
    ]

    public static func resolve(_ transcript: String) -> VoiceFinishResolution {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandCandidate = trimmed.trimmingCharacters(in: trailingPunctuation)
        for suffix in suffixes {
            guard let range = commandCandidate.range(
                of: suffix,
                options: [.caseInsensitive, .anchored, .backwards]
            ) else { continue }
            let prefix = commandCandidate[..<range.lowerBound]
                .trimmingCharacters(in: finishSeparators)
            guard !prefix.isEmpty else { continue }
            return VoiceFinishResolution(text: prefix, requestsSubmit: true)
        }
        return VoiceFinishResolution(text: trimmed, requestsSubmit: false)
    }

    public static func permitsSubmit(in context: CapturedContext) -> Bool {
        guard !context.isSecureField,
              context.processIdentifier != nil,
              context.bundleIdentifier != nil else { return false }
        guard context.role == "AXTextArea" || context.role == "AXTextField" else { return false }
        let rejectedSubroles = [
            "AXSearchField",
            "AXAddressField",
            "AXSecureTextField",
        ]
        guard !rejectedSubroles.contains(context.subrole ?? "") else { return false }
        let bundle = context.bundleIdentifier?.lowercased() ?? ""
        let rejectedBundleFragments = [
            "terminal",
            "iterm",
            "warp",
            "alacritty",
            "wezterm",
        ]
        return !rejectedBundleFragments.contains { bundle.contains($0) }
    }

    private static let finishSeparators = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: ",.!?;:，。！？；：")
    )
    private static let trailingPunctuation = CharacterSet(charactersIn: ",.!?;:，。！？；：")
}
