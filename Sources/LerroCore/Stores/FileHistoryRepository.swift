import Foundation

public actor FileHistoryRepository: HistoryRepository {
    private let store: JSONDocumentStore<[HistoryEntry]>
    private var cachedSnapshot: CachedSnapshot?

    private struct CachedSnapshot {
        let revision: UInt64
        let entries: [HistoryEntry]
    }

    public init(fileURL: URL) {
        self.store = JSONDocumentStore(url: fileURL, fallback: { [] })
    }

    public func entries() async throws -> [HistoryEntry] {
        try await snapshot().entries
    }

    public func page(_ request: HistoryPageRequest) async throws -> HistoryPage {
        let snapshot = try await snapshot().entries
        let matches: [HistoryEntry]
        if request.searchText.isEmpty, request.mode == nil {
            matches = snapshot
        } else {
            matches = snapshot.filter { entry in
                let matchesMode = request.mode.map { entry.mode == $0 } ?? true
                let matchesSearch = request.searchText.isEmpty
                    || entry.finalText.localizedCaseInsensitiveContains(request.searchText)
                    || entry.applicationName.localizedCaseInsensitiveContains(request.searchText)
                return matchesMode && matchesSearch
            }
        }

        let start = min(request.offset, matches.count)
        let end = min(matches.count, start + request.limit)
        return HistoryPage(
            entries: Array(matches[start..<end]),
            totalCount: matches.count,
            hasMore: end < matches.count
        )
    }

    public func save(_ entry: HistoryEntry) async throws {
        try await mutateSnapshot { values in
            if let index = values.firstIndex(where: { $0.id == entry.id }) {
                guard values[index] != entry else { return false }
                values[index] = entry
            } else {
                values.append(entry)
            }
            return true
        }
    }

    public func delete(id: UUID) async throws {
        try await mutateSnapshot { values in
            let originalCount = values.count
            values.removeAll { $0.id == id }
            return values.count != originalCount
        }
    }

    public func deleteAll() async throws {
        try await mutateSnapshot { values in
            guard !values.isEmpty else { return false }
            values.removeAll()
            return true
        }
    }

    public func applyRetention(_ retention: HistoryRetention, now: Date = .now) async throws {
        guard retention != .forever, retention != .never else { return }

        try await mutateSnapshot { values in
            let originalCount = values.count
            values.removeAll { !retention.retains(createdAt: $0.createdAt, now: now) }
            return values.count != originalCount
        }
    }

    private func snapshot() async throws -> CachedSnapshot {
        if let cachedSnapshot,
           try await store.isCurrent(revision: cachedSnapshot.revision) {
            return cachedSnapshot
        }
        cachedSnapshot = nil

        let result = try await store.readSnapshot()
        let candidate = CachedSnapshot(
            revision: result.revision,
            entries: Self.sorted(result.value)
        )
        acceptSnapshot(candidate)
        return cachedSnapshot ?? candidate
    }

    private func mutateSnapshot(
        _ update: @Sendable ([HistoryEntry]) -> [HistoryEntry]?
    ) async throws {
        while true {
            let base = try await snapshot()
            guard let updated = update(base.entries) else { return }
            let sorted = Self.sorted(updated)
            if let revision = try await store.write(sorted, ifRevision: base.revision) {
                acceptSnapshot(CachedSnapshot(revision: revision, entries: sorted))
                return
            }
            if cachedSnapshot?.revision == base.revision {
                cachedSnapshot = nil
            }
        }
    }

    private func mutateSnapshot(
        _ update: @Sendable (inout [HistoryEntry]) -> Bool
    ) async throws {
        try await mutateSnapshot { current in
            var updated = current
            return update(&updated) ? updated : nil
        }
    }

    private func acceptSnapshot(_ candidate: CachedSnapshot) {
        guard cachedSnapshot.map({ candidate.revision >= $0.revision }) ?? true else { return }
        cachedSnapshot = candidate
    }

    private static func sorted(_ values: [HistoryEntry]) -> [HistoryEntry] {
        values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
