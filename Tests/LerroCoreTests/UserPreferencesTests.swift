import Foundation
import Testing
@testable import LerroCore

@Suite("User preferences")
struct UserPreferencesTests {
    @Test("Default preferences provide the expected first-run behavior")
    func validatesDefaults() {
        let preferences = UserPreferences()

        #expect(preferences.localProfileEmail.isEmpty)
        #expect(preferences.recognitionLocaleIdentifier == "zh_CN")
        #expect(preferences.translationLanguageIdentifiers == ["en_US"])
        #expect(preferences.appLanguage == .system)
        #expect(preferences.microphoneDeviceUID == nil)
        #expect(preferences.muteOtherAudio)
        #expect(preferences.appearance == .system)
        #expect(!preferences.launchAtLogin)
        #expect(preferences.showInDock)
        #expect(!preferences.saveAudio)
        #expect(preferences.historyRetention == .forever)
        #expect(!preferences.enhancementEnabled)
        #expect(preferences.intelligenceMode == .raw)
        #expect(preferences.localModelIdentifier == "mlx-community/Qwen3.5-4B-MLX-4bit")
        #expect(preferences.remoteProvider == RemoteProviderConfiguration())
        #expect(preferences.appToneProfiles.isEmpty)
        #expect(preferences.automaticDictionaryLearningEnabled)
        #expect(!preferences.isAutomaticDictionaryLearningActive)
        #expect(!preferences.quickDictateEnabled)
        #expect(!preferences.hasApprovedModelDownload)
        #expect(!preferences.hasCompletedOnboarding)
        #expect(preferences.onboardingStepIndex == nil)
        #expect(IntelligenceMode.allCases == [.raw, .remote, .local])
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

    @Test("Legacy shortcut activation and modifier key codes migrate without changing behavior")
    func migratesLegacyHotkeys() throws {
        let legacy = Data(#"""
        {
          "hotkeys": [
            {"action":"dictate","keyCode":null,"modifiers":0,"usesFunctionKey":true,"activation":"press","displayName":"Fn"},
            {"action":"translate","keyCode":56,"modifiers":8388608,"usesFunctionKey":true,"activation":"press","displayName":"Fn Left Shift"},
            {"action":"ask","keyCode":2,"modifiers":1048576,"usesFunctionKey":false,"activation":"press","displayName":"⌘D"},
            {"action":"pasteLastResult","keyCode":9,"modifiers":1310720,"usesFunctionKey":false,"activation":"doublePress","displayName":"⌃⌘V"}
          ]
        }
        """#.utf8)

        let preferences = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        let dictate = try #require(preferences.hotkeys.first { $0.action == .dictate })
        let translate = try #require(preferences.hotkeys.first { $0.action == .translate })
        let paste = try #require(preferences.hotkeys.first { $0.action == .pasteLastResult })

        #expect(dictate.activation == .hold)
        #expect(dictate.modifiers == 1 << 23)
        #expect(translate.activation == .hold)
        #expect(translate.keyCode == nil)
        #expect(translate.modifiers == (1 << 23) | (1 << 17))
        #expect(!preferences.hotkeys.contains { $0.action == .ask })
        #expect(paste.activation == .toggle)
    }

    @Test("Legacy hands-free shortcuts become base toggle bindings")
    func migratesLegacyHandsFreeHotkeys() throws {
        let legacy = Data(#"""
        {
          "hotkeys": [
            {"action":"dictateHandsFree","keyCode":2,"modifiers":262144,"usesFunctionKey":false,"activation":"doublePress","displayName":"⌃D"},
            {"action":"translateHandsFree","keyCode":17,"modifiers":524288,"usesFunctionKey":false,"activation":"press","displayName":"⌥T"},
            {"action":"askHandsFree","keyCode":0,"modifiers":1048576,"usesFunctionKey":false,"activation":"hold","displayName":"⌘A"}
          ]
        }
        """#.utf8)

        let preferences = try JSONDecoder().decode(UserPreferences.self, from: legacy)

        #expect(preferences.hotkeys.map(\.action) == [.dictate, .translate])
        #expect(preferences.hotkeys.allSatisfy { $0.activation == .toggle })
    }

    @Test("Shortcut documents without activation use the legacy migration path")
    func migratesMissingShortcutActivation() throws {
        let legacy = Data(
            #"{"hotkeys":[{"action":"dictate","modifiers":0,"usesFunctionKey":true,"displayName":"Fn"}]}"#.utf8
        )

        let preferences = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        let dictate = try #require(preferences.hotkeys.first)
        #expect(dictate.activation == .hold)
        #expect(dictate.modifiers == 1 << 23)
    }

    @Test("Physical shortcut aliases share one canonical signature and deduplicate on load")
    func canonicalizesShortcutAliases() throws {
        let legacy = Data(#"""
        {
          "hotkeys": [
            {"action":"dictate","keyCode":63,"modifiers":0,"usesFunctionKey":false,"activation":"hold","displayName":"Fn key"},
            {"action":"ask","keyCode":null,"modifiers":8388608,"usesFunctionKey":true,"activation":"toggle","displayName":"Fn flag"}
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

    @Test("Translation language choices are limited to three")
    func limitsTranslationLanguages() {
        let preferences = UserPreferences(
            translationLanguageIdentifiers: ["en_US", "ja_JP", "fr_FR", "de_DE"]
        )

        #expect(preferences.translationLanguageIdentifiers == ["en_US", "ja_JP", "fr_FR"])
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
            localProfileEmail: "local@example.com",
            localInvitationCode: "LOCAL-2026",
            appLanguage: .english,
            intelligenceMode: .remote,
            remoteProvider: RemoteProviderConfiguration(
                provider: .custom,
                baseURL: "https://models.example.test/v1",
                modelIdentifier: "fast-model",
                apiKey: "secret-test-key",
                contextSharing: .minimal
            ),
            hasApprovedModelDownload: true,
            hasCompletedOnboarding: false,
            onboardingStepIndex: 17
        )
        let encoded = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: encoded)

        #expect(decoded == preferences)
        #expect(decoded.localProfileEmail == "local@example.com")
        #expect(decoded.localInvitationCode == "LOCAL-2026")
        #expect(decoded.intelligenceMode == .remote)
        #expect(decoded.enhancementEnabled)
        #expect(decoded.remoteProvider.apiKey == "secret-test-key")
        #expect(decoded.hasApprovedModelDownload)
        #expect(decoded.onboardingStepIndex == 17)
        #expect(decoded.appLanguage == .english)
        #expect(decoded.automaticDictionaryLearningEnabled)
        #expect(decoded.isAutomaticDictionaryLearningActive)
        #expect(!decoded.quickDictateEnabled)
    }

    @Test("Older preference documents keep their saved values and default model consent to off")
    func migratesOlderDocuments() throws {
        let legacy = Data(#"{"recognitionLocaleIdentifier":"en_US","interactionSoundsEnabled":true,"enhancementEnabled":false,"hasCompletedOnboarding":true}"#.utf8)

        let decoded = try JSONDecoder().decode(UserPreferences.self, from: legacy)
        let reencoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)

        #expect(decoded.recognitionLocaleIdentifier == "en_US")
        #expect(!decoded.enhancementEnabled)
        #expect(decoded.intelligenceMode == .raw)
        #expect(decoded.remoteProvider == RemoteProviderConfiguration())
        #expect(decoded.hasCompletedOnboarding)
        #expect(!decoded.hasApprovedModelDownload)
        #expect(decoded.localInvitationCode.isEmpty)
        #expect(decoded.translationLanguageIdentifiers == ["en_US"])
        #expect(decoded.appLanguage == .system)
        #expect(decoded.automaticDictionaryLearningEnabled)
        #expect(!decoded.quickDictateEnabled)
        #expect(!reencoded.contains("interactionSoundsEnabled"))
    }

    @Test("Legacy enhancement and the explicit intelligence mode stay source compatible")
    func synchronizesLegacyEnhancementFlag() {
        var preferences = UserPreferences()

        preferences.enhancementEnabled = false
        #expect(preferences.intelligenceMode == .raw)

        preferences.enhancementEnabled = true
        #expect(preferences.intelligenceMode == .local)

        preferences.intelligenceMode = .remote
        #expect(preferences.enhancementEnabled)

        preferences.intelligenceMode = .raw
        #expect(!preferences.enhancementEnabled)
    }

    @Test("Automatic dictionary learning requires an active AI mode")
    func gatesAutomaticDictionaryLearning() {
        var preferences = UserPreferences()
        #expect(!preferences.isAutomaticDictionaryLearningActive)

        preferences.intelligenceMode = .remote
        #expect(preferences.isAutomaticDictionaryLearningActive)

        preferences.automaticDictionaryLearningEnabled = false
        #expect(!preferences.isAutomaticDictionaryLearningActive)
    }

    @Test("Dictionary entries become application-scoped Speech vocabulary terms")
    func mapsDictionaryToSpeechVocabulary() throws {
        let entry = DictionaryEntry(
            phrase: "乐若",
            replacement: "Lerro",
            source: .learned,
            applicationBundleIdentifier: "com.openai.chat",
            useCount: 8
        )
        let term = SpeechVocabularyTerm(dictionaryEntry: entry)

        #expect(term.phrase == "乐若")
        #expect(term.replacement == "Lerro")
        #expect(term.applicationBundleIdentifier == "com.openai.chat")
        #expect(term.priority == 8)
        #expect(try JSONDecoder().decode(
            SpeechVocabularyTerm.self,
            from: JSONEncoder().encode(term)
        ) == term)
    }

    @Test("Local model policy gates enhanced dictation, translation, and Ask")
    func validatesLocalModelUsagePolicy() {
        #expect(LocalModelUsagePolicy.requiresModel(for: .dictation, enhancementEnabled: true))
        #expect(!LocalModelUsagePolicy.requiresModel(for: .dictation, enhancementEnabled: false))
        #expect(LocalModelUsagePolicy.requiresModel(for: .translation, enhancementEnabled: false))
        #expect(LocalModelUsagePolicy.requiresModel(for: .ask, enhancementEnabled: false))
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
