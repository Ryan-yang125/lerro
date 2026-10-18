import Foundation

public actor FileDictionarySuggestionRepository: DictionarySuggestionRepository {
    private let store: JSONDocumentStore<DictionarySuggestionState>

    public init(fileURL: URL) {
        self.store = JSONDocumentStore(
            url: fileURL,
            fallback: { DictionarySuggestionState() },
            filePermissions: 0o600
        )
    }

    public func load() async throws -> DictionarySuggestionState {
        try await store.read()
    }

    public func save(_ state: DictionarySuggestionState) async throws {
        try await store.write(state)
    }
}
