import Foundation

/// Aggregated dictation numbers for one calendar day. Holds counts only: no
/// transcript, window title or other text from the capture.
public struct DailyUsage: Codable, Equatable, Sendable {
    /// Completed captures older than this many days are pruned on write.
    public static let retentionDays = 400

    /// "yyyy-MM-dd" in the calendar's time zone at record time.
    public var day: String
    public var words: Int
    public var dictations: Int
    public var duration: TimeInterval
    /// Key: bundle identifier, or "name:<appName>" when there is none.
    public var apps: [String: AppDailyUsage]
    /// Exactly 24 counts of dictations by hour of day.
    public var hours: [Int]

    public init(day: String) {
        self.day = day
        self.words = 0
        self.dictations = 0
        self.duration = 0
        self.apps = [:]
        self.hours = Array(repeating: 0, count: 24)
    }
}

public struct AppDailyUsage: Codable, Equatable, Sendable {
    public var name: String
    public var bundleIdentifier: String?
    public var words: Int
}

public protocol DailyUsageRepository: Sendable {
    /// Sorted by day, oldest first.
    func days() async throws -> [DailyUsage]
    /// Adds one completed capture and prunes days older than `DailyUsage.retentionDays`.
    func record(_ entry: HistoryEntry) async throws
    /// Replaces the stored days, used for the one-time seed from history.
    func replaceAll(_ days: [DailyUsage]) async throws
    func deleteAll() async throws
}

extension DailyUsage {
    /// Builds days from history. Only `.completed` entries count.
    public static func seed(from entries: [HistoryEntry], calendar: Calendar) -> [DailyUsage] {
        var days: [String: DailyUsage] = [:]
        for entry in entries where entry.status == .completed {
            let key = dayKey(for: entry.createdAt, calendar: calendar)
            days[key, default: DailyUsage(day: key)].add(entry, calendar: calendar)
        }
        return days.values.sorted { $0.day < $1.day }
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Start of the day named by `day`, nil when the key is malformed.
    func startOfDay(calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Adds `entry` to `days`, keeping them sorted, and prunes expired days.
    /// Entries that are not `.completed` are ignored.
    static func record(
        _ entry: HistoryEntry,
        into days: inout [DailyUsage],
        calendar: Calendar,
        now: Date
    ) {
        guard entry.status == .completed else { return }
        let key = dayKey(for: entry.createdAt, calendar: calendar)
        if let index = days.firstIndex(where: { $0.day == key }) {
            days[index].add(entry, calendar: calendar)
        } else {
            var day = DailyUsage(day: key)
            day.add(entry, calendar: calendar)
            days.append(day)
            days.sort { $0.day < $1.day }
        }
        let cutoff = dayKey(
            for: calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now,
            calendar: calendar
        )
        days.removeAll { $0.day < cutoff }
    }

    private mutating func add(_ entry: HistoryEntry, calendar: Calendar) {
        let entryWords = TextMetrics.countWords(in: entry.finalText)
        words += entryWords
        dictations += 1
        duration += entry.duration
        hours[calendar.component(.hour, from: entry.createdAt)] += 1

        let bundleIdentifier = entry.bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        let key: String
        if let bundleIdentifier {
            key = bundleIdentifier
        } else if !entry.applicationName.isEmpty {
            key = "name:" + entry.applicationName
        } else {
            return
        }
        var app = apps[key] ?? AppDailyUsage(
            name: entry.applicationName,
            bundleIdentifier: bundleIdentifier,
            words: 0
        )
        if !entry.applicationName.isEmpty { app.name = entry.applicationName }
        app.words += entryWords
        apps[key] = app
    }
}
