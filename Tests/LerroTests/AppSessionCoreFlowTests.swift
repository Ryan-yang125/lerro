import AppKit
import Foundation
import Testing
import LerroCore
import LerroMac
@testable import Lerro

@Suite("App session V1.6 core flow", .serialized)
struct AppSessionCoreFlowTests {
    @Test("Speech resources prepare automatically and cancelled capture never starts afterward")
    @MainActor
    func automaticSpeechPreparation() async {
        let harness = makeHarness(text: "hello", resourcesReady: false)
        await harness.session.start()
        #expect(await waitUntil { await harness.speech.preparations() == ["zh_CN"] })
        #expect(harness.session.speechResourceStatus.state == .downloading)
        await harness.session.refreshLanguageResources()
        #expect(await harness.speech.preparations().count == 1)

        harness.session.toggleCapture(.dictation)
        harness.session.cancelCapture()
        await harness.speech.finishPreparation("zh_CN")
        #expect(await waitUntil { harness.session.speechResourceStatus.state == .ready })
        #expect(await harness.speech.starts().isEmpty)

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(await harness.speech.starts().count == 1)
        harness.session.cancelCapture()
    }

    @Test("Capture reports waiting while Speech resources prepare and clears the flag on every exit")
    @MainActor
    func captureWaitsForSpeechResources() async {
        let harness = makeHarness(text: "hello", resourcesReady: false)
        await harness.session.start()
        #expect(await waitUntil { await harness.speech.preparations() == ["zh_CN"] })

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.isWaitingForSpeechResources })
        harness.session.cancelCapture()
        #expect(!harness.session.isWaitingForSpeechResources)
        // A cancelled capture finishes cleanup before the next shortcut is accepted.
        #expect(await waitUntil { harness.session.phase == .idle })

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.isWaitingForSpeechResources })
        await harness.speech.finishPreparation("zh_CN")
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(!harness.session.isWaitingForSpeechResources)
        harness.session.cancelCapture()
    }

    @Test("A language change prepares new Speech resources and ignores the previous result")
    @MainActor
    func speechPreparationFollowsLanguage() async {
        let harness = makeHarness(text: "", resourcesReady: false)
        await harness.session.start()
        #expect(await waitUntil { await harness.speech.preparations() == ["zh_CN"] })
        let previous = harness.session.preferences
        harness.session.preferences.recognitionLocaleIdentifier = "ja_JP"
        harness.session.savePreferences(from: previous, to: harness.session.preferences)
        #expect(await waitUntil { await harness.speech.preparations() == ["zh_CN", "ja_JP"] })
        await harness.speech.finishPreparation("ja_JP")
        #expect(await waitUntil { harness.session.speechResourceStatus.state == .ready })
        await harness.speech.finishPreparation("zh_CN")
        await Task.yield()
        #expect(harness.session.speechResourceStatus.sourceLanguageIdentifier == "ja_JP")
        #expect(harness.session.speechResourceStatus.state == .ready)
    }

    @Test("An incomplete Speech installation stops loading and can be retried")
    @MainActor
    func speechPreparationCanRetry() async {
        let harness = makeHarness(text: "", resourcesReady: false)
        await harness.session.start()
        #expect(await waitUntil { await harness.speech.preparations().count == 1 })
        await harness.speech.finishPreparation("zh_CN", installed: false)
        #expect(await waitUntil { harness.session.speechResourceStatus.state == .failed })
        harness.session.prepareSpeechResources()
        #expect(await waitUntil { await harness.speech.preparations().count == 2 })
        await harness.speech.finishPreparation("zh_CN")
        #expect(await waitUntil { harness.session.speechResourceStatus.state == .ready })
    }

    @Test("Closing or reviewing onboarding preserves whether setup was completed", arguments: [false, true])
    @MainActor
    func onboardingCanBeDismissed(completed: Bool) async {
        var preferences = basePreferences()
        preferences.hasCompletedOnboarding = completed
        let harness = makeHarness(text: "", preferences: preferences)
        await harness.session.start()
        harness.session.restartOnboarding()
        #expect(harness.session.isOnboardingPresented)
        #expect(harness.session.preferences.hasCompletedOnboarding == completed)
        harness.session.dismissOnboarding()
        #expect(!harness.session.isOnboardingPresented)
        #expect(harness.session.preferences.hasCompletedOnboarding == completed)
    }

    @Test("Raw dictation previews, inserts, persists, and ends without a success receipt")
    @MainActor
    func rawDictationCompletesCleanly() async {
        let harness = makeHarness(text: "hello Lerro")
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(harness.session.partialTranscript == "hello Lerro")

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .idle })
        #expect(await harness.delivery.values() == ["hello Lerro"])
        #expect(await harness.history.entries().first?.finalText == "hello Lerro")
        #expect(harness.session.recoveryPresentation == nil)
        #expect(harness.session.dictionaryLearningToast == nil)
    }

    @Test("Paste delivers the given text and pasteLastResult delivers the last result")
    @MainActor
    func pasteDeliversText() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()

        harness.session.paste("from the panel")
        #expect(await waitUntil { await harness.delivery.values() == ["from the panel"] })

        harness.session.paste("")
        harness.session.pasteLastResult()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await harness.delivery.values() == ["from the panel"])

        harness.session.lastResult = "last result"
        harness.session.pasteLastResult()
        #expect(await waitUntil {
            await harness.delivery.values() == ["from the panel", "last result"]
        })
    }

    @Test("Delivery failure copies the final text and exposes only recovery actions")
    @MainActor
    func deliveryFailureCreatesRecovery() async {
        let harness = makeHarness(text: "keep this text", deliveryFails: true)
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.recoveryPresentation != nil })

        #expect(harness.session.phase == .failed)
        #expect(harness.session.recoveryPresentation?.text == "keep this text")
        #expect(await harness.recovery.values() == ["keep this text"])
        #expect(await harness.history.entries().first?.status == .failed)

        harness.session.recopyRecoveryText()
        #expect(await waitUntil { await harness.recovery.values().count == 2 })
        harness.session.dismissRecovery()
        #expect(harness.session.recoveryPresentation == nil)
        #expect(harness.session.phase == .idle)
    }

    @Test("Quick Dictate endpoint detection follows its setting")
    @MainActor
    func quickDictateSettingControlsEndpointDetection() async {
        var disabled = basePreferences()
        disabled.quickDictateEnabled = false
        let first = makeHarness(text: "disabled", preferences: disabled)
        await first.session.start()
        first.session.toggleQuickDictate()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await first.speech.starts().isEmpty)
        #expect(first.session.phase == .idle)

        var enabled = basePreferences()
        enabled.quickDictateEnabled = true
        let second = makeHarness(text: "enabled", preferences: enabled)
        await second.session.start()
        second.session.toggleQuickDictate()
        #expect(await waitUntil { await second.speech.starts().count == 1 })
        #expect(await second.speech.starts()[0].detectSpeechEndpoint == true)
        await second.speech.emit(.speechStarted)
        await second.speech.emit(.silenceElapsed)
        #expect(await waitUntil { second.session.phase == .idle })
        #expect(await second.delivery.values() == ["enabled"])
    }

    @Test("Apple-only dictation never starts correction observation")
    @MainActor
    func rawModeDoesNotObserveEdits() async {
        let harness = makeHarness(text: "raw text")
        await harness.session.start()
        await dictate(harness.session)
        #expect(await harness.observer.observeCount() == 0)
        #expect(await harness.intelligence.classificationCount() == 0)
    }

    @Test("AI dictation learns an app-scoped correction and can undo it")
    @MainActor
    func aiCorrectionLearning() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            baseURL: "https://api.example.com/v1",
            modelIdentifier: "test-model",
            apiKey: "test-key"
        )
        let decision = try! DictionaryLearningDecision(validating: [
            DictionaryLearningCandidate(phrase: "乐若", replacement: "Lerro", confidence: 0.98)
        ])
        let harness = makeHarness(
            text: "欢迎使用乐若",
            preferences: preferences,
            intelligenceText: "欢迎使用乐若",
            learningDecision: decision
        )
        await harness.session.start()
        await dictate(harness.session)
        #expect(await waitUntil { await harness.observer.observeCount() == 1 })

        await harness.observer.emit(DeliveredTextEdit(
            originalSpan: "乐若",
            correctedSpan: "Lerro",
            contextBefore: "欢迎使用",
            applicationName: "Editor",
            bundleIdentifier: "com.example.Editor"
        ))
        #expect(await waitUntil { harness.session.dictionaryLearningToast != nil })

        let learned = await harness.dictionary.entries()
        #expect(learned.count == 1)
        #expect(learned[0].phrase == "乐若")
        #expect(learned[0].replacement == "Lerro")
        #expect(learned[0].applicationBundleIdentifier == nil)

        harness.session.undoDictionaryLearning()
        #expect(await waitUntil { await harness.dictionary.entries().isEmpty })
        #expect(harness.session.dictionaryLearningToast == nil)
    }

    @Test("Onboarding accepts an already learned correction without creating a duplicate")
    @MainActor
    func onboardingCorrectionCanBeRepeated() async throws {
        var preferences = basePreferences()
        preferences.intelligenceMode = .local
        let decision = try DictionaryLearningDecision(validating: [
            DictionaryLearningCandidate(phrase: "乐若", replacement: "Lerro", confidence: 0.98)
        ])
        let harness = makeHarness(text: "", preferences: preferences, learningDecision: decision)
        await harness.session.start()
        for _ in 0..<2 {
            let result = await harness.session.learnOnboardingCorrection(
                originalText: "我正在使用乐若完成语音写作。",
                correctedText: "我正在使用Lerro完成语音写作。"
            )
            #expect(result == .learned)
        }
        #expect(await harness.dictionary.entries().count == 1)
    }

    @Test("Onboarding distinguishes no learning from a failed AI request")
    @MainActor
    func onboardingCorrectionReportsOutcome() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .local
        let harness = makeHarness(text: "", preferences: preferences)
        await harness.session.start()
        let rejected = await harness.session.learnOnboardingCorrection(
            originalText: "明天开会", correctedText: "昨天开会"
        )
        #expect(rejected == .noLearning)
        let failed = makeHarness(text: "", preferences: preferences, intelligenceFails: true)
        await failed.session.start()
        let failure = await failed.session.learnOnboardingCorrection(
            originalText: "乐若", correctedText: "Lerro"
        )
        guard case .failed(let message) = failure else {
            Issue.record("Expected a visible failure result")
            return
        }
        #expect(!message.isEmpty)
        #expect(await failed.dictionary.entries().isEmpty)
    }

    @Test("Cancelling onboarding discards a late AI correction before persistence")
    @MainActor
    func onboardingCorrectionCancellation() async throws {
        var preferences = basePreferences()
        preferences.intelligenceMode = .local
        let decision = try DictionaryLearningDecision(validating: [
            DictionaryLearningCandidate(phrase: "乐若", replacement: "Lerro", confidence: 0.98)
        ])
        let harness = makeHarness(
            text: "", preferences: preferences, learningDecision: decision,
            classificationDelay: .seconds(30)
        )
        await harness.session.start()
        let task = Task { await harness.session.learnOnboardingCorrection(
            originalText: "乐若", correctedText: "Lerro"
        ) }
        #expect(await waitUntil { await harness.intelligence.classificationCount() == 1 })
        task.cancel()
        _ = await task.value
        #expect(await harness.dictionary.entries().isEmpty)
    }

    @Test("Translation requires AI and uses the selected runtime")
    @MainActor
    func translationUsesAI() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            baseURL: "https://api.example.com/v1",
            modelIdentifier: "test-model",
            apiKey: "test-key"
        )
        let harness = makeHarness(
            text: "你好",
            preferences: preferences,
            intelligenceText: "Hello"
        )
        await harness.session.start()
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .idle })

        #expect(await harness.delivery.values() == ["Hello"])
        #expect(await harness.intelligence.requests().last?.task == .translate)
    }

    @Test("Raw dictation hides the HUD at the commit point")
    @MainActor
    func rawDictationShowsDeliveredFeedback() async {
        let harness = makeHarness(text: "hello Lerro")
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.hudDeliveryFeedback != nil })

        #expect(await harness.delivery.values() == ["hello Lerro"])
        #expect(harness.session.hudDeliveryFeedback == .delivered)
        #expect(harness.session.currentHUDVisualState == .idleHidden)
    }

    @Test("AI dictation falls back to the raw transcript when processing fails")
    @MainActor
    func aiFailureDeliversRawFallback() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            baseURL: "https://api.example.com/v1",
            modelIdentifier: "test-model",
            apiKey: "test-key"
        )
        let harness = makeHarness(
            text: "raw transcript",
            preferences: preferences,
            intelligenceText: "unused",
            intelligenceFails: true
        )
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.hudDeliveryFeedback != nil })

        #expect(await harness.delivery.values() == ["raw transcript"])
        #expect(await harness.intelligence.requests().count == 1)
        #expect(harness.session.hudDeliveryFeedback == .deliveredRawFallback)
        #expect(harness.session.currentHUDVisualState == .deliveredRawFallback)
    }

    @Test("Delivery failure shows recovery without delivery feedback")
    @MainActor
    func deliveryFailureHasNoDeliveryFeedback() async {
        let harness = makeHarness(text: "keep this text", deliveryFails: true)
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.recoveryPresentation != nil })

        #expect(harness.session.hudDeliveryFeedback == nil)
        #expect(harness.session.currentHUDVisualState == .recovery)
    }

    @Test("Translation direction label shows only for translation captures")
    @MainActor
    func translationDirectionLabel() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            baseURL: "https://api.example.com/v1",
            modelIdentifier: "test-model",
            apiKey: "test-key"
        )
        preferences.recognitionLocaleIdentifier = "zh_CN"
        preferences.translationLanguageIdentifiers = ["en"]
        let harness = makeHarness(
            text: "你好",
            preferences: preferences,
            intelligenceText: "Hello"
        )
        let dictationHarness = makeHarness(text: "你好", preferences: preferences)
        await dictationHarness.session.start()
        dictationHarness.session.toggleCapture(.dictation)
        #expect(await waitUntil { dictationHarness.session.phase == .listening })
        #expect(dictationHarness.session.activeTranslationDirectionLabel == nil)
        dictationHarness.session.cancelCapture()

        await harness.session.start()
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(harness.session.activeTranslationDirectionLabel == "中 → EN")
        harness.session.cancelCapture()
    }

    @Test("A successful hands-free capture increments the stop hint counter once")
    @MainActor
    func handsFreeCaptureCountsStopHint() async {
        let harness = makeHarness(text: "hands free")
        await harness.session.start()
        #expect(harness.session.preferences.handsFreeStopHintUseCount == 0)

        harness.session.enterHandsFreeCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(harness.session.isHandsFreeCapture)
        #expect(harness.session.showsHandsFreeStopHint)

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .idle })
        #expect(await harness.delivery.values() == ["hands free"])
        #expect(harness.session.preferences.handsFreeStopHintUseCount == 1)
    }

    @Test("Application catalog and the settings tab are first-class session surfaces")
    @MainActor
    func settingsSurfacesApplications() async {
        let applications = [ApplicationDescriptor(
            bundleIdentifier: "com.example.Editor",
            name: "Editor",
            isRunning: true
        )]
        let harness = makeHarness(text: "unused", applications: applications)
        await harness.session.start()
        harness.session.refreshAvailableApplications()
        #expect(await waitUntil { harness.session.availableApplications == applications })

        #expect(harness.session.settingsTab == .general)
        harness.session.settingsTab = .intelligence
        #expect(harness.session.settingsTab == .intelligence)
        #expect(!harness.session.isOnboardingPresented)
    }

    @Test("The audio input is prewarmed at launch and when the microphone changes")
    @MainActor
    func prewarmsAudioInput() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()
        #expect(await waitUntil { await harness.speech.prewarms().first == .some(nil) })

        harness.session.selectMicrophone(uid: "usb-mic")
        #expect(await waitUntil { await harness.speech.prewarms().last == .some("usb-mic") })
    }

    @Test("Tone preview requests are tagged for usage statistics")
    @MainActor
    func tonePreviewUsageFeature() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            baseURL: "https://api.example.com/v1",
            modelIdentifier: "test-model",
            apiKey: "test-key"
        )
        let harness = makeHarness(text: "unused", preferences: preferences)
        await harness.session.start()
        let output = await harness.session.previewAppTone(
            application: ApplicationDescriptor(bundleIdentifier: "com.example.Editor", name: "Editor"),
            instruction: "简洁"
        )
        #expect(output != nil)
        #expect(await harness.intelligence.requests().last?.usageFeature == .tonePreview)
    }

    @Test("Deleting AI usage empties the repository")
    @MainActor
    func deleteAllAIUsage() async throws {
        let record = AIUsageRecord(
            date: .now,
            feature: .dictate,
            provider: .deepSeek,
            modelIdentifier: "deepseek-v4-flash",
            tokens: AITokenUsage(inputTokens: 100, outputTokens: 10),
            latencyMilliseconds: 500,
            succeeded: true
        )
        let harness = makeHarness(text: "unused", aiUsageRecords: [record])
        let since = Date.now.addingTimeInterval(-3_600)
        #expect(await harness.session.aiUsageRecords(since: since).count == 1)
        await harness.session.deleteAllAIUsage()
        #expect(await harness.session.aiUsageRecords(since: since).isEmpty)
        #expect(try await harness.aiUsage.records(since: .distantPast).isEmpty)
    }

    @Test("Model price overrides replace case-insensitively and reset removes them")
    @MainActor
    func modelPriceOverrides() {
        let harness = makeHarness(text: "unused")
        let session = harness.session
        session.setModelPrice(AIModelPrice(
            modelIdentifier: "DeepSeek-V4-Flash",
            currency: .cny,
            inputPerMillion: 1,
            cachedInputPerMillion: 0.1,
            outputPerMillion: 4
        ))
        session.setModelPrice(AIModelPrice(
            modelIdentifier: "deepseek-v4-flash",
            currency: .usd,
            inputPerMillion: 2,
            cachedInputPerMillion: 0.2,
            outputPerMillion: 8
        ))
        session.setModelPrice(AIModelPrice(
            modelIdentifier: "other-model",
            currency: .usd,
            inputPerMillion: 3,
            cachedInputPerMillion: 0.3,
            outputPerMillion: 9
        ))
        #expect(session.preferences.modelPrices.count == 2)
        #expect(session.preferences.modelPrices.first?.currency == .usd)
        #expect(session.preferences.modelPrices.first?.inputPerMillion == 2)

        session.resetModelPrice(modelIdentifier: "DEEPSEEK-V4-FLASH")
        #expect(session.preferences.modelPrices.map(\.id) == ["other-model"])
    }

    @Test("Tone resolves to the enabled app profile, then the default instruction, then none")
    @MainActor
    func toneInstructionResolution() async {
        func tone(
            profiles: [AppToneProfile],
            defaultInstruction: String
        ) async -> String? {
            var preferences = basePreferences()
            preferences.intelligenceMode = .remote
            preferences.remoteProvider = RemoteProviderConfiguration(
                baseURL: "https://api.example.com/v1",
                modelIdentifier: "test-model",
                apiKey: "test-key"
            )
            preferences.appToneProfiles = profiles
            preferences.defaultToneInstruction = defaultInstruction
            let harness = makeHarness(text: "hello", preferences: preferences)
            await harness.session.start()
            await dictate(harness.session)
            _ = await waitUntil { await harness.intelligence.requests().count == 1 }
            return await harness.intelligence.requests().first?.toneInstruction
        }
        let profile = AppToneProfile(
            bundleIdentifier: "com.example.Editor",
            applicationName: "Editor",
            instruction: "专用语气"
        )
        var disabled = profile
        disabled.enabled = false

        #expect(await tone(profiles: [profile], defaultInstruction: "默认语气") == "专用语气")
        #expect(await tone(profiles: [disabled], defaultInstruction: "默认语气") == "默认语气")
        #expect(await tone(profiles: [], defaultInstruction: "默认语气") == "默认语气")
        #expect(await tone(profiles: [disabled], defaultInstruction: "  ") == nil)
    }

    @Test("History summaries ignore list filters and expose the six newest entries")
    @MainActor
    func historySummaries() async {
        let now = Date.now
        let entries = (0..<8).map { index in
            HistoryEntry(
                createdAt: now.addingTimeInterval(-Double(index) * 60),
                mode: .dictation,
                rawText: "entry \(index)",
                finalText: "entry \(index)",
                duration: 4,
                applicationName: "Editor"
            )
        }
        let harness = makeHarness(text: "unused", historyEntries: entries)
        await harness.session.start()

        #expect(harness.session.historyAllCount == 8)
        #expect(harness.session.recentHistoryEntries.map(\.finalText)
            == (0..<6).map { "entry \($0)" })
        #expect(harness.session.usageStatistics.today.totalWords > 0)
        #expect(harness.session.usageStatistics.dailyWords.count == 7)
        #expect(harness.session.recordingURL(for: entries[0]) == nil)
    }

    @Test("Microphone selection persists and the sidebar status follows the intelligence mode")
    @MainActor
    func microphoneAndIntelligenceStatus() async {
        var preferences = basePreferences()
        preferences.appLanguage = .simplifiedChinese
        let harness = makeHarness(text: "unused", preferences: preferences)
        await harness.session.start()

        harness.session.selectMicrophone(uid: "mic-1")
        #expect(harness.session.preferences.microphoneDeviceUID == "mic-1")
        harness.session.selectMicrophone(uid: nil)
        #expect(harness.session.preferences.microphoneDeviceUID == nil)

        #expect(harness.session.intelligenceStatus
            == IntelligenceStatus(title: "原始听写", detail: "不使用 AI", isReady: true))

        harness.session.preferences.intelligenceMode = .remote
        #expect(harness.session.intelligenceStatus
            == IntelligenceStatus(title: "DeepSeek", detail: "未配置 API", isReady: false))

        harness.session.preferences.remoteProvider = .preset(.deepSeek, apiKey: "test-key")
        #expect(harness.session.intelligenceStatus
            == IntelligenceStatus(title: "DeepSeek", detail: "AI 润色已开启", isReady: true))
    }

    @Test("Completed raw dictation records the startup and finish chains")
    @MainActor
    func completedDictationRecordsTrace() async throws {
        let harness = makeHarness(text: "trace me")
        await harness.session.start()

        await dictate(harness.session)
        #expect(await waitUntil { harness.trace.finishedTraces().count == 1 })

        let entry = try #require(await harness.history.entries().first)
        let timings = try #require(entry.phaseTimings)
        #expect(timings.outcome == .completed)
        #expect((timings.duration(of: .readyToSpeak) ?? -1) >= 0)
        let expected: [CaptureMilestone] = [
            .hotkeyPressed, .contextCaptured, .speechStartRequested, .speechLocaleResolved,
            .listening, .stopRequested, .transcriptionFinished, .processingFinished,
            .deliveryCommitted, .deliveryFinished
        ]
        for milestone in expected {
            #expect(timings.milestones[milestone] != nil, "missing \(milestone.rawValue)")
        }

        let finished = harness.trace.finishedTraces()
        #expect(harness.trace.begunIDs().count == 1)
        #expect(finished.count == 1)
        let trace = try #require(finished.first)
        #expect(trace.outcome == .completed)
        #expect(trace.processingRoute == .raw)
        #expect(trace.offset(of: .historySaved) != nil)
        #expect(trace.offset(of: .finished) != nil)
        let chain = CaptureMilestone.startupChain + CaptureMilestone.finishChain
        let offsets = chain.compactMap { trace.offset(of: $0) }
        #expect(offsets == offsets.sorted())
    }

    @Test("Cancelling during startup or listening finishes the trace as cancelled and saves nothing")
    @MainActor
    func cancelledCaptureFinishesTrace() async {
        let listening = makeHarness(text: "cancel me")
        await listening.session.start()
        listening.session.toggleCapture(.dictation)
        #expect(await waitUntil { listening.session.phase == .listening })
        listening.session.cancelCapture()
        #expect(await waitUntil { listening.session.phase == .idle })
        #expect(listening.trace.finishedTraces().map(\.outcome) == [.cancelled])
        #expect(await listening.history.entries().isEmpty)

        let starting = makeHarness(text: "cancel me", resourcesReady: false)
        await starting.session.start()
        starting.session.toggleCapture(.dictation)
        #expect(await waitUntil { starting.session.isWaitingForSpeechResources })
        starting.session.cancelCapture()
        #expect(await waitUntil { starting.session.phase == .idle })
        #expect(starting.trace.finishedTraces().map(\.outcome) == [.cancelled])
        #expect(await starting.history.entries().isEmpty)
    }

    @Test("AI dictation that falls back to the raw transcript records the fallback outcome")
    @MainActor
    func rawFallbackRecordsTraceOutcome() async throws {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            baseURL: "https://api.example.com/v1",
            modelIdentifier: "test-model",
            apiKey: "test-key"
        )
        let harness = makeHarness(
            text: "raw transcript",
            preferences: preferences,
            intelligenceText: "unused",
            intelligenceFails: true
        )
        await harness.session.start()

        await dictate(harness.session)
        #expect(await waitUntil { harness.trace.finishedTraces().count == 1 })

        #expect(harness.trace.finishedTraces().first?.outcome == .completedWithRawFallback)
        let entry = try #require(await harness.history.entries().first)
        #expect(entry.phaseTimings?.outcome == .completedWithRawFallback)
    }

    @Test("A failed delivery saves history with failed-delivery timings")
    @MainActor
    func deliveryFailureRecordsTrace() async throws {
        let harness = makeHarness(text: "keep this text", deliveryFails: true)
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.trace.finishedTraces().count == 1 })

        #expect(harness.trace.finishedTraces().first?.outcome == .deliveryFailed)
        let entry = try #require(await harness.history.entries().first)
        #expect(entry.status == .failed)
        #expect(entry.phaseTimings?.outcome == .deliveryFailed)
        #expect(entry.phaseTimings?.milestones[.deliveryFinished] != nil)
        #expect(entry.phaseTimings?.milestones[.deliveryCommitted] == nil)
    }

    @Test("A reporter from a cancelled capture cannot mark the next capture")
    @MainActor
    func staleReporterIsIgnored() async throws {
        let harness = makeHarness(text: "second capture")
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        let staleReporter = await harness.speech.reporter(at: 0)
        harness.session.cancelCapture()
        #expect(await waitUntil { harness.session.phase == .idle })

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        staleReporter(.analyzerPrepared, ContinuousClock.now)
        try? await Task.sleep(for: .milliseconds(50))
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.trace.finishedTraces().count == 2 })

        let entry = try #require(await harness.history.entries().first)
        let timings = try #require(entry.phaseTimings)
        #expect(timings.outcome == .completed)
        #expect(timings.milestones[.analyzerPrepared] == nil)
        let completed = try #require(harness.trace.finishedTraces().last)
        #expect(completed.outcome == .completed)
        #expect(!harness.trace.markedMilestones(for: completed.id).contains(.analyzerPrepared))
    }

    // MARK: Dictionary suggestions

    private func suggestionPreferences() -> UserPreferences {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            baseURL: "https://api.example.com/v1",
            modelIdentifier: "test-model",
            apiKey: "test-key"
        )
        return preferences
    }

    private func suggestionDecision() throws -> DictionaryLearningDecision {
        try DictionaryLearningDecision(validating: [
            DictionaryLearningCandidate(phrase: "史册", replacement: "实测", confidence: 0.95)
        ])
    }

    private func suggestionHistoryEntry(
        raw: String,
        final: String,
        enhanced: Bool = true
    ) -> HistoryEntry {
        HistoryEntry(
            mode: .dictation,
            rawText: raw,
            finalText: final,
            duration: 3,
            applicationName: "Editor",
            bundleIdentifier: "com.example.Editor",
            wasEnhanced: enhanced
        )
    }

    /// Two entries with the same correction, one identical entry and one raw entry.
    private func suggestionHistory() -> [HistoryEntry] {
        [
            suggestionHistoryEntry(raw: "我昨天做了史册，结果不错", final: "我昨天做了实测，结果不错"),
            suggestionHistoryEntry(raw: "今天再做一次史册", final: "今天再做一次实测"),
            suggestionHistoryEntry(raw: "没有任何修改", final: "没有任何修改"),
            suggestionHistoryEntry(raw: "未润色的史册", final: "未润色的实测", enhanced: false)
        ]
    }

    @MainActor
    private func scanForSuggestions(_ harness: Harness) async {
        harness.session.scanHistoryForDictionarySuggestions()
        _ = await waitUntil { harness.session.dictionarySuggestionScan == nil }
    }

    @Test("Scanning history turns AI corrections into suggestions and marks entries scanned")
    @MainActor
    func scanProducesSuggestions() async throws {
        let history = suggestionHistory()
        let harness = makeHarness(
            text: "unused",
            preferences: suggestionPreferences(),
            learningDecision: try suggestionDecision(),
            historyEntries: history
        )
        await harness.session.start()
        #expect(harness.session.canScanDictionarySuggestions)

        await scanForSuggestions(harness)

        let suggestion = try #require(harness.session.dictionarySuggestions.first)
        #expect(harness.session.dictionarySuggestions.count == 1)
        #expect(suggestion.phrase == "史册")
        #expect(suggestion.replacement == "实测")
        #expect(suggestion.occurrences == 2)
        #expect(suggestion.applicationName == "Editor")
        #expect(await harness.intelligence.classificationCount() == 2)

        let state = try await harness.suggestions.load()
        #expect(state.scannedEntryIDs == Set(history.prefix(3).map(\.id)))

        await scanForSuggestions(harness)
        #expect(await harness.intelligence.classificationCount() == 2)
        #expect(harness.session.dictionarySuggestions.first?.occurrences == 2)
    }

    @Test("Scanning is unavailable while AI is off")
    @MainActor
    func scanRequiresAI() async {
        let harness = makeHarness(text: "unused", historyEntries: suggestionHistory())
        await harness.session.start()
        #expect(!harness.session.canScanDictionarySuggestions)
        harness.session.scanHistoryForDictionarySuggestions()
        #expect(harness.session.dictionarySuggestionScan == nil)
        #expect(await harness.intelligence.classificationCount() == 0)
    }

    @Test("Accepting a suggestion saves a learned dictionary entry and removes it")
    @MainActor
    func acceptSuggestion() async throws {
        let harness = makeHarness(
            text: "unused",
            preferences: suggestionPreferences(),
            learningDecision: try suggestionDecision(),
            historyEntries: suggestionHistory()
        )
        await harness.session.start()
        await scanForSuggestions(harness)
        let suggestion = try #require(harness.session.dictionarySuggestions.first)

        harness.session.acceptDictionarySuggestion(suggestion)
        #expect(await waitUntil { harness.session.dictionaryEntries.count == 1 })

        let entry = try #require(await harness.dictionary.entries().first)
        #expect(entry.phrase == "史册")
        #expect(entry.replacement == "实测")
        #expect(entry.source == .learned)
        #expect(entry.applicationBundleIdentifier == nil)
        #expect(harness.session.dictionarySuggestions.isEmpty)
        #expect(await waitUntil { (try? await harness.suggestions.load().suggestions.isEmpty) == true })
    }

    @Test("Ignoring a suggestion persists its key and hides it from later scans")
    @MainActor
    func ignoreSuggestion() async throws {
        let harness = makeHarness(
            text: "unused",
            preferences: suggestionPreferences(),
            learningDecision: try suggestionDecision(),
            historyEntries: suggestionHistory()
        )
        await harness.session.start()
        await scanForSuggestions(harness)
        let suggestion = try #require(harness.session.dictionarySuggestions.first)

        harness.session.ignoreDictionarySuggestion(suggestion)
        #expect(harness.session.dictionarySuggestions.isEmpty)
        #expect(await waitUntil {
            (try? await harness.suggestions.load().ignoredKeys.contains(suggestion.id)) == true
        })

        try await harness.history.save(suggestionHistoryEntry(raw: "再测一次史册", final: "再测一次实测"))
        await scanForSuggestions(harness)
        #expect(await harness.intelligence.classificationCount() == 3)
        #expect(harness.session.dictionarySuggestions.isEmpty)
        #expect(try await harness.suggestions.load().suggestions.isEmpty)
    }

    @Test("Suggestions whose replacement is already in the dictionary are hidden")
    @MainActor
    func existingReplacementHidesSuggestion() async throws {
        let dictionary = InMemoryDictionaryRepository(entries: [DictionaryEntry(phrase: "实测")])
        let harness = makeHarness(
            text: "unused",
            preferences: suggestionPreferences(),
            dictionary: dictionary,
            learningDecision: try suggestionDecision(),
            historyEntries: suggestionHistory()
        )
        await harness.session.start()
        await scanForSuggestions(harness)

        #expect(await harness.intelligence.classificationCount() == 2)
        #expect(harness.session.dictionarySuggestions.isEmpty)
        #expect(try await harness.suggestions.load().suggestions.count == 1)
    }

    @MainActor
    private func dictate(_ session: AppSession) async {
        session.toggleCapture(.dictation)
        _ = await waitUntil { session.phase == .listening }
        session.toggleCapture(.dictation)
        _ = await waitUntil { session.phase == .idle }
    }

    @MainActor
    private func makeHarness(
        text: String,
        preferences: UserPreferences? = nil,
        deliveryFails: Bool = false,
        dictionary: InMemoryDictionaryRepository? = nil,
        intelligenceText: String? = nil,
        learningDecision: DictionaryLearningDecision = .noLearning,
        applications: [ApplicationDescriptor] = [],
        intelligenceFails: Bool = false,
        historyEntries: [HistoryEntry] = [],
        classificationDelay: Duration? = nil,
        resourcesReady: Bool = true,
        aiUsageRecords: [AIUsageRecord] = []
    ) -> Harness {
        _ = NSApplication.shared
        let speech = StubSpeech(text: text, resourcesReady: resourcesReady)
        let delivery = StubDelivery(fails: deliveryFails)
        let recovery = StubRecovery()
        let observer = StubObserver()
        let intelligence = StubIntelligence(
            resultText: intelligenceText ?? text,
            learningDecision: learningDecision,
            fails: intelligenceFails,
            classificationDelay: classificationDelay
        )
        let trace = RecordingTraceObserver()
        let history = InMemoryHistoryRepository(entries: historyEntries)
        let dictionary = dictionary ?? InMemoryDictionaryRepository()
        let suggestions = InMemoryDictionarySuggestionRepository()
        let aiUsage = InMemoryAIUsageRepository(records: aiUsageRecords)
        let preferences = preferences ?? basePreferences()
        let dependencies = AppDependencies(
            applicationPaths: nil,
            dataMigrationResult: nil,
            startupStorageError: nil,
            speech: speech,
            microphoneTest: StubMicrophoneTester(),
            context: StubContextCapture(),
            textDelivery: delivery,
            recoveryText: recovery,
            deliveredTextObserver: observer,
            applicationCatalog: StubApplicationCatalog(values: applications),
            hotkeys: StubHotkeyMonitor(),
            permissions: StubPermissions(),
            loginItem: StubLoginItem(),
            identityMonitor: StubIdentityMonitor(),
            history: history,
            dictionary: dictionary,
            dictionarySuggestions: suggestions,
            preferences: InMemoryPreferencesRepository(value: preferences),
            aiUsage: aiUsage,
            intelligence: intelligence,
            deviceCapabilities: StubDeviceCapabilities(),
            captureTrace: trace
        )
        return Harness(
            session: AppSession(dependencies: dependencies, presentsFloatingPanels: false),
            speech: speech,
            delivery: delivery,
            recovery: recovery,
            observer: observer,
            intelligence: intelligence,
            history: history,
            dictionary: dictionary,
            suggestions: suggestions,
            aiUsage: aiUsage,
            trace: trace
        )
    }

    private func basePreferences() -> UserPreferences {
        UserPreferences(
            muteOtherAudio: false,
            historyRetention: .forever,
            enhancementEnabled: false,
            hotkeys: [],
            hasCompletedOnboarding: true
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }
}

