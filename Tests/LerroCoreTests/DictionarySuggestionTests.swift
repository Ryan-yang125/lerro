import Foundation
import Testing
@testable import LerroCore

@Suite("Dictionary suggestions")
struct DictionarySuggestionTests {
    private func candidate(_ phrase: String, _ replacement: String) -> DictionaryLearningCandidate {
        DictionaryLearningCandidate(phrase: phrase, replacement: replacement, confidence: 0.9)
    }

    @Test("Keys ignore case and surrounding whitespace")
    func keyNormalization() {
        #expect(
            DictionarySuggestion.key(phrase: " Code X ", replacement: "Codex\n")
                == DictionarySuggestion.key(phrase: "code x", replacement: "codex")
        )
        #expect(
            DictionarySuggestion.key(phrase: "a", replacement: "b")
                != DictionarySuggestion.key(phrase: "b", replacement: "a")
        )
        #expect(DictionarySuggestion(phrase: "史册", replacement: "实测").id == "史册\u{0}实测")
    }

    @Test("Merging an existing mapping increments occurrences and keeps the newest sighting")
    func mergeIncrements() {
        var state = DictionarySuggestionState()
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        state.merge(candidate: candidate("史册", "实测"), seenAt: late, applicationName: "Slack")
        state.merge(candidate: candidate("史册", "实测"), seenAt: early, applicationName: "Notes")
        #expect(state.suggestions.count == 1)
        #expect(state.suggestions[0].occurrences == 2)
        #expect(state.suggestions[0].lastSeen == late)
        #expect(state.suggestions[0].applicationName == "Slack")

        let latest = Date(timeIntervalSince1970: 3_000)
        state.merge(candidate: candidate("史册", "实测"), seenAt: latest, applicationName: "Mail")
        #expect(state.suggestions[0].occurrences == 3)
        #expect(state.suggestions[0].lastSeen == latest)
        #expect(state.suggestions[0].applicationName == "Mail")
    }

    @Test("Ignored mappings are not added again")
    func ignoredKeysAreNotReAdded() {
        var state = DictionarySuggestionState()
        state.merge(candidate: candidate("糊涂", "富途"), seenAt: .now, applicationName: nil)
        let suggestion = state.suggestions[0]
        state.ignore(suggestion)
        #expect(state.suggestions.isEmpty)
        #expect(state.ignoredKeys == [suggestion.id])

        state.merge(candidate: candidate("糊涂", "富途"), seenAt: .now, applicationName: nil)
        #expect(state.suggestions.isEmpty)
    }

    @Test("The file repository round-trips the state")
    func fileRepositoryRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "lerro-suggestions-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileDictionarySuggestionRepository(
            fileURL: directory.appending(path: "dictionary-suggestions.json")
        )
        #expect(try await repository.load() == DictionarySuggestionState())

        var state = DictionarySuggestionState()
        state.scannedEntryIDs = [UUID()]
        state.ignoredKeys = ["a\u{0}b"]
        state.merge(
            candidate: candidate("畅巧", "长桥"),
            seenAt: Date(timeIntervalSince1970: 1_700_000_000),
            applicationName: "Claude"
        )
        try await repository.save(state)
        #expect(try await repository.load() == state)
    }
}
