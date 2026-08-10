import Foundation
import Testing
@testable import LerroCore

@Suite("Usage summary")
struct UsageSummaryTests {
    @Test("Counts Latin tokens, numbers, and individual CJK characters")
    func countsMixedLanguageWords() {
        #expect(TextMetrics.countWords(in: "Hello, 世界! 2026.") == 4)
        #expect(TextMetrics.countWords(in: "🎙️ …") == 0)
    }

    @Test("Uses completed history to calculate time, words, and speed")
    func summarizesCompletedHistory() {
        let eightyWords = Array(repeating: "word", count: 80).joined(separator: " ")
        let completed = makeEntry(text: eightyWords, duration: 30, status: .completed)
        let failed = makeEntry(
            text: Array(repeating: "ignored", count: 100).joined(separator: " "),
            duration: 600,
            status: .failed
        )

        let summary = TextMetrics.usageSummary(entries: [completed, failed])

        #expect(summary.totalDuration == 30)
        #expect(summary.totalWords == 80)
        #expect(summary.savedSeconds == 90)
        #expect(summary.averageWordsPerMinute == 160)
    }

    @Test("Clamps saved time to zero")
    func clampsSummaryValues() {
        let slowEntry = makeEntry(text: "one two", duration: 60, status: .completed)

        let summary = TextMetrics.usageSummary(entries: [slowEntry])

        #expect(summary.savedSeconds == 0)
    }

    @Test("Returns zero speed for an empty history")
    func summarizesEmptyHistory() {
        let summary = TextMetrics.usageSummary(entries: [])

        #expect(summary == UsageSummary())
    }

    private func makeEntry(
        text: String,
        duration: TimeInterval,
        status: HistoryStatus
    ) -> HistoryEntry {
        HistoryEntry(
            mode: .dictation,
            rawText: text,
            finalText: text,
            duration: duration,
            applicationName: "Tests",
            status: status
        )
    }
}
