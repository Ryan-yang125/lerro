import Foundation

public enum IntelligenceMode: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case raw
    case remote
    case local

    public var id: String { rawValue }
}

public enum RemoteProviderKind: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case deepSeek
    case openAI
    case gemini
    case custom

    public var id: String { rawValue }

    public var defaultBaseURL: String {
        switch self {
        case .deepSeek:
            "https://api.deepseek.com"
        case .openAI:
            "https://api.openai.com/v1"
        case .gemini:
            "https://generativelanguage.googleapis.com/v1beta/openai"
        case .custom:
            ""
        }
    }

    public var defaultModelIdentifier: String {
        switch self {
        case .deepSeek:
            "deepseek-v4-flash"
        case .openAI, .gemini, .custom:
            ""
        }
    }
}

public enum RemoteProviderEndpointValidation: Sendable, Equatable {
    case valid
    case invalid
    case insecure
}

public enum RemoteProviderEndpointPolicy {
    public static func validate(_ value: String) -> RemoteProviderEndpointValidation {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return .invalid
        }

        switch scheme {
        case "https":
            return .valid
        case "http" where isLoopback(host: host):
            return .valid
        case "http":
            return .insecure
        default:
            return .invalid
        }
    }

    public static func credentialOrigin(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validate(trimmed) == .valid,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    private static func isLoopback(host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "localhost" || normalized == "::1" {
            return true
        }
        let octets = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.allSatisfy({ UInt8($0) != nil }) else {
            return false
        }
        return octets[0] == "127"
    }
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
    public static let minimal = RemoteContextSharing(
        application: false,
        windowTitle: false,
        nearbyText: false,
        selectedText: false,
        dictionary: false,
        tone: false
    )
}

public struct RemoteProviderConfiguration: Codable, Hashable, Sendable {
    public var provider: RemoteProviderKind
    public var baseURL: String
    public var modelIdentifier: String
    public var apiKey: String
    public var contextSharing: RemoteContextSharing

    public init(
        provider: RemoteProviderKind = .deepSeek,
        baseURL: String? = nil,
        modelIdentifier: String? = nil,
        apiKey: String = "",
        contextSharing: RemoteContextSharing = .full
    ) {
        self.provider = provider
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.modelIdentifier = modelIdentifier ?? provider.defaultModelIdentifier
        self.apiKey = apiKey
        self.contextSharing = contextSharing
    }

    public static func preset(
        _ provider: RemoteProviderKind,
        apiKey: String = "",
        contextSharing: RemoteContextSharing = .full
    ) -> RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            provider: provider,
            apiKey: apiKey,
            contextSharing: contextSharing
        )
    }

    public var isReadyForUse: Bool {
        !modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && RemoteProviderEndpointPolicy.validate(baseURL) == .valid
    }
}

public struct RemoteConnectionTestOutcome: Sendable, Equatable {
    public var succeeded: Bool
    public var message: String
    public var latencyMilliseconds: Int?
    public var modelIdentifier: String?

    public init(
        succeeded: Bool,
        message: String,
        latencyMilliseconds: Int? = nil,
        modelIdentifier: String? = nil
    ) {
        self.succeeded = succeeded
        self.message = message
        self.latencyMilliseconds = latencyMilliseconds
        self.modelIdentifier = modelIdentifier
    }

    public static func success(
        message: String = "连接成功",
        latencyMilliseconds: Int? = nil,
        modelIdentifier: String? = nil
    ) -> RemoteConnectionTestOutcome {
        RemoteConnectionTestOutcome(
            succeeded: true,
            message: message,
            latencyMilliseconds: latencyMilliseconds,
            modelIdentifier: modelIdentifier
        )
    }

    public static func failure(_ message: String) -> RemoteConnectionTestOutcome {
        RemoteConnectionTestOutcome(succeeded: false, message: message)
    }
}

public typealias RemoteConnectionTestResult = RemoteConnectionTestOutcome

public enum IntelligenceResultSource: String, Codable, Hashable, Sendable {
    case raw
    case local
    case remote
}
