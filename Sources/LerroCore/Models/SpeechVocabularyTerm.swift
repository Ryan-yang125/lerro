import Foundation

public struct SpeechVocabularyTerm: Codable, Equatable, Hashable, Sendable {
    public var phrase: String
    public var replacement: String
    public var applicationBundleIdentifier: String?
    public var priority: Int

    public init(
        phrase: String,
        replacement: String? = nil,
        applicationBundleIdentifier: String? = nil,
        priority: Int = 0
    ) {
        self.phrase = phrase
        self.replacement = replacement ?? phrase
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.priority = priority
    }

    public init(dictionaryEntry: DictionaryEntry, priority: Int? = nil) {
        self.init(
            phrase: dictionaryEntry.phrase,
            replacement: dictionaryEntry.replacement,
            applicationBundleIdentifier: dictionaryEntry.applicationBundleIdentifier,
            priority: priority ?? dictionaryEntry.useCount
        )
    }
}
