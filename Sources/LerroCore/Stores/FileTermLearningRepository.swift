import Foundation

public actor FileTermLearningRepository: TermLearningRepository {
    private let store: JSONDocumentStore<TermLearningState>

    public init(fileURL: URL) {
        self.store = JSONDocumentStore(url: fileURL, fallback: { .empty }, filePermissions: 0o600)
    }

    public func load() async throws -> TermLearningState {
        try await store.read()
    }

    public func save(_ state: TermLearningState) async throws {
        try await store.write(state)
    }

    public func deleteAll() async throws {
        try await store.write(.empty)
    }
}
