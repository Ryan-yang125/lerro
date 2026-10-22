import Foundation
import Testing
@testable import LerroCore

@Suite("AI usage", .serialized)
struct AIUsageTests {
    private static let shanghai: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return calendar
    }()

    private static func shanghaiDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        // October 2026: the 12th is a Monday, the 14th a Wednesday, the 17th a Saturday.
        let components = DateComponents(
            year: 2026,
            month: 10,
            day: day,
            hour: hour,
            minute: minute
        )
        return shanghai.date(from: components) ?? .distantPast
    }

    private static func record(
        date: Date,
        feature: AIUsageFeature = .dictate,
        model: String = "deepseek-v4-flash",
        tokens: AITokenUsage? = AITokenUsage(inputTokens: 100, outputTokens: 10),
        succeeded: Bool = true
    ) -> AIUsageRecord {
        AIUsageRecord(
            date: date,
            feature: feature,
            modelIdentifier: model,
            tokens: tokens,
            latencyMilliseconds: 500,
            succeeded: succeeded
        )
    }

    @Test("Cached input tokens never exceed input tokens")
    func clampsCachedTokens() {
        let usage = AITokenUsage(inputTokens: 100, outputTokens: 20, cachedInputTokens: 500)
        #expect(usage.cachedInputTokens == 100)
        #expect(usage.totalTokens == 120)
        #expect(AITokenUsage(inputTokens: -5, outputTokens: -1, cachedInputTokens: -3).totalTokens == 0)
    }

    @Test("Cost splits input into uncached, cached and output tokens")
    func computesPeakCost() throws {
        let price = try #require(AIModelPrice.builtIn.first { $0.modelIdentifier == "deepseek-flash" })
        let tokens = AITokenUsage(inputTokens: 1_000_000, outputTokens: 100_000, cachedInputTokens: 400_000)
        let peak = Self.shanghaiDate(day: 14, hour: 10)

        let expected = 0.6 * 2 + 0.4 * 0.04 + 0.1 * 8
        #expect(abs(price.cost(of: tokens, at: peak) - expected) < 1e-9)
    }

    @Test("Off-peak hours and weekends halve DeepSeek prices")
    func appliesOffPeakFactor() throws {
        let price = try #require(AIModelPrice.builtIn.first { $0.modelIdentifier == "deepseek-flash" })
        let tokens = AITokenUsage(inputTokens: 1_000_000, outputTokens: 100_000, cachedInputTokens: 400_000)
        let peakCost = price.cost(of: tokens, at: Self.shanghaiDate(day: 14, hour: 10))

        let wednesdayLunch = Self.shanghaiDate(day: 14, hour: 13)
        let saturdayMorning = Self.shanghaiDate(day: 17, hour: 10)
        #expect(!AIModelPrice.isDeepSeekPeak(wednesdayLunch))
        #expect(!AIModelPrice.isDeepSeekPeak(saturdayMorning))
        #expect(AIModelPrice.isDeepSeekPeak(Self.shanghaiDate(day: 14, hour: 14)))
        #expect(abs(price.cost(of: tokens, at: wednesdayLunch) - peakCost / 2) < 1e-9)
        #expect(abs(price.cost(of: tokens, at: saturdayMorning) - peakCost / 2) < 1e-9)
    }

    @Test("Flat prices ignore the time of day")
    func flatPriceIgnoresPeak() {
        let price = AIModelPrice(
            modelIdentifier: "flat-test",
            currency: .cny,
            inputPerMillion: 1,
            cachedInputPerMillion: 0.5,
            outputPerMillion: 2
        )
        let tokens = AITokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000)

        #expect(price.cost(of: tokens, at: Self.shanghaiDate(day: 14, hour: 10)) == 3)
        #expect(price.cost(of: tokens, at: Self.shanghaiDate(day: 17, hour: 3)) == 3)
    }

    @Test("Built-in price lookup ignores case and surrounding whitespace")
    func priceLookup() throws {
        #expect(AIModelPrice.price(for: "deepseek-v4-flash") == AIModelPrice.builtIn[1])
        #expect(AIModelPrice.price(for: "  DEEPSEEK-V4-FLASH ") == AIModelPrice.builtIn[1])
        #expect(try #require(AIModelPrice.price(for: "deepseek-v4-pro")).currency == .cny)
        #expect(AIModelPrice.price(for: "unknown-model") == nil)
    }

    @Test("Unknown models are counted as unpriced and add no cost")
    func countsUnpricedRequests() {
        let now = Self.shanghaiDate(day: 14, hour: 15)
        let report = AIUsageStatistics.report(
            records: [
                Self.record(date: Self.shanghaiDate(day: 14, hour: 10), model: "mystery-model"),
                Self.record(date: Self.shanghaiDate(day: 14, hour: 11), model: "mystery-model", tokens: nil, succeeded: false)
            ],
            days: 7,
            now: now,
            calendar: Self.shanghai
        )

        #expect(report.totals.requests == 2)
        #expect(report.totals.failedRequests == 1)
        #expect(report.totals.unpricedRequests == 1)
        #expect(report.totals.costs.isEmpty)
        #expect(report.totals.totalTokens == 110)
    }

    @Test("Report covers every day in range and ignores older records")
    func reportDailyRange() throws {
        let now = Self.shanghaiDate(day: 14, hour: 15)
        let records = [
            Self.record(date: Self.shanghaiDate(day: 11, hour: 23), feature: .dictate),
            Self.record(date: Self.shanghaiDate(day: 12, hour: 10), feature: .translate),
            Self.record(
                date: Self.shanghaiDate(day: 14, hour: 10),
                feature: .dictate,
                tokens: AITokenUsage(inputTokens: 5_000, outputTokens: 500, cachedInputTokens: 1_000)
            ),
            Self.record(
                date: Self.shanghaiDate(day: 14, hour: 11),
                feature: .dictionaryLearning,
                model: "deepseek-v4-pro",
                tokens: AITokenUsage(inputTokens: 200, outputTokens: 20)
            )
        ]

        let report = AIUsageStatistics.report(
            records: records,
            days: 3,
            now: now,
            calendar: Self.shanghai
        )

        #expect(report.daily.count == 3)
        #expect(report.daily.map { Self.shanghai.component(.day, from: $0.day) } == [12, 13, 14])
        #expect(report.daily.map(\.totals.requests) == [1, 0, 2])
        #expect(report.totals.requests == 3)
        #expect(report.totals.inputTokens == 5_300)
        #expect(report.totals.cachedInputTokens == 1_000)
        #expect(report.byFeature.map(\.feature) == [.dictate, .dictionaryLearning, .translate])
        #expect(report.byFeature.map(\.totals.totalTokens) == [5_500, 220, 110])
        #expect(report.byModel.map(\.modelIdentifier) == ["deepseek-v4-flash", "deepseek-v4-pro"])
        #expect(report.totals.costs[.cny] ?? 0 > 0)
    }

    @Test("Range start is the first calendar day of the window")
    func rangeStart() {
        let now = Self.shanghaiDate(day: 14, hour: 15)
        let start = AIUsageStatistics.rangeStart(days: 7, now: now, calendar: Self.shanghai)

        #expect(start == Self.shanghaiDate(day: 8, hour: 0))
        #expect(AIUsageStatistics.rangeStart(days: 1, now: now, calendar: Self.shanghai) == Self.shanghaiDate(day: 14, hour: 0))
    }

    @Test("File repository appends, filters and sorts records")
    func fileRepositoryAppendAndRead() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "ai-usage.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = FileAIUsageRepository(fileURL: fileURL, now: { now })
        let newer = Self.record(date: now.addingTimeInterval(-3_600))
        let older = Self.record(date: now.addingTimeInterval(-7_200))

        try await repository.append(newer)
        try await repository.append(older)

        let reopened = FileAIUsageRepository(fileURL: fileURL, now: { now })
        let all = try await reopened.records(since: .distantPast)
        #expect(all.map(\.id) == [older.id, newer.id])
        let recent = try await reopened.records(since: now.addingTimeInterval(-5_000))
        #expect(recent.map(\.id) == [newer.id])
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Appending prunes records older than the retention window")
    func fileRepositoryPrunesOldRecords() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = FileAIUsageRepository(
            fileURL: directory.appending(path: "ai-usage.json"),
            now: { now }
        )
        let expired = Self.record(date: now.addingTimeInterval(-91 * 86_400))
        let kept = Self.record(date: now.addingTimeInterval(-89 * 86_400))
        let fresh = Self.record(date: now)

        try await repository.append(expired)
        try await repository.append(kept)
        try await repository.append(fresh)

        let ids = try await repository.records(since: .distantPast).map(\.id)
        #expect(ids == [kept.id, fresh.id])
    }

    @Test("deleteAll empties the file")
    func fileRepositoryDeleteAll() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = FileAIUsageRepository(
            fileURL: directory.appending(path: "nested/ai-usage.json"),
            now: { now }
        )

        try await repository.append(Self.record(date: now))
        try await repository.deleteAll()

        #expect(try await repository.records(since: .distantPast).isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "lerro-ai-usage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
