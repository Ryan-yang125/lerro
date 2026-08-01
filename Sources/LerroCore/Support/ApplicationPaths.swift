import Foundation

public enum ApplicationIdentity {
    public static let displayName = "Lerro"
    public static let bundleIdentifier = "app.lerro.mac"
    public static let legacyBundleIdentifier = "com.ryanyang.typelessnative"
}

public struct ApplicationPaths: Sendable {
    static let privateRootPermissions = 0o700

    public let rootDirectory: URL
    public let historyFile: URL
    public let dictionaryFile: URL
    public let preferencesFile: URL
    public let audioDirectory: URL
    public let modelsDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        self.historyFile = rootDirectory.appending(path: "history.json")
        self.dictionaryFile = rootDirectory.appending(path: "dictionary.json")
        self.preferencesFile = rootDirectory.appending(path: "preferences.json")
        self.audioDirectory = rootDirectory.appending(path: "Audio", directoryHint: .isDirectory)
        self.modelsDirectory = rootDirectory.appending(path: "Models", directoryHint: .isDirectory)
    }

    public static func live(bundleIdentifier: String = ApplicationIdentity.bundleIdentifier) -> ApplicationPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return ApplicationPaths(rootDirectory: base.appending(path: bundleIdentifier, directoryHint: .isDirectory))
    }

    public static func legacy() -> ApplicationPaths {
        live(bundleIdentifier: ApplicationIdentity.legacyBundleIdentifier)
    }

    public func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Self.privateRootPermissions)]
        )
        try hardenRootDirectoryPermissions()
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    func hardenRootDirectoryPermissions(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Self.privateRootPermissions)],
            ofItemAtPath: rootDirectory.path
        )
    }
}
