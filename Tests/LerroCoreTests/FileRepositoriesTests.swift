import Foundation
import Testing
@testable import LerroCore

@Suite("File repositories", .serialized)
struct FileRepositoriesTests {
    @Test("JSON documents write compact output and read legacy pretty-printed files")
    func compactJSONAndLegacyCompatibility() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let compactURL = directory.appending(path: "compact.json")
        let entry = DictionaryEntry(phrase: "compact", replacement: "Compact")
        let compactStore = JSONDocumentStore<[DictionaryEntry]>(url: compactURL, fallback: { [] })
        _ = try await compactStore.write([entry])
        let compactData = try Data(contentsOf: compactURL)
        #expect(!compactData.contains(UInt8(ascii: "\n")))

        let legacyURL = directory.appending(path: "legacy.json")
        let legacyEncoder = JSONEncoder()
        legacyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        legacyEncoder.dateEncodingStrategy = .iso8601
        try legacyEncoder.encode([entry]).write(to: legacyURL)
        let legacyData = try Data(contentsOf: legacyURL)
        #expect(legacyData.contains(UInt8(ascii: "\n")))

        let legacyStore = JSONDocumentStore<[DictionaryEntry]>(url: legacyURL, fallback: { [] })
        #expect(try await legacyStore.read().map(\.id) == [entry.id])
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
            translationLanguageIdentifier: "ja_JP",
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
