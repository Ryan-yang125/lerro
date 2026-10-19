import Foundation

/// Everything the Home page shows, derived from `DailyUsage` days.
public struct HomeStatistics: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public var id: Date { date }
        /// Start of day.
        public var date: Date
        public var words: Int
        public var dictations: Int
        /// 0...4. 0 means no use.
        public var level: Int
        public var isFuture: Bool
        public var isToday: Bool
    }

    public struct AppShare: Equatable, Sendable, Identifiable {
        /// Same key as `DailyUsage.apps`.
        public var id: String
        public var name: String
        public var bundleIdentifier: String?
        public var words: Int
        /// 0...1 of all words in the window.
        public var share: Double
    }

    public struct MonthLabel: Equatable, Sendable {
        public var column: Int
        /// 1...12.
        public var month: Int
    }

    /// Number of week columns in `weeks`.
    static let weekCount = 53

    /// All retained days.
    public var total: UsageSummary
    public var totalDictations: Int
    public var today: UsageSummary
    public var todayDictations: Int
    /// Days with dictations in the weeks shown.
    public var activeDays: Int
    /// Consecutive active days ending today, or yesterday when today has no use yet.
    public var currentStreak: Int
    /// Over all retained days.
    public var longestStreak: Int
    /// 53 columns of 7 days, Sunday to Saturday. The last column contains today.
    public var weeks: [[Day]]
    /// One label per column that contains the 1st of a month, except the last two columns.
    public var monthLabels: [MonthLabel]
    /// Up to 5 apps by words, over the weeks shown.
    public var topApps: [AppShare]
    /// 24 counts of dictations by hour, over the weeks shown.
    public var hourCounts: [Int]
    /// Nil when there are no dictations.
    public var peakHour: Int?

    public static let empty = HomeStatistics(
        total: UsageSummary(),
        totalDictations: 0,
        today: UsageSummary(),
        todayDictations: 0,
        activeDays: 0,
        currentStreak: 0,
        longestStreak: 0,
        weeks: [],
        monthLabels: [],
        topApps: [],
        hourCounts: Array(repeating: 0, count: 24),
        peakHour: nil
    )

    private init(
        total: UsageSummary,
        totalDictations: Int,
        today: UsageSummary,
        todayDictations: Int,
        activeDays: Int,
        currentStreak: Int,
        longestStreak: Int,
        weeks: [[Day]],
        monthLabels: [MonthLabel],
        topApps: [AppShare],
        hourCounts: [Int],
        peakHour: Int?
    ) {
        self.total = total
        self.totalDictations = totalDictations
        self.today = today
        self.todayDictations = todayDictations
        self.activeDays = activeDays
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.weeks = weeks
        self.monthLabels = monthLabels
        self.topApps = topApps
        self.hourCounts = hourCounts
        self.peakHour = peakHour
    }

    public init(days: [DailyUsage], now: Date, calendar: Calendar) {
        let byKey = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let today = calendar.startOfDay(for: now)
        let todayUsage = byKey[DailyUsage.dayKey(for: today, calendar: calendar)]

        // Grid: Sunday-first columns, the last one containing today.
        let weekday = calendar.component(.weekday, from: today)
        let lastColumnStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let firstColumnStart = calendar.date(
            byAdding: .day,
            value: -(Self.weekCount - 1) * 7,
            to: lastColumnStart
        ) ?? lastColumnStart

        struct Cell {
            var date: Date
            var usage: DailyUsage?
            var isFuture: Bool
        }
        let cells: [[Cell]] = (0..<Self.weekCount).map { column in
            (0..<7).map { row in
                let date = calendar.date(byAdding: .day, value: column * 7 + row, to: firstColumnStart)
                    .map { calendar.startOfDay(for: $0) } ?? firstColumnStart
                let isFuture = date > today
                let usage = isFuture ? nil : byKey[DailyUsage.dayKey(for: date, calendar: calendar)]
                return Cell(date: date, usage: usage, isFuture: isFuture)
            }
        }
        let windowUsage = cells.joined().compactMap(\.usage)

        // Levels: quartiles of words over active days in the window.
        let activeWords = windowUsage.filter { $0.dictations > 0 }.map(\.words).sorted()
        func percentile(_ fraction: Double) -> Int {
            activeWords[max(0, Int((fraction * Double(activeWords.count)).rounded(.up)) - 1)]
        }
        let thresholds = activeWords.count > 1
            ? (percentile(0.25), percentile(0.5), percentile(0.75))
            : nil
        func level(for usage: DailyUsage?) -> Int {
            guard let usage, usage.dictations > 0 else { return 0 }
            guard let (q25, q50, q75) = thresholds else { return 4 }
            if usage.words <= q25 { return 1 }
            if usage.words <= q50 { return 2 }
            if usage.words <= q75 { return 3 }
            return 4
        }

        let weeks = cells.map { column in
            column.map { cell in
                Day(
                    date: cell.date,
                    words: cell.usage?.words ?? 0,
                    dictations: cell.usage?.dictations ?? 0,
                    level: level(for: cell.usage),
                    isFuture: cell.isFuture,
                    isToday: cell.date == today
                )
            }
        }

        let monthLabels = weeks.indices.dropLast(2).compactMap { column -> MonthLabel? in
            weeks[column]
                .first { calendar.component(.day, from: $0.date) == 1 }
                .map { MonthLabel(column: column, month: calendar.component(.month, from: $0.date)) }
        }

        // Apps and hours over the window.
        var appTotals: [String: AppDailyUsage] = [:]
        var hourCounts = Array(repeating: 0, count: 24)
        for usage in windowUsage {
            for (key, app) in usage.apps {
                var merged = appTotals[key] ?? AppDailyUsage(
                    name: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    words: 0
                )
                merged.words += app.words
                appTotals[key] = merged
            }
            for (hour, count) in usage.hours.prefix(24).enumerated() { hourCounts[hour] += count }
        }
        let windowWords = windowUsage.reduce(0) { $0 + $1.words }
        let topApps = appTotals
            .sorted { ($1.value.words, $0.key) < ($0.value.words, $1.key) }
            .prefix(5)
            .map { key, app in
                AppShare(
                    id: key,
                    name: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    words: app.words,
                    share: windowWords > 0 ? min(1, Double(app.words) / Double(windowWords)) : 0
                )
            }
        let peakHour = hourCounts.max().flatMap { $0 > 0 ? hourCounts.firstIndex(of: $0) : nil }

        // Streaks.
        let activeKeys = Set(days.filter { $0.dictations > 0 }.map(\.day))
        func isActive(_ date: Date) -> Bool {
            activeKeys.contains(DailyUsage.dayKey(for: date, calendar: calendar))
        }
        var cursor = isActive(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var currentStreak = 0
        while isActive(cursor) {
            currentStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        var longestStreak = 0
        var run = 0
        var previousDate: Date?
        for date in days.filter({ $0.dictations > 0 }).sorted(by: { $0.day < $1.day })
            .compactMap({ $0.startOfDay(calendar: calendar) }) {
            if let previousDate, calendar.date(byAdding: .day, value: 1, to: previousDate) == date {
                run += 1
            } else {
                run = 1
            }
            longestStreak = max(longestStreak, run)
            previousDate = date
        }

        self.init(
            total: TextMetrics.usageSummary(
                duration: days.reduce(0) { $0 + $1.duration },
                words: days.reduce(0) { $0 + $1.words }
            ),
            totalDictations: days.reduce(0) { $0 + $1.dictations },
            today: TextMetrics.usageSummary(duration: todayUsage?.duration ?? 0, words: todayUsage?.words ?? 0),
            todayDictations: todayUsage?.dictations ?? 0,
            activeDays: windowUsage.filter { $0.dictations > 0 }.count,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            weeks: weeks,
            monthLabels: monthLabels,
            topApps: Array(topApps),
            hourCounts: hourCounts,
            peakHour: peakHour
        )
    }
}
