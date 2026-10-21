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
    /// How an automatically learned term was misrecognized before. Latest last, at most 5.
    public var heardAs: [String]
    /// History entries the term was learned from. At most 5.
    public var learnedFromEntryIDs: [UUID]
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        phrase: String,
        replacement: String? = nil,
        source: DictionaryEntrySource = .manual,
        applicationBundleIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        useCount: Int = 0,
        heardAs: [String] = [],
        learnedFromEntryIDs: [UUID] = [],
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.phrase = phrase
        self.replacement = replacement ?? phrase
        self.source = source
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useCount = useCount
        self.heardAs = heardAs
        self.learnedFromEntryIDs = learnedFromEntryIDs
        self.lastUsedAt = lastUsedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        phrase = try container.decode(String.self, forKey: .phrase)
        replacement = try container.decode(String.self, forKey: .replacement)
        source = try container.decode(DictionaryEntrySource.self, forKey: .source)
        applicationBundleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .applicationBundleIdentifier
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        useCount = try container.decode(Int.self, forKey: .useCount)
        heardAs = try container.decodeIfPresent([String].self, forKey: .heardAs) ?? []
        learnedFromEntryIDs = try container.decodeIfPresent([UUID].self, forKey: .learnedFromEntryIDs) ?? []
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
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
