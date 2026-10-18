import Foundation
import LerroCore

public actor OpenAICompatibleRemoteLanguageModelRuntime: RemoteLanguageModelRuntime {
    private let protocolClasses: [AnyClass]?

    public init() {
        protocolClasses = nil
    }

    init(protocolClasses: [AnyClass]) {
        self.protocolClasses = protocolClasses
    }

    public func generate(
        configuration: RemoteProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> RemoteGeneration {
        let client = try client(for: configuration)
        let completion = try await client.complete(
            messages: Self.messages(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            ),
            maxTokens: maxTokens
        )
        return RemoteGeneration(
            text: completion.text,
            modelIdentifier: completion.modelIdentifier,
            tokens: completion.tokens
        )
    }

    public func testConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome {
        let client = try client(for: configuration)
        let probe = try await client.testConnection()
        return .success(
            latencyMilliseconds: Self.milliseconds(probe.latency),
            modelIdentifier: probe.modelIdentifier,
            tokens: probe.tokens
        )
    }

    private func client(
        for configuration: RemoteProviderConfiguration
    ) throws -> OpenAICompatibleHTTPClient {
        guard let baseURL = URL(string: configuration.baseURL) else {
            throw OpenAICompatibleRuntimeError.invalidEndpoint
        }
        return try OpenAICompatibleHTTPClient(
            endpoint: OpenAICompatibleEndpoint(
                providerIdentifier: configuration.provider.rawValue,
                baseURL: baseURL,
                modelIdentifier: configuration.modelIdentifier
            ),
            apiKey: configuration.apiKey,
            protocolClasses: protocolClasses
        )
    }

    private nonisolated static func messages(
        systemPrompt: String,
        userPrompt: String
    ) -> [OpenAICompatibleMessage] {
        [
            OpenAICompatibleMessage(role: .system, content: systemPrompt),
            OpenAICompatibleMessage(role: .user, content: userPrompt)
        ]
    }

    private nonisolated static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let wholeMilliseconds = components.seconds.multipliedReportingOverflow(by: 1_000)
        let fractionalMilliseconds = components.attoseconds / 1_000_000_000_000_000
        guard !wholeMilliseconds.overflow else { return Int.max }
        let total = wholeMilliseconds.partialValue.addingReportingOverflow(
            fractionalMilliseconds
        )
        guard !total.overflow else { return Int.max }
        return max(0, Int(clamping: total.partialValue))
    }
}
