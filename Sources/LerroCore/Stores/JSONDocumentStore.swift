import Foundation

public actor JSONDocumentStore<Value: Codable & Sendable> {
    private let url: URL
    private let fallback: @Sendable () -> Value
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let filePermissions: Int?
    private var revision: UInt64 = 0
    private var observedFingerprint: FileFingerprint?

    private struct FileFingerprint: Equatable {
        var exists: Bool
        var fileNumber: UInt64
        var fileSize: UInt64
        var modificationDate: Date?

        static var missing: FileFingerprint {
            FileFingerprint(
                exists: false,
                fileNumber: 0,
                fileSize: 0,
                modificationDate: nil
            )
        }
    }

    public init(
        url: URL,
        fallback: @escaping @Sendable () -> Value,
        filePermissions: Int? = nil
    ) {
        self.url = url
        self.fallback = fallback
        self.filePermissions = filePermissions
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func read() throws -> Value {
        try readSnapshot().value
    }

    public func readSnapshot() throws -> (value: Value, revision: UInt64) {
        try applyConfiguredFilePermissionsIfPresent(at: url)
        var result: (Value, FileFingerprint)?
        var operationError: (any Error)?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                let fingerprint = try Self.fingerprint(for: coordinatedURL)
                let value: Value
                if fingerprint.exists {
                    value = try decoder.decode(Value.self, from: Data(contentsOf: coordinatedURL))
                } else {
                    value = fallback()
                }
                result = (value, fingerprint)
            } catch {
                operationError = error
            }
        }
        if let operationError { throw operationError }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }
        synchronizeRevision(with: result.1)
        return (result.0, revision)
    }

    public func isCurrent(revision expectedRevision: UInt64) throws -> Bool {
        guard revision == expectedRevision else { return false }
        let fingerprint = try Self.fingerprint(for: url)
        synchronizeRevision(with: fingerprint)
        return revision == expectedRevision
    }

    @discardableResult
    public func write(_ value: Value) throws -> UInt64 {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        guard let fingerprint = try coordinateWrite(data, expectedFingerprint: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        synchronizeRevision(with: fingerprint)
        return revision
    }

    public func write(_ value: Value, ifRevision expectedRevision: UInt64) throws -> UInt64? {
        guard revision == expectedRevision,
              let expectedFingerprint = observedFingerprint else {
            return nil
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        guard let fingerprint = try coordinateWrite(data, expectedFingerprint: expectedFingerprint) else {
            let current = try Self.fingerprint(for: url)
            synchronizeRevision(with: current)
            return nil
        }
        synchronizeRevision(with: fingerprint)
        return revision
    }

    @discardableResult
    public func mutate(
        _ update: @Sendable (inout Value) throws -> Void
    ) throws -> (value: Value, revision: UInt64) {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var result: (Value, FileFingerprint)?
        var operationError: (any Error)?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                let fingerprint = try Self.fingerprint(for: coordinatedURL)
                var value: Value
                if fingerprint.exists {
                    value = try decoder.decode(Value.self, from: Data(contentsOf: coordinatedURL))
                } else {
                    value = fallback()
                }
                try update(&value)
                try encoder.encode(value).write(to: coordinatedURL, options: [.atomic])
                try applyConfiguredFilePermissionsIfPresent(at: coordinatedURL)
                result = (value, try Self.fingerprint(for: coordinatedURL))
            } catch {
                operationError = error
            }
        }
        if let operationError { throw operationError }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw CocoaError(.fileWriteUnknown)
        }
        synchronizeRevision(with: result.1)
        return (result.0, revision)
    }

    private func coordinateWrite(
        _ data: Data,
        expectedFingerprint: FileFingerprint?
    ) throws -> FileFingerprint? {
        var result: FileFingerprint?
        var operationError: (any Error)?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                let current = try Self.fingerprint(for: coordinatedURL)
                if let expectedFingerprint, current != expectedFingerprint {
                    return
                }
                try data.write(to: coordinatedURL, options: [.atomic])
                try applyConfiguredFilePermissionsIfPresent(at: coordinatedURL)
                result = try Self.fingerprint(for: coordinatedURL)
            } catch {
                operationError = error
            }
        }
        if let operationError { throw operationError }
        if let coordinationError { throw coordinationError }
        return result
    }

    private func synchronizeRevision(with fingerprint: FileFingerprint) {
        if let observedFingerprint, observedFingerprint != fingerprint {
            revision &+= 1
        }
        self.observedFingerprint = fingerprint
    }

    private func applyConfiguredFilePermissionsIfPresent(at fileURL: URL) throws {
        guard let filePermissions,
              FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: filePermissions)],
            ofItemAtPath: fileURL.path
        )
    }

    private static func fingerprint(for url: URL) throws -> FileFingerprint {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return FileFingerprint(
                exists: true,
                fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                modificationDate: attributes[.modificationDate] as? Date
            )
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        }
    }
}