private struct Harness {
    let session: AppSession
    let speech: StubSpeech
    let delivery: StubDelivery
    let recovery: StubRecovery
    let observer: StubObserver
    let intelligence: StubIntelligence
    let history: InMemoryHistoryRepository
    let dictionary: InMemoryDictionaryRepository
    let suggestions: InMemoryDictionarySuggestionRepository
    let aiUsage: InMemoryAIUsageRepository
    let trace: RecordingTraceObserver
}

private final class RecordingTraceObserver: CaptureTraceObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var begun: [UUID] = []
    private var marks: [(id: UUID, milestone: CaptureMilestone)] = []
    private var finished: [CaptureTrace] = []

    func captureTraceDidBegin(_ trace: CaptureTrace) {
        lock.withLock { begun.append(trace.id) }
    }

    func captureTrace(_ id: UUID, didMark milestone: CaptureMilestone, offset: TimeInterval) {
        lock.withLock { marks.append((id, milestone)) }
    }

    func captureTraceDidFinish(_ trace: CaptureTrace) {
        lock.withLock { finished.append(trace) }
    }

    func dictionaryLearningDidClassify(duration: TimeInterval, candidateCount: Int, savedCount: Int) {}

    func begunIDs() -> [UUID] { lock.withLock { begun } }
    func finishedTraces() -> [CaptureTrace] { lock.withLock { finished } }
    func markedMilestones(for id: UUID) -> [CaptureMilestone] {
        lock.withLock { marks.filter { $0.id == id }.map(\.milestone) }
    }
}

