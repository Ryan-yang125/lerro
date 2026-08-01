import Foundation

public enum LoginItemIdentityMigrationStatus: String, Codable, Equatable, Sendable {
    case pending
    case completed
    case requiresUserReview
}

public struct ApplicationDataMigrationResult: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case noLegacyData
        case currentDataAlreadyPresent
        case migrated
        case resumed
        case alreadyMigrated
    }

    public let state: State
    public let receiptURL: URL?
    public let loginItemStatus: LoginItemIdentityMigrationStatus?

    public init(
        state: State,
        receiptURL: URL?,
        loginItemStatus: LoginItemIdentityMigrationStatus?
    ) {
        self.state = state
        self.receiptURL = receiptURL
        self.loginItemStatus = loginItemStatus
    }

    public var requiresLoginItemReconciliation: Bool {
        loginItemStatus == .pending
    }
}

public struct ApplicationDataMigrationReceipt: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let version: Int
    public let migrationIdentifier: UUID
    public let sourceBundleIdentifier: String
    public let destinationBundleIdentifier: String
    public let completedAt: Date
    public let rootDeviceIdentifier: UInt64
    public let rootFileIdentifier: UInt64
    public var loginItemStatus: LoginItemIdentityMigrationStatus

    public init(
        version: Int = schemaVersion,
        migrationIdentifier: UUID,
        sourceBundleIdentifier: String,
        destinationBundleIdentifier: String,
        completedAt: Date,
        rootDeviceIdentifier: UInt64,
        rootFileIdentifier: UInt64,
        loginItemStatus: LoginItemIdentityMigrationStatus
    ) {
        self.version = version
        self.migrationIdentifier = migrationIdentifier
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.destinationBundleIdentifier = destinationBundleIdentifier
        self.completedAt = completedAt
        self.rootDeviceIdentifier = rootDeviceIdentifier
        self.rootFileIdentifier = rootFileIdentifier
        self.loginItemStatus = loginItemStatus
    }
}

public enum ApplicationDataMigrationError: LocalizedError, Equatable, Sendable {
    case rootsMustShareParent
    case sourceIsNotDirectory(String)
    case reconciliationConflicts(String)
    case migrationLocked(String)
    case invalidJournal(String)
    case invalidReceipt(String)
    case recoveryRequired(String)

    public var errorDescription: String? {
        switch self {
        case .rootsMustShareParent:
            "旧数据目录与新数据目录必须位于同一个 Application Support 父目录"
        case .sourceIsNotDirectory(let path):
            "旧数据路径不是目录：\(path)"
        case .reconciliationConflicts(let path):
            "新旧数据存在内容冲突，迁移已安全停止；恢复报告：\(path)"
        case .migrationLocked(let path):
            "另一个 Lerro 数据迁移仍在进行：\(path)"
        case .invalidJournal(let detail):
            "数据迁移日志无法验证：\(detail)"
        case .invalidReceipt(let detail):
            "数据迁移回执无法验证：\(detail)"
        case .recoveryRequired(let detail):
            "数据迁移需要人工恢复：\(detail)"
        }
    }
}

public struct ApplicationDataMigrator {
    static let receiptFilename = ".lerro-data-migration-v1.receipt.json"
    static let journalFilename = ".lerro-data-migration-v1.journal.json"
    static let lockFilename = ".lerro-data-migration-v1.lock"
    static let stagingDirectoryName = ".app.lerro.mac.migration-staging-v1"
    static let recoveryReportFilename = ".lerro-data-migration-v1.recovery.json"

    enum MigrationMode: String, Codable, Equatable, Sendable {
        case wholeRoot
        case reconcile
    }

    struct RootIdentity: Codable, Equatable, Sendable {
        let deviceIdentifier: UInt64
        let fileIdentifier: UInt64
    }

    struct MigrationJournal: Codable, Equatable, Sendable {
        static let schemaVersion = 1

        let version: Int
        let migrationIdentifier: UUID
        let sourceBundleIdentifier: String
        let destinationBundleIdentifier: String
        let startedAt: Date
        let mode: MigrationMode
        let rootIdentity: RootIdentity?
    }

