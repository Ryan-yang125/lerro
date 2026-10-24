import Foundation

public enum IntelligenceMode: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case raw
    case remote

    public var id: String { rawValue }
}

public struct RemoteContextSharing: Codable, Hashable, Sendable {
    public var application: Bool
    public var windowTitle: Bool
    public var nearbyText: Bool
    public var selectedText: Bool
    public var dictionary: Bool
    public var tone: Bool

    public init(
        application: Bool = true,
        windowTitle: Bool = true,
        nearbyText: Bool = true,
        selectedText: Bool = true,
        dictionary: Bool = true,
        tone: Bool = true
    ) {
        self.application = application
        self.windowTitle = windowTitle
        self.nearbyText = nearbyText
        self.selectedText = selectedText
        self.dictionary = dictionary
        self.tone = tone
    }

    public static let full = RemoteContextSharing()
    public static let balanced = RemoteContextSharing(windowTitle: false)
}

public struct RemoteProviderConfiguration: Codable, Hashable, Sendable {
    public var apiKey: String
    public var contextSharing: RemoteContextSharing

    public init(
        apiKey: String = "",
        contextSharing: RemoteContextSharing = .full
    ) {
        self.apiKey = apiKey
        self.contextSharing = contextSharing
    }

    /// The only endpoint Lerro talks to.
    public static let baseURL = URL(string: "https://api.deepseek.com")!
    public static let modelIdentifier = "deepseek-flash"

    public var isReadyForUse: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case contextSharing
        /// Present only in files saved before Lerro supported DeepSeek alone.
        case provider
    }

    /// A saved key is kept only when it was a DeepSeek key, so that a key issued
    /// by another provider is never sent to DeepSeek.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var apiKey = ""
        let isDeepSeekKey = !container.contains(.provider)
            || (try? container.decode(String.self, forKey: .provider)) == "deepSeek"
        if isDeepSeekKey {
            apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        }
        self.init(
            apiKey: apiKey,
            contextSharing: try container.decodeIfPresent(
                RemoteContextSharing.self,
                forKey: .contextSharing
            ) ?? .full
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(contextSharing, forKey: .contextSharing)
    }
}

/// Text and token usage of one remote completion.
public struct RemoteGeneration: Sendable, Equatable {
    public var text: String
    public var modelIdentifier: String
    public var tokens: AITokenUsage?

    public init(text: String, modelIdentifier: String, tokens: AITokenUsage? = nil) {
        self.text = text
        self.modelIdentifier = modelIdentifier
        self.tokens = tokens
    }
}

public struct RemoteConnectionTestOutcome: Sendable, Equatable {
    public var succeeded: Bool
    public var message: String
    public var latencyMilliseconds: Int?
    public var modelIdentifier: String?
    public var tokens: AITokenUsage?

    public init(
        succeeded: Bool,
        message: String,
        latencyMilliseconds: Int? = nil,
        modelIdentifier: String? = nil,
        tokens: AITokenUsage? = nil
    ) {
        self.succeeded = succeeded
        self.message = message
        self.latencyMilliseconds = latencyMilliseconds
        self.modelIdentifier = modelIdentifier
        self.tokens = tokens
    }

    public static func success(
        message: String = "连接成功",
        latencyMilliseconds: Int? = nil,
        modelIdentifier: String? = nil,
        tokens: AITokenUsage? = nil
    ) -> RemoteConnectionTestOutcome {
        RemoteConnectionTestOutcome(
            succeeded: true,
            message: message,
            latencyMilliseconds: latencyMilliseconds,
            modelIdentifier: modelIdentifier,
            tokens: tokens
        )
    }
}

public enum IntelligenceResultSource: String, Codable, Hashable, Sendable {
    case raw
    case remote
}