private struct SpeechStart: Sendable {
    let detectSpeechEndpoint: Bool
}

private actor StubSpeech: SpeechTranscribing {
    private let text: String
    private var records: [SpeechStart] = []
    private var reporters: [CaptureMilestoneReporter] = []
    private var continuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation?
    private let resourcesReady: Bool
    private var readyLocales = Set<String>()
    private var preparedLocales: [String] = []
    private var preparationWaiters: [String: CheckedContinuation<Void, Never>] = [:]

    init(text: String, resourcesReady: Bool) {
        self.text = text
        self.resourcesReady = resourcesReady
    }

    func resourceStatus(localeIdentifier: String) async -> LanguageResourceStatus {
        LanguageResourceStatus(
            state: resourcesReady || readyLocales.contains(localeIdentifier) ? .ready : .available,
            sourceLanguageIdentifier: localeIdentifier,
            message: ""
        )
    }

    func prepareResources(localeIdentifier: String) async throws -> LanguageResourceStatus {
        preparedLocales.append(localeIdentifier)
        await withCheckedContinuation { preparationWaiters[localeIdentifier] = $0 }
        return await resourceStatus(localeIdentifier: localeIdentifier)
    }

    func finishPreparation(_ locale: String, installed: Bool = true) {
        if installed { readyLocales.insert(locale) }
        preparationWaiters.removeValue(forKey: locale)?.resume()
    }

    func preparations() -> [String] { preparedLocales }

    private var prewarmedDevices: [String?] = []

    func prewarmAudioInput(microphoneDeviceUID: String?) async {
        prewarmedDevices.append(microphoneDeviceUID)
    }

    func prewarms() -> [String?] { prewarmedDevices }

    func availableInputDevices() async -> [AudioInputDevice] { [] }

    func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        muteOtherAudio: Bool,
        saveAudio: Bool,
        detectSpeechEndpoint: Bool,
        milestones: @escaping CaptureMilestoneReporter
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error> {
        records.append(SpeechStart(detectSpeechEndpoint: detectSpeechEndpoint))
        reporters.append(milestones)
        milestones(.speechLocaleResolved, ContinuousClock.now)
        milestones(.audioEngineStarted, ContinuousClock.now)
        let pair = AsyncThrowingStream<SpeechEvent, any Error>.makeStream()
        continuation = pair.continuation
        continuation?.yield(.partial(text))
        return pair.stream
    }

    func stop() async throws -> SpeechTranscription {
        continuation?.finish()
        continuation = nil
        return SpeechTranscription(rawText: text, localeIdentifier: "en_US", duration: 1)
    }

    func cancel() async {
        continuation?.finish()
        continuation = nil
    }

    func starts() -> [SpeechStart] { records }
    func reporter(at index: Int) -> CaptureMilestoneReporter { reporters[index] }
    func emit(_ event: SpeechEvent) { continuation?.yield(event) }
}

