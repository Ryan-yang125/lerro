import Foundation
import Testing
@testable import LerroCore

@Suite("Usage statistics")
struct UsageStatisticsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// 2026-10-16 15:30 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 16, hour: 15, minute: 30
        )) ?? .now
    }

    private func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let today = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private func entry(
        at createdAt: Date,
        text: String = "one two three four",
        duration: TimeInterval = 10,
        status: HistoryStatus = .completed
    ) -> HistoryEntry {
        HistoryEntry(
            createdAt: createdAt,
            mode: .dictation,
            rawText: text,
            finalText: text,
            duration: duration,
            applicationName: "Editor",
            status: status
        )
    }

    @Test("Empty history yields zero summaries and seven empty days")
    func emptyHistory() {
        let statistics = UsageStatistics(entries: [], now: now, calendar: calendar)

        #expect(statistics.today == UsageSummary())
        #expect(statistics.lastSevenDays == UsageSummary())
        #expect(statistics.allTime == UsageSummary())
        #expect(statistics.dailyWords.count == 7)
        #expect(statistics.dailyWords.allSatisfy { $0.words == 0 })
        #expect(statistics.dailyWords.last?.day == calendar.startOfDay(for: now))
    }

    @Test("Today starts at midnight and excludes the previous evening")
    func todayBoundary() {
        let entries = [
            entry(at: date(daysAgo: 0, hour: 0, minute: 0)),
            entry(at: date(daysAgo: 0, hour: 9)),
            entry(at: date(daysAgo: 1, hour: 23, minute: 59))
        ]
        let statistics = UsageStatistics(entries: entries, now: now, calendar: calendar)

        #expect(statistics.today.totalWords == 8)
        #expect(statistics.today.totalDuration == 20)
        #expect(statistics.todayCount == 2)
        #expect(statistics.lastSevenDays.totalWords == 12)
        #expect(statistics.allTime.totalWords == 12)
        #expect(statistics.summary(for: .today) == statistics.today)
        #expect(statistics.summary(for: .lastSevenDays) == statistics.lastSevenDays)
        #expect(statistics.summary(for: .allTime) == statistics.allTime)
    }

    @Test("Seven day window is today and the six previous days")
    func sevenDayWindow() {
        let entries = [
            entry(at: date(daysAgo: 6, hour: 0)),
            entry(at: date(daysAgo: 7, hour: 23, minute: 59)),
            entry(at: date(daysAgo: 30, hour: 12))
        ]
        let statistics = UsageStatistics(entries: entries, now: now, calendar: calendar)

        #expect(statistics.lastSevenDays.totalWords == 4)
        #expect(statistics.allTime.totalWords == 12)
        #expect(statistics.today.totalWords == 0)
    }

    @Test("Daily words are ordered oldest to newest and count completed entries only")
    func dailyWordsOrder() {
        let entries = [
            entry(at: date(daysAgo: 0, hour: 8), text: "a b c"),
            entry(at: date(daysAgo: 0, hour: 10), text: "d e"),
            entry(at: date(daysAgo: 2, hour: 12), text: "f g h i j"),
            entry(at: date(daysAgo: 6, hour: 12), text: "k"),
            entry(at: date(daysAgo: 1, hour: 12), text: "ignored words here", status: .failed),
            entry(at: date(daysAgo: 8, hour: 12), text: "too old")
        ]
        let statistics = UsageStatistics(entries: entries, now: now, calendar: calendar)

        #expect(statistics.dailyWords.count == 7)
        #expect(statistics.dailyWords.map(\.words) == [1, 0, 0, 0, 5, 0, 5])
        let days = statistics.dailyWords.map(\.day)
        #expect(days == days.sorted())
        #expect(days.last == calendar.startOfDay(for: now))
        #expect(days.first == calendar.date(
            byAdding: .day,
            value: -6,
            to: calendar.startOfDay(for: now)
        ))
    }
}
