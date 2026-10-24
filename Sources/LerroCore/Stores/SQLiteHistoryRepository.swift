import Foundation
import SQLite3

public struct SQLiteHistoryError: LocalizedError, Sendable {
    public let code: Int32
    public let message: String

    public var errorDescription: String? {
        "SQLite error \(code): \(message)"
    }
}

/// History stored in one SQLite database (WAL). Each row keeps the JSON-encoded `HistoryEntry`
/// plus the columns used for ordering, filtering, and full-text search.
public actor SQLiteHistoryRepository: HistoryRepository {
    private static let schemaVersion = 1
    private static let busyTimeoutMilliseconds: Int32 = 5000
    private static let ftsMinimumScalarCount = 3

    private let databaseURL: URL
    private let legacyJSONURL: URL?
    private var opened: Connection?

    public init(databaseURL: URL, legacyJSONURL: URL? = nil) {
        self.databaseURL = databaseURL
        self.legacyJSONURL = legacyJSONURL
    }

    deinit {
        if let opened {
            sqlite3_close_v2(opened.handle)
        }
    }

    // MARK: HistoryRepository

    public func entries() throws -> [HistoryEntry] {
        let connection = try connection()
        return try Self.decodeEntries(
            from: connection.query("SELECT entry FROM history \(Self.order)") { $0.blob(0) }
        )
    }

    public func entries(ids: Set<UUID>) throws -> [HistoryEntry] {
        guard !ids.isEmpty else { return [] }
        let connection = try connection()
        let array = "[" + ids.map { "\"\($0.uuidString)\"" }.joined(separator: ",") + "]"
        return try Self.decodeEntries(
            from: connection.query(
                "SELECT entry FROM history WHERE id IN (SELECT value FROM json_each(?)) \(Self.order)",
                [.text(array)]
            ) { $0.blob(0) }
        )
    }

    public func entries(since: Date) throws -> [HistoryEntry] {
        let connection = try connection()
        return try Self.decodeEntries(
            from: connection.query(
                "SELECT entry FROM history WHERE created_at >= ? \(Self.order)",
                [.double(since.timeIntervalSinceReferenceDate)]
            ) { $0.blob(0) }
        )
    }

    public func page(_ request: HistoryPageRequest) throws -> HistoryPage {
        let connection = try connection()
        var conditions: [String] = []
        var binds: [Bind] = []
        if let mode = request.mode {
            conditions.append("mode = ?")
            binds.append(.text(mode.rawValue))
        }
        if !request.searchText.isEmpty {
            if request.searchText.unicodeScalars.count >= Self.ftsMinimumScalarCount {
                conditions.append("seq IN (SELECT rowid FROM history_search WHERE history_search MATCH ?)")
                binds.append(.text(Self.ftsPhrase(request.searchText)))
            } else {
                let pattern = Self.likePattern(request.searchText)
                conditions.append("""
                    seq IN (SELECT rowid FROM history_search \
                    WHERE final_text LIKE ? ESCAPE '\\' OR application_name LIKE ? ESCAPE '\\')
                    """)
                binds.append(.text(pattern))
                binds.append(.text(pattern))
            }
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        let totalCount = try connection.query(
            "SELECT count(*) FROM history \(whereClause)", binds
        ) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
        let blobs = try connection.query(
            "SELECT entry FROM history \(whereClause) \(Self.order) LIMIT ? OFFSET ?",
            binds + [.int(request.limit), .int(request.offset)]
        ) { $0.blob(0) }
        let entries = try Self.decodeEntries(from: blobs)
        return HistoryPage(
            entries: entries,
            totalCount: totalCount,
            hasMore: request.offset + entries.count < totalCount
        )
    }

    public func audioRelativePaths(createdBefore date: Date?) throws -> [String] {
        let connection = try connection()
        if let date {
            return try connection.query(
                "SELECT audio_relative_path FROM history WHERE audio_relative_path IS NOT NULL AND created_at < ?",
                [.double(date.timeIntervalSinceReferenceDate)]
            ) { $0.text(0) }
        }
        return try connection.query(
            "SELECT audio_relative_path FROM history WHERE audio_relative_path IS NOT NULL"
        ) { $0.text(0) }
    }

    public func bundleIdentifierCounts() throws -> [String: Int] {
        let connection = try connection()
        let rows = try connection.query("""
            SELECT bundle_identifier, count(*) FROM history \
            WHERE bundle_identifier IS NOT NULL AND bundle_identifier <> '' \
            GROUP BY bundle_identifier
            """) { ($0.text(0), Int(sqlite3_column_int64($0, 1))) }
        return Dictionary(uniqueKeysWithValues: rows)
    }

    public func save(_ entry: HistoryEntry) throws {
        try Self.upsert([entry], on: connection())
    }

    public func delete(id: UUID) throws {
        try connection().run("DELETE FROM history WHERE id = ?", [.text(id.uuidString)])
    }

    public func deleteAll() throws {
        try connection().run("DELETE FROM history")
    }

    public func applyRetention(_ retention: HistoryRetention, now: Date) throws {
        guard let cutoff = retention.cutoff(now: now) else { return }
        try connection().run(
            "DELETE FROM history WHERE created_at < ?",
            [.double(cutoff.timeIntervalSinceReferenceDate)]
        )
    }

    // MARK: Opening

    private static let order = "ORDER BY created_at DESC, id ASC"

    private func connection() throws -> Connection {
        if let opened { return opened }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let path = databaseURL.path
        if !fileManager.fileExists(atPath: path) {
            guard fileManager.createFile(
                atPath: path,
                contents: Data(),
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw SQLiteHistoryError(code: SQLITE_CANTOPEN, message: "Cannot create the history database file")
            }
        }
        // SQLite creates the -wal and -shm files with the mode of the database file.
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(path, &handle, flags, nil)
        guard let handle else {
            throw SQLiteHistoryError(code: code, message: "Cannot open the history database")
        }
        let connection = Connection(handle: handle)
        guard code == SQLITE_OK else {
            let error = connection.failure(code)
            sqlite3_close_v2(handle)
            throw error
        }
        do {
            sqlite3_busy_timeout(handle, Self.busyTimeoutMilliseconds)
            try connection.run("PRAGMA journal_mode=WAL")
            try connection.run("PRAGMA synchronous=NORMAL")
            try Self.createSchemaIfNeeded(connection)
            try importLegacyJSON(into: connection)
        } catch {
            sqlite3_close_v2(handle)
            throw error
        }
        opened = connection
        return connection
    }

    private static func createSchemaIfNeeded(_ connection: Connection) throws {
        func userVersion() throws -> Int {
            try connection.query("PRAGMA user_version") { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
        }
        guard try userVersion() == 0 else { return }
        try connection.transaction {
            guard try userVersion() == 0 else { return }
            for statement in schema {
                try connection.run(statement)
            }
            try connection.run("PRAGMA user_version = \(schemaVersion)")
        }
    }

    private static let schema = [
        """
        CREATE TABLE history (
          seq INTEGER PRIMARY KEY,
          id TEXT NOT NULL UNIQUE,
          created_at REAL NOT NULL,
          mode TEXT NOT NULL,
          status TEXT NOT NULL,
          final_text TEXT NOT NULL,
          application_name TEXT NOT NULL,
          bundle_identifier TEXT,
          audio_relative_path TEXT,
          entry BLOB NOT NULL
        )
        """,
        "CREATE INDEX history_created_at ON history(created_at DESC, id)",
        "CREATE INDEX history_mode_created_at ON history(mode, created_at DESC, id)",
        """
        CREATE VIRTUAL TABLE history_search USING fts5(
          final_text, application_name,
          content='history', content_rowid='seq',
          tokenize='trigram case_sensitive 0'
        )
        """,
        """
        CREATE TRIGGER history_after_insert AFTER INSERT ON history BEGIN
          INSERT INTO history_search(rowid, final_text, application_name)
          VALUES (new.seq, new.final_text, new.application_name);
        END
        """,
        """
        CREATE TRIGGER history_after_delete AFTER DELETE ON history BEGIN
          INSERT INTO history_search(history_search, rowid, final_text, application_name)
          VALUES ('delete', old.seq, old.final_text, old.application_name);
        END
        """,
        """
        CREATE TRIGGER history_after_update AFTER UPDATE ON history BEGIN
          INSERT INTO history_search(history_search, rowid, final_text, application_name)
          VALUES ('delete', old.seq, old.final_text, old.application_name);
          INSERT INTO history_search(rowid, final_text, application_name)
          VALUES (new.seq, new.final_text, new.application_name);
        END
        """
    ]

    // MARK: Legacy JSON import

    /// Imports `history.json` written by earlier versions, then deletes it. The upsert is idempotent,
    /// so a crash between commit and deletion re-imports the same rows on the next launch.
    private func importLegacyJSON(into connection: Connection) throws {
        guard let legacyJSONURL, FileManager.default.fileExists(atPath: legacyJSONURL.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([HistoryEntry].self, from: Data(contentsOf: legacyJSONURL))
        try Self.upsert(entries, on: connection)
        try FileManager.default.removeItem(at: legacyJSONURL)
    }

    // MARK: Helpers

    private static func upsert(_ entries: [HistoryEntry], on connection: Connection) throws {
        let sql = """
            INSERT INTO history(
              id, created_at, mode, status, final_text, application_name,
              bundle_identifier, audio_relative_path, entry
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              created_at = excluded.created_at,
              mode = excluded.mode,
              status = excluded.status,
              final_text = excluded.final_text,
              application_name = excluded.application_name,
              bundle_identifier = excluded.bundle_identifier,
              audio_relative_path = excluded.audio_relative_path,
              entry = excluded.entry
            """
        let encoder = JSONEncoder()
        let write = {
            for entry in entries {
                try connection.run(sql, [
                    .text(entry.id.uuidString),
                    .double(entry.createdAt.timeIntervalSinceReferenceDate),
                    .text(entry.mode.rawValue),
                    .text(entry.status.rawValue),
                    .text(entry.finalText),
                    .text(entry.applicationName),
                    .optionalText(entry.bundleIdentifier),
                    .optionalText(entry.audioRelativePath),
                    .blob(try encoder.encode(entry))
                ])
            }
        }
        if entries.count == 1 {
            try write()
        } else {
            try connection.transaction(write)
        }
    }

    private static func decodeEntries(from blobs: [Data]) throws -> [HistoryEntry] {
        let decoder = JSONDecoder()
        return try blobs.map { try decoder.decode(HistoryEntry.self, from: $0) }
    }

    /// FTS5 phrase query. With the trigram tokenizer a phrase matches as a case-folded substring.
    private static func ftsPhrase(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func likePattern(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%" + escaped + "%"
    }
}

// MARK: - SQLite wrappers

private enum Bind {
    case text(String)
    case double(Double)
    case int(Int)
    case blob(Data)
    case null

    static func optionalText(_ value: String?) -> Bind {
        value.map(Bind.text) ?? .null
    }

    func apply(to statement: OpaquePointer, at index: Int32) -> Int32 {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        switch self {
        case .text(let value):
            return sqlite3_bind_text(statement, index, value, Int32(value.utf8.count), transient)
        case .double(let value):
            return sqlite3_bind_double(statement, index, value)
        case .int(let value):
            return sqlite3_bind_int64(statement, index, Int64(value))
        case .blob(let value):
            return value.withUnsafeBytes {
                sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient)
            }
        case .null:
            return sqlite3_bind_null(statement, index)
        }
    }
}

private extension OpaquePointer {
    func text(_ column: Int32) -> String {
        sqlite3_column_text(self, column).map { String(cString: $0) } ?? ""
    }

    func blob(_ column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(self, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(self, column)))
    }
}

/// The handle is opened with `SQLITE_OPEN_FULLMUTEX` (serialized mode), so SQLite allows use from
/// any thread. The actor is the only user apart from closing it in `deinit`.
private struct Connection: @unchecked Sendable {
    let handle: OpaquePointer

    func failure(_ code: Int32) -> SQLiteHistoryError {
        SQLiteHistoryError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }

    @discardableResult
    func query<T>(
        _ sql: String,
        _ binds: [Bind] = [],
        row: (OpaquePointer) throws -> T
    ) throws -> [T] {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw failure(prepared) }
        defer { sqlite3_finalize(statement) }
        for (offset, bind) in binds.enumerated() {
            let code = bind.apply(to: statement, at: Int32(offset + 1))
            guard code == SQLITE_OK else { throw failure(code) }
        }
        var rows: [T] = []
        while true {
            let code = sqlite3_step(statement)
            switch code {
            case SQLITE_ROW: rows.append(try row(statement))
            case SQLITE_DONE: return rows
            default: throw failure(code)
            }
        }
    }

    func run(_ sql: String, _ binds: [Bind] = []) throws {
        try query(sql, binds) { _ in () }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try run("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try run("COMMIT")
            return value
        } catch {
            _ = try? run("ROLLBACK")
            throw error
        }
    }
}
