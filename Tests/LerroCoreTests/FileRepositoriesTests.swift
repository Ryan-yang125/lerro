import Foundation
import Testing
@testable import LerroCore

@Suite("File repositories", .serialized)
struct FileRepositoriesTests {
    @Test("History repository persists, sorts, updates, and deletes entries")
    func historyLifecycle() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "history/history.json")
        let repository = FileHistoryRepository(fileURL: fileURL)
        let older = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            text: "older"
        )
        var newer = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            text: "newer"
        )

        try await repository.save(older)
        try await repository.save(newer)

        let reopened = FileHistoryRepository(fileURL: fileURL)
        let initialEntries = try await reopened.entries()
        #expect(initialEntries.map(\.id) == [newer.id, older.id])

        newer.finalText = "updated"
        try await reopened.save(newer)
        let updatedEntries = try await reopened.entries()
        #expect(updatedEntries.count == 2)
        #expect(updatedEntries.first { $0.id == newer.id }?.finalText == "updated")

        try await reopened.delete(id: older.id)
        #expect(try await reopened.entries().map(\.id) == [newer.id])

        try await reopened.deleteAll()
        #expect(try await reopened.entries().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("History pages normalize requests and expose stable boundaries")
    func historyPagesAndRequestNormalization() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileHistoryRepository(
            fileURL: directory.appending(path: "paged-history.json")
        )
        let entries = (0..<6).map { index in
            makeHistoryEntry(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                text: "entry-\(index)"
            )
        }
        for entry in entries {
            try await repository.save(entry)
        }

        let normalized = HistoryPageRequest(
            offset: -12,
            limit: .max,
            searchText: "  entry  "
        )
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
        #expect(middle.totalCount == 6)
        #expect(middle.hasMore)

        let final = try await repository.page(HistoryPageRequest(offset: 4, limit: 2))
        #expect(final.entries.map(\.id) == [entries[1].id, entries[0].id])
        #expect(final.totalCount == 6)
        #expect(!final.hasMore)

        let beyondEnd = try await repository.page(HistoryPageRequest(offset: 100, limit: 2))
        #expect(beyondEnd.entries.isEmpty)
        #expect(beyondEnd.totalCount == 6)
        #expect(!beyondEnd.hasMore)
    }

    @Test("History pages search text and application names within an optional mode")
    func historyPageFilters() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileHistoryRepository(
            fileURL: directory.appending(path: "filtered-history.json")
        )
        let matchingText = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 300),
            mode: .dictation,
            text: "Hello Lerro",
            applicationName: "Notes"
        )
        let matchingApplication = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            mode: .translation,
            text: "translated",
            applicationName: "Lerro Editor"
        )
        let wrongMode = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            mode: .ask,
            text: "Lerro question",
            applicationName: "Browser"
        )
        for entry in [matchingText, matchingApplication, wrongMode] {
            try await repository.save(entry)
        }

        let allMatches = try await repository.page(
            HistoryPageRequest(limit: 20, searchText: "lErRo")
        )
        #expect(allMatches.entries.map(\.id) == [
            matchingText.id,
            matchingApplication.id,
            wrongMode.id
        ])
        #expect(allMatches.totalCount == 3)

        let filtered = try await repository.page(
            HistoryPageRequest(limit: 20, searchText: "LERRO", mode: .translation)
        )
        #expect(filtered.entries.map(\.id) == [matchingApplication.id])
        #expect(filtered.totalCount == 1)
        #expect(!filtered.hasMore)
    }

    @Test("History snapshot cache remains coherent after every mutation")
    func historySnapshotCacheCoherence() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileHistoryRepository(
            fileURL: directory.appending(path: "cached-history.json")
        )
        var entry = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            text: "original"
        )
        try await repository.save(entry)
        #expect(try await repository.entries().first?.finalText == "original")

        entry.finalText = "updated"
        try await repository.save(entry)
        #expect(try await repository.page(HistoryPageRequest()).entries.first?.finalText == "updated")

        let newer = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            text: "newer"
        )
        try await repository.save(newer)
        #expect(try await repository.entries().map(\.id) == [newer.id, entry.id])

        try await repository.delete(id: newer.id)
        #expect(try await repository.page(HistoryPageRequest()).entries.map(\.id) == [entry.id])
    }

    @Test("History cache observes writes from another repository instance")
    func historyCacheTracksExternalRepositoryWrites() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "shared-history.json")
        let firstRepository = FileHistoryRepository(fileURL: fileURL)
        let secondRepository = FileHistoryRepository(fileURL: fileURL)
        let first = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            text: "first"
        )
        let second = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            text: "second"
        )
        let third = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 300),
            text: "third"
        )

        try await firstRepository.save(first)
        #expect(try await firstRepository.entries().map(\.id) == [first.id])

        try await secondRepository.save(second)
        #expect(try await firstRepository.entries().map(\.id) == [second.id, first.id])

        try await firstRepository.save(third)
        let concurrent = (0..<20).map { index in
            makeHistoryEntry(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(400 + index)),
                text: "concurrent-\(index)"
            )
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, entry) in concurrent.enumerated() {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        try await firstRepository.save(entry)
                    } else {
                        try await secondRepository.save(entry)
                    }
                }
            }
            try await group.waitForAll()
        }

        let reopened = FileHistoryRepository(fileURL: fileURL)
        let expectedIDs = Set([first.id, second.id, third.id] + concurrent.map(\.id))
        #expect(Set(try await reopened.entries().map(\.id)) == expectedIDs)
    }

    @Test("File and in-memory history use the same deterministic tie-break")
    func historyOrderingTieBreakIsStable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let createdAt = Date(timeIntervalSince1970: 100)
        let lowerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let lower = makeHistoryEntry(id: lowerID, createdAt: createdAt, text: "lower")
        let higher = makeHistoryEntry(id: higherID, createdAt: createdAt, text: "higher")
        let fileRepository = FileHistoryRepository(
            fileURL: directory.appending(path: "stable-history.json")
        )
        try await fileRepository.save(higher)
        try await fileRepository.save(lower)
        let inMemoryRepository = InMemoryHistoryRepository(entries: [higher, lower])

        #expect(try await fileRepository.entries().map(\.id) == [lowerID, higherID])
        #expect(await inMemoryRepository.entries().map(\.id) == [lowerID, higherID])
    }

    @Test("History retention keeps entries at each boundary and removes older entries")
    func appliesTimedHistoryRetention() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let policies: [(HistoryRetention, TimeInterval)] = [
            (.oneDay, 86_400),
            (.oneWeek, 7 * 86_400),
            (.oneMonth, 30 * 86_400)
        ]

        for (index, policy) in policies.enumerated() {
            let repository = FileHistoryRepository(
                fileURL: directory.appending(path: "retention-\(index).json")
            )
            let boundary = makeHistoryEntry(
                id: UUID(),
                createdAt: now.addingTimeInterval(-policy.1),
                text: "boundary"
            )
            let expired = makeHistoryEntry(
                id: UUID(),
                createdAt: now.addingTimeInterval(-policy.1 - 1),
                text: "expired"
            )
            try await repository.save(boundary)
            try await repository.save(expired)

            try await repository.applyRetention(policy.0, now: now)

            let ids = Set(try await repository.entries().map(\.id))
            #expect(ids == [boundary.id])
        }
    }

    @Test("Concurrent history saves and deletion preserve every independent update")
    func concurrentHistoryMutationsAreAtomic() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileHistoryRepository(
            fileURL: directory.appending(path: "concurrent-history.json")
        )
        let deleted = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1),
            text: "delete me"
        )
        let saved = (0..<100).map { index in
            makeHistoryEntry(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index + 2)),
                text: "entry-\(index)"
            )
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

        let ids = Set(try await repository.entries().map(\.id))
        #expect(ids == Set(saved.map(\.id)))
    }

    @Test("Forever and disabled retention preserve existing history")
    func appliesTerminalRetentionPolicies() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "terminal-retention.json")
        let repository = FileHistoryRepository(fileURL: fileURL)
        let entry = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1),
            text: "retained"
        )
        try await repository.save(entry)

        let initialFileNumber = try systemFileNumber(for: fileURL)

        try await repository.applyRetention(.forever, now: Date(timeIntervalSince1970: 2_000_000_000))
        #expect(try await repository.entries().map(\.id) == [entry.id])
        #expect(try systemFileNumber(for: fileURL) == initialFileNumber)

        try await repository.applyRetention(.never, now: Date(timeIntervalSince1970: 2_000_000_000))
        #expect(try await repository.entries().map(\.id) == [entry.id])
        #expect(try systemFileNumber(for: fileURL) == initialFileNumber)

        let reopened = FileHistoryRepository(fileURL: fileURL)
        #expect(try await reopened.entries().map(\.id) == [entry.id])

        let inMemory = InMemoryHistoryRepository(entries: [entry])
        await inMemory.applyRetention(.never, now: Date(timeIntervalSince1970: 2_000_000_000))
        #expect(await inMemory.entries().map(\.id) == [entry.id])
    }

    @Test("Timed retention skips persistence when every entry remains eligible")
    func timedRetentionWithoutExpirationSkipsWrite() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "unexpired-retention.json")
        let repository = FileHistoryRepository(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try await repository.save(makeHistoryEntry(
            id: UUID(),
            createdAt: now.addingTimeInterval(-30),
            text: "recent"
        ))
        let initialFileNumber = try systemFileNumber(for: fileURL)

        try await repository.applyRetention(.oneDay, now: now)

        #expect(try systemFileNumber(for: fileURL) == initialFileNumber)
        #expect(try await repository.entries().count == 1)
    }

    @Test("JSON documents write compact output and read legacy pretty-printed files")
    func compactJSONAndLegacyCompatibility() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let compactURL = directory.appending(path: "compact-history.json")
        let entry = makeHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 42),
            text: "compact"
        )
        let compactRepository = FileHistoryRepository(fileURL: compactURL)
        try await compactRepository.save(entry)
        let compactData = try Data(contentsOf: compactURL)
        #expect(!compactData.contains(UInt8(ascii: "\n")))

        let legacyURL = directory.appending(path: "legacy-history.json")
        let legacyEncoder = JSONEncoder()
        legacyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        legacyEncoder.dateEncodingStrategy = .iso8601
        try legacyEncoder.encode([entry]).write(to: legacyURL)
        let legacyData = try Data(contentsOf: legacyURL)
        #expect(legacyData.contains(UInt8(ascii: "\n")))

        let legacyRepository = FileHistoryRepository(fileURL: legacyURL)
        #expect(try await legacyRepository.entries() == [entry])
    }

    @Test("Dictionary repository persists updates and merges imports by scoped phrase")
    func dictionaryLifecycleAndImport() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "dictionary.json")
        let repository = FileDictionaryRepository(fileURL: fileURL)
        var entry = DictionaryEntry(phrase: "type less", replacement: "Lerro")
        try await repository.save(entry)

        entry.replacement = "Lerro Native"
        try await repository.save(entry)

        let reopened = FileDictionaryRepository(fileURL: fileURL)
        var entries = try await reopened.entries()
        #expect(entries.count == 1)
        #expect(entries[0].replacement == "Lerro Native")

        let replacement = DictionaryEntry(phrase: "TYPE LESS", replacement: "Lerro")
        let scoped = DictionaryEntry(
            phrase: "type less",
            replacement: "Lerro for Notes",
            applicationBundleIdentifier: "com.apple.Notes"
        )
        try await reopened.importEntries([replacement, scoped])

        entries = try await reopened.entries()
        #expect(entries.count == 2)
        #expect(entries.contains { $0.id == replacement.id && $0.applicationBundleIdentifier == nil })
        #expect(entries.contains { $0.id == scoped.id && $0.applicationBundleIdentifier == "com.apple.Notes" })

        try await reopened.delete(id: scoped.id)
        #expect(try await reopened.entries().map(\.id) == [replacement.id])
    }

    @Test("Preferences repository supplies defaults and round-trips saved preferences")
    func preferencesRoundTrip() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "nested/preferences.json")
        let repository = FilePreferencesRepository(fileURL: fileURL)

        #expect(try await repository.load() == UserPreferences())

        let preferences = UserPreferences(
            recognitionLocaleIdentifier: "en_US",
            translationLanguageIdentifiers: ["zh_CN", "ja_JP"],
            appearance: .dark,
            historyRetention: .oneWeek,
            hasCompletedOnboarding: true
        )
        try await repository.save(preferences)

        let reopened = FilePreferencesRepository(fileURL: fileURL)
        #expect(try await reopened.load() == preferences)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try posixPermissions(for: fileURL) == 0o600)
    }

    @Test("Preferences repository hardens an existing document on first read")
    func preferencesHardenExistingDocument() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "preferences.json")
        try JSONEncoder().encode(UserPreferences()).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: fileURL.path
        )

        let repository = FilePreferencesRepository(fileURL: fileURL)
        _ = try await repository.load()

        #expect(try posixPermissions(for: fileURL) == 0o600)
    }

    @Test("Concurrent dictionary saves, imports, and deletion preserve every independent update")
    func concurrentDictionaryMutationsAreAtomic() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileDictionaryRepository(
            fileURL: directory.appending(path: "concurrent-dictionary.json")
        )
        let deleted = DictionaryEntry(phrase: "delete me", replacement: "deleted")
        let saved = (0..<60).map { index in
            DictionaryEntry(phrase: "saved-\(index)", replacement: "SAVED-\(index)")
        }
        let imported = (0..<60).map { index in
            DictionaryEntry(
                phrase: "imported-\(index)",
                replacement: "IMPORTED-\(index)",
                applicationBundleIdentifier: "com.example.import"
            )
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
            for batch in imported.chunked(maxCount: 10) {
                group.addTask {
                    try await repository.importEntries(batch)
                }
            }
            try await group.waitForAll()
        }

        let entries = try await repository.entries()
        let ids = Set(entries.map(\.id))
        #expect(entries.count == saved.count + imported.count)
        #expect(ids == Set(saved.map(\.id) + imported.map(\.id)))
    }

    @Test("Preferences repository reports malformed JSON")
    func preferencesReportsMalformedDocument() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "preferences.json")
        try Data("{malformed".utf8).write(to: fileURL)

        let repository = FilePreferencesRepository(fileURL: fileURL)

        await #expect(throws: (any Error).self) {
            try await repository.load()
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LerroTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeHistoryEntry(
        id: UUID,
        createdAt: Date,
        mode: CaptureMode = .dictation,
        text: String,
        applicationName: String = "Tests"
    ) -> HistoryEntry {
        HistoryEntry(
            id: id,
            createdAt: createdAt,
            mode: mode,
            rawText: text,
            finalText: text,
            duration: 1,
            applicationName: applicationName
        )
    }

    private func systemFileNumber(for url: URL) throws -> NSNumber {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.systemFileNumber] as? NSNumber)
    }

    private func posixPermissions(for url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start..<Swift.min(start + maxCount, count)])
        }
    }
}
