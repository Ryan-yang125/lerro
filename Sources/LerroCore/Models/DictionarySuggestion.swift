import Foundation

/// A correction the AI polish applied to a recognized phrase, waiting for the
/// user to add it to the dictionary or ignore it.
public struct DictionarySuggestion: Codable, Hashable, Sendable, Identifiable {
    /// What speech recognition produced.
    public var phrase: String
    /// What the AI corrected it to.
    public var replacement: String
    public var occurrences: Int
    public var lastSeen: Date
    /// Application of the most recent occurrence.
    public var applicationName: String?

    public var id: String { DictionarySuggestion.key(phrase: phrase, replacement: replacement) }

    public init(
        phrase: String,
        replacement: String,
        occurrences: Int = 1,
        lastSeen: Date = .now,
        applicationName: String? = nil
    ) {
        self.phrase = phrase
        self.replacement = replacement
        self.occurrences = occurrences
        self.lastSeen = lastSeen
        self.applicationName = applicationName
    }

    public static func key(phrase: String, replacement: String) -> String {
        let source = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let target = replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(source)\u{0}\(target)"
    }
}

public struct DictionarySuggestionState: Codable, Sendable, Equatable {
    public var scannedEntryIDs: Set<UUID> = []
    public var suggestions: [DictionarySuggestion] = []
    public var ignoredKeys: Set<String> = []

    public init() {}

    /// Counts one more occurrence of the candidate. Ignored mappings are not added.
    public mutating func merge(
        candidate: DictionaryLearningCandidate,
        seenAt: Date,
        applicationName: String?
    ) {
        let phrase = candidate.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = candidate.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !replacement.isEmpty else { return }
        let key = DictionarySuggestion.key(phrase: phrase, replacement: replacement)
        guard !ignoredKeys.contains(key) else { return }
        if let index = suggestions.firstIndex(where: { $0.id == key }) {
            suggestions[index].occurrences += 1
            if seenAt > suggestions[index].lastSeen {
                suggestions[index].lastSeen = seenAt
                suggestions[index].applicationName = applicationName
            }
        } else {
            suggestions.append(DictionarySuggestion(
                phrase: phrase,
                replacement: replacement,
                occurrences: 1,
                lastSeen: seenAt,
                applicationName: applicationName
            ))
        }
    }

    public mutating func remove(_ suggestion: DictionarySuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
    }

    public mutating func ignore(_ suggestion: DictionarySuggestion) {
        ignoredKeys.insert(suggestion.id)
        remove(suggestion)
    }
}

public protocol DictionarySuggestionRepository: Sendable {
    func load() async throws -> DictionarySuggestionState
    func save(_ state: DictionarySuggestionState) async throws
}
