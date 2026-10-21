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

public protocol TermLearningRepository: Sendable {
    func load() async throws -> TermLearningState
    func save(_ state: TermLearningState) async throws
    func deleteAll() async throws
}

public protocol PreferencesRepository: Sendable {
    func load() async throws -> UserPreferences
    func save(_ preferences: UserPreferences) async throws
}

public protocol IntelligenceProcessing: Sendable {
    func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult
    func classifyCorrection(
        _ request: DictionaryLearningRequest
    ) async throws -> DictionaryLearningDecision
    func testRemoteConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome
}

public protocol RemoteLanguageModelRuntime: Sendable {
    func generate(
        configuration: RemoteProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> RemoteGeneration
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

    func testRemoteConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome {
        throw LerroError.remoteUnavailable("当前智能服务没有配置远程模型运行时")
    }
}
