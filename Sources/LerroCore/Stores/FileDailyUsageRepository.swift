import Foundation

public actor FileDailyUsageRepository: DailyUsageRepository {
    private let store: JSONDocumentStore<[DailyUsage]>
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        fileURL: URL,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = JSONDocumentStore(url: fileURL, fallback: { [] }, filePermissions: 0o600)
        self.calendar = calendar
        self.now = now
    }

    public func days() async throws -> [DailyUsage] {
        try await store.read().sorted { $0.day < $1.day }
    }

    public func record(_ entry: HistoryEntry) async throws {
        let calendar = calendar
        let now = now()
        try await store.mutate { days in
            DailyUsage.record(entry, into: &days, calendar: calendar, now: now)
        }
    }

    public func replaceAll(_ days: [DailyUsage]) async throws {
        try await store.write(days.sorted { $0.day < $1.day })
    }

    public func deleteAll() async throws {
        try await store.write([])
    }
}