    struct RecoveryReport: Codable, Equatable, Sendable {
        static let schemaVersion = 1

        struct Conflict: Codable, Equatable, Sendable {
            let relativePath: String
            let reason: String
        }

        let version: Int
        let createdAt: Date
        let sourceBundleIdentifier: String
        let destinationBundleIdentifier: String
        let conflicts: [Conflict]
    }

    private enum ReconciliationAction {
        case move(source: URL, destination: URL)
        case removeDuplicate(source: URL, destination: URL)
    }

    private struct MigrationLock: Codable, Sendable {
        let processIdentifier: Int32
        let createdAt: Date
    }

    private let fileManager: FileManager
    private let now: () -> Date
    private let lockStaleAfter: TimeInterval
    private let afterDestinationMove: () throws -> Void

    public init() {
        self.init(
            fileManager: .default,
            now: { .now },
            lockStaleAfter: 5 * 60,
            afterDestinationMove: {}
        )
    }

    init(
        fileManager: FileManager,
        now: @escaping () -> Date,
        lockStaleAfter: TimeInterval = 5 * 60,
        afterDestinationMove: @escaping () throws -> Void = {}
    ) {
        self.fileManager = fileManager
        self.now = now
        self.lockStaleAfter = lockStaleAfter
        self.afterDestinationMove = afterDestinationMove
    }

    public func migrateIfNeeded(
        from legacyPaths: ApplicationPaths = .legacy(),
        to currentPaths: ApplicationPaths = .live()
    ) throws -> ApplicationDataMigrationResult {
        try currentPaths.hardenRootDirectoryPermissions(fileManager: fileManager)
        defer { try? currentPaths.hardenRootDirectoryPermissions(fileManager: fileManager) }
        let result = try migrateDataIfNeeded(from: legacyPaths, to: currentPaths)
        try currentPaths.hardenRootDirectoryPermissions(fileManager: fileManager)
        return result
    }

