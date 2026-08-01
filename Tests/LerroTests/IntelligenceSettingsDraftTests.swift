import Testing
import LerroCore
@testable import Lerro

@Suite("Intelligence settings draft")
struct IntelligenceSettingsDraftTests {
    @Test("Provider changes apply the public preset, clear the old key, and preserve sharing choices")
    func providerPreset() {
        var sharing = RemoteContextSharing.full
        sharing.windowTitle = false
        var draft = IntelligenceProviderDraft(configuration: RemoteProviderConfiguration(
            provider: .custom,
            baseURL: "https://gateway.example/v1",
            modelIdentifier: "custom-model",
            apiKey: "secret",
            contextSharing: sharing
        ))

        draft.selectProvider(.deepSeek)

        #expect(draft.provider == .deepSeek)
        #expect(draft.baseURL == "https://api.deepseek.com")
        #expect(draft.modelIdentifier == "deepseek-v4-flash")
        #expect(draft.apiKey.isEmpty)
        #expect(draft.contextSharing.windowTitle == false)
    }

    @Test("API configuration stays view-local and trims fields at save time")
    func normalizedConfiguration() {
        let draft = IntelligenceProviderDraft(configuration: RemoteProviderConfiguration(
            provider: .custom,
            baseURL: "  https://gateway.example/v1  ",
            modelIdentifier: "  model-a  ",
            apiKey: "  key-a  "
        ))

        #expect(draft.validationMessage == nil)
        #expect(draft.configuration.baseURL == "https://gateway.example/v1")
        #expect(draft.configuration.modelIdentifier == "model-a")
        #expect(draft.configuration.apiKey == "key-a")
    }

    @Test("Incomplete or malformed custom configurations explain the blocking field")
    func validation() {
        var draft = IntelligenceProviderDraft(configuration: .preset(.custom))
        #expect(draft.validationMessage == "请输入 Model ID。")

        draft.modelIdentifier = "model-a"
        #expect(draft.validationMessage == "请输入 API Base URL。")

        draft.baseURL = "gateway.example/v1"
        #expect(draft.validationMessage == "API Base URL 需要是完整的 HTTP 或 HTTPS 地址。")

        draft.baseURL = "https://gateway.example/v1"
        #expect(draft.validationMessage == "请输入 API Key。")

        draft.apiKey = "key-a"
        #expect(draft.validationMessage == nil)

        draft.baseURL = "http://gateway.example/v1"
        #expect(
            draft.validationMessage
                == "远程 API 需要使用 HTTPS；localhost 与 loopback 地址可以使用 HTTP。"
        )

        draft.baseURL = "http://127.0.0.1:11434/v1"
        #expect(draft.validationMessage == nil)
    }

    @Test("Changing a custom endpoint origin clears the credential")
    func customOriginChangeClearsCredential() {
        var draft = IntelligenceProviderDraft(configuration: RemoteProviderConfiguration(
            provider: .custom,
            baseURL: "https://gateway.example/v1",
            modelIdentifier: "model-a",
            apiKey: "endpoint-bound-key"
        ))

        let sameOriginCleared = draft.updateBaseURL("https://gateway.example/v2")
        #expect(!sameOriginCleared)
        #expect(draft.apiKey == "endpoint-bound-key")
        let changedOriginCleared = draft.updateBaseURL("https://other.example/v1")
        #expect(changedOriginCleared)
        #expect(draft.apiKey.isEmpty)
    }

    @Test("Every context category remains independently configurable")
    func contextSharing() {
        var draft = IntelligenceProviderDraft()
        draft.contextSharing.application = false
        draft.contextSharing.windowTitle = false
        draft.contextSharing.nearbyText = false
        draft.contextSharing.selectedText = true
        draft.contextSharing.dictionary = true
        draft.contextSharing.tone = false

        let saved = draft.configuration.contextSharing
        #expect(saved.application == false)
        #expect(saved.windowTitle == false)
        #expect(saved.nearbyText == false)
        #expect(saved.selectedText)
        #expect(saved.dictionary)
        #expect(saved.tone == false)
    }
}
