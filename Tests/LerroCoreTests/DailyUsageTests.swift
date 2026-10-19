import Foundation
import Testing
@testable import LerroCore

@Suite("Daily usage and home statistics", .serialized)
struct DailyUsageTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return calendar
    }()

    private static func date(year: Int = 2026, month: Int = 10, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    /// Wednesday 14 October 2026. The week column starts on Sunday the 11th.
    private static let now = date(day: 14)

    private static func daysAgo(_ count: Int, hour: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: -count, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
    }

    private static func entry(
        at createdAt: Date,
        text: String = "one two three",
        duration: TimeInterval = 10,
        app: String = "Notes",
        bundle: String? = "com.apple.Notes",
        status: HistoryStatus = .completed
    ) -> HistoryEntry {
        HistoryEntry(
            createdAt: createdAt,
            mode: .dictation,
            rawText: text,
            finalText: text,
            duration: duration,
            applicationName: app,
            bundleIdentifier: bundle,
            status: status
        )
    }

    private static func usage(
        daysAgo count: Int,
        words: Int = 10,
        dictations: Int = 1,
        duration: TimeInterval = 10,
        apps: [String: AppDailyUsage] = [:],
        hours: [Int: Int] = [:]
    ) -> DailyUsage {
        var day = DailyUsage(day: DailyUsage.dayKey(for: daysAgo(count), calendar: calendar))
        day.words = words
        day.dictations = dictations
        day.duration = duration
        day.apps = apps
        for (hour, value) in hours { day.hours[hour] = value }
        return day
    }

    private static func statistics(_ days: [DailyUsage]) -> HomeStatistics {
        HomeStatistics(days: days, now: now, calendar: calendar)
    }

    // MARK: Seeding and recording

    @Test("Seeding buckets completed entries by day, app and hour")
    func seedsFromHistory() throws {
        let entries = [
            Self.entry(at: Self.date(day: 13, hour: 9), text: "one two three", duration: 10),
            Self.entry(at: Self.date(day: 13, hour: 9, minute: 30), text: "four five", duration: 5, app: "Xcode", bundle: "com.apple.dt.Xcode"),
            Self.entry(at: Self.date(day: 13, hour: 23, minute: 30), text: "你好世界", duration: 2),
            Self.entry(at: Self.date(day: 12, hour: 8), text: "alpha"),
            Self.entry(at: Self.date(day: 14, hour: 8), text: "ignored words", status: .failed),
            Self.entry(at: Self.date(day: 14, hour: 9), text: "ignored words", status: .cancelled),
            Self.entry(at: Self.date(day: 14, hour: 10), text: "ignored words", status: .undone)
        ]

        let days = DailyUsage.seed(from: entries, calendar: Self.calendar)

        #expect(days.map(\.day) == ["2026-10-12", "2026-10-13"])
        let thirteenth = try #require(days.last)
        #expect(thirteenth.words == 3 + 2 + 4)
        #expect(thirteenth.dictations == 3)
        #expect(thirteenth.duration == 17)
        #expect(thirteenth.hours.count == 24)
        #expect(thirteenth.hours[9] == 2)
        #expect(thirteenth.hours[23] == 1)
        #expect(thirteenth.hours.reduce(0, +) == 3)
        #expect(thirteenth.apps["com.apple.Notes"] == AppDailyUsage(name: "Notes", bundleIdentifier: "com.apple.Notes", words: 7))
        #expect(thirteenth.apps["com.apple.dt.Xcode"]?.words == 2)
    }

    @Test("Apps without a bundle identifier are keyed by name and nameless apps are skipped")
    func appKeys() throws {
        let entries = [
            Self.entry(at: Self.date(day: 13), app: "Terminal", bundle: nil),
            Self.entry(at: Self.date(day: 13), app: "Terminal", bundle: ""),
            Self.entry(at: Self.date(day: 13), app: "", bundle: nil)
        ]

        let day = try #require(DailyUsage.seed(from: entries, calendar: Self.calendar).first)

        #expect(day.dictations == 3)
        #expect(day.words == 9)
        #expect(Set(day.apps.keys) == ["name:Terminal"])
        #expect(day.apps["name:Terminal"] == AppDailyUsage(name: "Terminal", bundleIdentifier: nil, words: 6))
    }

    @Test("Recording adds completed captures and ignores other statuses")
    func recordsEntries() async throws {
        let repository = InMemoryDailyUsageRepository(calendar: Self.calendar)

        try await repository.record(Self.entry(at: Self.date(day: 14, hour: 10)))
        try await repository.record(Self.entry(at: Self.date(day: 14, hour: 10), text: "four five"))
        try await repository.record(Self.entry(at: Self.date(day: 14, hour: 11), status: .failed))
        try await repository.record(Self.entry(at: Self.date(day: 13, hour: 11)))

        let days = try await repository.days()
        #expect(days.map(\.day) == ["2026-10-13", "2026-10-14"])
        #expect(days[1].words == 5)
        #expect(days[1].dictations == 2)
        #expect(days[1].hours[10] == 2)
        #expect(days[1].hours[11] == 0)
        try await repository.deleteAll()
        #expect(try await repository.days().isEmpty)
    }

    @Test("Recording prunes days older than the retention window")
    func recordingPrunes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Self.now
        let repository = FileDailyUsageRepository(
            fileURL: directory.appending(path: "usage-days.json"),
            calendar: Self.calendar,
            now: { now }
        )
        try await repository.replaceAll([
            Self.usage(daysAgo: 500),
            Self.usage(daysAgo: 401),
            Self.usage(daysAgo: 400),
            Self.usage(daysAgo: 399)
        ])

        try await repository.record(Self.entry(at: Self.daysAgo(0)))
        try await repository.record(Self.entry(at: Self.daysAgo(450)))

        let keys = try await repository.days().map(\.day)
        let expected = [399, 400, 0].map { DailyUsage.dayKey(for: Self.daysAgo($0), calendar: Self.calendar) }
        #expect(keys == expected.sorted())
        #expect(DailyUsage.retentionDays == 400)
    }

    @Test("File repository round-trips days with owner-only permissions")
    func fileRoundTrip() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "nested/usage-days.json")
        let now = Self.now
        let repository = FileDailyUsageRepository(fileURL: fileURL, calendar: Self.calendar, now: { now })

        try await repository.record(Self.entry(at: Self.date(day: 14, hour: 9)))
        try await repository.record(Self.entry(at: Self.date(day: 12, hour: 15), app: "Terminal", bundle: nil))

        let reopened = FileDailyUsageRepository(fileURL: fileURL, calendar: Self.calendar, now: { now })
        let days = try await reopened.days()
        #expect(days.map(\.day) == ["2026-10-12", "2026-10-14"])
        #expect(days[0].apps["name:Terminal"]?.words == 3)
        #expect(days[1].hours[9] == 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        try await reopened.deleteAll()
        #expect(try await reopened.days().isEmpty)
    }

    // MARK: HomeStatistics

    @Test("Empty input produces zero values")
    func emptyInput() {
        let statistics = Self.statistics([])

        #expect(statistics.total == UsageSummary())
        #expect(statistics.totalDictations == 0)
        #expect(statistics.today == UsageSummary())
        #expect(statistics.todayDictations == 0)
        #expect(statistics.activeDays == 0)
        #expect(statistics.currentStreak == 0)
        #expect(statistics.longestStreak == 0)
        #expect(statistics.topApps.isEmpty)
        #expect(statistics.hourCounts == Array(repeating: 0, count: 24))
        #expect(statistics.peakHour == nil)
        #expect(statistics.weeks.joined().allSatisfy { $0.level == 0 && $0.words == 0 && $0.dictations == 0 })

        let empty = HomeStatistics.empty
        #expect(empty.total == statistics.total)
        #expect(empty.today == statistics.today)
        #expect(empty.hourCounts == statistics.hourCounts)
        #expect(empty.topApps.isEmpty)
        #expect(empty.peakHour == nil)
        #expect(empty.currentStreak == 0)
        #expect(empty.activeDays == 0)
    }

    @Test("Totals cover all retained days and today covers only today")
    func totalsAndToday() {
        let statistics = Self.statistics([
            Self.usage(daysAgo: 0, words: 80, dictations: 2, duration: 60),
            Self.usage(daysAgo: 3, words: 20, dictations: 1, duration: 30),
            Self.usage(daysAgo: 380, words: 5, dictations: 1, duration: 5)
        ])

        #expect(statistics.total == TextMetrics.usageSummary(duration: 95, words: 105))
        #expect(statistics.totalDictations == 4)
        #expect(statistics.today == TextMetrics.usageSummary(duration: 60, words: 80))
        #expect(statistics.todayDictations == 2)
        // The day 380 days ago falls outside the 53 weeks shown.
        #expect(statistics.activeDays == 2)
    }

    @Test("Streak counts back from today")
    func streakWithTodayActive() {
        let statistics = Self.statistics([0, 1, 2, 5].map { Self.usage(daysAgo: $0) })

        #expect(statistics.currentStreak == 3)
        #expect(statistics.longestStreak == 3)
    }

    @Test("Streak ending yesterday survives an idle today")
    func streakWithTodayInactive() {
        let statistics = Self.statistics([1, 2].map { Self.usage(daysAgo: $0) })

        #expect(statistics.currentStreak == 2)
        #expect(statistics.longestStreak == 2)
    }

    @Test("A gap before yesterday ends the current streak")
    func streakWithGap() {
        let statistics = Self.statistics([2, 3].map { Self.usage(daysAgo: $0) })

        #expect(statistics.currentStreak == 0)
        #expect(statistics.longestStreak == 2)
    }

    @Test("Longest streak looks at all retained days")
    func longestStreakAcrossHistory() {
        let days = (100...106).map { Self.usage(daysAgo: $0) } + [Self.usage(daysAgo: 0)]
        let statistics = Self.statistics(days)

        #expect(statistics.currentStreak == 1)
        #expect(statistics.longestStreak == 7)
    }

    @Test("Days with no dictations do not extend a streak")
    func zeroDictationDaysAreInactive() {
        let statistics = Self.statistics([
            Self.usage(daysAgo: 0),
            Self.usage(daysAgo: 1, words: 0, dictations: 0)
        ])

        #expect(statistics.currentStreak == 1)
    }

    @Test("Weeks form a 53 by 7 Sunday-first grid ending with today's week")
    func gridLayout() throws {
        let statistics = Self.statistics([])
        let weeks = statistics.weeks

        #expect(weeks.count == 53)
        #expect(weeks.allSatisfy { $0.count == 7 })
        let lastWeek = try #require(weeks.last)
        #expect(lastWeek[3].isToday)
        #expect(lastWeek[3].date == Self.calendar.startOfDay(for: Self.now))
        #expect(lastWeek[0].date == Self.date(day: 11, hour: 0))
        #expect(lastWeek.map(\.isFuture) == [false, false, false, false, true, true, true])
        #expect(weeks.dropLast().joined().allSatisfy { !$0.isFuture })
        #expect(weeks.joined().filter(\.isToday).count == 1)
        let first = try #require(weeks.first?.first)
        #expect(Self.calendar.component(.weekday, from: first.date) == 1)
        #expect(first.date == Self.calendar.date(byAdding: .day, value: -52 * 7, to: lastWeek[0].date))
        let dates = weeks.joined().map(\.date)
        #expect(dates == dates.sorted())
    }

    @Test("Day cells carry words and dictations from their day")
    func gridCellsCarryUsage() throws {
        let statistics = Self.statistics([Self.usage(daysAgo: 1, words: 42, dictations: 3)])

        let cell = try #require(statistics.weeks.last?[2])
        #expect(cell.words == 42)
        #expect(cell.dictations == 3)
        #expect(!cell.isToday)
        #expect(cell.level == 4)
    }

    @Test("Levels follow the quartiles of active days")
    func quartileLevels() throws {
        let days = [
            Self.usage(daysAgo: 0, words: 40),
            Self.usage(daysAgo: 1, words: 30),
            Self.usage(daysAgo: 2, words: 20),
            Self.usage(daysAgo: 3, words: 10),
            Self.usage(daysAgo: 8, words: 0, dictations: 0)
        ]
        let statistics = Self.statistics(days)
        let byDate = Dictionary(uniqueKeysWithValues: statistics.weeks.joined().map { ($0.date, $0.level) })

        func level(_ count: Int) -> Int? {
            byDate[Self.calendar.startOfDay(for: Self.daysAgo(count))]
        }
        #expect(level(3) == 1)
        #expect(level(2) == 2)
        #expect(level(1) == 3)
        #expect(level(0) == 4)
        #expect(level(8) == 0)
        #expect(level(5) == 0)
    }

    @Test("A single active day is level four")
    func singleActiveDayLevel() throws {
        let statistics = Self.statistics([Self.usage(daysAgo: 2, words: 3)])

        let levels = statistics.weeks.joined().map(\.level)
        #expect(levels.filter { $0 == 4 }.count == 1)
        #expect(levels.filter { $0 == 0 }.count == levels.count - 1)
    }

    @Test("Month labels mark the column containing the 1st, except the last two columns")
    func monthLabels() {
        let labels = Self.statistics([]).monthLabels

        #expect(labels.map(\.month) == [11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(labels.first == HomeStatistics.MonthLabel(column: 2, month: 11))
        #expect(labels.contains(HomeStatistics.MonthLabel(column: 46, month: 9)))
        #expect(labels.last == HomeStatistics.MonthLabel(column: 50, month: 10))
        #expect(labels.allSatisfy { $0.column < 51 })
    }

    @Test("Top apps are ranked by words with shares of the window total")
    func topApps() {
        let statistics = Self.statistics([
            Self.usage(daysAgo: 0, words: 150, apps: [
                "a": AppDailyUsage(name: "A", bundleIdentifier: "a", words: 100),
                "b": AppDailyUsage(name: "B", bundleIdentifier: "b", words: 50)
            ]),
            Self.usage(daysAgo: 1, words: 100, apps: [
                "a": AppDailyUsage(name: "A", bundleIdentifier: "a", words: 50),
                "name:C": AppDailyUsage(name: "C", bundleIdentifier: nil, words: 50)
            ])
        ])

        #expect(statistics.topApps.map(\.id) == ["a", "b", "name:C"])
        #expect(statistics.topApps.map(\.words) == [150, 50, 50])
        #expect(abs(statistics.topApps[0].share - 0.6) < 1e-9)
        #expect(abs(statistics.topApps[1].share - 0.2) < 1e-9)
        #expect(statistics.topApps[0].name == "A")
        #expect(statistics.topApps[2].bundleIdentifier == nil)
    }

    @Test("Top apps are limited to five")
    func topAppsLimit() {
        let apps = Dictionary(uniqueKeysWithValues: (1...6).map {
            ("app\($0)", AppDailyUsage(name: "App \($0)", bundleIdentifier: "app\($0)", words: $0))
        })
        let statistics = Self.statistics([Self.usage(daysAgo: 0, words: 21, apps: apps)])

        #expect(statistics.topApps.map(\.id) == ["app6", "app5", "app4", "app3", "app2"])
    }

    @Test("Hour counts add up across days and the busiest hour is the peak")
    func peakHour() {
        let statistics = Self.statistics([
            Self.usage(daysAgo: 0, dictations: 3, hours: [9: 2, 14: 1]),
            Self.usage(daysAgo: 1, dictations: 3, hours: [14: 2, 22: 1])
        ])

        #expect(statistics.hourCounts.count == 24)
        #expect(statistics.hourCounts[9] == 2)
        #expect(statistics.hourCounts[14] == 3)
        #expect(statistics.hourCounts[22] == 1)
        #expect(statistics.peakHour == 14)
    }

    @Test("Equal hour counts resolve to the earliest hour")
    func peakHourTie() {
        let statistics = Self.statistics([Self.usage(daysAgo: 0, dictations: 2, hours: [16: 1, 8: 1])])

        #expect(statistics.peakHour == 8)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "lerro-daily-usage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