    private func migrateDataIfNeeded(
        from legacyPaths: ApplicationPaths,
        to currentPaths: ApplicationPaths
    ) throws -> ApplicationDataMigrationResult {
        let source = legacyPaths.rootDirectory.standardizedFileURL
        let destination = currentPaths.rootDirectory.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        guard source.deletingLastPathComponent() == parent else {
            throw ApplicationDataMigrationError.rootsMustShareParent
        }

        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let receiptURL = destination.appending(path: Self.receiptFilename)
        if fileManager.fileExists(atPath: receiptURL.path) {
            let receipt = try readAndValidateReceipt(
                at: receiptURL,
                sourceBundleIdentifier: source.lastPathComponent,
                destinationBundleIdentifier: destination.lastPathComponent
            )
            if fileManager.fileExists(atPath: source.path) {
                let reportURL = parent.appending(path: Self.recoveryReportFilename)
                let report = RecoveryReport(
                    version: RecoveryReport.schemaVersion,
                    createdAt: now(),
                    sourceBundleIdentifier: source.lastPathComponent,
                    destinationBundleIdentifier: destination.lastPathComponent,
                    conflicts: [.init(
                        relativePath: ".",
                        reason: "迁移回执完成后旧数据根再次出现；请先确认旧版应用已经退出"
                    )]
                )
                try write(report, to: reportURL, atomically: true)
                throw ApplicationDataMigrationError.reconciliationConflicts(reportURL.path)
            }
            return ApplicationDataMigrationResult(
                state: .alreadyMigrated,
                receiptURL: receiptURL,
                loginItemStatus: receipt.loginItemStatus
            )
        }

        let lockURL = parent.appending(path: Self.lockFilename)
        try acquireLock(at: lockURL)
        defer { try? fileManager.removeItem(at: lockURL) }

        if fileManager.fileExists(atPath: receiptURL.path) {
            let receipt = try readAndValidateReceipt(
                at: receiptURL,
                sourceBundleIdentifier: source.lastPathComponent,
                destinationBundleIdentifier: destination.lastPathComponent
            )
            return ApplicationDataMigrationResult(
                state: .alreadyMigrated,
                receiptURL: receiptURL,
                loginItemStatus: receipt.loginItemStatus
            )
        }

        let journalURL = parent.appending(path: Self.journalFilename)
        let stagingURL = parent.appending(path: Self.stagingDirectoryName, directoryHint: .isDirectory)
        let recoveryReportURL = parent.appending(path: Self.recoveryReportFilename)
        if fileManager.fileExists(atPath: journalURL.path) {
            let journal = try readAndValidateJournal(
                at: journalURL,
                sourceBundleIdentifier: source.lastPathComponent,
                destinationBundleIdentifier: destination.lastPathComponent
            )
            switch journal.mode {
            case .wholeRoot:
                return try resume(
                    journal: journal,
                    journalURL: journalURL,
                    source: source,
                    staging: stagingURL,
                    destination: destination,
                    receiptURL: receiptURL
                )
            case .reconcile:
                return try reconcileRoots(
                    journal: journal,
                    journalURL: journalURL,
                    source: source,
                    destination: destination,
                    receiptURL: receiptURL,
                    recoveryReportURL: recoveryReportURL,
                    resultState: .resumed
                )
            }
        }

        if fileManager.fileExists(atPath: stagingURL.path) {
            throw ApplicationDataMigrationError.recoveryRequired(
                "发现没有事务日志的 staging 目录：\(stagingURL.path)"
            )
        }

        guard fileManager.fileExists(atPath: source.path) else {
            return ApplicationDataMigrationResult(
                state: fileManager.fileExists(atPath: destination.path)
                    ? .currentDataAlreadyPresent
                    : .noLegacyData,
                receiptURL: nil,
                loginItemStatus: nil
            )
        }
        try requireDirectory(at: source)

        if fileManager.fileExists(atPath: destination.path) {
            try requireDirectory(at: destination)
            let contents = try fileManager.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            )
            if !contents.isEmpty {
                let journal = MigrationJournal(
                    version: MigrationJournal.schemaVersion,
                    migrationIdentifier: UUID(),
                    sourceBundleIdentifier: source.lastPathComponent,
                    destinationBundleIdentifier: destination.lastPathComponent,
                    startedAt: now(),
                    mode: .reconcile,
                    rootIdentity: nil
                )
                return try reconcileRoots(
                    journal: journal,
                    journalURL: journalURL,
                    source: source,
                    destination: destination,
                    receiptURL: receiptURL,
                    recoveryReportURL: recoveryReportURL,
                    resultState: .migrated
                )
            }
            try fileManager.removeItem(at: destination)
        }

