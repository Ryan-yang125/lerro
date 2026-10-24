import Foundation
import Testing
@testable import LerroCore

@Suite("User preferences")
struct UserPreferencesTests {
    @Test("Default preferences provide the expected first-run behavior")
    func validatesDefaults() {
        let preferences = UserPreferences()

        #expect(preferences.recognitionLocaleIdentifier == "zh_CN")
        #expect(preferences.translationLanguageIdentifier == "en_US")
        #expect(!preferences.aiOfferDismissed)
        #expect(preferences.appLanguage == .system)
        #expect(preferences.microphoneDeviceUID == nil)
        #expect(preferences.muteOtherAudio)
        #expect(preferences.playsCaptureSounds)
        #expect(preferences.appearance == .system)
        #expect(!preferences.launchAtLogin)
        #expect(preferences.showInDock)
        #expect(!preferences.saveAudio)
        #expect(preferences.historyRetention == .forever)
        #expect(preferences.intelligenceMode == .raw)
        #expect(preferences.remoteProvider == RemoteProviderConfiguration())
        #expect(preferences.appToneProfiles.isEmpty)
        #expect(preferences.automaticDictionaryLearningEnabled)
        #expect(!preferences.hasCompletedOnboarding)
        #expect(preferences.onboardingStepIndex == nil)
        #expect(IntelligenceMode.allCases == [.raw, .remote])
    }

    @Test("Audio capture requires explicit opt in and enabled history")
    func validatesAudioCapturePolicy() {
        var preferences = UserPreferences()
        #expect(!preferences.shouldSaveCaptureAudio)

        preferences.saveAudio = true
        #expect(preferences.shouldSaveCaptureAudio)

        preferences.historyRetention = .never
        #expect(!preferences.shouldSaveCaptureAudio)

        preferences.historyRetention = .oneWeek
        #expect(preferences.shouldSaveCaptureAudio)

        preferences.saveAudio = false
        #expect(!preferences.shouldSaveCaptureAudio)
    }

    @Test("Default tone instruction is empty and round-trips through JSON")
    func defaultToneInstructionDecoding() throws {
        let legacy = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        #expect(decoded.defaultToneInstruction == "")

        var preferences = UserPreferences()
        preferences.defaultToneInstruction = "自然、简洁"
        let roundTrip = try JSONDecoder().decode(
            UserPreferences.self,
            from: JSONEncoder().encode(preferences)
        )
        #expect(roundTrip.defaultToneInstruction == "自然、简洁")
    }

    @Test("Default hotkeys provide the clean first-run capture profile")
    func validatesDefaultHotkeys() throws {
        let hotkeys = UserPreferences().hotkeys

        #expect(hotkeys.count == 3)
        #expect(Set(hotkeys.map(\.action)) == [.dictate, .translate, .pasteLastResult])

        let dictate = try #require(hotkeys.first { $0.action == .dictate })
        #expect(dictate.usesFunctionKey)
        #expect(dictate.activation == .toggle)
        #expect(dictate.keyCode == nil)
        #expect(dictate.modifiers == 1 << 23)
        #expect(dictate.displayName == "Fn")

        let translate = try #require(hotkeys.first { $0.action == .translate })
        #expect(translate.usesFunctionKey)
        #expect(translate.activation == .toggle)
        #expect(translate.keyCode == nil)
        #expect(translate.modifiers == (1 << 23) | (1 << 17))
        #expect(translate.displayName == "Fn ⇧")

        let paste = try #require(hotkeys.first { $0.action == .pasteLastResult })
        #expect(paste.keyCode == 9)
        #expect(paste.displayName == "⌃⌘V")
        #expect(paste.activation == .toggle)
    }

