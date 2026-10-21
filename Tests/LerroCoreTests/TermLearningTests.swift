import Foundation
import Testing
@testable import LerroCore

@Suite("Term learning")
struct TermLearningTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Filters

    @Test("Single characters are not learned")
    func rejectsSingleCharacter() {
        let result = observe(corrected: "X", text: "用 X 做")

        #expect(result.state.candidates.isEmpty)
        #expect(result.learned.isEmpty)
    }

    @Test("Overlong terms are not learned")
    func rejectsOverlongTerm() {
        let term = String(repeating: "a", count: 41)

        #expect(observe(corrected: term, text: term).state.candidates.isEmpty)
        #expect(!observe(corrected: String(repeating: "a", count: 40), text: term).state.candidates.isEmpty)
    }

    @Test("Time-like and numeric strings are not learned")
    func rejectsTimeAndNumbers() {
        #expect(observe(corrected: "2:00", text: "下午 2:00 开会").state.candidates.isEmpty)
        #expect(observe(corrected: "10:30", text: "10:30 见").state.candidates.isEmpty)
        #expect(observe(corrected: "2026", text: "2026 年").state.candidates.isEmpty)
        #expect(observe(corrected: "--", text: "a -- b").state.candidates.isEmpty)
    }

    @Test("Words the model did not list in terms are not learned")
    func rejectsOrdinaryWord() {
        let result = TermLearner.observe(
            state: .empty,
            fixes: [AIWordFix(recognized: "公式", corrected: "工时")],
            terms: ["Notion"],
            finalText: "估一下工时",
            entryID: UUID(),
            dictionary: [],
            now: now
        )

        #expect(result.state.candidates.isEmpty)
    }

    @Test("Terms that are not a corrected value in fixes are not learned")
    func rejectsTermWithoutFix() {
        let result = TermLearner.observe(
            state: .empty,
            fixes: [],
            terms: ["Notion"],
            finalText: "写到 Notion 里",
            entryID: UUID(),
            dictionary: [],
            now: now
        )

        #expect(result.state.candidates.isEmpty)
    }

    @Test("Terms missing from the final text are not learned")
    func rejectsTermAbsentFromFinalText() {
        #expect(observe(corrected: "Notion", text: "写到笔记里").state.candidates.isEmpty)
    }

    @Test("Terms already in the dictionary are not learned")
    func rejectsDictionaryTerm() {
        let byReplacement = [DictionaryEntry(phrase: "叉扣", replacement: "Xcode")]
        let byPhrase = [DictionaryEntry(phrase: "xcode")]

        #expect(observe(corrected: "Xcode", text: "用 Xcode", dictionary: byReplacement).state.candidates.isEmpty)
        #expect(observe(corrected: "Xcode", text: "用 Xcode", dictionary: byPhrase).state.candidates.isEmpty)
    }

    @Test("Dismissed terms are not learned")
    func rejectsDismissedTerm() {
        let state = TermLearner.dismiss("Xcode", in: .empty)

        #expect(observe(corrected: "Xcode", text: "用 Xcode", state: state).state.candidates.isEmpty)
    }

    // MARK: Learning

    @Test("Two distinct entries learn the term and remove the candidate")
    func twoEntriesLearn() throws {
        let first = UUID()
        let second = UUID()

        let afterFirst = observe(
            recognized: "叉扣", corrected: "Xcode", text: "用 Xcode 构建", entryID: first
        )
        #expect(afterFirst.learned.isEmpty)
        let candidate = try #require(afterFirst.state.candidates["xcode"])
        #expect(candidate.term == "Xcode")
        #expect(candidate.heardAs == ["叉扣"])
        #expect(candidate.entryIDs == [first])
        #expect(candidate.firstSeenAt == now)

        let later = now.addingTimeInterval(60)
        let afterSecond = observe(
            recognized: "插扣", corrected: "xcode", text: "打开 xcode", entryID: second,
            state: afterFirst.state, now: later
        )

        #expect(afterSecond.state.candidates.isEmpty)
        let entry = try #require(afterSecond.learned.first)
        #expect(afterSecond.learned.count == 1)
        #expect(entry.phrase == "xcode")
        #expect(entry.replacement == "xcode")
        #expect(entry.source == .learned)
        #expect(entry.heardAs == ["叉扣", "插扣"])
        #expect(entry.learnedFromEntryIDs == [first, second])
        #expect(entry.createdAt == later)
        #expect(entry.useCount == 0)
        #expect(entry.lastUsedAt == nil)
        #expect(!entry.isSnippet)
    }

    @Test("The same entry twice does not count twice")
    func sameEntryCountsOnce() throws {
        let id = UUID()

        let first = observe(corrected: "Xcode", text: "用 Xcode", entryID: id)
        let second = observe(corrected: "Xcode", text: "用 Xcode", entryID: id, state: first.state)

        #expect(second.learned.isEmpty)
        #expect(second.state == first.state)
        #expect(try #require(second.state.candidates["xcode"]).entryIDs == [id])
    }

    @Test("Repeated fixes of one term inside one call count once")
    func duplicateFixesInOneCall() throws {
        let result = TermLearner.observe(
            state: .empty,
            fixes: [
                AIWordFix(recognized: "叉扣", corrected: "Xcode"),
                AIWordFix(recognized: "插扣", corrected: "Xcode")
            ],
            terms: ["Xcode", "Xcode"],
            finalText: "Xcode",
            entryID: UUID(),
            dictionary: [],
            now: now
        )

        #expect(result.learned.isEmpty)
        let candidate = try #require(result.state.candidates["xcode"])
        #expect(candidate.entryIDs.count == 1)
        #expect(candidate.heardAs == ["叉扣", "插扣"])
    }

    // MARK: Status

    @Test("Status reports dictionary, pending and not learning")
    func statusValues() {
        let observed = observe(corrected: "CapEx", text: "CapEx 预算")
        let dictionary = [DictionaryEntry(phrase: "Xcode", source: .learned)]

        #expect(TermLearner.status(of: "xcode", state: observed.state, dictionary: dictionary) == .inDictionary)
        #expect(TermLearner.status(of: " capex ", state: observed.state, dictionary: dictionary)
            == .pending(remaining: 1))
        #expect(TermLearner.status(of: "Figma", state: observed.state, dictionary: dictionary) == .notLearning)

        let dismissed = TermLearner.dismiss("CapEx", in: observed.state)
        #expect(dismissed.candidates.isEmpty)
        #expect(TermLearner.status(of: "CapEx", state: dismissed, dictionary: dictionary) == .notLearning)
    }

    @Test("Normalization trims, collapses whitespace and lowercases")
    func normalization() {
        #expect(TermLearner.normalized("  Grid   Search ") == "grid search")
    }

    // MARK: Usage counter

    @Test("Usage counter increments matching non-snippet entries only")
    func usageCounter() {
        let learned = DictionaryEntry(phrase: "Xcode", source: .learned, useCount: 2)
        let manual = DictionaryEntry(phrase: "Laura", useCount: 0)
        let snippet = DictionaryEntry(phrase: "地址", replacement: "上海市浦东新区")
        let unused = DictionaryEntry(phrase: "Figma")

        let used = DictionaryUsageCounter.entriesUsed(
            in: "让 laura 用 XCODE 打开，地址：上海市浦东新区",
            dictionary: [learned, manual, snippet, unused],
            now: now
        )

        #expect(used.map(\.id) == [learned.id, manual.id])
        #expect(used.map(\.useCount) == [3, 1])
        #expect(used.allSatisfy { $0.lastUsedAt == now })
    }

    // MARK: Week summary

    @Test("Week summary lists recent learned terms and counts corrections")
    func weekSummary() {
        let day: TimeInterval = 86_400
        let dictionary = [
            DictionaryEntry(phrase: "Xcode", source: .learned, createdAt: now.addingTimeInterval(-2 * day)),
            DictionaryEntry(phrase: "Notion", source: .learned, createdAt: now.addingTimeInterval(-1 * day)),
            DictionaryEntry(phrase: "Figma", source: .learned, createdAt: now.addingTimeInterval(-9 * day)),
            DictionaryEntry(phrase: "Laura", createdAt: now.addingTimeInterval(-1 * day))
        ]
        let recent = historyEntry(
            createdAt: now.addingTimeInterval(-day),
            response: #"{"fixes": [["叉扣", "xcode"], ["公式", "工时"]], "terms": [], "text": "x"}"#
        )
        let old = historyEntry(
            createdAt: now.addingTimeInterval(-10 * day),
            response: #"{"fixes": [["a", "Xcode"]], "terms": [], "text": "x"}"#
        )
        let noCall = HistoryEntry(
            createdAt: now,
            mode: .dictation,
            rawText: "a",
            finalText: "b",
            duration: 1,
            applicationName: "Tests"
        )

        let summary = DictionaryWeek.summary(history: [recent, old, noCall], dictionary: dictionary, now: now)

        #expect(summary.learnedTerms == ["Notion", "Xcode"])
        #expect(summary.corrections == 2)
        #expect(summary.correctionsUsingDictionary == 1)
        #expect(DictionaryWeek.summary(history: [], dictionary: [], now: now) == .empty)
    }

    // MARK: Codable

    @Test("Dictionary entries from older files decode with empty learning fields")
    func dictionaryEntryDecodesOldJSON() throws {
        let json = """
        {"id":"\(UUID().uuidString)","phrase":"叉扣","replacement":"Xcode","source":"manual",
        "createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z","useCount":3}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let entry = try decoder.decode(DictionaryEntry.self, from: Data(json.utf8))

        #expect(entry.phrase == "叉扣")
        #expect(entry.useCount == 3)
        #expect(entry.heardAs.isEmpty)
        #expect(entry.learnedFromEntryIDs.isEmpty)
        #expect(entry.lastUsedAt == nil)
    }

    @Test("Dictionary entries round trip the learning fields")
    func dictionaryEntryRoundTrip() throws {
        let entry = DictionaryEntry(
            phrase: "Xcode",
            source: .learned,
            createdAt: Date(timeIntervalSince1970: 1_799_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_799_000_000),
            useCount: 4,
            heardAs: ["叉扣"],
            learnedFromEntryIDs: [UUID(), UUID()],
            lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        #expect(try decoder.decode(DictionaryEntry.self, from: encoder.encode(entry)) == entry)
    }

    // MARK: Repositories

    @Test("File repository round trips state and clears it")
    func fileRepositoryRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LerroTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = ApplicationPaths(rootDirectory: directory).termCandidatesFile
        #expect(fileURL.lastPathComponent == "term-candidates.json")

        let repository = FileTermLearningRepository(fileURL: fileURL)
        #expect(try await repository.load() == .empty)

        let state = TermLearningState(
            candidates: [
                "capex": TermCandidate(
                    term: "CapEx",
                    heardAs: ["开普克斯"],
                    entryIDs: [UUID()],
                    firstSeenAt: Date(timeIntervalSince1970: 1_800_000_000),
                    lastSeenAt: Date(timeIntervalSince1970: 1_800_000_100)
                )
            ],
            dismissed: ["xcode"]
        )
        try await repository.save(state)

        let reopened = FileTermLearningRepository(fileURL: fileURL)
        #expect(try await reopened.load() == state)
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        try await reopened.deleteAll()
        #expect(try await reopened.load() == .empty)
    }

    @Test("In-memory repository saves and clears state")
    func inMemoryRepository() async {
        let repository = InMemoryTermLearningRepository()
        let state = TermLearner.dismiss("Xcode", in: .empty)

        await repository.save(state)
        #expect(await repository.load() == state)

        await repository.deleteAll()
        #expect(await repository.load() == .empty)
    }

    // MARK: Helpers

    private func observe(
        recognized: String = "听错",
        corrected: String,
        text: String,
        entryID: UUID = UUID(),
        dictionary: [DictionaryEntry] = [],
        state: TermLearningState = .empty,
        now: Date? = nil
    ) -> (state: TermLearningState, learned: [DictionaryEntry]) {
        TermLearner.observe(
            state: state,
            fixes: [AIWordFix(recognized: recognized, corrected: corrected)],
            terms: [corrected],
            finalText: text,
            entryID: entryID,
            dictionary: dictionary,
            now: now ?? self.now
        )
    }

    private func historyEntry(createdAt: Date, response: String) -> HistoryEntry {
        HistoryEntry(
            createdAt: createdAt,
            mode: .dictation,
            rawText: "a",
            finalText: "b",
            duration: 1,
            applicationName: "Tests",
            aiCall: AICallTrace(
                prompt: .dictate,
                promptVersion: "v",
                provider: .deepSeek,
                modelIdentifier: "deepseek-flash",
                userPrompt: "{}",
                response: response,
                latencyMilliseconds: 10,
                startedAt: createdAt
            )
        )
    }
}
