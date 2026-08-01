import Foundation
import Testing
@testable import LerroCore

@Suite("Application data migration", .serialized)
struct ApplicationDataMigratorTests {
    @Test("Live paths use the frozen Lerro bundle identifier")
    func livePathsUseFrozenIdentity() {
        let paths = ApplicationPaths.live()

        #expect(paths.rootDirectory.lastPathComponent == "app.lerro.mac")
        #expect(ApplicationIdentity.legacyBundleIdentifier == "com.ryanyang.typelessnative")
    }

    @Test("Legacy data moves atomically and reruns from its receipt")
    func migratesWholeRootWithoutCopyingModelFiles() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = paths(in: parent, bundleIdentifier: ApplicationIdentity.legacyBundleIdentifier)
        let current = paths(in: parent, bundleIdentifier: ApplicationIdentity.bundleIdentifier)
        try seedLegacyData(at: legacy)
        let modelFile = legacy.modelsDirectory.appending(path: "model/model.safetensors")
        let originalFileIdentifier = try fileIdentifier(at: modelFile)

        let migrator = ApplicationDataMigrator()
        let first = try migrator.migrateIfNeeded(from: legacy, to: current)

        #expect(first.state == .migrated)
        #expect(first.requiresLoginItemReconciliation)
        #expect(!FileManager.default.fileExists(atPath: legacy.rootDirectory.path))
        #expect(FileManager.default.fileExists(atPath: current.preferencesFile.path))
        #expect(try Data(contentsOf: current.preferencesFile) == Data("preferences".utf8))
        #expect(try posixPermissions(at: current.rootDirectory) == 0o700)
        #expect(try fileIdentifier(
            at: current.modelsDirectory.appending(path: "model/model.safetensors")
        ) == originalFileIdentifier)

        let second = try migrator.migrateIfNeeded(from: legacy, to: current)
        #expect(second.state == .alreadyMigrated)
        #expect(second.receiptURL == first.receiptURL)

        let receiptURL = try #require(first.receiptURL)
        try migrator.recordLoginItemReconciliation(.completed, receiptURL: receiptURL)
        let third = try migrator.migrateIfNeeded(from: legacy, to: current)
        #expect(third.loginItemStatus == .completed)
        #expect(!third.requiresLoginItemReconciliation)
    }

    @Test("Preparing an existing data root hardens it to owner-only access")
    func prepareDirectoriesHardensExistingRoot() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let current = paths(in: parent, bundleIdentifier: ApplicationIdentity.bundleIdentifier)
        try FileManager.default.createDirectory(
            at: current.rootDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: current.rootDirectory.path
        )

        try current.prepareDirectories()

        #expect(try posixPermissions(at: current.rootDirectory) == 0o700)
    }

    @Test("Destination conflicts preserve both roots")
    func destinationConflictFailsClosed() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = paths(in: parent, bundleIdentifier: ApplicationIdentity.legacyBundleIdentifier)
        let current = paths(in: parent, bundleIdentifier: ApplicationIdentity.bundleIdentifier)
        try seedLegacyData(at: legacy)
        try current.prepareDirectories()
        try Data("current".utf8).write(to: current.preferencesFile)

        #expect(throws: ApplicationDataMigrationError.self) {
            try ApplicationDataMigrator().migrateIfNeeded(from: legacy, to: current)
        }
        #expect(FileManager.default.fileExists(atPath: legacy.preferencesFile.path))
        #expect(try Data(contentsOf: current.preferencesFile) == Data("current".utf8))
        #expect(FileManager.default.fileExists(
            atPath: legacy.modelsDirectory.appending(path: "model/model.safetensors").path
        ))
        let reportURL = parent.appending(path: ApplicationDataMigrator.recoveryReportFilename)
        let reportData = try Data(contentsOf: reportURL)
        #expect(String(decoding: reportData, as: UTF8.self).contains("preferences.json"))
    }

    @Test("Coexisting roots deduplicate identical files and move unique files")
    func reconcilesCoexistingRootsWithoutModelCopies() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = paths(in: parent, bundleIdentifier: ApplicationIdentity.legacyBundleIdentifier)
        let current = paths(in: parent, bundleIdentifier: ApplicationIdentity.bundleIdentifier)
        try seedLegacyData(at: legacy)
        try current.prepareDirectories()
        try Data("preferences".utf8).write(to: current.preferencesFile)
        let currentModelDirectory = current.modelsDirectory
            .appending(path: "model", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: currentModelDirectory,
            withIntermediateDirectories: true
        )
        let currentModel = currentModelDirectory.appending(path: "model.safetensors")
        try Data(repeating: 0xA5, count: 4_096).write(to: currentModel)
        let currentModelIdentifier = try fileIdentifier(at: currentModel)
        let legacyAudio = legacy.audioDirectory.appending(path: "capture.caf")
        try Data("audio".utf8).write(to: legacyAudio)
        let legacyAudioIdentifier = try fileIdentifier(at: legacyAudio)

        let result = try ApplicationDataMigrator().migrateIfNeeded(from: legacy, to: current)

        #expect(result.state == .migrated)
        #expect(!FileManager.default.fileExists(atPath: legacy.rootDirectory.path))
        #expect(try fileIdentifier(at: currentModel) == currentModelIdentifier)
        #expect(try fileIdentifier(
            at: current.audioDirectory.appending(path: "capture.caf")
        ) == legacyAudioIdentifier)
        #expect(try Data(contentsOf: current.historyFile) == Data("history".utf8))
    }

    @Test("Receipt failure rolls the complete tree back to the legacy path")
    func receiptFailureRollsBack() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = paths(in: parent, bundleIdentifier: ApplicationIdentity.legacyBundleIdentifier)
        let current = paths(in: parent, bundleIdentifier: ApplicationIdentity.bundleIdentifier)
        try seedLegacyData(at: legacy)
        let migrator = ApplicationDataMigrator(
            fileManager: .default,
            now: { Date(timeIntervalSince1970: 1_000) },
            afterDestinationMove: { throw SyntheticMigrationError.receiptWrite }
        )

        #expect(throws: SyntheticMigrationError.self) {
            try migrator.migrateIfNeeded(from: legacy, to: current)
        }
        #expect(FileManager.default.fileExists(atPath: legacy.preferencesFile.path))
        #expect(!FileManager.default.fileExists(atPath: current.rootDirectory.path))
        #expect(!FileManager.default.fileExists(
            atPath: parent.appending(path: ApplicationDataMigrator.journalFilename).path
        ))
    }

    @Test("An interrupted committed move resumes from its journal")
    func resumesMovedRootFromJournal() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = paths(in: parent, bundleIdentifier: ApplicationIdentity.legacyBundleIdentifier)
        let current = paths(in: parent, bundleIdentifier: ApplicationIdentity.bundleIdentifier)
        try seedLegacyData(at: legacy)
        let attributes = try FileManager.default.attributesOfItem(atPath: legacy.rootDirectory.path)
        let device = try #require(attributes[.systemNumber] as? NSNumber)
        let file = try #require(attributes[.systemFileNumber] as? NSNumber)
        let journal = ApplicationDataMigrator.MigrationJournal(
            version: ApplicationDataMigrator.MigrationJournal.schemaVersion,
            migrationIdentifier: UUID(),
            sourceBundleIdentifier: ApplicationIdentity.legacyBundleIdentifier,
            destinationBundleIdentifier: ApplicationIdentity.bundleIdentifier,
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .wholeRoot,
            rootIdentity: ApplicationDataMigrator.RootIdentity(
                deviceIdentifier: device.uint64Value,
                fileIdentifier: file.uint64Value
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(
            to: parent.appending(path: ApplicationDataMigrator.journalFilename),
            options: .atomic
        )
        try FileManager.default.moveItem(at: legacy.rootDirectory, to: current.rootDirectory)

        let result = try ApplicationDataMigrator().migrateIfNeeded(from: legacy, to: current)

        #expect(result.state == .resumed)
        #expect(FileManager.default.fileExists(atPath: current.preferencesFile.path))
        #expect(!FileManager.default.fileExists(
            atPath: parent.appending(path: ApplicationDataMigrator.journalFilename).path
        ))
    }

    @Test("A fresh migration lock blocks concurrent mutation")
    func activeLockBlocksMigration() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = paths(in: parent, bundleIdentifier: ApplicationIdentity.legacyBundleIdentifier)
        let current = paths(in: parent, bundleIdentifier: ApplicationIdentity.bundleIdentifier)
        try seedLegacyData(at: legacy)
        try Data("active".utf8).write(
            to: parent.appending(path: ApplicationDataMigrator.lockFilename),
            options: .withoutOverwriting
        )

        #expect(throws: ApplicationDataMigrationError.self) {
            try ApplicationDataMigrator().migrateIfNeeded(from: legacy, to: current)
        }
        #expect(FileManager.default.fileExists(atPath: legacy.preferencesFile.path))
        #expect(!FileManager.default.fileExists(atPath: current.rootDirectory.path))
    }

    @Test("A legacy root that reappears after the receipt fails closed")
    func legacyRootReappearingAfterReceiptRequiresRecovery() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let legacy = paths(in: parent, bundleIdentifier: ApplicationIdentity.legacyBundleIdentifier)
        let current = paths(in: parent, bundleIdentifier: ApplicationIdentity.bundleIdentifier)
        try seedLegacyData(at: legacy)
        let migrator = ApplicationDataMigrator()
        _ = try migrator.migrateIfNeeded(from: legacy, to: current)
        try legacy.prepareDirectories()
        try Data("late legacy data".utf8).write(to: legacy.historyFile)

        #expect(throws: ApplicationDataMigrationError.self) {
            try migrator.migrateIfNeeded(from: legacy, to: current)
        }
        #expect(try Data(contentsOf: legacy.historyFile) == Data("late legacy data".utf8))
        #expect(FileManager.default.fileExists(atPath: current.preferencesFile.path))
        let reportURL = parent.appending(path: ApplicationDataMigrator.recoveryReportFilename)
        let reportData = try Data(contentsOf: reportURL)
        #expect(String(decoding: reportData, as: UTF8.self).contains("旧数据根再次出现"))
    }

    private func paths(in parent: URL, bundleIdentifier: String) -> ApplicationPaths {
        ApplicationPaths(
            rootDirectory: parent.appending(path: bundleIdentifier, directoryHint: .isDirectory)
        )
    }

    private func seedLegacyData(at paths: ApplicationPaths) throws {
        try paths.prepareDirectories()
        try Data("preferences".utf8).write(to: paths.preferencesFile)
        try Data("history".utf8).write(to: paths.historyFile)
        let modelDirectory = paths.modelsDirectory.appending(path: "model", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0xA5, count: 4_096).write(
            to: modelDirectory.appending(path: "model.safetensors")
        )
    }

    private func fileIdentifier(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.systemFileNumber] as? NSNumber).uint64Value
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LerroMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum SyntheticMigrationError: Error {
    case receiptWrite
}
