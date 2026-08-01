import Foundation

public actor FilePreferencesRepository: PreferencesRepository {
    private let store: JSONDocumentStore<UserPreferences>

    public init(fileURL: URL) {
        self.store = JSONDocumentStore(
            url: fileURL,
            fallback: { UserPreferences() },
            filePermissions: 0o600
        )
    }

    public func load() async throws -> UserPreferences {
        try await store.read()
    }

    public func save(_ preferences: UserPreferences) async throws {
        try await store.write(preferences)
    }
}