        let identity = try rootIdentity(at: source)
        let journal = MigrationJournal(
            version: MigrationJournal.schemaVersion,
            migrationIdentifier: UUID(),
            sourceBundleIdentifier: source.lastPathComponent,
            destinationBundleIdentifier: destination.lastPathComponent,
            startedAt: now(),
            mode: .wholeRoot,
            rootIdentity: identity
        )
        try write(journal, to: journalURL, atomically: true)
        return try performMigration(
            journal: journal,
            journalURL: journalURL,
            source: source,
            staging: stagingURL,
            destination: destination,
            receiptURL: receiptURL,
            resultState: .migrated
        )
    }

    public func recordLoginItemReconciliation(
        _ status: LoginItemIdentityMigrationStatus,
        receiptURL: URL
    ) throws {
        guard status != .pending else { return }
        var receipt: ApplicationDataMigrationReceipt = try read(receiptURL)
        guard receipt.version == ApplicationDataMigrationReceipt.schemaVersion,
              receipt.destinationBundleIdentifier == ApplicationIdentity.bundleIdentifier else {
            throw ApplicationDataMigrationError.invalidReceipt(receiptURL.path)
        }
        receipt.loginItemStatus = status
        try write(receipt, to: receiptURL, atomically: true)
    }

    private func resume(
        journal: MigrationJournal,
        journalURL: URL,
        source: URL,
        staging: URL,
        destination: URL,
        receiptURL: URL
    ) throws -> ApplicationDataMigrationResult {
        guard journal.mode == .wholeRoot, let expectedIdentity = journal.rootIdentity else {
            throw ApplicationDataMigrationError.invalidJournal(
                "整根迁移缺少目录文件系统身份"
            )
        }
        let present = [source, staging, destination].filter {
            fileManager.fileExists(atPath: $0.path)
        }
        guard present.count == 1, let locatedRoot = present.first else {
            throw ApplicationDataMigrationError.recoveryRequired(
                "事务目录数量异常；保留 source、staging 与 destination 供人工检查"
            )
        }
        guard try rootIdentity(at: locatedRoot) == expectedIdentity else {
            throw ApplicationDataMigrationError.invalidJournal(
                "事务目录的文件系统身份与日志不一致：\(locatedRoot.path)"
            )
        }

        if locatedRoot == source {
            return try performMigration(
                journal: journal,
                journalURL: journalURL,
                source: source,
                staging: staging,
                destination: destination,
                receiptURL: receiptURL,
                resultState: .resumed
            )
        }
        if locatedRoot == staging {
            try fileManager.moveItem(at: staging, to: destination)
        }
        return try finishMigration(
            journal: journal,
            journalURL: journalURL,
            source: source,
            staging: staging,
            destination: destination,
            receiptURL: receiptURL,
            resultState: .resumed
        )
    }

    private func performMigration(
        journal: MigrationJournal,
        journalURL: URL,
        source: URL,
        staging: URL,
        destination: URL,
        receiptURL: URL,
        resultState: ApplicationDataMigrationResult.State
    ) throws -> ApplicationDataMigrationResult {
        guard let expectedIdentity = journal.rootIdentity else {
            throw ApplicationDataMigrationError.invalidJournal(
                "整根迁移缺少目录文件系统身份"
            )
        }
        do {
            try fileManager.moveItem(at: source, to: staging)
            guard try rootIdentity(at: staging) == expectedIdentity else {
                throw ApplicationDataMigrationError.invalidJournal(
                    "staging 目录的文件系统身份发生变化"
                )
            }
            try fileManager.moveItem(at: staging, to: destination)
            return try finishMigration(
                journal: journal,
                journalURL: journalURL,
                source: source,
                staging: staging,
                destination: destination,
                receiptURL: receiptURL,
                resultState: resultState
            )
        } catch {
            try rollbackIfSafe(
                source: source,
                staging: staging,
                destination: destination,
                receiptURL: receiptURL,
                journalURL: journalURL,
                originalError: error
            )
            throw error
        }
    }

    private func finishMigration(
        journal: MigrationJournal,
        journalURL: URL,
        source: URL,
        staging: URL,
        destination: URL,
        receiptURL: URL,
        resultState: ApplicationDataMigrationResult.State
    ) throws -> ApplicationDataMigrationResult {
        guard let expectedIdentity = journal.rootIdentity else {
            throw ApplicationDataMigrationError.invalidJournal(
                "整根迁移缺少目录文件系统身份"
            )
        }
        do {
            guard try rootIdentity(at: destination) == expectedIdentity else {
                throw ApplicationDataMigrationError.invalidJournal(
                    "目标目录的文件系统身份发生变化"
                )
            }
            try afterDestinationMove()
            let receipt = ApplicationDataMigrationReceipt(
                version: ApplicationDataMigrationReceipt.schemaVersion,
                migrationIdentifier: journal.migrationIdentifier,
                sourceBundleIdentifier: journal.sourceBundleIdentifier,
                destinationBundleIdentifier: journal.destinationBundleIdentifier,
                completedAt: now(),
                rootDeviceIdentifier: expectedIdentity.deviceIdentifier,
                rootFileIdentifier: expectedIdentity.fileIdentifier,
                loginItemStatus: .pending
            )
            try write(receipt, to: receiptURL, atomically: true)
            try? fileManager.removeItem(at: journalURL)
            return ApplicationDataMigrationResult(
                state: resultState,
                receiptURL: receiptURL,
                loginItemStatus: .pending
            )
        } catch {
            try rollbackIfSafe(
                source: source,
                staging: staging,
                destination: destination,
                receiptURL: receiptURL,
                journalURL: journalURL,
                originalError: error
            )
            throw error
        }
    }

    private func reconcileRoots(
        journal: MigrationJournal,
        journalURL: URL,
        source: URL,
        destination: URL,
        receiptURL: URL,
        recoveryReportURL: URL,
        resultState: ApplicationDataMigrationResult.State
    ) throws -> ApplicationDataMigrationResult {
        guard journal.mode == .reconcile, journal.rootIdentity == nil else {
            throw ApplicationDataMigrationError.invalidJournal(
                "并存目录迁移日志的模式或目录身份字段无效"
            )
        }
        if !fileManager.fileExists(atPath: source.path) {
            try requireDirectory(at: destination)
            let identity = try rootIdentity(at: destination)
            let receipt = ApplicationDataMigrationReceipt(
                version: ApplicationDataMigrationReceipt.schemaVersion,
                migrationIdentifier: journal.migrationIdentifier,
                sourceBundleIdentifier: journal.sourceBundleIdentifier,
                destinationBundleIdentifier: journal.destinationBundleIdentifier,
                completedAt: now(),
                rootDeviceIdentifier: identity.deviceIdentifier,
                rootFileIdentifier: identity.fileIdentifier,
                loginItemStatus: .pending
            )
            try write(receipt, to: receiptURL, atomically: true)
            try? fileManager.removeItem(at: journalURL)
            try? fileManager.removeItem(at: recoveryReportURL)
            return ApplicationDataMigrationResult(
                state: resultState,
                receiptURL: receiptURL,
                loginItemStatus: .pending
            )
        }
        try requireDirectory(at: source)
        try requireDirectory(at: destination)

        var actions: [ReconciliationAction] = []
        var conflicts: [RecoveryReport.Conflict] = []
        try planReconciliation(
            source: source,
            destination: destination,
            relativePath: "",
            actions: &actions,
            conflicts: &conflicts
        )
        guard conflicts.isEmpty else {
            let report = RecoveryReport(
                version: RecoveryReport.schemaVersion,
                createdAt: now(),
                sourceBundleIdentifier: journal.sourceBundleIdentifier,
                destinationBundleIdentifier: journal.destinationBundleIdentifier,
                conflicts: conflicts.sorted { $0.relativePath < $1.relativePath }
            )
            try write(report, to: recoveryReportURL, atomically: true)
            throw ApplicationDataMigrationError.reconciliationConflicts(recoveryReportURL.path)
        }

        if !fileManager.fileExists(atPath: journalURL.path) {
            try write(journal, to: journalURL, atomically: true)
        }
        do {
            for action in actions {
                switch action {
                case .move(let sourceURL, let destinationURL):
                    guard fileManager.fileExists(atPath: sourceURL.path),
                          !fileManager.fileExists(atPath: destinationURL.path) else {
                        throw ApplicationDataMigrationError.recoveryRequired(
                            "reconcile move 的源或目标状态已经变化：\(sourceURL.path)"
                        )
                    }
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                case .removeDuplicate(let sourceURL, let destinationURL):
                    guard try itemsAreByteIdentical(sourceURL, destinationURL) else {
                        throw ApplicationDataMigrationError.recoveryRequired(
                            "reconcile 去重前内容发生变化：\(sourceURL.path)"
                        )
                    }
                    try fileManager.removeItem(at: sourceURL)
                }
            }
            try removeEmptyDirectoriesRecursively(at: source)
            guard !fileManager.fileExists(atPath: source.path) else {
                throw ApplicationDataMigrationError.recoveryRequired(
                    "reconcile 完成后旧数据根仍包含文件：\(source.path)"
                )
            }
            try afterDestinationMove()
            let identity = try rootIdentity(at: destination)
            let receipt = ApplicationDataMigrationReceipt(
                version: ApplicationDataMigrationReceipt.schemaVersion,
                migrationIdentifier: journal.migrationIdentifier,
                sourceBundleIdentifier: journal.sourceBundleIdentifier,
                destinationBundleIdentifier: journal.destinationBundleIdentifier,
                completedAt: now(),
                rootDeviceIdentifier: identity.deviceIdentifier,
                rootFileIdentifier: identity.fileIdentifier,
                loginItemStatus: .pending
            )
            try write(receipt, to: receiptURL, atomically: true)
            try? fileManager.removeItem(at: journalURL)
            try? fileManager.removeItem(at: recoveryReportURL)
            return ApplicationDataMigrationResult(
                state: resultState,
                receiptURL: receiptURL,
                loginItemStatus: .pending
            )
        } catch {
            // Every operation is independently replay-safe: moves never overwrite,
            // and removals only discard a byte-identical source duplicate.
            // The journal stays in place so the next launch can rescan and resume.
            throw error
        }
    }

    private func planReconciliation(
        source: URL,
        destination: URL,
        relativePath: String,
        actions: inout [ReconciliationAction],
        conflicts: inout [RecoveryReport.Conflict]
    ) throws {
        let sourceEntries = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for sourceEntry in sourceEntries {
            let childRelativePath = relativePath.isEmpty
                ? sourceEntry.lastPathComponent
                : "\(relativePath)/\(sourceEntry.lastPathComponent)"
            let destinationEntry = destination.appending(path: sourceEntry.lastPathComponent)
            guard fileManager.fileExists(atPath: destinationEntry.path) else {
                actions.append(.move(source: sourceEntry, destination: destinationEntry))
                continue
            }

            let sourceType = try fileType(at: sourceEntry)
            let destinationType = try fileType(at: destinationEntry)
            guard sourceType == destinationType else {
                conflicts.append(.init(
                    relativePath: childRelativePath,
                    reason: "文件类型不同"
                ))
                continue
            }

            switch sourceType {
            case .typeDirectory:
                try planReconciliation(
                    source: sourceEntry,
                    destination: destinationEntry,
                    relativePath: childRelativePath,
                    actions: &actions,
                    conflicts: &conflicts
                )
            case .typeRegular, .typeSymbolicLink:
                if try itemsAreByteIdentical(sourceEntry, destinationEntry) {
                    actions.append(.removeDuplicate(
                        source: sourceEntry,
                        destination: destinationEntry
                    ))
                } else {
                    conflicts.append(.init(
                        relativePath: childRelativePath,
                        reason: "同名内容不同"
                    ))
                }
            default:
                conflicts.append(.init(
                    relativePath: childRelativePath,
                    reason: "暂不支持的文件类型"
                ))
            }
        }
    }

    private func itemsAreByteIdentical(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let lhsType = try fileType(at: lhs)
        guard lhsType == (try fileType(at: rhs)) else { return false }
        if lhsType == .typeSymbolicLink {
            return try fileManager.destinationOfSymbolicLink(atPath: lhs.path)
                == fileManager.destinationOfSymbolicLink(atPath: rhs.path)
        }
        guard lhsType == .typeRegular else { return false }

        let lhsAttributes = try fileManager.attributesOfItem(atPath: lhs.path)
        let rhsAttributes = try fileManager.attributesOfItem(atPath: rhs.path)
        guard (lhsAttributes[.size] as? NSNumber)?.uint64Value
                == (rhsAttributes[.size] as? NSNumber)?.uint64Value else {
            return false
        }
        if try rootIdentity(at: lhs) == rootIdentity(at: rhs) {
            return true
        }

        let lhsHandle = try FileHandle(forReadingFrom: lhs)
        let rhsHandle = try FileHandle(forReadingFrom: rhs)
        defer {
            try? lhsHandle.close()
            try? rhsHandle.close()
        }
        while true {
            let lhsChunk = try lhsHandle.read(upToCount: 1_048_576) ?? Data()
            let rhsChunk = try rhsHandle.read(upToCount: 1_048_576) ?? Data()
            guard lhsChunk == rhsChunk else { return false }
            if lhsChunk.isEmpty { return true }
        }
    }

    private func fileType(at url: URL) throws -> FileAttributeType {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let type = attributes[.type] as? FileAttributeType else {
            throw ApplicationDataMigrationError.recoveryRequired(
                "无法读取文件类型：\(url.path)"
            )
        }
        return type
    }

    private func removeEmptyDirectoriesRecursively(at directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for child in children where (try? fileType(at: child)) == .typeDirectory {
            try removeEmptyDirectoriesRecursively(at: child)
        }
        let remaining = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        if remaining.isEmpty {
            try fileManager.removeItem(at: directory)
        }
    }

    private func rollbackIfSafe(
        source: URL,
        staging: URL,
        destination: URL,
        receiptURL: URL,
        journalURL: URL,
        originalError: any Error
    ) throws {
        guard !fileManager.fileExists(atPath: receiptURL.path) else { return }
        do {
            if fileManager.fileExists(atPath: staging.path),
               !fileManager.fileExists(atPath: source.path),
               !fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: staging, to: source)
            } else if fileManager.fileExists(atPath: destination.path),
                      !fileManager.fileExists(atPath: source.path),
                      !fileManager.fileExists(atPath: staging.path) {
                try fileManager.moveItem(at: destination, to: source)
            }
            if fileManager.fileExists(atPath: source.path),
               !fileManager.fileExists(atPath: staging.path),
               !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: journalURL)
                return
            }
        } catch {
            throw ApplicationDataMigrationError.recoveryRequired(
                "回滚失败：\(error.localizedDescription)；原始错误：\(originalError.localizedDescription)"
            )
        }
        throw ApplicationDataMigrationError.recoveryRequired(
            "自动回滚无法确认唯一数据根；原始错误：\(originalError.localizedDescription)"
        )
    }

    private func requireDirectory(at url: URL) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ApplicationDataMigrationError.sourceIsNotDirectory(url.path)
        }
    }

    private func rootIdentity(at url: URL) throws -> RootIdentity {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let file = attributes[.systemFileNumber] as? NSNumber else {
            throw ApplicationDataMigrationError.invalidJournal(
                "无法读取目录文件系统身份：\(url.path)"
            )
        }
        return RootIdentity(
            deviceIdentifier: device.uint64Value,
            fileIdentifier: file.uint64Value
        )
    }

    private func acquireLock(at lockURL: URL) throws {
        if fileManager.fileExists(atPath: lockURL.path) {
            let attributes = try? fileManager.attributesOfItem(atPath: lockURL.path)
            let modifiedAt = attributes?[.modificationDate] as? Date
            if let modifiedAt, now().timeIntervalSince(modifiedAt) >= lockStaleAfter {
                let staleURL = lockURL.appendingPathExtension("stale-\(UUID().uuidString)")
                do {
                    try fileManager.moveItem(at: lockURL, to: staleURL)
                    try? fileManager.removeItem(at: staleURL)
                } catch {
                    throw ApplicationDataMigrationError.migrationLocked(lockURL.path)
                }
            } else {
                throw ApplicationDataMigrationError.migrationLocked(lockURL.path)
            }
        }

        let lock = MigrationLock(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            createdAt: now()
        )
        do {
            let data = try encode(lock)
            try data.write(to: lockURL, options: .withoutOverwriting)
        } catch {
            throw ApplicationDataMigrationError.migrationLocked(lockURL.path)
        }
    }

    private func readAndValidateJournal(
        at url: URL,
        sourceBundleIdentifier: String,
        destinationBundleIdentifier: String
    ) throws -> MigrationJournal {
        let journal: MigrationJournal = try read(url)
        guard journal.version == MigrationJournal.schemaVersion,
              journal.sourceBundleIdentifier == sourceBundleIdentifier,
              journal.destinationBundleIdentifier == destinationBundleIdentifier else {
            throw ApplicationDataMigrationError.invalidJournal(url.path)
        }
        return journal
    }

    private func readAndValidateReceipt(
        at url: URL,
        sourceBundleIdentifier: String,
        destinationBundleIdentifier: String
    ) throws -> ApplicationDataMigrationReceipt {
        let receipt: ApplicationDataMigrationReceipt = try read(url)
        guard receipt.version == ApplicationDataMigrationReceipt.schemaVersion,
              receipt.sourceBundleIdentifier == sourceBundleIdentifier,
              receipt.destinationBundleIdentifier == destinationBundleIdentifier else {
            throw ApplicationDataMigrationError.invalidReceipt(url.path)
        }
        return receipt
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL, atomically: Bool) throws {
        let options: Data.WritingOptions = atomically ? .atomic : []
        try encode(value).write(to: url, options: options)
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func read<Value: Decodable>(_ url: URL) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: Data(contentsOf: url))
    }
}
