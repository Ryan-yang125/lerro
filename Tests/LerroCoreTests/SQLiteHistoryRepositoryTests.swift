import Foundation
import Testing
@testable import LerroCore

@Suite("SQLite history repository", .serialized)
struct SQLiteHistoryRepositoryTests {
    @Test("Persists, sorts, updates, and deletes entries across instances")
    func lifecycle() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "nested/history.sqlite")
        let repository = SQLiteHistoryRepository(databaseURL: databaseURL)
        let older = makeEntry(createdAt: Date(timeIntervalSince1970: 100), text: "older")
        var newer = makeEntry(createdAt: Date(timeIntervalSince1970: 200), text: "newer")

        try await repository.save(older)
        try await repository.save(newer)

        let reopened = SQLiteHistoryRepository(databaseURL: databaseURL)
        #expect(try await reopened.entries().map(\.id) == [newer.id, older.id])
        #expect(try await reopened.entries() == [newer, older])

        newer.finalText = "updated"
        try await reopened.save(newer)
        let updated = try await reopened.entries()
        #expect(updated.count == 2)
        #expect(updated.first { $0.id == newer.id }?.finalText == "updated")

        try await reopened.delete(id: older.id)
        #expect(try await reopened.entries().map(\.id) == [newer.id])

        try await reopened.deleteAll()
        #expect(try await reopened.entries().isEmpty)
        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    @Test("Pages normalize requests and expose stable boundaries")
    func pagesAndRequestNormalization() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SQLiteHistoryRepository(databaseURL: directory.appending(path: "history.sqlite"))
        let entries = (0..<6).map { index in
            makeEntry(createdAt: Date(timeIntervalSince1970: TimeInterval(index)), text: "entry-\(index)")
        }
        for entry in entries {
            try await repository.save(entry)
        }

        let normalized = HistoryPageRequest(offset: -12, limit: .max, searchText: "  entry  ")
        #expect(normalized.offset == 0)
        #expect(normalized.limit == HistoryPageRequest.maximumLimit)
        #expect(normalized.searchText == "entry")
        #expect(HistoryPageRequest(limit: 0).limit == 1)

        let first = try await repository.page(HistoryPageRequest(offset: 0, limit: 2))
        #expect(first.entries.map(\.id) == [entries[5].id, entries[4].id])
        #expect(first.totalCount == 6)
        #expect(first.hasMore)

        let middle = try await repository.page(HistoryPageRequest(offset: 2, limit: 2))
        #expect(middle.entries.map(\.id) == [entries[3].id, entries[2].id])
        #expect(middle.hasMore)

        let final = try await repository.page(HistoryPageRequest(offset: 4, limit: 2))
        #expect(final.entries.map(\.id) == [entries[1].id, entries[0].id])
        #expect(final.totalCount == 6)
        #expect(!final.hasMore)

        let beyondEnd = try await repository.page(HistoryPageRequest(offset: 100, limit: 2))
        #expect(beyondEnd.entries.isEmpty)
        #expect(beyondEnd.totalCount == 6)
        #expect(!beyondEnd.hasMore)

        let all = try await repository.page(HistoryPageRequest(limit: .max))
        #expect(all.entries.count == 6)
        #expect(!all.hasMore)
    }

    @Test("Search matches final text and application name within an optional mode")
    func searchFiltersByTextApplicationAndMode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SQLiteHistoryRepository(databaseURL: directory.appending(path: "history.sqlite"))
        let matchingText = makeEntry(
            createdAt: Date(timeIntervalSince1970: 300),
            mode: .dictation,
            text: "Hello Lerro",
            applicationName: "Notes"
        )
        let matchingApplication = makeEntry(
            createdAt: Date(timeIntervalSince1970: 200),
            mode: .translation,
            text: "translated",
            applicationName: "Lerro Editor"
        )
        let wrongMode = makeEntry(
            createdAt: Date(timeIntervalSince1970: 100),
            mode: .dictation,
            text: "Lerro question",
            applicationName: "Browser"
        )
        let unrelated = makeEntry(
            createdAt: Date(timeIntervalSince1970: 50),
            text: "nothing here",
            applicationName: "Mail"
        )
        for entry in [matchingText, matchingApplication, wrongMode, unrelated] {
            try await repository.save(entry)
        }

        let allMatches = try await repository.page(HistoryPageRequest(limit: 20, searchText: "lErRo"))
        #expect(allMatches.entries.map(\.id) == [matchingText.id, matchingApplication.id, wrongMode.id])
        #expect(allMatches.totalCount == 3)

        let filtered = try await repository.page(
            HistoryPageRequest(limit: 20, searchText: "LERRO", mode: .translation)
        )
        #expect(filtered.entries.map(\.id) == [matchingApplication.id])
        #expect(filtered.totalCount == 1)
        #expect(!filtered.hasMore)

        let modeOnly = try await repository.page(HistoryPageRequest(limit: 20, mode: .translation))
        #expect(modeOnly.entries.map(\.id) == [matchingApplication.id])

        let paged = try await repository.page(HistoryPageRequest(offset: 1, limit: 1, searchText: "lerro"))
        #expect(paged.entries.map(\.id) == [matchingApplication.id])
        #expect(paged.totalCount == 3)
        #expect(paged.hasMore)
    }

    @Test("Search follows updates and deletions")
    func searchTracksMutations() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SQLiteHistoryRepository(databaseURL: directory.appending(path: "history.sqlite"))
        var entry = makeEntry(createdAt: Date(timeIntervalSince1970: 1), text: "alpha beta")
        try await repository.save(entry)
        #expect(try await repository.page(HistoryPageRequest(searchText: "alpha")).totalCount == 1)

        entry.finalText = "gamma delta"
        try await repository.save(entry)
        #expect(try await repository.page(HistoryPageRequest(searchText: "alpha")).totalCount == 0)
        #expect(try await repository.page(HistoryPageRequest(searchText: "gamma")).totalCount == 1)

        try await repository.delete(id: entry.id)
        #expect(try await repository.page(HistoryPageRequest(searchText: "gamma")).totalCount == 0)
    }

    @Test("Search folds Unicode case, matches short CJK queries, and treats wildcards literally")
    func searchUnicodeAndLiteralCharacters() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SQLiteHistoryRepository(databaseURL: directory.appending(path: "history.sqlite"))
        let school = makeEntry(createdAt: Date(timeIntervalSince1970: 10), text: "ÉCOLE primaire")
        let weather = makeEntry(createdAt: Date(timeIntervalSince1970: 9), text: "今天天气很好")
        let percent = makeEntry(createdAt: Date(timeIntervalSince1970: 8), text: "100% sure")
        let plainPercent = makeEntry(createdAt: Date(timeIntervalSince1970: 7), text: "100 percent")
        let underscore = makeEntry(createdAt: Date(timeIntervalSince1970: 6), text: "a_b value")
        let plainUnderscore = makeEntry(createdAt: Date(timeIntervalSince1970: 5), text: "axb value")
        let quoted = makeEntry(createdAt: Date(timeIntervalSince1970: 4), text: "say \"hi\" now")
        let plainQuote = makeEntry(createdAt: Date(timeIntervalSince1970: 3), text: "say hi now")
        let backslash = makeEntry(createdAt: Date(timeIntervalSince1970: 2), text: "C:\\temp\\file")
        for entry in [school, weather, percent, plainPercent, underscore, plainUnderscore, quoted, plainQuote, backslash] {
            try await repository.save(entry)
        }

        func ids(_ text: String) async throws -> [UUID] {
            try await repository.page(HistoryPageRequest(searchText: text)).entries.map(\.id)
        }

        #expect(try await ids("école") == [school.id])
        #expect(try await ids("ÉCOLE") == [school.id])
        #expect(try await ids("co") == [school.id])
        #expect(try await ids("天气") == [weather.id])
        #expect(try await ids("很好") == [weather.id])
        #expect(try await ids("100%") == [percent.id])
        #expect(try await ids("%") == [percent.id])
        #expect(try await ids("a_b") == [underscore.id])
        #expect(try await ids("_") == [underscore.id])
        #expect(try await ids("\"hi\"") == [quoted.id])
        #expect(try await ids("\"") == [quoted.id])
        #expect(try await ids("\\") == [backslash.id])
        #expect(try await ids("c:\\temp") == [backslash.id])
        #expect(try await ids("missing text").isEmpty)
    }

    @Test("Equal creation dates order by identifier like the in-memory repository")
    func orderingTieBreakIsStable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let createdAt = Date(timeIntervalSince1970: 100)
        let lowerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let lower = makeEntry(id: lowerID, createdAt: createdAt, text: "lower")
        let higher = makeEntry(id: higherID, createdAt: createdAt, text: "higher")
        let repository = SQLiteHistoryRepository(databaseURL: directory.appending(path: "history.sqlite"))
        try await repository.save(higher)
        try await repository.save(lower)
        let inMemory = InMemoryHistoryRepository(entries: [higher, lower])

        #expect(try await repository.entries().map(\.id) == [lowerID, higherID])
        #expect(await inMemory.entries().map(\.id) == [lowerID, higherID])
        #expect(try await repository.page(HistoryPageRequest()).entries.map(\.id) == [lowerID, higherID])
    }

    @Test("Lookups by identifier and date, audio paths, and bundle identifier counts")
    func lookups() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SQLiteHistoryRepository(databaseURL: directory.appending(path: "history.sqlite"))
        let first = makeEntry(
            createdAt: Date(timeIntervalSince1970: 100),
            text: "first",
            bundleIdentifier: "com.example.one",
            audioRelativePath: "audio/first.m4a"
        )
        let second = makeEntry(
            createdAt: Date(timeIntervalSince1970: 200),
            text: "second",
            bundleIdentifier: "com.example.one"
        )
        let third = makeEntry(
            createdAt: Date(timeIntervalSince1970: 300),
            text: "third",
            bundleIdentifier: "com.example.two",
            audioRelativePath: "audio/third.m4a"
        )
        let fourth = makeEntry(createdAt: Date(timeIntervalSince1970: 400), text: "fourth", bundleIdentifier: "")
        let fifth = makeEntry(createdAt: Date(timeIntervalSince1970: 500), text: "fifth")
        for entry in [first, second, third, fourth, fifth] {
            try await repository.save(entry)
        }

        #expect(try await repository.entries(ids: []).isEmpty)
        #expect(try await repository.entries(ids: [first.id, third.id, UUID()]).map(\.id) == [third.id, first.id])

        let since = try await repository.entries(since: Date(timeIntervalSince1970: 300))
        #expect(since.map(\.id) == [fifth.id, fourth.id, third.id])

        #expect(Set(try await repository.audioRelativePaths(createdBefore: nil)) == [
            "audio/first.m4a", "audio/third.m4a"
        ])
        #expect(try await repository.audioRelativePaths(
            createdBefore: Date(timeIntervalSince1970: 300)
        ) == ["audio/first.m4a"])
        #expect(try await repository.audioRelativePaths(
            createdBefore: Date(timeIntervalSince1970: 100)
        ).isEmpty)

        #expect(try await repository.bundleIdentifierCounts() == [
            "com.example.one": 2,
            "com.example.two": 1
        ])
    }

    @Test("Retention keeps entries at the cutoff and removes older ones")
    func appliesTimedRetention() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let policies: [(HistoryRetention, TimeInterval)] = [
            (.oneDay, 86_400),
            (.oneWeek, 7 * 86_400),
            (.oneMonth, 30 * 86_400)
        ]

        for (index, policy) in policies.enumerated() {
            let repository = SQLiteHistoryRepository(
                databaseURL: directory.appending(path: "retention-\(index).sqlite")
            )
            let boundary = makeEntry(createdAt: now.addingTimeInterval(-policy.1), text: "boundary")
            let expired = makeEntry(createdAt: now.addingTimeInterval(-policy.1 - 1), text: "expired")
            try await repository.save(boundary)
            try await repository.save(expired)

            try await repository.applyRetention(policy.0, now: now)

            #expect(try await repository.entries().map(\.id) == [boundary.id])
            #expect(try await repository.page(HistoryPageRequest(searchText: "expired")).totalCount == 0)
        }
    }

    @Test("Forever and disabled retention keep existing history")
    func terminalRetentionKeepsHistory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SQLiteHistoryRepository(databaseURL: directory.appending(path: "history.sqlite"))
        let entry = makeEntry(createdAt: Date(timeIntervalSince1970: 1), text: "retained")
        try await repository.save(entry)

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try await repository.applyRetention(.forever, now: now)
        #expect(try await repository.entries().map(\.id) == [entry.id])
        try await repository.applyRetention(.never, now: now)
        #expect(try await repository.entries().map(\.id) == [entry.id])
    }

    @Test("Creation dates keep sub-second precision")
    func dateRoundTripIsExact() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "history.sqlite")
        let createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000.123_456_789)
        let entry = makeEntry(createdAt: createdAt, text: "precise")
        try await SQLiteHistoryRepository(databaseURL: databaseURL).save(entry)

        let reloaded = try await SQLiteHistoryRepository(databaseURL: databaseURL).entries()
        #expect(reloaded == [entry])
        #expect(reloaded.first?.createdAt == createdAt)
        let since = try await SQLiteHistoryRepository(databaseURL: databaseURL).entries(since: createdAt)
        #expect(since.map(\.id) == [entry.id])
    }

    @Test("Imports the legacy JSON file once and deletes it")
    func importsLegacyJSONOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "history.sqlite")
        let legacyURL = directory.appending(path: "history.json")
        let legacy = [
            makeEntry(createdAt: Date(timeIntervalSince1970: 1_700_000_000), text: "legacy one"),
            makeEntry(
                createdAt: Date(timeIntervalSince1970: 1_700_000_100),
                text: "legacy two",
                bundleIdentifier: "com.example.legacy",
                audioRelativePath: "audio/legacy.m4a"
            )
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(to: legacyURL)

        let repository = SQLiteHistoryRepository(databaseURL: databaseURL, legacyJSONURL: legacyURL)
        #expect(try await repository.entries() == Array(legacy.reversed()))
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
        #expect(try await repository.page(HistoryPageRequest(searchText: "legacy")).totalCount == 2)
        #expect(try await repository.audioRelativePaths(createdBefore: nil) == ["audio/legacy.m4a"])

        try await repository.deleteAll()
        let second = SQLiteHistoryRepository(databaseURL: databaseURL, legacyJSONURL: legacyURL)
        #expect(try await second.entries().isEmpty)
    }

    @Test("Malformed legacy JSON reports an error and stays in place")
    func malformedLegacyJSONThrows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appending(path: "history.json")
        try Data("{malformed".utf8).write(to: legacyURL)

        let repository = SQLiteHistoryRepository(
            databaseURL: directory.appending(path: "history.sqlite"),
            legacyJSONURL: legacyURL
        )

        await #expect(throws: (any Error).self) {
            try await repository.entries()
        }
        #expect(try Data(contentsOf: legacyURL) == Data("{malformed".utf8))
    }

    @Test("Database files are private and shared between instances")
    func permissionsAndSharedFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "history.sqlite")
        let first = SQLiteHistoryRepository(databaseURL: databaseURL)
        let second = SQLiteHistoryRepository(databaseURL: databaseURL)
        let entry = makeEntry(createdAt: Date(timeIntervalSince1970: 1), text: "shared")

        try await first.save(entry)
        #expect(try await second.entries().map(\.id) == [entry.id])
        let other = makeEntry(createdAt: Date(timeIntervalSince1970: 2), text: "other")
        try await second.save(other)
        #expect(try await first.entries().map(\.id) == [other.id, entry.id])

        #expect(try posixPermissions(for: databaseURL) == 0o600)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                #expect(try posixPermissions(for: sidecar) == 0o600)
            }
        }
    }

    @Test("An existing database file is restricted to the owner on open")
    func existingDatabaseIsHardened() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "history.sqlite")
        try SQLiteHistoryRepositoryTests.createEmptyFile(at: databaseURL, permissions: 0o644)

        let repository = SQLiteHistoryRepository(databaseURL: databaseURL)
        _ = try await repository.entries()

        #expect(try posixPermissions(for: databaseURL) == 0o600)
    }

    @Test("Concurrent saves and a deletion end with exactly the expected entries")
    func concurrentMutations() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "history.sqlite")
        let repository = SQLiteHistoryRepository(databaseURL: databaseURL)
        let deleted = makeEntry(createdAt: Date(timeIntervalSince1970: 1), text: "delete me")
        let saved = (0..<40).map { index in
            makeEntry(createdAt: Date(timeIntervalSince1970: TimeInterval(index + 2)), text: "entry-\(index)")
        }
        try await repository.save(deleted)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await repository.delete(id: deleted.id)
            }
            for entry in saved {
                group.addTask {
                    try await repository.save(entry)
                }
            }
            try await group.waitForAll()
        }

        let reopened = SQLiteHistoryRepository(databaseURL: databaseURL)
        #expect(Set(try await reopened.entries().map(\.id)) == Set(saved.map(\.id)))
        #expect(try await reopened.page(HistoryPageRequest(searchText: "delete me")).totalCount == 0)
        #expect(try await reopened.page(HistoryPageRequest(searchText: "entry-")).totalCount == saved.count)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LerroTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEntry(
        id: UUID = UUID(),
        createdAt: Date,
        mode: CaptureMode = .dictation,
        text: String,
        applicationName: String = "Tests",
        bundleIdentifier: String? = nil,
        audioRelativePath: String? = nil
    ) -> HistoryEntry {
        HistoryEntry(
            id: id,
            createdAt: createdAt,
            mode: mode,
            rawText: text,
            finalText: text,
            duration: 1,
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            audioRelativePath: audioRelativePath
        )
    }

    private func posixPermissions(for url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    private static func createEmptyFile(at url: URL, permissions: Int) throws {
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: Data(),
            attributes: [.posixPermissions: NSNumber(value: permissions)]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