    @Test("Modifier key codes and the Fn flag normalize on load")
    func normalizesHotkeysOnLoad() throws {
        let saved = Data(#"""
        {
          "hotkeys": [
            {"action":"dictate","keyCode":null,"modifiers":0,"usesFunctionKey":true,"activation":"hold","displayName":"Fn"},
            {"action":"translate","keyCode":56,"modifiers":8388608,"usesFunctionKey":true,"activation":"hold","displayName":"Fn Left Shift"},
            {"action":"pasteLastResult","keyCode":9,"modifiers":1310720,"usesFunctionKey":false,"activation":"toggle","displayName":"⌃⌘V"}
          ]
        }
        """#.utf8)

        let preferences = try JSONDecoder().decode(UserPreferences.self, from: saved)
        let dictate = try #require(preferences.hotkeys.first { $0.action == .dictate })
        let translate = try #require(preferences.hotkeys.first { $0.action == .translate })
        let paste = try #require(preferences.hotkeys.first { $0.action == .pasteLastResult })

        #expect(dictate.activation == .hold)
        #expect(dictate.modifiers == 1 << 23)
        #expect(translate.activation == .hold)
        #expect(translate.keyCode == nil)
        #expect(translate.modifiers == (1 << 23) | (1 << 17))
        #expect(paste.activation == .toggle)
    }

    @Test("Physical shortcut aliases share one canonical signature and deduplicate on load")
    func canonicalizesShortcutAliases() throws {
        let legacy = Data(#"""
        {
          "hotkeys": [
            {"action":"dictate","keyCode":63,"modifiers":0,"usesFunctionKey":false,"activation":"hold","displayName":"Fn key"},
            {"action":"translate","keyCode":null,"modifiers":8388608,"usesFunctionKey":true,"activation":"toggle","displayName":"Fn flag"}
          ]
        }
        """#.utf8)

        let preferences = try JSONDecoder().decode(UserPreferences.self, from: legacy)

        #expect(preferences.hotkeys.count == 1)
        #expect(preferences.hotkeys[0].signature == HotkeySignature(
            keyCode: nil,
            modifiers: 1 << 23
        ))
    }

    @Test("The translation language and the AI offer dismissal survive a round trip")
    func roundTripsTranslationLanguageAndOfferDismissal() throws {
        let preferences = UserPreferences(
            translationLanguageIdentifier: "ja_JP",
            aiOfferDismissed: true
        )
        let decoded = try JSONDecoder().decode(
            UserPreferences.self,
            from: JSONEncoder().encode(preferences)
        )

        #expect(decoded.translationLanguageIdentifier == "ja_JP")
        #expect(decoded.aiOfferDismissed)
        #expect(decoded == preferences)
    }

    @Test("Persists audio paths and onboarding progress fields")
    func roundTripsPersistenceFields() throws {
        let transcription = SpeechTranscription(
            rawText: "Transcript",
            localeIdentifier: "en_US",
            duration: 3.5,
            audioRelativePath: "Audio/session-001.caf"
        )
        #expect(transcription.audioRelativePath == "Audio/session-001.caf")

        let preferences = UserPreferences(
            appLanguage: .english,
            intelligenceMode: .remote,
            remoteProvider: RemoteProviderConfiguration(
                apiKey: "secret-test-key",
                contextSharing: RemoteContextSharing(
                    application: false,
                    windowTitle: false,
                    nearbyText: false,
                    selectedText: false,
                    dictionary: false,
                    tone: false
                )
            ),
            hasCompletedOnboarding: false,
            onboardingStepIndex: 17
        )
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: encoded)

        #expect(decoded == preferences)
        #expect(decoded.intelligenceMode == .remote)
        #expect(decoded.remoteProvider.apiKey == "secret-test-key")
        #expect(decoded.onboardingStepIndex == 17)
        #expect(decoded.appLanguage == .english)
        #expect(decoded.automaticDictionaryLearningEnabled)
    }

    @Test("Capture sounds default to on when missing and keep a saved off value")
    func captureSoundsPersistence() throws {
        let missing = try JSONDecoder().decode(UserPreferences.self, from: Data("{}".utf8))
        #expect(missing.playsCaptureSounds)

        let off = try JSONDecoder().decode(
            UserPreferences.self,
            from: Data(#"{"playsCaptureSounds":false}"#.utf8)
        )
        #expect(!off.playsCaptureSounds)
    }

    @Test("Hands-free stop hint count defaults to zero and survives a round trip")
    func handsFreeStopHintUseCountPersistence() throws {
        let legacy = Data(#"{"recognitionLocaleIdentifier":"en_US","hasCompletedOnboarding":true}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        #expect(decodedLegacy.handsFreeStopHintUseCount == 0)

        let preferences = UserPreferences(handsFreeStopHintUseCount: 7)
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: encoded)
        #expect(decoded.handsFreeStopHintUseCount == 7)
        #expect(decoded == preferences)
    }

    @Test("Older preference documents keep their saved values and drop retired keys")
    func migratesOlderDocuments() throws {
        let legacy = Data(#"{"recognitionLocaleIdentifier":"en_US","interactionSoundsEnabled":true,"quickDictateEnabled":true,"hasCompletedOnboarding":true}"#.utf8)

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        let reencoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)

        #expect(decoded.recognitionLocaleIdentifier == "en_US")
        #expect(decoded.intelligenceMode == .raw)
        #expect(decoded.remoteProvider == RemoteProviderConfiguration())
        #expect(decoded.hasCompletedOnboarding)
        #expect(decoded.translationLanguageIdentifier == "en_US")
        #expect(decoded.appLanguage == .system)
        #expect(decoded.automaticDictionaryLearningEnabled)
        #expect(!reencoded.contains("interactionSoundsEnabled"))
        #expect(!reencoded.contains("quickDictateEnabled"))
    }

    @Test("A saved DeepSeek key survives and a key from another provider is discarded")
    func legacyProviderKeys() throws {
        func decode(_ json: String) throws -> RemoteProviderConfiguration {
            try JSONDecoder().decode(RemoteProviderConfiguration.self, from: Data(json.utf8))
        }

        let deepSeek = try decode(#"{"provider":"deepSeek","apiKey":"sk-deepseek","contextSharing":{"application":true,"windowTitle":false,"nearbyText":true,"selectedText":true,"dictionary":true,"tone":true}}"#)
        #expect(deepSeek.apiKey == "sk-deepseek")
        #expect(!deepSeek.contextSharing.windowTitle)

        #expect(try decode(#"{"provider":"openAI","apiKey":"sk-openai"}"#).apiKey.isEmpty)
        #expect(try decode(#"{"provider":"gemini","baseURL":"https://x.test","apiKey":"k"}"#).apiKey.isEmpty)
        #expect(try decode(#"{"provider":"custom","apiKey":"k"}"#).apiKey.isEmpty)
        #expect(try decode(#"{"provider":7,"apiKey":"k"}"#).apiKey.isEmpty)

        let withoutProvider = try decode(#"{"apiKey":"sk-current"}"#)
        #expect(withoutProvider.apiKey == "sk-current")
        #expect(withoutProvider.contextSharing == .full)

        let reencoded = String(
            decoding: try JSONEncoder().encode(deepSeek),
            as: UTF8.self
        )
        #expect(!reencoded.contains("provider"))
        #expect(!reencoded.contains("baseURL"))
        #expect(!reencoded.contains("modelIdentifier"))
    }

    @Test("Remote configuration is fixed to DeepSeek and ready only with a key")
    func remoteConfigurationReadiness() {
        #expect(RemoteProviderConfiguration.baseURL.absoluteString == "https://api.deepseek.com")
        #expect(RemoteProviderConfiguration.modelIdentifier == "deepseek-flash")
        #expect(!RemoteProviderConfiguration().isReadyForUse)
        #expect(!RemoteProviderConfiguration(apiKey: "  \n").isReadyForUse)
        #expect(RemoteProviderConfiguration(apiKey: " sk-test ").isReadyForUse)
    }

    @Test("A saved intelligence mode that no longer exists decodes as raw")
    func retiredIntelligenceModeDecodesAsRaw() throws {
        let saved = Data(#"{"intelligenceMode":"local","hasCompletedOnboarding":true}"#.utf8)

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: saved)

        #expect(decoded.intelligenceMode == .raw)
        #expect(decoded.hasCompletedOnboarding)
    }

    @Test("The insufficient balance error names DeepSeek")
    func describesInsufficientBalance() {
        #expect(LerroError.insufficientBalance.errorDescription == "DeepSeek 余额用完了")
    }

    @Test("Secure field errors explain the privacy boundary")
    func describesSecureFieldBoundary() {
        #expect(LerroError.secureField.errorDescription == "为保护敏感信息，密码输入框中已停用语音输入")
        #expect(!CapturePrivacyPolicy.permitsCapture(in: CapturedContext(isSecureField: true)))
        #expect(CapturePrivacyPolicy.permitsCapture(in: CapturedContext(isSecureField: false)))
    }

    @Test("Captured selection state round-trips and legacy nil remains unavailable")
    func capturedSelectionStateIsBackwardCompatible() throws {
        let current = CapturedContext(
            applicationName: "Editor",
            processIdentifier: 42,
            selectionState: .knownEmpty,
            focusedElementAvailable: true,
            focusedElementFingerprint: 123,
            focusedValueFingerprint: 456,
            selectedRange: UTF16TextRange(location: 7, length: 2)
        )
        let roundTripped = try JSONDecoder().decode(
            CapturedContext.self,
            from: JSONEncoder().encode(current)
        )
        #expect(roundTripped == current)
        #expect(roundTripped.cursorBefore == nil)
        #expect(roundTripped.cursorAfter == nil)
        #expect(roundTripped.focusedElementAvailable)
        #expect(roundTripped.focusedElementFingerprint == 123)
        #expect(roundTripped.focusedValueFingerprint == 456)
        #expect(roundTripped.selectedRange == UTF16TextRange(location: 7, length: 2))

        let legacyEmpty = Data(
            #"{"applicationName":"Legacy","isSecureField":false}"#.utf8
        )
        let decodedEmpty = try JSONDecoder().decode(CapturedContext.self, from: legacyEmpty)
        #expect(decodedEmpty.selectionState == .unavailable)
        #expect(!decodedEmpty.selectedTextWasTruncated)
        #expect(!decodedEmpty.focusedElementAvailable)

        let legacySelection = Data(
            #"{"applicationName":"Legacy","selectedText":"selected","isSecureField":false}"#.utf8
        )
        let decodedSelection = try JSONDecoder().decode(
            CapturedContext.self,
            from: legacySelection
        )
        #expect(decodedSelection.selectionState == .knownSelection)

        let truncated = CapturedContext(
            applicationName: "Editor",
            selectedText: "bounded",
            selectedTextWasTruncated: true
        )
        let decodedTruncated = try JSONDecoder().decode(
            CapturedContext.self,
            from: JSONEncoder().encode(truncated)
        )
        #expect(decodedTruncated.selectedTextWasTruncated)

        let cursorContext = CapturedContext(
            applicationName: "Editor",
            cursorBefore: "before",
            cursorAfter: "after"
        )
        let decodedCursorContext = try JSONDecoder().decode(
            CapturedContext.self,
            from: JSONEncoder().encode(cursorContext)
        )
        #expect(decodedCursorContext.cursorBefore == "before")
        #expect(decodedCursorContext.cursorAfter == "after")
    }
}
