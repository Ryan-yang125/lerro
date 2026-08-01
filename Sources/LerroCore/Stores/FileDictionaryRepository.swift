import Foundation

public actor FileDictionaryRepository: DictionaryRepository {
    private let store: JSONDocumentStore<[DictionaryEntry]>

    public init(fileURL: URL) {
        self.store = JSONDocumentStore(url: fileURL, fallback: { [] })
    }

    public func entries() async throws -> [DictionaryEntry] {
        try await store.read().sorted { lhs, rhs in
            lhs.updatedAt == rhs.updatedAt ? lhs.phrase < rhs.phrase : lhs.updatedAt > rhs.updatedAt
        }
    }

    public func save(_ entry: DictionaryEntry) async throws {
        var updated = entry
        updated.updatedAt = .now
        let entryToSave = updated
        try await store.mutate { values in
            if let index = values.firstIndex(where: { $0.id == entryToSave.id }) {
                values[index] = entryToSave
            } else {
                values.append(entryToSave)
            }
        }
    }

    public func delete(id: UUID) async throws {
        try await store.mutate { values in
            values.removeAll { $0.id == id }
        }
    }

    public func importEntries(_ entries: [DictionaryEntry]) async throws {
        try await store.mutate { values in
            for entry in entries {
                if let index = values.firstIndex(where: {
                    $0.phrase.caseInsensitiveCompare(entry.phrase) == .orderedSame
                        && $0.applicationBundleIdentifier == entry.applicationBundleIdentifier
                }) {
                    values[index] = entry
                } else {
                    values.append(entry)
                }
            }
        }
    }
}
