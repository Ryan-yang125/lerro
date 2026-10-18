import Foundation

public actor FileAIUsageRepository: AIUsageRepository {
    private let store: JSONDocumentStore<[AIUsageRecord]>
    private let now: @Sendable () -> Date

    public init(fileURL: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = JSONDocumentStore(url: fileURL, fallback: { [] }, filePermissions: 0o600)
        self.now = now
    }

    public func append(_ record: AIUsageRecord) async throws {
        let cutoff = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -AIUsageRecord.retentionDays,
            to: now()
        ) ?? .distantPast
        try await store.mutate { values in
            values.removeAll { $0.date < cutoff }
            values.append(record)
        }
    }

    public func records(since: Date) async throws -> [AIUsageRecord] {
        try await store.read()
            .filter { $0.date >= since }
            .sorted { $0.date < $1.date }
    }

    public func deleteAll() async throws {
        try await store.write([])
    }
}
