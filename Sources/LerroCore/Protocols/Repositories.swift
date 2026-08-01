import Foundation

public struct HistoryPageRequest: Sendable, Equatable {
    public static let defaultLimit = 50
    public static let maximumLimit = 200

    public let offset: Int
    public let limit: Int
    public let searchText: String
    public let mode: CaptureMode?

    public init(
        offset: Int = 0,
        limit: Int = HistoryPageRequest.defaultLimit,
        searchText: String = "",
        mode: CaptureMode? = nil
    ) {
        self.offset = max(0, offset)
        self.limit = min(max(1, limit), Self.maximumLimit)
        self.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mode = mode
    }
}

public struct HistoryPage: Sendable, Equatable {
    public let entries: [HistoryEntry]
    public let totalCount: Int
    public let hasMore: Bool

    public init(entries: [HistoryEntry], totalCount: Int, hasMore: Bool) {
        self.entries = entries
        self.totalCount = max(0, totalCount)
        self.hasMore = hasMore
    }
}

public protocol HistoryRepository: Sendable {
    func entries() async throws -> [HistoryEntry]
    func page(_ request: HistoryPageRequest) async throws -> HistoryPage
    func save(_ entry: HistoryEntry) async throws
    func delete(id: UUID) async throws
    func deleteAll() async throws
    func applyRetention(_ retention: HistoryRetention, now: Date) async throws
}

public protocol DictionaryRepository: Sendable {
    func entries() async throws -> [DictionaryEntry]
    func save(_ entry: DictionaryEntry) async throws
    func delete(id: UUID) async throws
    func importEntries(_ entries: [DictionaryEntry]) async throws
}

public protocol PreferencesRepository: Sendable {
    func load() async throws -> UserPreferences
    func save(_ preferences: UserPreferences) async throws
}

public protocol IntelligenceProcessing: Sendable {
    func prepare(modelIdentifier: String) async throws
    func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult
    func processStream(
        _ request: IntelligenceRequest
    ) async throws -> AsyncThrowingStream<IntelligenceResult, any Error>
    func modelStatus() async -> LocalModelStatus
    func testRemoteConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome
}

public protocol LocalLanguageModelRuntime: Sendable {
    func load(modelIdentifier: String) async throws
    func generate(systemPrompt: String, userPrompt: String, maxTokens: Int) async throws -> String
    func generateStream(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, any Error>
    func status() async -> LocalModelStatus
}

public protocol RemoteLanguageModelRuntime: Sendable {
    func generate(
        configuration: RemoteProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String
    func generateStream(
        configuration: RemoteProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, any Error>
    func testConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome
}

public extension IntelligenceProcessing {
    func processStream(
        _ request: IntelligenceRequest
    ) async throws -> AsyncThrowingStream<IntelligenceResult, any Error> {
        let result = try await process(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
    }

    func testRemoteConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome {
        throw LerroError.remoteUnavailable("当前智能服务没有配置远程模型运行时")
    }
}

public extension LocalLanguageModelRuntime {
    func generateStream(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, any Error> {
        let result = try await generate(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
    }
}

public extension RemoteLanguageModelRuntime {
    func generateStream(
        configuration: RemoteProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, any Error> {
        let result = try await generate(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
    }
}

public enum LocalModelState: String, Codable, Sendable {
    case unavailable
    case downloading
    case ready
    case loading
    case loaded
    case failed
}

public struct LocalModelStatus: Codable, Sendable, Equatable {
    public var state: LocalModelState
    public var modelIdentifier: String
    public var progress: Double
    public var message: String

    public init(
        state: LocalModelState,
        modelIdentifier: String,
        progress: Double = 0,
        message: String = ""
    ) {
        self.state = state
        self.modelIdentifier = modelIdentifier
        self.progress = progress
        self.message = message
    }
}
