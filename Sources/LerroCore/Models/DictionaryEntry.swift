import Foundation

public enum DictionaryEntrySource: String, CaseIterable, Codable, Sendable {
    case manual
    case learned
}

public struct DictionaryEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var phrase: String
    public var replacement: String
    public var source: DictionaryEntrySource
    public var applicationBundleIdentifier: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var useCount: Int

    public var isSnippet: Bool {
        source == .manual && replacement != phrase
    }

    public init(
        id: UUID = UUID(),
        phrase: String,
        replacement: String? = nil,
        source: DictionaryEntrySource = .manual,
        applicationBundleIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        useCount: Int = 0
    ) {
        self.id = id
        self.phrase = phrase
        self.replacement = replacement ?? phrase
        self.source = source
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
    }
}

public struct AppToneProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public var bundleIdentifier: String
    public var applicationName: String
    public var instruction: String
    public var enabled: Bool

    public init(bundleIdentifier: String, applicationName: String, instruction: String, enabled: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.instruction = instruction
        self.enabled = enabled
    }
}
