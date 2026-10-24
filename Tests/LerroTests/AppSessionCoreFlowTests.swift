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
        #expect(await harness.speech.startCount() == 0)
        #expect(await waitUntil { !harness.session.isCleaningCapture })

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(await harness.speech.startCount() == 1)
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

    @Test("Capture sounds play on start and finish, with audio output restored before the stop sound")
    @MainActor
    func captureSoundsFollowStartAndFinish() async {
        let harness = makeHarness(text: "hello")
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(harness.events.all().contains("sound.start"))
        let beforeFinish = harness.events.all()
        #expect(!beforeFinish.contains("sound.stop"))

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .idle })
        #expect(await waitUntil { harness.events.all().contains("sound.stop") })
        let events = harness.events.all()
        let restored = events.firstIndex(of: "speech.endAudioCapture")
        let stopSound = events.firstIndex(of: "sound.stop")
        #expect(restored != nil && stopSound != nil && restored! < stopSound!)
        #expect(events.contains("speech.stop"))
    }

    @Test("Other audio is lowered only after the start sound has finished")
    @MainActor
    func lowersOtherAudioAfterStartSound() async {
        var preferences = basePreferences()
        preferences.muteOtherAudio = true
        let harness = makeHarness(text: "hello", preferences: preferences, holdStartSound: true)
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(await waitUntil { harness.events.all().contains("sound.start") })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!harness.events.all().contains("speech.lowerOtherAudio"))

        await harness.sounds.releaseStart()
        #expect(await waitUntil { harness.events.all().contains("speech.lowerOtherAudio") })
        let events = harness.events.all()
        let started = events.firstIndex(of: "speech.start")
        let finished = events.firstIndex(of: "sound.start.finished")
        let lowered = events.firstIndex(of: "speech.lowerOtherAudio")
        #expect(started != nil && finished != nil && lowered != nil)
        #expect(started! < lowered! && finished! < lowered!)
        harness.session.cancelCapture()
    }

    @Test("A capture cancelled before the start sound finishes never lowers other audio")
    @MainActor
    func cancelledCaptureDoesNotLowerOtherAudio() async {
        var preferences = basePreferences()
        preferences.muteOtherAudio = true
        let harness = makeHarness(text: "hello", preferences: preferences, holdStartSound: true)
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.cancelCapture()
        #expect(await waitUntil { !harness.session.isCleaningCapture })

        await harness.sounds.releaseStart()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!harness.events.all().contains("speech.lowerOtherAudio"))
    }

    @Test("With capture sounds off, other audio is lowered as soon as the microphone is open")
    @MainActor
    func lowersOtherAudioImmediatelyWithoutSounds() async {
        var preferences = basePreferences()
        preferences.muteOtherAudio = true
        preferences.playsCaptureSounds = false
        let harness = makeHarness(text: "hello", preferences: preferences)
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.events.all().contains("speech.lowerOtherAudio") })
        #expect(!harness.events.all().contains("sound.start"))
        harness.session.cancelCapture()
    }

    @Test("Other audio stays untouched when the preference is off")
    @MainActor
    func doesNotLowerOtherAudioWhenDisabled() async {
        let harness = makeHarness(text: "hello")
        await harness.session.start()

        await dictate(harness.session)
        #expect(!harness.events.all().contains("speech.lowerOtherAudio"))
    }

    @Test("Cancelling a capture plays no stop sound")
    @MainActor
    func cancelledCapturePlaysNoStopSound() async {
        let harness = makeHarness(text: "hello")
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.cancelCapture()
        #expect(await waitUntil { !harness.session.isCleaningCapture })
        let events = harness.events.all()
        #expect(events.contains("sound.start"))
        #expect(!events.contains("sound.stop"))
        #expect(!events.contains("speech.endAudioCapture"))
    }

    @Test("Capture sounds stay silent when the preference is off")
    @MainActor
    func captureSoundsFollowPreference() async {
        var preferences = basePreferences()
        preferences.playsCaptureSounds = false
        let harness = makeHarness(text: "hello", preferences: preferences)
        await harness.session.start()

        await dictate(harness.session)
        let events = harness.events.all()
        #expect(events.contains("speech.endAudioCapture"))
        #expect(!events.contains("sound.start"))
        #expect(!events.contains("sound.stop"))
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
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
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

    @Test("Translation requires AI and uses the selected runtime")
    @MainActor
    func translationUsesAI() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
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

    @Test("A remote dictation saves the AI call on its history entry and links the request to it")
    @MainActor
    func remoteDictationStoresAICall() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
        let harness = makeHarness(
            text: "嗯你好",
            preferences: preferences,
            intelligenceText: "你好"
        )
        await harness.session.start()
        await dictate(harness.session)

        let entry = await harness.history.entries().first
        #expect(entry?.finalText == "你好")
        #expect(entry?.aiCall?.prompt == .dictate)
        #expect(entry?.aiCall?.response == "你好")
        #expect(entry?.aiCall?.modelIdentifier == "test-model")
        #expect(await harness.intelligence.requests().last?.historyEntryID == entry?.id)
    }

    private static let termFixResponse = """
    {"fixes":[["CAPax","CapEx"]],"terms":["CapEx"],"text":"本季度 CapEx 预算不变"}
    """

    private func termLearningPreferences() -> UserPreferences {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
        return preferences
    }

    @Test("A term the AI corrects in two separate dictations is learned and shown in a toast")
    @MainActor
    func termCorrectedTwiceIsLearned() async throws {
        let harness = makeHarness(
            text: "本季度 CAPax 预算不变",
            preferences: termLearningPreferences(),
            intelligenceText: "本季度 CapEx 预算不变",
            intelligenceResponse: Self.termFixResponse
        )
        await harness.session.start()

        await dictate(harness.session)
        #expect(await harness.dictionary.entries().isEmpty)
        #expect(harness.session.termLearningStatus(for: "CapEx") == .pending(remaining: 1))
        #expect(harness.session.dictionaryLearningToast == nil)

        await dictate(harness.session)
        #expect(await waitUntil { harness.session.dictionaryLearningToast != nil })
        let entries = await harness.dictionary.entries()
        let learned = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(learned.source == .learned)
        #expect(learned.phrase == "CapEx")
        #expect(learned.replacement == "CapEx")
        #expect(learned.heardAs == ["CAPax"])
        #expect(learned.learnedFromEntryIDs.count == 2)
        #expect(harness.session.dictionaryEntries.map(\.id) == [learned.id])
        #expect(harness.session.termLearningStatus(for: "CapEx") == .inDictionary)
        #expect(harness.session.dictionaryLearningToast?.phrase == "CAPax")
        #expect(harness.session.dictionaryLearningToast?.replacement == "CapEx")
    }

    @Test("Deleting a learned term dismisses it so later dictations do not learn it again")
    @MainActor
    func deletingLearnedTermDismissesIt() async throws {
        let harness = makeHarness(
            text: "本季度 CAPax 预算不变",
            preferences: termLearningPreferences(),
            intelligenceText: "本季度 CapEx 预算不变",
            intelligenceResponse: Self.termFixResponse
        )
        await harness.session.start()
        await dictate(harness.session)
        await dictate(harness.session)
        let learned = try #require(await harness.dictionary.entries().first)

        harness.session.deleteDictionaryEntry(learned)
        #expect(await waitUntil { await harness.dictionary.entries().isEmpty })
        #expect(await waitUntil {
            await harness.termLearning.load().dismissed.contains(TermLearner.normalized("CapEx"))
        })

        await dictate(harness.session)
        await dictate(harness.session)
        #expect(await harness.dictionary.entries().isEmpty)
        #expect(harness.session.termLearningStatus(for: "CapEx") == .notLearning)
    }

    @Test("Undoing the learning toast dismisses the learned term")
    @MainActor
    func undoingToastDismissesTerm() async {
        let harness = makeHarness(
            text: "本季度 CAPax 预算不变",
            preferences: termLearningPreferences(),
            intelligenceText: "本季度 CapEx 预算不变",
            intelligenceResponse: Self.termFixResponse
        )
        await harness.session.start()
        await dictate(harness.session)
        await dictate(harness.session)
        #expect(await waitUntil { harness.session.dictionaryLearningToast != nil })

        harness.session.undoDictionaryLearning()
        #expect(await waitUntil { await harness.dictionary.entries().isEmpty })
        #expect(await waitUntil {
            await harness.termLearning.load().dismissed.contains(TermLearner.normalized("CapEx"))
        })
    }

    @Test("Term learning stays off when history is never saved or the learning setting is off")
    @MainActor
    func termLearningHonorsGates() async {
        var noHistory = termLearningPreferences()
        noHistory.historyRetention = .never
        var learningOff = termLearningPreferences()
        learningOff.automaticDictionaryLearningEnabled = false
        for preferences in [noHistory, learningOff] {
            let harness = makeHarness(
                text: "本季度 CAPax 预算不变",
                preferences: preferences,
                intelligenceText: "本季度 CapEx 预算不变",
                intelligenceResponse: Self.termFixResponse
            )
            await harness.session.start()
            await dictate(harness.session)
            await dictate(harness.session)
            #expect(await harness.dictionary.entries().isEmpty)
            #expect(await harness.termLearning.load() == .empty)
        }
    }

    @Test("Deleting all history clears term learning")
    @MainActor
    func deleteAllHistoryClearsTermLearning() async {
        let harness = makeHarness(
            text: "本季度 CAPax 预算不变",
            preferences: termLearningPreferences(),
            intelligenceText: "本季度 CapEx 预算不变",
            intelligenceResponse: Self.termFixResponse
        )
        await harness.session.start()
        await dictate(harness.session)
        #expect(await harness.termLearning.load().candidates.count == 1)

        harness.session.deleteAllHistory()
        #expect(await waitUntil { await harness.termLearning.load() == .empty })
        #expect(await waitUntil { harness.session.termLearningState == .empty })
    }

    @Test("A delivered dictation increments the use count of dictionary entries it contains")
    @MainActor
    func dictionaryUsageCounting() async throws {
        let entry = DictionaryEntry(phrase: "CapEx")
        let unused = DictionaryEntry(phrase: "Kubernetes")
        let harness = makeHarness(
            text: "本季度 CAPax 预算不变",
            preferences: termLearningPreferences(),
            dictionary: InMemoryDictionaryRepository(entries: [entry, unused]),
            intelligenceText: "本季度 CapEx 预算不变"
        )
        await harness.session.start()
        await dictate(harness.session)

        #expect(await waitUntil {
            await harness.dictionary.entries().first { $0.id == entry.id }?.useCount == 1
        })
        let entries = await harness.dictionary.entries()
        let used = try #require(entries.first { $0.id == entry.id })
        #expect(used.lastUsedAt != nil)
        #expect(entries.first { $0.id == unused.id }?.useCount == 0)
    }

    @Test("Showing a history entry selects the page and sets the focus and highlight IDs")
    @MainActor
    func showHistoryEntryFocusesEntry() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()
        harness.session.historySearch = "查询"
        harness.session.historyModeFilter = .translation
        let id = UUID()

        harness.session.showHistoryEntry(id)

        #expect(harness.session.destination == .history)
        #expect(harness.session.historySearch.isEmpty)
        #expect(harness.session.historyModeFilter == nil)
        #expect(harness.session.historyFocusID == id)
        #expect(harness.session.aiCallHighlightID == id)
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
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
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
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
        preferences.recognitionLocaleIdentifier = "zh_CN"
        preferences.translationLanguageIdentifier = "en"
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
        harness.session.settingsTab = .ai
        #expect(harness.session.settingsTab == .ai)
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
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
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

    @Test("Tone resolves to the enabled app profile, then the default instruction, then none")
    @MainActor
    func toneInstructionResolution() async {
        func tone(
            profiles: [AppToneProfile],
            defaultInstruction: String
        ) async -> String? {
            var preferences = basePreferences()
            preferences.intelligenceMode = .remote
            preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
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
        #expect(harness.session.homeStatistics.today.totalWords > 0)
        #expect(harness.session.homeStatistics.weeks.count == 53)
        #expect(harness.session.recordingURL(for: entries[0]) == nil)
    }

    @Test("Microphone selection persists")
    @MainActor
    func microphoneSelectionPersists() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()

        harness.session.selectMicrophone(uid: "mic-1")
        #expect(harness.session.preferences.microphoneDeviceUID == "mic-1")
        harness.session.selectMicrophone(uid: nil)
        #expect(harness.session.preferences.microphoneDeviceUID == nil)
    }

    @Test("AI status is off without a Key or in raw mode, ready with a Key and balance")
    @MainActor
    func aiStatusFollowsKeyAndMode() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()
        #expect(harness.session.aiStatus == .off)
        #expect(!harness.session.hasDeepSeekKey)

        harness.session.setAIEnabled(true)
        #expect(harness.session.aiStatus == .off)

        let keyed = makeHarness(text: "unused", preferences: remotePreferences())
        await keyed.session.start()
        #expect(keyed.session.hasDeepSeekKey)
        #expect(keyed.session.aiStatus == .ready)
        #expect(await waitUntil { keyed.session.deepSeekBalance == .loaded(Self.balance("8.42")) })

        keyed.session.setAIEnabled(false)
        #expect(keyed.session.aiStatus == .off)
        keyed.session.setAIEnabled(true)
        #expect(keyed.session.aiStatus == .ready)
    }

    @Test("A loaded empty balance marks AI as out of balance and a refill clears it")
    @MainActor
    func emptyBalanceMarksOutOfBalance() async {
        let harness = makeHarness(
            text: "unused",
            preferences: remotePreferences(),
            balance: Self.balance("0", isAvailable: false)
        )
        await harness.session.start()
        #expect(await waitUntil { harness.session.aiStatus == .outOfBalance })

        await harness.intelligence.setBalance(Self.balance("20"))
        await harness.session.refreshDeepSeekBalance(force: true)
        #expect(harness.session.deepSeekBalance == .loaded(Self.balance("20")))
        #expect(harness.session.aiStatus == .ready)
    }

    @Test("Balance reads within 60 seconds are reused unless forced, and a failure shows as failed")
    @MainActor
    func balanceRefreshThrottle() async {
        let harness = makeHarness(text: "unused", preferences: remotePreferences())
        await harness.session.start()
        #expect(await waitUntil { harness.session.deepSeekBalance == .loaded(Self.balance("8.42")) })
        #expect(await harness.intelligence.balanceRequestCount() == 1)

        await harness.session.refreshDeepSeekBalance()
        #expect(await harness.intelligence.balanceRequestCount() == 1)
        await harness.session.refreshDeepSeekBalance(force: true)
        #expect(await harness.intelligence.balanceRequestCount() == 2)

        await harness.intelligence.setBalance(nil)
        await harness.session.refreshDeepSeekBalance(force: true)
        #expect(harness.session.deepSeekBalance == .failed)
        #expect(harness.session.aiStatus == .ready)
    }

    @Test("Without a Key the balance is never requested")
    @MainActor
    func noKeyNoBalanceRequest() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()
        await harness.session.refreshDeepSeekBalance(force: true)
        #expect(harness.session.deepSeekBalance == .unknown)
        #expect(await harness.intelligence.balanceRequestCount() == 0)
    }

    @Test("Connecting a working Key saves it and turns AI on")
    @MainActor
    func connectDeepSeekSavesKey() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()

        let outcome = await harness.session.connectDeepSeek(apiKey: "  sk-0123456789abcdef  ")
        #expect(outcome == .connected)
        #expect(harness.session.preferences.remoteProvider.apiKey == "sk-0123456789abcdef")
        #expect(harness.session.preferences.intelligenceMode == .remote)
        #expect(harness.session.deepSeekBalance == .loaded(Self.balance("8.42")))
        #expect(harness.session.aiStatus == .ready)
        #expect((try? await harness.preferences.load())?.remoteProvider.apiKey == "sk-0123456789abcdef")
    }

    @Test("Connecting rejects a Key that is not shaped like a DeepSeek Key without any request")
    @MainActor
    func connectDeepSeekRejectsBadFormat() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()

        for key in ["", "abc", "sk-", "pk-0123456789abcdef", "sk-0123 456789"] {
            #expect(await harness.session.connectDeepSeek(apiKey: key) == .invalidKey)
        }
        #expect(await harness.intelligence.connectionTestCount() == 0)
        #expect(!harness.session.hasDeepSeekKey)
    }

    @Test("A Key the server rejects is invalid and is not saved")
    @MainActor
    func connectDeepSeekInvalidKey() async {
        let harness = makeHarness(text: "unused", connectionError: LerroError.invalidAPIKey)
        await harness.session.start()

        #expect(await harness.session.connectDeepSeek(apiKey: "sk-0123456789abcdef") == .invalidKey)
        #expect(!harness.session.hasDeepSeekKey)
        #expect(harness.session.preferences.intelligenceMode == .raw)
    }

    @Test("A Key with no balance is saved and reported as no balance")
    @MainActor
    func connectDeepSeekNoBalance() async {
        let emptyAccount = makeHarness(
            text: "unused",
            balance: Self.balance("0", isAvailable: false)
        )
        await emptyAccount.session.start()
        #expect(await emptyAccount.session.connectDeepSeek(apiKey: "sk-0123456789abcdef") == .noBalance)
        #expect(emptyAccount.session.hasDeepSeekKey)
        #expect(emptyAccount.session.preferences.intelligenceMode == .remote)
        #expect(emptyAccount.session.aiStatus == .outOfBalance)

        let rejectedWithPaymentRequired = makeHarness(
            text: "unused",
            connectionError: LerroError.insufficientBalance,
            balance: nil
        )
        await rejectedWithPaymentRequired.session.start()
        #expect(await rejectedWithPaymentRequired.session.connectDeepSeek(
            apiKey: "sk-0123456789abcdef"
        ) == .noBalance)
        #expect(rejectedWithPaymentRequired.session.hasDeepSeekKey)
        #expect(rejectedWithPaymentRequired.session.aiStatus == .outOfBalance)
    }

    @Test("Other connection errors are reported and nothing is saved")
    @MainActor
    func connectDeepSeekFailure() async {
        let harness = makeHarness(
            text: "unused",
            connectionError: LerroError.remoteUnavailable("网络不可用")
        )
        await harness.session.start()

        let outcome = await harness.session.connectDeepSeek(apiKey: "sk-0123456789abcdef")
        guard case .failed(let message) = outcome else {
            Issue.record("Expected a failed outcome, got \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        #expect(!harness.session.hasDeepSeekKey)
    }

    @Test("Replacing the Key clears it, turns AI off, and forgets the balance")
    @MainActor
    func clearDeepSeekKeyTurnsAIOff() async {
        let harness = makeHarness(text: "unused", preferences: remotePreferences())
        await harness.session.start()
        #expect(await waitUntil { harness.session.deepSeekBalance == .loaded(Self.balance("8.42")) })

        #expect(await harness.session.clearDeepSeekKey())
        #expect(!harness.session.hasDeepSeekKey)
        #expect(harness.session.preferences.intelligenceMode == .raw)
        #expect(harness.session.deepSeekBalance == .unknown)
        #expect(harness.session.aiStatus == .off)
        #expect((try? await harness.preferences.load())?.remoteProvider.apiKey == "")
    }

    @Test("The AI offer shows until a Key exists or the offer is dismissed, and the guide follows the Key")
    @MainActor
    func aiOfferAndGuide() async {
        let harness = makeHarness(text: "unused")
        await harness.session.start()
        #expect(harness.session.showsAIOffer)

        harness.session.presentAIGuide()
        #expect(harness.session.isAIGuidePresented)

        harness.session.dismissAIOffer()
        #expect(!harness.session.showsAIOffer)
        #expect(harness.session.preferences.aiOfferDismissed)
        #expect(await waitUntil { (try? await harness.preferences.load())?.aiOfferDismissed == true })

        let keyed = makeHarness(text: "unused", preferences: remotePreferences())
        await keyed.session.start()
        #expect(!keyed.session.showsAIOffer)
        keyed.session.presentAIGuide()
        #expect(!keyed.session.isAIGuidePresented)
        #expect(keyed.session.settingsTab == .ai)
    }

    @Test("A successful AI call refreshes the balance without forcing")
    @MainActor
    func successfulCallRefreshesBalance() async {
        let harness = makeHarness(
            text: "嗯你好",
            preferences: remotePreferences(),
            intelligenceText: "你好"
        )
        await harness.session.start()
        #expect(await waitUntil { await harness.intelligence.balanceRequestCount() == 1 })
        await dictate(harness.session)
        // The read at launch is under 60 seconds old.
        #expect(await harness.intelligence.balanceRequestCount() == 1)
        #expect(harness.session.aiStatus == .ready)
    }

    @Test("Dictation falls back to raw text when the balance is used up and says why")
    @MainActor
    func insufficientBalanceFallsBackToRaw() async {
        let harness = makeHarness(
            text: "raw transcript",
            preferences: remotePreferences(),
            intelligenceError: LerroError.insufficientBalance
        )
        await harness.session.start()
        #expect(harness.session.aiStatus == .ready)

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.hudDeliveryFeedback != nil })

        #expect(await harness.delivery.values() == ["raw transcript"])
        #expect(harness.session.hudDeliveryFeedback == .deliveredRawFallback)
        #expect(harness.session.hudFallbackMessage == "DeepSeek 余额已用完，本次写入的是原文")
        #expect(harness.session.aiStatus == .outOfBalance)
    }

    @Test("Other AI failures fall back to raw text without a balance message")
    @MainActor
    func otherFailureHasNoBalanceMessage() async {
        let harness = makeHarness(
            text: "raw transcript",
            preferences: remotePreferences(),
            intelligenceFails: true
        )
        await harness.session.start()

        await dictate(harness.session)
        #expect(await waitUntil { harness.trace.finishedTraces().count == 1 })
        #expect(harness.session.hudFallbackMessage == nil)
        #expect(harness.session.aiStatus == .ready)
    }

    @Test("Translation fails when the balance is used up")
    @MainActor
    func translationFailsWithoutBalance() async {
        let harness = makeHarness(
            text: "你好",
            preferences: remotePreferences(),
            intelligenceError: LerroError.insufficientBalance
        )
        await harness.session.start()

        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .failed })
        #expect(harness.session.captureError == "DeepSeek 余额已用完，请充值后再用")
        #expect(await harness.delivery.values().isEmpty)
        #expect(harness.session.aiStatus == .outOfBalance)
    }

    @Test("Translation without a Key fails before recording")
    @MainActor
    func translationNeedsKey() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        let harness = makeHarness(text: "你好", preferences: preferences)
        await harness.session.start()

        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .failed })
        #expect(await harness.speech.startCount() == 0)
    }

    @Test("Dictation with AI on but no Key writes the raw transcript without a request")
    @MainActor
    func dictationWithoutKeyIsRaw() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        let harness = makeHarness(text: "raw words", preferences: preferences)
        await harness.session.start()

        await dictate(harness.session)
        #expect(await harness.delivery.values() == ["raw words"])
        #expect(await harness.intelligence.requests().isEmpty)
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
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
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
        intelligenceResponse: String? = nil,
        learningDecision: DictionaryLearningDecision = .noLearning,
        applications: [ApplicationDescriptor] = [],
        intelligenceFails: Bool = false,
        historyEntries: [HistoryEntry] = [],
        classificationDelay: Duration? = nil,
        resourcesReady: Bool = true,
        aiUsageRecords: [AIUsageRecord] = [],
        holdStartSound: Bool = false,
        intelligenceError: (any Error)? = nil,
        connectionError: (any Error)? = nil,
        balance: DeepSeekBalance? = DeepSeekBalance(
            isAvailable: true,
            total: Decimal(string: "8.42") ?? 8.42,
            currencyCode: "CNY"
        )
    ) -> Harness {
        _ = NSApplication.shared
        let events = EventLog()
        let speech = StubSpeech(text: text, resourcesReady: resourcesReady, events: events)
        let sounds = StubSoundPlayer(events: events, holdsStart: holdStartSound)
        let delivery = StubDelivery(fails: deliveryFails)
        let recovery = StubRecovery()
        let observer = StubObserver()
        let intelligence = StubIntelligence(
            resultText: intelligenceText ?? text,
            responseText: intelligenceResponse,
            learningDecision: learningDecision,
            fails: intelligenceFails,
            classificationDelay: classificationDelay,
            processError: intelligenceError,
            connectionError: connectionError,
            balance: balance
        )
        let trace = RecordingTraceObserver()
        let history = InMemoryHistoryRepository(entries: historyEntries)
        let dictionary = dictionary ?? InMemoryDictionaryRepository()
        let termLearning = InMemoryTermLearningRepository()
        let aiUsage = InMemoryAIUsageRepository(records: aiUsageRecords)
        let preferences = preferences ?? basePreferences()
        let preferencesRepository = InMemoryPreferencesRepository(value: preferences)
        let dependencies = AppDependencies(
            applicationPaths: nil,
            startupStorageError: nil,
            speech: speech,
            soundPlayer: sounds,
            microphoneTest: StubMicrophoneTester(),
            context: StubContextCapture(),
            textDelivery: delivery,
            recoveryText: recovery,
            deliveredTextObserver: observer,
            applicationCatalog: StubApplicationCatalog(values: applications),
            hotkeys: StubHotkeyMonitor(),
            permissions: StubPermissions(),
            loginItem: StubLoginItem(),
            history: history,
            dictionary: dictionary,
            preferences: preferencesRepository,
            aiUsage: aiUsage,
            dailyUsage: InMemoryDailyUsageRepository(),
            termLearning: termLearning,
            intelligence: intelligence,
            captureTrace: trace
        )
        return Harness(
            session: AppSession(dependencies: dependencies, presentsFloatingPanels: false),
            speech: speech,
            sounds: sounds,
            events: events,
            delivery: delivery,
            recovery: recovery,
            observer: observer,
            intelligence: intelligence,
            history: history,
            dictionary: dictionary,
            termLearning: termLearning,
            aiUsage: aiUsage,
            preferences: preferencesRepository,
            trace: trace
        )
    }

    private func remotePreferences() -> UserPreferences {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "sk-test-key")
        return preferences
    }

    private static func balance(_ total: String, isAvailable: Bool = true) -> DeepSeekBalance {
        DeepSeekBalance(
            isAvailable: isAvailable,
            total: Decimal(string: total) ?? 0,
            currencyCode: "CNY"
        )
    }

    private func basePreferences() -> UserPreferences {
        UserPreferences(
            muteOtherAudio: false,
            historyRetention: .forever,
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
    let sounds: StubSoundPlayer
    let events: EventLog
    let delivery: StubDelivery
    let recovery: StubRecovery
    let observer: StubObserver
    let intelligence: StubIntelligence
    let history: InMemoryHistoryRepository
    let dictionary: InMemoryDictionaryRepository
    let termLearning: InMemoryTermLearningRepository
    let aiUsage: InMemoryAIUsageRepository
    let preferences: InMemoryPreferencesRepository
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

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) { lock.withLock { values.append(value) } }
    func all() -> [String] { lock.withLock { values } }
}

