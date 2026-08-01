import Foundation
import Testing
@testable import LerroCore

@Suite("Remote intelligence configuration")
struct IntelligenceProviderModelsTests {
    @Test("Provider presets and full context sharing have stable defaults")
    func validatesProviderDefaults() {
        let configuration = RemoteProviderConfiguration()

        #expect(configuration.provider == .deepSeek)
        #expect(configuration.baseURL == "https://api.deepseek.com")
        #expect(configuration.modelIdentifier == "deepseek-v4-flash")
        #expect(configuration.apiKey.isEmpty)
        #expect(configuration.contextSharing == .full)
        #expect(RemoteProviderKind.openAI.defaultBaseURL == "https://api.openai.com/v1")
        #expect(
            RemoteProviderKind.gemini.defaultBaseURL
                == "https://generativelanguage.googleapis.com/v1beta/openai"
        )
    }

    @Test("Remote provider JSON round-trips the API key and six individual sharing flags")
    func roundTripsProviderConfiguration() throws {
        let configuration = RemoteProviderConfiguration(
            provider: .custom,
            baseURL: "https://models.example.test/v1",
            modelIdentifier: "fast-model",
            apiKey: "secret-test-key",
            contextSharing: RemoteContextSharing(
                application: true,
                windowTitle: false,
                nearbyText: true,
                selectedText: false,
                dictionary: true,
                tone: false
            )
        )

        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(RemoteProviderConfiguration.self, from: encoded)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let sharing = try #require(object["contextSharing"] as? [String: Any])

        #expect(decoded == configuration)
        #expect(object["apiKey"] as? String == "secret-test-key")
        #expect(Set(sharing.keys) == [
            "application", "windowTitle", "nearbyText", "selectedText", "dictionary", "tone"
        ])
    }

    @Test("Capture sessions retain an immutable intelligence configuration snapshot")
    func snapshotsCaptureConfiguration() {
        var configuration = RemoteProviderConfiguration(apiKey: "captured-key")
        let session = CaptureSession(
            mode: .dictation,
            context: CapturedContext(applicationName: "Editor"),
            intelligenceMode: .remote,
            remoteProvider: configuration
        )
        configuration.apiKey = "later-key"

        #expect(session.intelligenceMode == .remote)
        #expect(session.remoteProvider?.apiKey == "captured-key")
    }

    @Test("Endpoint policy accepts HTTPS and local HTTP only")
    func endpointPolicy() {
        #expect(RemoteProviderEndpointPolicy.validate("https://models.example/v1") == .valid)
        #expect(RemoteProviderEndpointPolicy.validate("http://localhost:11434/v1") == .valid)
        #expect(RemoteProviderEndpointPolicy.validate("http://127.0.0.2:8000/v1") == .valid)
        #expect(RemoteProviderEndpointPolicy.validate("http://models.example/v1") == .insecure)
        #expect(RemoteProviderEndpointPolicy.validate("https://user@models.example/v1") == .invalid)
        #expect(
            RemoteProviderEndpointPolicy.credentialOrigin("https://models.example/v1")
                == "https://models.example:443"
        )
    }
}
