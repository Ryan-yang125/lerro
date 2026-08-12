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
    func pauseLocalModelPreparation() async
    func discardLocalModelDownload() async throws
    func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult
    func processStream(
        _ request: IntelligenceRequest
    ) async throws -> AsyncThrowingStream<IntelligenceResult, any Error>
    func classifyCorrection(
        _ request: DictionaryLearningRequest
    ) async throws -> DictionaryLearningDecision
    func modelStatus() async -> LocalModelStatus
    func testRemoteConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome
}

public protocol LocalLanguageModelRuntime: Sendable {
    func load(modelIdentifier: String) async throws
    func pauseLoad() async
    func discardDownload() async throws
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
    func classifyCorrection(
        _ request: DictionaryLearningRequest
    ) async throws -> DictionaryLearningDecision {
        _ = request
        throw LerroError.modelUnavailable("当前智能服务不支持自动词典学习")
    }
}

public extension IntelligenceProcessing {
    func pauseLocalModelPreparation() async {}

    func discardLocalModelDownload() async throws {}

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
    func pauseLoad() async {}

    func discardDownload() async throws {}

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
    case paused
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
    public var downloadedBytes: Int64
    public var totalBytes: Int64
    public var bytesPerSecond: Double?

    public init(
        state: LocalModelState,
        modelIdentifier: String,
        progress: Double = 0,
        message: String = "",
        downloadedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        bytesPerSecond: Double? = nil
    ) {
        self.state = state
        self.modelIdentifier = modelIdentifier
        self.progress = progress
        self.message = message
        self.downloadedBytes = max(0, downloadedBytes)
        self.totalBytes = max(0, totalBytes)
        self.bytesPerSecond = bytesPerSecond
    }
}