/// With `holdsStart`, `play(.start)` suspends until `releaseStart()`.
private actor StubSoundPlayer: CaptureSoundPlaying {
    private let events: EventLog
    private let holdsStart: Bool
    private var startReleased = false
    private var startWaiter: CheckedContinuation<Void, Never>?

    init(events: EventLog, holdsStart: Bool) {
        self.events = events
        self.holdsStart = holdsStart
    }

    func prepare() async { events.append("sound.prepare") }

    func play(_ sound: CaptureSound) async {
        switch sound {
        case .start:
            events.append("sound.start")
            if holdsStart, !startReleased {
                await withCheckedContinuation { startWaiter = $0 }
            }
            events.append("sound.start.finished")
        case .stop:
            events.append("sound.stop")
        }
    }

    func releaseStart() {
        startReleased = true
        startWaiter?.resume()
        startWaiter = nil
    }
}

private actor StubSpeech: SpeechTranscribing {
    private let text: String
    private var startTotal = 0
    private var reporters: [CaptureMilestoneReporter] = []
    private var continuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation?
    private let resourcesReady: Bool
    private var readyLocales = Set<String>()
    private var preparedLocales: [String] = []
    private var preparationWaiters: [String: CheckedContinuation<Void, Never>] = [:]

    private let events: EventLog

    init(text: String, resourcesReady: Bool, events: EventLog) {
        self.text = text
        self.resourcesReady = resourcesReady
        self.events = events
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
        saveAudio: Bool,
        milestones: @escaping CaptureMilestoneReporter
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error> {
        events.append("speech.start")
        startTotal += 1
        reporters.append(milestones)
        milestones(.speechLocaleResolved, ContinuousClock.now)
        milestones(.audioEngineStarted, ContinuousClock.now)
        let pair = AsyncThrowingStream<SpeechEvent, any Error>.makeStream()
        continuation = pair.continuation
        continuation?.yield(.partial(text))
        return pair.stream
    }

    func lowerOtherAudio() async {
        events.append("speech.lowerOtherAudio")
    }

    func endAudioCapture() async {
        events.append("speech.endAudioCapture")
    }

    func stop() async throws -> SpeechTranscription {
        events.append("speech.stop")
        continuation?.finish()
        continuation = nil
        return SpeechTranscription(rawText: text, localeIdentifier: "en_US", duration: 1)
    }

    func cancel() async {
        events.append("speech.cancel")
        continuation?.finish()
        continuation = nil
    }

    func startCount() -> Int { startTotal }
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
    private let responseText: String?
    private let learningDecision: DictionaryLearningDecision
    private let fails: Bool
    private let classificationDelay: Duration?
    private let processError: (any Error)?
    private let connectionError: (any Error)?
    private var balance: DeepSeekBalance?
    private var recordedRequests: [IntelligenceRequest] = []
    private var classifications = 0
    private var balanceRequests = 0
    private var connectionTests = 0

    init(
        resultText: String, responseText: String? = nil,
        learningDecision: DictionaryLearningDecision,
        fails: Bool = false, classificationDelay: Duration? = nil,
        processError: (any Error)? = nil,
        connectionError: (any Error)? = nil,
        balance: DeepSeekBalance? = nil
    ) {
        self.processError = processError
        self.connectionError = connectionError
        self.balance = balance
        self.resultText = resultText
        self.responseText = responseText
        self.learningDecision = learningDecision
        self.fails = fails
        self.classificationDelay = classificationDelay
    }

    func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult {
        recordedRequests.append(request)
        if let processError { throw processError }
        if fails { throw TestFailure.intelligence }
        return IntelligenceResult(
            text: resultText,
            modelIdentifier: "test-model",
            source: request.mode == .remote ? .remote : .raw,
            call: request.mode == .remote
                ? AICallTrace(
                    prompt: request.task == .translate ? .translate : .dictate,
                    promptVersion: "test_v1",
                    modelIdentifier: "test-model",
                    userPrompt: "{\"raw_data\":{\"transcript\":\"\(request.transcript)\"}}",
                    response: responseText ?? resultText,
                    tokens: AITokenUsage(inputTokens: 100, outputTokens: 10),
                    latencyMilliseconds: 500,
                    startedAt: .now
                )
                : nil
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
    func testRemoteConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome {
        connectionTests += 1
        if let connectionError { throw connectionError }
        return .success()
    }
    func remoteBalance(
        configuration: RemoteProviderConfiguration
    ) async throws -> DeepSeekBalance {
        balanceRequests += 1
        guard let balance else { throw TestFailure.intelligence }
        return balance
    }
    func setBalance(_ balance: DeepSeekBalance?) { self.balance = balance }
    func balanceRequestCount() -> Int { balanceRequests }
    func connectionTestCount() -> Int { connectionTests }
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

private enum TestFailure: Error {
    case delivery
    case intelligence
}
