import Foundation

public actor InMemoryHistoryRepository: HistoryRepository {
    private var values: [HistoryEntry]

    public init(entries: [HistoryEntry] = []) {
        self.values = entries
    }

    public func entries() -> [HistoryEntry] {
        values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
    public func page(_ request: HistoryPageRequest) -> HistoryPage {
        let matches = entries().filter { entry in
            let matchesMode = request.mode.map { entry.mode == $0 } ?? true
            let matchesSearch = request.searchText.isEmpty
                || entry.finalText.localizedCaseInsensitiveContains(request.searchText)
                || entry.applicationName.localizedCaseInsensitiveContains(request.searchText)
            return matchesMode && matchesSearch
        }
        let start = min(request.offset, matches.count)
        let end = min(matches.count, start + request.limit)
        return HistoryPage(
            entries: Array(matches[start..<end]),
            totalCount: matches.count,
            hasMore: end < matches.count
        )
    }
    public func save(_ entry: HistoryEntry) {
        values.removeAll { $0.id == entry.id }
        values.append(entry)
    }
    public func delete(id: UUID) { values.removeAll { $0.id == id } }
    public func deleteAll() { values.removeAll() }
    public func applyRetention(_ retention: HistoryRetention, now: Date) {
        guard retention != .forever, retention != .never else { return }
        values.removeAll { !retention.retains(createdAt: $0.createdAt, now: now) }
    }
}

public actor InMemoryDictionaryRepository: DictionaryRepository {
    private var values: [DictionaryEntry]
    public init(entries: [DictionaryEntry] = []) { self.values = entries }
    public func entries() -> [DictionaryEntry] { values }
    public func save(_ entry: DictionaryEntry) {
        values.removeAll { $0.id == entry.id }
        values.append(entry)
    }
    public func delete(id: UUID) { values.removeAll { $0.id == id } }
    public func importEntries(_ entries: [DictionaryEntry]) { values.append(contentsOf: entries) }
}

public actor InMemoryPreferencesRepository: PreferencesRepository {
    private var value: UserPreferences
    public init(value: UserPreferences = UserPreferences()) { self.value = value }
    public func load() -> UserPreferences { value }
    public func save(_ preferences: UserPreferences) { value = preferences }
}

public actor InMemoryAIUsageRepository: AIUsageRepository {
    private var values: [AIUsageRecord]
    public init(records: [AIUsageRecord] = []) { self.values = records }
    public func append(_ record: AIUsageRecord) { values.append(record) }
    public func records(since: Date) -> [AIUsageRecord] {
        values.filter { $0.date >= since }.sorted { $0.date < $1.date }
    }
    public func deleteAll() { values.removeAll() }
}

public actor InMemoryDailyUsageRepository: DailyUsageRepository {
    private var values: [DailyUsage]
    private let calendar: Calendar
    public init(days: [DailyUsage] = [], calendar: Calendar = .current) {
        self.values = days.sorted { $0.day < $1.day }
        self.calendar = calendar
    }
    public func days() -> [DailyUsage] { values }
    public func record(_ entry: HistoryEntry) {
        DailyUsage.record(entry, into: &values, calendar: calendar, now: Date())
    }
    public func replaceAll(_ days: [DailyUsage]) { values = days.sorted { $0.day < $1.day } }
    public func deleteAll() { values.removeAll() }
}