private actor StubDelivery: TextDelivering {
    private let fails: Bool
    private var delivered: [String] = []

    init(fails: Bool) { self.fails = fails }

    func deliver(
        _ text: String,
        to context: CapturedContext,
        replacingSelection: Bool,
        targetPolicy: TextDeliveryTargetPolicy,
        onCommit: @escaping TextDeliveryCommitHandler
    ) async throws -> TextDeliveryReceipt {
        delivered.append(text)
        if fails { throw TestFailure.delivery }
        await onCommit()
        return TextDeliveryReceipt(context: context)
    }

    func values() -> [String] { delivered }
}

private actor StubRecovery: RecoveryTextCopying {
    private var copied: [String] = []
    func copyForRecovery(_ text: String) async throws { copied.append(text) }
    func values() -> [String] { copied }
}

private actor StubObserver: DeliveredTextObserving {
    private var continuation: AsyncThrowingStream<DeliveredTextEdit, any Error>.Continuation?
    private var observations = 0

    func observe(
        text: String,
        receipt: TextDeliveryReceipt,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<DeliveredTextEdit, any Error> {
        observations += 1
        let pair = AsyncThrowingStream<DeliveredTextEdit, any Error>.makeStream()
        continuation = pair.continuation
        return pair.stream
    }

    func stopObserving() async {
        continuation?.finish()
        continuation = nil
    }

    func observeCount() -> Int { observations }
    func emit(_ edit: DeliveredTextEdit) { continuation?.yield(edit) }
}

private actor StubIntelligence: IntelligenceProcessing {
    private let resultText: String
    private let learningDecision: DictionaryLearningDecision
    private let fails: Bool
    private let classificationDelay: Duration?
    private var recordedRequests: [IntelligenceRequest] = []
    private var classifications = 0

    init(
        resultText: String, learningDecision: DictionaryLearningDecision,
        fails: Bool = false, classificationDelay: Duration? = nil
    ) {
        self.resultText = resultText
        self.learningDecision = learningDecision
        self.fails = fails
        self.classificationDelay = classificationDelay
    }

    func prepare(modelIdentifier: String) async throws {}
    func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult {
        recordedRequests.append(request)
        if fails { throw TestFailure.intelligence }
        return IntelligenceResult(
            text: resultText,
            disposition: .insert,
            modelIdentifier: "test-model",
            source: request.mode == .remote ? .remote : .local
        )
    }
    func classifyCorrection(
        _ request: DictionaryLearningRequest
    ) async throws -> DictionaryLearningDecision {
        classifications += 1
        if fails { throw TestFailure.intelligence }
        // Return a late result even when cancellation interrupts the delay.
        if let classificationDelay { try? await Task.sleep(for: classificationDelay) }
        return learningDecision
    }
    func modelStatus() async -> LocalModelStatus {
        LocalModelStatus(
            state: .ready,
            modelIdentifier: "test-model",
            progress: 1,
            message: "Ready"
        )
    }
    func requests() -> [IntelligenceRequest] { recordedRequests }
    func classificationCount() -> Int { classifications }
}

private struct StubContextCapture: ContextCapturing {
    func captureCurrentContext() async -> CapturedContext {
        CapturedContext(
            applicationName: "Editor",
            processIdentifier: 42,
            bundleIdentifier: "com.example.Editor",
            selectionState: .knownEmpty,
            focusedElementAvailable: true,
            focusedElementFingerprint: 11,
            focusedValueFingerprint: 12,
            selectedRange: UTF16TextRange(location: 0, length: 0)
        )
    }
}

private struct StubApplicationCatalog: ApplicationCataloging {
    let values: [ApplicationDescriptor]
    func applications() async -> [ApplicationDescriptor] { values }
}

private struct StubMicrophoneTester: MicrophoneLevelTesting {
    func availableInputDevices() async -> [AudioInputDevice] { [] }
    func start(microphoneDeviceUID: String?) async throws -> MicrophoneLevelTestSession {
        MicrophoneLevelTestSession(
            id: UUID(),
            levels: AsyncThrowingStream { $0.finish() }
        )
    }
    func stop(sessionID: UUID) async {}
}

private final class StubHotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    func start(handler: @escaping @Sendable (HotkeyTrigger) -> Void) throws {}
    func update(definitions: [HotkeyDefinition]) {}
    func resetTransientState() {}
    func stop() {}
}

private struct StubPermissions: PermissionChecking {
    func microphoneAuthorized() async -> Bool { true }
    func requestMicrophone() async -> Bool { true }
    func accessibilityAuthorized(prompt: Bool) -> Bool { true }
}

private struct StubLoginItem: LoginItemManaging {
    func isEnabled() -> Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

private struct StubIdentityMonitor: ApplicationIdentityMonitoring {
    func legacyApplicationIsRunning() -> Bool { false }
}

private struct StubDeviceCapabilities: DeviceCapabilityAssessing {
    func snapshot() -> DeviceCapabilitySnapshot {
        DeviceCapabilitySnapshot(
            chipName: "Test Apple silicon",
            isAppleSilicon: true,
            supportsMetal: true,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
            availableStorageBytes: 40 * 1_024 * 1_024 * 1_024
        )
    }
}

private enum TestFailure: Error {
    case delivery
    case intelligence
}
