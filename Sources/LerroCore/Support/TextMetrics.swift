import Foundation

public enum TextMetrics {
    public static func countWords(in text: String) -> Int {
        let latinWords = text.split { character in
            character.isWhitespace || character.isPunctuation
        }.filter { token in
            token.contains { $0.isLetter || $0.isNumber }
        }

        let cjkCount = text.unicodeScalars.reduce(into: 0) { result, scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                result += 1
            default:
                break
            }
        }

        let latinOnlyCount = latinWords.filter { token in
            token.unicodeScalars.contains { scalar in
                !(0x3400...0x4DBF).contains(scalar.value)
                    && !(0x4E00...0x9FFF).contains(scalar.value)
                    && !(0xF900...0xFAFF).contains(scalar.value)
            }
        }.count

        return cjkCount + latinOnlyCount
    }

    public static func usageSummary(entries: [HistoryEntry]) -> UsageSummary {
        let completed = entries.filter { $0.status == .completed }
        let duration = completed.reduce(0) { $0 + $1.duration }
        let words = completed.reduce(0) { $0 + countWords(in: $1.finalText) }
        return usageSummary(duration: duration, words: words)
    }

    static func usageSummary(duration: TimeInterval, words: Int) -> UsageSummary {
        let typingSeconds = Double(words) / 40.0 * 60.0
        let saved = max(0, typingSeconds - duration)
        let wpm = duration > 0 ? Int((Double(words) / duration) * 60.0) : 0
        return UsageSummary(
            totalDuration: duration,
            totalWords: words,
            savedSeconds: saved,
            averageWordsPerMinute: wpm
        )
    }
}

public enum UsageRange: String, CaseIterable, Sendable {
    case today
    case lastSevenDays
    case allTime
}

public struct DailyWordCount: Hashable, Sendable {
    public var day: Date
    public var words: Int

    public init(day: Date, words: Int) {
        self.day = day
        self.words = words
    }
}

public struct UsageStatistics: Equatable, Sendable {
    public var today: UsageSummary
    /// Completed captures since the start of today.
    public var todayCount: Int
    public var lastSevenDays: UsageSummary
    public var allTime: UsageSummary
    /// Exactly seven days, oldest first. The last item is today.
    public var dailyWords: [DailyWordCount]

    public init(
        today: UsageSummary = UsageSummary(),
        todayCount: Int = 0,
        lastSevenDays: UsageSummary = UsageSummary(),
        allTime: UsageSummary = UsageSummary(),
        dailyWords: [DailyWordCount] = []
    ) {
        self.today = today
        self.todayCount = todayCount
        self.lastSevenDays = lastSevenDays
        self.allTime = allTime
        self.dailyWords = dailyWords
    }

    public init(
        entries: [HistoryEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let startOfToday = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: startOfToday)
                .map { calendar.startOfDay(for: $0) }
        }
        let weekStart = days.first ?? startOfToday
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(86_400)

        var allDuration: TimeInterval = 0
        var allWords = 0
        var weekDuration: TimeInterval = 0
        var weekWords = 0
        var todayDuration: TimeInterval = 0
        var todayWords = 0
        var todayCount = 0
        var wordsByDay: [Date: Int] = [:]

        for entry in entries where entry.status == .completed {
            let words = TextMetrics.countWords(in: entry.finalText)
            allDuration += entry.duration
            allWords += words
            guard entry.createdAt >= weekStart, entry.createdAt < tomorrow else { continue }
            weekDuration += entry.duration
            weekWords += words
            wordsByDay[calendar.startOfDay(for: entry.createdAt), default: 0] += words
            if entry.createdAt >= startOfToday {
                todayDuration += entry.duration
                todayWords += words
                todayCount += 1
            }
        }

        self.init(
            today: TextMetrics.usageSummary(duration: todayDuration, words: todayWords),
            todayCount: todayCount,
            lastSevenDays: TextMetrics.usageSummary(duration: weekDuration, words: weekWords),
            allTime: TextMetrics.usageSummary(duration: allDuration, words: allWords),
            dailyWords: days.map { DailyWordCount(day: $0, words: wordsByDay[$0] ?? 0) }
        )
    }

    public func summary(for range: UsageRange) -> UsageSummary {
        switch range {
        case .today: today
        case .lastSevenDays: lastSevenDays
        case .allTime: allTime
        }
    }
}
