import AppKit
import Foundation
import Testing
import LerroCore
import LerroMac
@testable import Lerro

@Suite("App session core flow", .serialized)
struct AppSessionCoreFlowTests {
    @Test("Settings presentation owns destination and dismisses onboarding")
    @MainActor
    func settingsPresentationState() async {
        let monitor = RecordingHotkeyMonitor()
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            hotkeys: monitor
        )
        await harness.session.start()
        #expect(monitor.startCount == 1)
        harness.session.isOnboardingPresented = true

        harness.session.presentSettings(SettingsEntryPoint.personalization)

        #expect(harness.session.isSettingsPresented)
        #expect(harness.session.settingsDestination == .personal)
        #expect(!harness.session.isOnboardingPresented)

        #expect(harness.session.beginShortcutConfiguration())
        harness.session.dismissSettings()
        #expect(!harness.session.isSettingsPresented)
        #expect(monitor.startCount == 2)

        harness.session.dismissSettings()
        #expect(monitor.startCount == 2)
    }

    @Test("History loads in stable 50-entry pages")
    @MainActor
    func historyLoadsInitialAndNextPages() async {
        let now = Date.now
        let entries = (0..<120).map { index in
            HistoryEntry(
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                mode: .dictation,
                rawText: "history \(index)",
                finalText: "history \(index)",
                duration: 1,
                applicationName: "Notes"
            )
        }
        let history = InMemoryHistoryRepository(entries: entries)
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            historyRepository: history
        )

        await harness.session.start()

        #expect(harness.session.historyEntries.count == 50)
        #expect(harness.session.historyEntries.first?.finalText == "history 0")
        #expect(harness.session.historyTotalCount == 120)
        #expect(harness.session.historyHasMore)

        await harness.session.loadNextHistoryPage()
        #expect(harness.session.historyEntries.count == 100)
        #expect(harness.session.historyTotalCount == 120)
        #expect(harness.session.historyHasMore)

        await harness.session.loadNextHistoryPage()
        #expect(harness.session.historyEntries.count == 120)
        #expect(!harness.session.historyHasMore)
    }

    @Test("A stale history query cannot replace a newer query")
    @MainActor
    func staleHistoryQueryIsSuppressed() async {
        let history = ControlledHistoryRepository(
            entries: [
                HistoryEntry(
                    mode: .dictation,
                    rawText: "old",
                    finalText: "old result",
                    duration: 1,
                    applicationName: "Notes"
                ),
                HistoryEntry(
                    mode: .translation,
                    rawText: "new",
                    finalText: "new result",
                    duration: 1,
                    applicationName: "Safari"
                )
            ],
            suspendedSearchText: "old"
        )
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            historyRepository: history
        )
        await harness.session.start()

        let staleQuery = Task { @MainActor in
            await harness.session.updateHistoryQuery(searchText: "old", mode: nil)
        }
        await history.waitUntilSuspended()
        await harness.session.updateHistoryQuery(searchText: "new", mode: .translation)
        await history.resumeSuspendedPage()
        await staleQuery.value

        #expect(harness.session.historyEntries.map(\.finalText) == ["new result"])
        #expect(harness.session.historyTotalCount == 1)
        #expect(!harness.session.historyHasMore)
        #expect(!harness.session.isLoadingHistoryPage)
    }

    @Test("History and dictionary mutations refresh only their own data source")
    @MainActor
    func dataMutationRefreshesAreScoped() async {
        let historyEntry = HistoryEntry(
            mode: .dictation,
            rawText: "history",
            finalText: "history",
            duration: 1,
            applicationName: "Notes"
        )
        let history = ControlledHistoryRepository(entries: [historyEntry])
        let dictionary = CountingDictionaryRepository()
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            historyRepository: history,
            dictionaryRepository: dictionary
        )
        await harness.session.start()

        let historyReadsBeforeDictionarySave = await history.readCounts()
        let dictionaryReadsBeforeSave = await dictionary.entriesReadCount()
        #expect(await harness.session.saveDictionaryEntry(DictionaryEntry(phrase: "Lerro")))
        #expect(await history.readCounts() == historyReadsBeforeDictionarySave)
        #expect(await dictionary.entriesReadCount() == dictionaryReadsBeforeSave + 1)

        let dictionaryReadsBeforeHistoryDelete = await dictionary.entriesReadCount()
        harness.session.deleteHistoryEntry(historyEntry)
        #expect(await waitUntil { harness.session.historyTotalCount == 0 })
        #expect(await dictionary.entriesReadCount() == dictionaryReadsBeforeHistoryDelete)
    }

    @Test("Base dictation transcribes, delivers, and persists without the model")
    @MainActor
    func baseDictationCompletesEndToEnd() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "hello world",
                localeIdentifier: "en_US",
                duration: 1.25
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .idle && harness.session.lastResult == "hello world" })

        let deliveries = await harness.delivery.deliveries()
        let history = await harness.history.entries()
        let startRequests = await harness.speech.startRequests()
        let intelligenceRequests = await harness.intelligence.requests()

        #expect(deliveries == [DeliveryRecord(text: "hello world", replacingSelection: false)])
        #expect(history.count == 1)
        #expect(history.first?.mode == .dictation)
        #expect(history.first?.rawText == "hello world")
        #expect(history.first?.finalText == "hello world")
        #expect(history.first?.wasEnhanced == false)
        #expect(startRequests == [
            SpeechStartRecord(
                localeIdentifier: "zh_CN",
                microphoneDeviceUID: nil,
                muteOtherAudio: false,
                saveAudio: false,
                detectSpeechEndpoint: false
            )
        ])
        #expect(intelligenceRequests.isEmpty)
    }

    @Test("Local model preparation keeps Quick Dictate available through raw delivery")
    @MainActor
    func localPreparationKeepsQuickDictateAvailable() async throws {
        var preferences = basePreferences()
        preferences.intelligenceMode = .local
        preferences.hasApprovedModelDownload = true
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "download continues in background",
                localeIdentifier: "en_US",
                duration: 1
            ),
            modelStatus: LocalModelStatus(
                state: .downloading,
                modelIdentifier: preferences.localModelIdentifier,
                progress: 0.4,
                message: "Downloading"
            )
        )
        await harness.session.start()

        harness.session.toggleQuickDictate()
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleQuickDictate()
        #expect(await waitUntil { harness.session.phase == .idle })

        #expect(await harness.delivery.deliveries().map(\.text) == ["download continues in background"])
        #expect(await harness.intelligence.requests().isEmpty)
        #expect(harness.session.preferences.intelligenceMode == .local)
    }

    @Test("Application termination pauses an active local model download")
    @MainActor
    func applicationTerminationPausesLocalDownload() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .local
        preferences.hasApprovedModelDownload = true
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            modelStatus: LocalModelStatus(
                state: .downloading,
                modelIdentifier: preferences.localModelIdentifier,
                progress: 0.25,
                message: "Downloading",
                downloadedBytes: 250,
                totalBytes: 1_000
            )
        )
        await harness.session.start()

        await harness.session.prepareForApplicationTermination()

        #expect(await harness.intelligence.pauseCount() == 1)
        #expect(harness.session.modelStatus.state == .paused)
    }

    @Test("Live transcript distinguishes progressive and stable speech events")
    @MainActor
    func liveTranscriptTracksStability() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "visible while speaking",
                localeIdentifier: "en_US",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(harness.session.partialTranscript == "visible while speaking")
        #expect(!harness.session.partialTranscriptIsStable)
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt != nil })
        let history = await harness.history.entries()
        #expect(history.first?.phaseTimings != nil)
        #expect(history.first?.processingRoute == .raw)
        #expect(history.first?.contextReceipt?.capturedCategories.contains(.application) == true)
    }

    @Test("Hands-free finish phrase waits for first-use confirmation and remembers the app")
    @MainActor
    func voiceFinishConfirmationAndSubmission() async {
        let context = CapturedContext(
            applicationName: "Messages",
            processIdentifier: 42,
            bundleIdentifier: "com.apple.MobileSMS",
            selectionState: .knownEmpty,
            role: "AXTextArea"
        )
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "See you at seven, send it",
                localeIdentifier: "en_US",
                duration: 1
            ),
            context: context
        )

        await harness.session.start()
        harness.session.enterHandsFreeCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil {
            harness.session.deliveryReceipt?.status == .confirmSubmit
        })
        #expect(await harness.delivery.deliveries().first?.text == "See you at seven")

        harness.session.submitRecentDelivery()
        #expect(await waitUntil {
            harness.session.deliveryReceipt?.status == .submitted
        })
        #expect(await harness.delivery.submitCount() == 1)
        #expect(harness.session.preferences.voiceFinishApplications == [
            VoiceFinishApplication(
                bundleIdentifier: "com.apple.MobileSMS",
                applicationName: "Messages"
            )
        ])
        let history = await harness.history.entries()
        #expect(history.first?.rawText == "See you at seven, send it")
        #expect(history.first?.finalText == "See you at seven")
        #expect(history.first?.finishAction == .submitted)
    }

    @Test("Recent delivery undo records the history state")
    @MainActor
    func recentDeliveryUndo() async {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 7,
            bundleIdentifier: "com.apple.Notes",
            selectionState: .knownEmpty,
            role: "AXTextArea"
        )
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "undo me",
                localeIdentifier: "en_US",
                duration: 1
            ),
            context: context
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt != nil })
        harness.session.undoRecentDelivery()
        #expect(await waitUntil { harness.session.deliveryReceipt?.status == .undone })
        #expect(await harness.delivery.undoCount() == 1)
        #expect(await harness.history.entries().first?.status == .undone)
    }

    @Test("Recent delivery correction replaces atomically and preserves lineage")
    @MainActor
    func recentDeliveryCorrection() async throws {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 7,
            bundleIdentifier: "com.apple.Notes",
            selectionState: .knownEmpty,
            role: "AXTextArea"
        )
        let dictionary = InMemoryDictionaryRepository()
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "larrow",
                localeIdentifier: "en_US",
                duration: 1
            ),
            context: context,
            dictionaryRepository: dictionary
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt != nil })
        let receiptID = try #require(harness.session.deliveryReceipt?.id)

        let saved = await harness.session.applyRecentDeliveryCorrection(
            receiptID: receiptID,
            correctedText: "Lerro",
            phrase: "larrow",
            replacement: "Lerro"
        )

        #expect(saved)
        #expect(await harness.delivery.correctionCount() == 1)
        #expect(await harness.delivery.undoCount() == 0)
        let entry = try #require(await harness.history.entries().first)
        #expect(entry.rawText == "larrow")
        #expect(entry.processedText == "larrow")
        #expect(entry.finalText == "Lerro")
        let learned = try #require(await dictionary.entries().first)
        #expect(learned.phrase == "larrow")
        #expect(learned.replacement == "Lerro")
    }

    @Test("Quick Dictate finishes after detected speech and endpoint silence")
    @MainActor
    func quickDictateFinishesFromSpeechEndpoint() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "quick result",
                localeIdentifier: "en_US",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:fn:toggle"
        ))
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(harness.session.isQuickDictateCapture)
        await harness.speech.emit(.speechStarted)
        await harness.speech.emit(.silenceElapsed)

        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "quick result"
        })
        #expect(await harness.speech.startRequests().last?.detectSpeechEndpoint == true)
    }

    @Test("Voice follow-up edits stack and restore the previous version")
    @MainActor
    func voiceFollowUpStacksAndRestores() async throws {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 7,
            bundleIdentifier: "com.apple.Notes",
            selectionState: .knownEmpty,
            role: "AXTextArea"
        )
        let dictionary = InMemoryDictionaryRepository()
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "Hello Toni.",
                localeIdentifier: "en_US",
                duration: 1
            ),
            context: context,
            dictionaryRepository: dictionary
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt?.text == "Hello Toni." })

        await harness.speech.setTranscription(SpeechTranscription(
            rawText: "把 Toni 改成 Tony",
            localeIdentifier: "zh_CN",
            duration: 0.8
        ))
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt?.text == "Hello Tony." })

        await harness.speech.setTranscription(SpeechTranscription(
            rawText: "恢复上一版",
            localeIdentifier: "zh_CN",
            duration: 0.6
        ))
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt?.text == "Hello Toni." })

        #expect(await harness.delivery.correctionCount() == 2)
        let history = try #require(await harness.history.entries().first)
        #expect(history.finalText == "Hello Toni.")
        #expect(history.editLineage?.versions.count == 2)
        #expect(history.editLineage?.currentPath.map(\.text) == ["Hello Toni."])
        let learned = try #require(await dictionary.entries().first)
        #expect(learned.phrase == "Toni")
        #expect(learned.replacement == "Tony")
    }

    @Test("Ordinary dictation after a receipt starts a new delivery")
    @MainActor
    func ordinaryDictationDoesNotEditPreviousDelivery() async {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 7,
            bundleIdentifier: "com.apple.Notes",
            selectionState: .knownEmpty,
            role: "AXTextArea"
        )
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "First delivery.",
                localeIdentifier: "en_US",
                duration: 1
            ),
            context: context
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt != nil })
        await harness.speech.setTranscription(SpeechTranscription(
            rawText: "A separate new thought.",
            localeIdentifier: "en_US",
            duration: 1
        ))

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.lastResult == "A separate new thought." })

        #expect(await harness.delivery.correctionCount() == 0)
        #expect(await harness.delivery.deliveries().map(\.text) == [
            "First delivery.",
            "A separate new thought.",
        ])
        #expect(await harness.history.entries().count == 2)
    }

    @Test("Semantic follow-up rewrites the delivered text with the selected model")
    @MainActor
    func semanticVoiceFollowUpUsesFrozenModelConfiguration() async throws {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 7,
            bundleIdentifier: "com.apple.Notes",
            selectionState: .knownEmpty,
            role: "AXTextArea"
        )
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "This is a long original delivery.",
                localeIdentifier: "en_US",
                duration: 1
            ),
            intelligenceResult: IntelligenceResult(
                text: "Short delivery.",
                disposition: .replaceSelection,
                modelIdentifier: "test-qwen",
                source: .local
            ),
            context: context
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt != nil })
        harness.session.preferences.hasApprovedModelDownload = true
        harness.session.preferences.intelligenceMode = .local
        await harness.speech.setTranscription(SpeechTranscription(
            rawText: "把刚才改短一点",
            localeIdentifier: "zh_CN",
            duration: 0.8
        ))

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt?.text == "Short delivery." })

        let request = try #require(await harness.intelligence.requests().last)
        #expect(request.task == .rewriteSelection)
        #expect(request.transcript == "把刚才改短一点")
        #expect(request.selectedText == "This is a long original delivery.")
        #expect(request.mode == .local)
        let history = try #require(await harness.history.entries().first)
        #expect(history.editLineage?.currentVersion?.origin == .semantic)
        #expect(history.editLineage?.currentVersion?.instruction == "把刚才改短一点")
        #expect(history.editLineage?.currentVersion?.modelIdentifier == "test-qwen")
        #expect(history.editLineage?.currentVersion?.processingRoute == .local)
    }

    @Test("Voice redictation replaces the previous delivery on the next utterance")
    @MainActor
    func voiceRedictationReplacesOnNextUtterance() async {
        let context = CapturedContext(
            applicationName: "Notes",
            processIdentifier: 7,
            bundleIdentifier: "com.apple.Notes",
            selectionState: .knownEmpty,
            role: "AXTextArea"
        )
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "Original delivery.",
                localeIdentifier: "en_US",
                duration: 1
            ),
            context: context
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.deliveryReceipt != nil })
        await harness.speech.setTranscription(SpeechTranscription(
            rawText: "重新听写",
            localeIdentifier: "zh_CN",
            duration: 0.5
        ))

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        await harness.speech.setTranscription(SpeechTranscription(
            rawText: "Replacement delivery.",
            localeIdentifier: "en_US",
            duration: 1
        ))
        harness.session.toggleCapture(.dictation)

        #expect(await waitUntil {
            harness.session.deliveryReceipt?.text == "Replacement delivery."
        })
        #expect(await harness.delivery.correctionCount() == 1)
        #expect(await harness.history.entries().first?.finalText == "Replacement delivery.")
    }

    @Test("Hold shortcut begins on key down and completes only for its matching release")
    @MainActor
    func holdShortcutLifecycleIsBoundToDefinition() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "hold shortcut result",
                localeIdentifier: "en_US",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: "dictate:fn:hold"
        ))
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(!harness.session.isHandsFreeCapture)

        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .ended,
            definitionID: "another-binding"
        ))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(harness.session.phase == .listening)

        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .ended,
            definitionID: "dictate:fn:hold"
        ))
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "hold shortcut result"
        })
        #expect(await harness.speech.stopCount() == 1)
    }

    @Test("Toggle shortcut starts latched capture and the second press completes it")
    @MainActor
    func toggleShortcutLifecycle() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "toggle shortcut result",
                localeIdentifier: "en_US",
                duration: 1
            )
        )
        let trigger = HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:option:toggle"
        )

        await harness.session.start()
        harness.session.handleHotkey(trigger)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(harness.session.isHandsFreeCapture)

        harness.session.handleHotkey(trigger)
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "toggle shortcut result"
        })
        #expect(await harness.speech.stopCount() == 1)
    }

    @Test("Toggle capture exposes its final HUD shell before Speech startup completes")
    @MainActor
    func toggleCaptureHUDOpensImmediatelyDuringSpeechStartup() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "waiting HUD result",
                localeIdentifier: "en_US",
                duration: 1
            ),
            speechStartSuspended: true
        )
        let trigger = HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:option:toggle"
        )

        await harness.session.start()
        harness.session.handleHotkey(trigger)

        #expect(harness.session.isStartingCapture)
        #expect(harness.session.phase == .idle)
        #expect(CaptureHUDVisualState.resolve(
            phase: harness.session.phase,
            isStartingCapture: harness.session.isStartingCapture,
            isHandsFreeCapture: harness.session.isHandsFreeCapture
        ) == .handsFree)

        let speechReadyAt = Date.now
        await harness.speechStartGate.open()
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(!harness.session.isStartingCapture)
        harness.session.handleHotkey(trigger)
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "waiting HUD result"
        })
        #expect(await harness.history.entries().first?.createdAt ?? .distantPast >= speechReadyAt)
    }

    @Test("Second toggle exposes processing before asynchronous Speech finalization")
    @MainActor
    func secondToggleShowsProcessingSynchronously() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "instant processing result",
                localeIdentifier: "en_US",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })

        harness.session.toggleCapture(.dictation)

        #expect(harness.session.phase == .transcribing)
        #expect(CaptureHUDVisualState.resolve(
            phase: harness.session.phase,
            isStartingCapture: harness.session.isStartingCapture,
            isHandsFreeCapture: harness.session.isHandsFreeCapture
        ) == .processing)
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "instant processing result"
        })
    }

    @Test("Another toggle binding for the same action completes latched capture")
    @MainActor
    func alternateToggleBindingCompletesLatchedCapture() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "alternate toggle result",
                localeIdentifier: "en_US",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:option:toggle"
        ))
        #expect(await waitUntil { harness.session.phase == .listening })

        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:control:toggle"
        ))
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "alternate toggle result"
        })
        #expect(await harness.speech.stopCount() == 1)
    }

    @Test("Another toggle binding cancels capture startup")
    @MainActor
    func alternateToggleBindingCancelsCaptureStartup() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            speechStartSuspended: true
        )

        await harness.session.start()
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:first-toggle"
        ))
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:second-toggle"
        ))

        #expect(await waitUntil {
            let cancelCount = await harness.speech.cancelCount()
            return harness.session.phase == .idle && cancelCount == 1
        })
        #expect(await harness.speech.startRequests().count <= 1)
    }

    @Test("Another binding completes a HUD-locked hold capture")
    @MainActor
    func alternateBindingCompletesHUDLockedHold() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "alternate locked result",
                localeIdentifier: "en_US",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: "dictate:first-hold"
        ))
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.enterHandsFreeCapture(.dictation)

        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: "dictate:second-hold"
        ))
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "alternate locked result"
        })
        #expect(await harness.speech.stopCount() == 1)
    }

    @Test("A hold capture expands to the hands-free shell during Speech startup")
    @MainActor
    func startupHoldCanExpandToHandsFree() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "startup lock result",
                localeIdentifier: "en_US",
                duration: 1
            ),
            speechStartSuspended: true
        )

        await harness.session.start()
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: "dictate:startup-hold"
        ))
        #expect(harness.session.isStartingCapture)
        #expect(!harness.session.isHandsFreeCapture)

        harness.session.enterHandsFreeCapture(.dictation)

        #expect(harness.session.isHandsFreeCapture)
        #expect(CaptureHUDVisualState.resolve(
            phase: harness.session.phase,
            isStartingCapture: harness.session.isStartingCapture,
            isHandsFreeCapture: harness.session.isHandsFreeCapture
        ) == .handsFree)
        harness.session.cancelCapture()
        await harness.speechStartGate.open()
        #expect(await waitUntil { harness.session.phase == .idle })
    }

    @Test("Shortcut handler preserves a rapid hold begin and end in FIFO order")
    @MainActor
    func hotkeyHandlerPreservesRapidGestureOrder() async throws {
        let monitor = RecordingHotkeyMonitor()
        let definition = HotkeyDefinition(
            action: .dictate,
            modifiers: 1 << 23,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        var preferences = basePreferences()
        preferences.hotkeys = [definition]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            speechStartSuspended: true,
            hotkeys: monitor
        )
        let definitionID = definition.id

        await harness.session.start()
        monitor.emit([
            HotkeyTrigger(
                action: .dictate,
                activation: .hold,
                phase: .began,
                definitionID: definitionID
            ),
            HotkeyTrigger(
                action: .dictate,
                activation: .hold,
                phase: .ended,
                definitionID: definitionID
            )
        ])

        #expect(await waitUntil {
            let cancelCount = await harness.speech.cancelCount()
            return harness.session.phase == .idle && cancelCount == 1
        })
        #expect(monitor.startCount == 1)
    }

    @Test("A more specific hold shortcut takes ownership after prefix cancellation")
    @MainActor
    func hotkeyPrefixUpgradeRestartsForTheSpecificAction() async throws {
        let monitor = RecordingHotkeyMonitor()
        let prefix = HotkeyDefinition(
            action: .dictate,
            modifiers: 1 << 23,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let specific = HotkeyDefinition(
            action: .ask,
            keyCode: 49,
            modifiers: 1 << 23,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Space"
        )
        var preferences = basePreferences()
        preferences.hasApprovedModelDownload = true
        preferences.intelligenceMode = .local
        preferences.hotkeys = [prefix, specific]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "specific shortcut result",
                localeIdentifier: "en_US",
                duration: 1
            ),
            intelligenceResult: IntelligenceResult(
                text: "specific shortcut result",
                disposition: .showAnswer,
                modelIdentifier: "test-qwen"
            ),
            hotkeys: monitor
        )
        let prefixID = prefix.id
        let specificID = specific.id

        await harness.session.start()
        monitor.emit([HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: prefixID
        )])
        #expect(await waitUntil { harness.session.phase == .listening })

        monitor.emit([
            HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began),
            HotkeyTrigger(
                action: .ask,
                activation: .hold,
                phase: .began,
                definitionID: specificID
            )
        ])
        #expect(await waitUntil {
            harness.session.phase == .listening && harness.session.activeMode == .ask
        })

        monitor.emit([HotkeyTrigger(
            action: .ask,
            activation: .hold,
            phase: .ended,
            definitionID: specificID
        )])
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.answerText == "specific shortcut result"
        })
        #expect(await harness.speech.cancelCount() == 1)
        #expect(await harness.speech.stopCount() == 1)
    }

    @Test("Releasing an upgraded hold during cancellation prevents a ghost capture")
    @MainActor
    func releasedPrefixUpgradeDoesNotRestart() async throws {
        let monitor = RecordingHotkeyMonitor()
        let prefix = HotkeyDefinition(
            action: .dictate,
            modifiers: 1 << 23,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        let specific = HotkeyDefinition(
            action: .ask,
            keyCode: 49,
            modifiers: 1 << 23,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn Space"
        )
        var preferences = basePreferences()
        preferences.hasApprovedModelDownload = true
        preferences.intelligenceMode = .local
        preferences.hotkeys = [prefix, specific]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            hotkeys: monitor
        )

        await harness.session.start()
        monitor.emit([HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: prefix.id
        )])
        #expect(await waitUntil { harness.session.phase == .listening })
        monitor.emit([
            HotkeyTrigger(action: .cancel, activation: .toggle, phase: .began),
            HotkeyTrigger(
                action: .ask,
                activation: .hold,
                phase: .began,
                definitionID: specific.id
            ),
            HotkeyTrigger(
                action: .ask,
                activation: .hold,
                phase: .ended,
                definitionID: specific.id
            )
        ])

        #expect(await waitUntil {
            let cancelCount = await harness.speech.cancelCount()
            return harness.session.phase == .idle && cancelCount == 1
        })
        #expect(await harness.speech.startRequests().count == 1)
        #expect(await harness.speech.cancelCount() == 1)
    }

    @Test("Second toggle during capture startup cancels without creating another generation")
    @MainActor
    func toggleDuringStartupCancels() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            speechStartSuspended: true
        )
        let trigger = HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:startup-toggle"
        )

        await harness.session.start()
        harness.session.handleHotkey(trigger)
        harness.session.handleHotkey(trigger)

        #expect(await waitUntil {
            let cancelCount = await harness.speech.cancelCount()
            return harness.session.phase == .idle && cancelCount == 1
        })
        #expect(await harness.speech.startRequests().count <= 1)
    }

    @Test("Two toggle presses queued during cancellation preserve the closed state")
    @MainActor
    func queuedToggleParityPreservesClosedState() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            )
        )
        let first = HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:first-toggle"
        )
        let second = HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:second-toggle"
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })

        harness.session.cancelCapture()
        harness.session.handleHotkey(first)
        harness.session.handleHotkey(second)

        #expect(await waitUntil {
            let cancelCount = await harness.speech.cancelCount()
            return harness.session.phase == .idle && cancelCount == 1
        })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await harness.speech.startRequests().count == 1)
        #expect(harness.session.phase == .idle)
    }

    @Test("Cancel during cleanup clears a queued capture restart")
    @MainActor
    func cancelDuringCleanupClearsQueuedRestart() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })

        harness.session.cancelCapture()
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "dictate:queued-during-cleanup"
        ))
        harness.session.handleHotkey(HotkeyTrigger(
            action: .cancel,
            activation: .toggle,
            phase: .began
        ))

        #expect(await waitUntil {
            let cancelCount = await harness.speech.cancelCount()
            return harness.session.phase == .idle && cancelCount == 1
        })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await harness.speech.startRequests().count == 1)
        #expect(harness.session.phase == .idle)
    }

    @Test("Programmatic startup ignores hold begin and the next programmatic toggle cancels")
    @MainActor
    func programmaticStartupKeepsSingleGeneration() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            speechStartSuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { await harness.speech.startRequests().count == 1 })

        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: "dictate:hold-during-programmatic-start"
        ))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(await harness.speech.startRequests().count == 1)

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil {
            let cancelCount = await harness.speech.cancelCount()
            return harness.session.phase == .idle && cancelCount == 1
        })
        await harness.speechStartGate.open()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(await harness.speech.startRequests().count == 1)
    }

    @Test("HUD lock ignores the original hold release and the next press completes")
    @MainActor
    func hudLockPromotesHoldToLatchedCapture() async throws {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "locked hold result",
                localeIdentifier: "en_US",
                duration: 1
            )
        )
        let began = HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: "dictate:lockable-hold"
        )
        let ended = HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .ended,
            definitionID: "dictate:lockable-hold"
        )

        await harness.session.start()
        harness.session.handleHotkey(began)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.enterHandsFreeCapture(.dictation)
        harness.session.handleHotkey(ended)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(harness.session.phase == .listening)
        #expect(harness.session.isHandsFreeCapture)

        harness.session.handleHotkey(began)
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "locked hold result"
        })
    }

    @Test("Hotkey mutation is rejected during active capture")
    @MainActor
    func hotkeyMutationIsRejectedDuringActiveCapture() async throws {
        var preferences = basePreferences()
        let first = HotkeyDefinition(
            action: .dictate,
            keyCode: 97,
            activation: .toggle,
            displayName: "F6"
        )
        let second = HotkeyDefinition(
            action: .dictate,
            keyCode: 98,
            activation: .toggle,
            displayName: "F7"
        )
        preferences.hotkeys = [first, second]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "mutation guard result",
                localeIdentifier: "en_US",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: first.id
        ))
        #expect(await waitUntil { harness.session.phase == .listening })

        harness.session.removeHotkey(first)
        let added = harness.session.addHotkey(
            for: .dictate,
            keyCode: 99,
            modifiers: 0,
            usesFunctionKey: false,
            activation: .toggle,
            displayName: "F8"
        )
        #expect(!added)
        #expect(harness.session.preferences.hotkeys == [first, second])
        #expect(harness.session.currentError == "请先完成当前语音输入")

        harness.session.handleHotkey(HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: second.id
        ))
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "mutation guard result"
        })
    }

    @Test("Stale monitor triggers stay invalid across shortcut configuration")
    @MainActor
    func staleTriggersAreDroppedAcrossShortcutConfiguration() async throws {
        let monitor = RecordingHotkeyMonitor()
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            hotkeys: monitor
        )

        await harness.session.start()
        #expect(monitor.startCount == 1)
        #expect(harness.session.beginShortcutConfiguration())

        monitor.emitFromStart(0, triggers: [HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "stale-before-end"
        )])
        harness.session.handleHotkey(HotkeyTrigger(
            action: .pasteLastResult,
            activation: .toggle,
            phase: .began
        ))
        harness.session.endShortcutConfiguration()
        #expect(monitor.startCount == 2)

        monitor.emitFromStart(0, triggers: [HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: "stale-after-end"
        )])
        try? await Task.sleep(for: .milliseconds(100))

        #expect(await harness.speech.startRequests().isEmpty)
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(harness.session.phase == .idle)
    }

    @Test("A queued trigger is dropped after its live binding is removed")
    @MainActor
    func removedBindingQueuedTriggerIsDropped() async throws {
        let removed = HotkeyDefinition(
            action: .dictate,
            keyCode: 97,
            activation: .toggle,
            displayName: "F6"
        )
        let retained = HotkeyDefinition(
            action: .dictate,
            keyCode: 98,
            activation: .toggle,
            displayName: "F7"
        )
        var preferences = basePreferences()
        preferences.hotkeys = [removed, retained]
        let monitor = RecordingHotkeyMonitor()
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            hotkeys: monitor
        )

        await harness.session.start()
        monitor.emit([HotkeyTrigger(
            action: .dictate,
            activation: .toggle,
            phase: .began,
            definitionID: removed.id
        )])
        harness.session.removeHotkey(removed)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(harness.session.preferences.hotkeys == [retained])
        #expect(await harness.speech.startRequests().isEmpty)
        #expect(harness.session.phase == .idle)
    }

    @Test("Canonical aliases cannot be assigned to two actions")
    @MainActor
    func rejectsCanonicalHotkeyAliasConflicts() async throws {
        var preferences = basePreferences()
        preferences.hotkeys = [HotkeyDefinition(
            action: .dictate,
            modifiers: 1 << 23,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            )
        )

        await harness.session.start()
        let saved = harness.session.addHotkey(
            for: .ask,
            keyCode: 63,
            modifiers: 0,
            usesFunctionKey: false,
            activation: .toggle,
            displayName: "Fn key"
        )

        #expect(!saved)
        #expect(harness.session.preferences.hotkeys.count == 1)
        #expect(harness.session.currentError == "这个快捷键已被使用")
    }

    @Test("Shortcut commit waits for persistence and keeps the recorder open on failure")
    @MainActor
    func shortcutCommitReportsPersistenceFailure() async throws {
        let initial = basePreferences()
        let repository = FailingPreferencesRepository(value: initial)
        let harness = makeHarness(
            preferences: initial,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            preferencesRepository: repository
        )

        await harness.session.start()
        let saved = await harness.session.commitHotkey(
            for: .dictate,
            keyCode: nil,
            modifiers: 1 << 19,
            usesFunctionKey: false,
            activation: .toggle,
            displayName: "⌥"
        )

        #expect(!saved)
        #expect(harness.session.preferences == initial)
        #expect(harness.session.currentError?.contains("设置保存失败") == true)
    }

    @Test("Shortcut commit succeeds when an unrelated preference is queued after it")
    @MainActor
    func shortcutCommitSurvivesConcurrentPreferenceSave() async throws {
        let initial = basePreferences()
        let repository = GatedPreferencesRepository(value: initial)
        let harness = makeHarness(
            preferences: initial,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            preferencesRepository: repository
        )

        await harness.session.start()
        let commit = Task { @MainActor in
            await harness.session.commitHotkey(
                for: .dictate,
                keyCode: nil,
                modifiers: 1 << 19,
                usesFunctionKey: false,
                activation: .toggle,
                displayName: "⌥"
            )
        }
        #expect(await waitUntil { await repository.saveCount() == 1 })

        harness.session.preferences.muteOtherAudio = true
        harness.session.savePreferences()
        await repository.releaseFirstSave()

        #expect(await commit.value)
        let persisted = await repository.currentValue()
        #expect(persisted.muteOtherAudio)
        #expect(persisted.hotkeys.contains {
            $0.action == .dictate
                && $0.signature == HotkeySignature(keyCode: nil, modifiers: 1 << 19)
                && $0.activation == .toggle
        })
    }

    @Test("Preference system effects are scoped to the fields that changed")
    func preferenceSystemEffectsAreFieldScoped() {
        let initial = basePreferences()

        var unrelated = initial
        unrelated.muteOtherAudio.toggle()
        let unrelatedChanges = PreferenceSystemChanges(from: initial, to: unrelated)
        #expect(!unrelatedChanges.appearance)
        #expect(!unrelatedChanges.dockVisibility)
        #expect(!unrelatedChanges.hotkeys)

        var changed = unrelated
        changed.appearance = .dark
        changed.showInDock.toggle()
        changed.hotkeys = [HotkeyDefinition(
            action: .dictate,
            keyCode: 97,
            activation: .toggle,
            displayName: "F6"
        )]
        let systemChanges = PreferenceSystemChanges(from: unrelated, to: changed)
        #expect(systemChanges.appearance)
        #expect(systemChanges.dockVisibility)
        #expect(systemChanges.hotkeys)
    }

    @Test("Unrelated preference saves do not reconfigure global hotkeys")
    @MainActor
    func unrelatedPreferenceSaveSkipsHotkeyUpdate() async {
        let monitor = RecordingHotkeyMonitor()
        let loginItem = CountingLoginItemManager()
        let initialPreferences = basePreferences()
        let repository = InMemoryPreferencesRepository(value: initialPreferences)
        let harness = makeHarness(
            preferences: initialPreferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            loginItem: loginItem,
            hotkeys: monitor,
            preferencesRepository: repository
        )

        await harness.session.start()
        let startupUpdates = monitor.updateCount
        let previous = harness.session.preferences
        harness.session.preferences.muteOtherAudio.toggle()
        let updated = harness.session.preferences
        harness.session.savePreferences(from: previous, to: updated)

        #expect(monitor.updateCount == startupUpdates)
        #expect(await waitUntil { await repository.load() == updated })
        #expect(loginItem.statusReadCount == 0)

        let beforeHotkeyChange = harness.session.preferences
        harness.session.preferences.hotkeys = [HotkeyDefinition(
            action: .dictate,
            keyCode: 97,
            activation: .toggle,
            displayName: "F6"
        )]
        let afterHotkeyChange = harness.session.preferences
        harness.session.savePreferences(from: beforeHotkeyChange, to: afterHotkeyChange)
        harness.session.savePreferences(from: beforeHotkeyChange, to: afterHotkeyChange)

        #expect(await waitUntil { await repository.load() == afterHotkeyChange })
        #expect(monitor.updateCount == startupUpdates + 1)
        #expect(monitor.latestDefinitions == afterHotkeyChange.hotkeys)
        #expect(loginItem.statusReadCount == 0)

        let beforeLoginItemChange = harness.session.preferences
        harness.session.preferences.launchAtLogin = true
        let afterLoginItemChange = harness.session.preferences
        harness.session.savePreferences(
            from: beforeLoginItemChange,
            to: afterLoginItemChange
        )

        #expect(await waitUntil {
            loginItem.statusReadCount == 1 && loginItem.enabled
        })
    }

    @Test("Whitespace-only dictation fails without empty delivery or completed history")
    @MainActor
    func fillerOnlyDictationFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "Lerro-FillerOnly-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let applicationPaths = ApplicationPaths(rootDirectory: root)
        try applicationPaths.prepareDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "  \n ",
                localeIdentifier: "zh_CN",
                duration: 1,
                audioRelativePath: "filler-only.caf"
            ),
            applicationPaths: applicationPaths
        )

        await harness.session.start()
        let recording = applicationPaths.audioDirectory.appending(path: "filler-only.caf")
        try Data("synthetic audio".utf8).write(to: recording)
        #expect(FileManager.default.fileExists(atPath: recording.path))
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .failed })

        #expect(harness.session.captureError == LerroError.emptyTranscription.localizedDescription)
        #expect(harness.session.currentError == nil)
        #expect(harness.session.lastResult.isEmpty)
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(await harness.history.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: recording.path))
    }

    @Test("Enhanced dictation falls back safely when local generation fails")
    @MainActor
    func enhancedDictationFallsBack() async throws {
        var preferences = basePreferences()
        preferences.enhancementEnabled = true
        preferences.hasApprovedModelDownload = true
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "hello hello",
                localeIdentifier: "en_US",
                duration: 1
            ),
            intelligenceError: StubError.generationFailed
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .idle && harness.session.lastResult == "hello hello" })

        let deliveries = await harness.delivery.deliveries()
        let history = await harness.history.entries()
        let intelligenceRequests = await harness.intelligence.requests()

        #expect(deliveries.first?.text == "hello hello")
        #expect(history.first?.finalText == "hello hello")
        #expect(history.first?.wasEnhanced == false)
        #expect(intelligenceRequests.map(\.task) == [.polish])
    }

    @Test("Translation uses device-local Apple Translation and delivers the result")
    @MainActor
    func translationCompletesEndToEnd() async throws {
        var preferences = basePreferences()
        preferences.intelligenceMode = .raw
        preferences.translationLanguageIdentifiers = ["en_US"]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "你好",
                localeIdentifier: "zh_CN",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .idle && harness.session.lastResult == "translated: 你好" })

        let delivery = try #require(await harness.delivery.deliveries().first)
        let history = try #require(await harness.history.entries().first)

        #expect(await harness.intelligence.requests().isEmpty)
        #expect(delivery == DeliveryRecord(text: "translated: 你好", replacingSelection: false))
        #expect(history.targetLanguage == "en_US")
        #expect(history.sourceLanguage == "zh_CN")
        #expect(history.wasEnhanced == false)
    }

    @Test("Changing languages refreshes resource state and invalidates stale preparation")
    @MainActor
    func languageChangesRefreshResources() async throws {
        var preferences = basePreferences()
        preferences.recognitionLocaleIdentifier = "zh_CN"
        preferences.translationLanguageIdentifiers = ["en_US"]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "zh_CN",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.prepareTranslationResources()
        let staleRequestID = try #require(harness.session.translationPreparationRequestID)

        harness.session.preferences.recognitionLocaleIdentifier = "ja_JP"
        harness.session.preferences.translationLanguageIdentifiers = ["ko_KR"]
        await harness.session.refreshLanguageResources(invalidatePreparations: true)

        #expect(harness.session.translationPreparationRequestID == nil)
        #expect(harness.session.speechResourceStatus.sourceLanguageIdentifier == "ja_JP")
        #expect(harness.session.translationResourceStatus.sourceLanguageIdentifier == "ja_JP")
        #expect(harness.session.translationResourceStatus.targetLanguageIdentifier == "ko_KR")

        harness.session.completeTranslationResourcePreparation(
            requestID: staleRequestID,
            errorMessage: "stale failure"
        )
        #expect(harness.session.translationResourceStatus.message != "stale failure")
    }

    @Test("Translation bypasses intelligence in every configured intelligence mode")
    @MainActor
    func translationNeverCallsIntelligence() async throws {
        for mode in [IntelligenceMode.raw, .local, .remote] {
            var preferences = basePreferences()
            preferences.intelligenceMode = mode
            preferences.translationLanguageIdentifiers = ["en_US"]
            let harness = makeHarness(
                preferences: preferences,
                transcription: SpeechTranscription(rawText: "你好", localeIdentifier: "zh_CN", duration: 1)
            )
            await harness.session.start()
            harness.session.toggleCapture(.translation)
            #expect(await waitUntil { harness.session.phase == .listening })
            harness.session.toggleCapture(.translation)
            #expect(await waitUntil { harness.session.phase == .idle })
            #expect(await harness.intelligence.requests().isEmpty)
            #expect(await harness.delivery.deliveries().first?.text == "translated: 你好")
        }
    }

    @Test("Unavailable translation resource never delivers or persists history")
    @MainActor
    func unavailableTranslationDoesNotDeliver() async throws {
        var preferences = basePreferences()
        preferences.intelligenceMode = .raw
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(rawText: "你好", localeIdentifier: "zh_CN", duration: 1),
            translation: UnavailableTranslation()
        )
        await harness.session.start()
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .failed })
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(await harness.history.entries().isEmpty)
        #expect(await harness.intelligence.requests().isEmpty)
    }

    @Test("Cancelling translation cancels its active device-local session")
    @MainActor
    func cancellingTranslationLeavesNoDeliveryOrHistory() async throws {
        var preferences = basePreferences()
        preferences.intelligenceMode = .raw
        let translation = BlockingTranslation()
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(rawText: "你好", localeIdentifier: "zh_CN", duration: 1),
            translation: translation
        )
        await harness.session.start()
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.translation)
        #expect(await waitUntil { await translation.hasStarted() })
        harness.session.cancelCapture()
        #expect(await waitUntil { harness.session.phase == .idle })
        #expect(await translation.cancelCount() == 1)
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(await harness.history.entries().isEmpty)
    }

    @Test("Ask streams an answer card and persists the final answer without text delivery")
    @MainActor
    func askStreamsAndPersistsAnswer() async throws {
        var preferences = basePreferences()
        preferences.hasApprovedModelDownload = true
        preferences.intelligenceMode = .local
        let chunks = [
            IntelligenceResult(text: "First", disposition: .showAnswer, modelIdentifier: "test-qwen"),
            IntelligenceResult(text: "First answer", disposition: .showAnswer, modelIdentifier: "test-qwen")
        ]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "What is the answer?",
                localeIdentifier: "en_US",
                duration: 1
            ),
            streamResults: chunks
        )

        await harness.session.start()
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .idle && harness.session.answerText == "First answer" })

        let history = try #require(await harness.history.entries().first)
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(history.mode == .ask)
        #expect(history.answerText == "First answer")
        #expect(history.finalText == "First answer")

        harness.session.insertAnswer()
        #expect(await waitUntil {
            let deliveryCount = await harness.delivery.deliveries().count
            return harness.session.answerText == nil && deliveryCount == 1
        })
        #expect(
            await harness.delivery.deliveries() == [
                DeliveryRecord(
                    text: "First answer",
                    replacingSelection: false,
                    targetPolicy: .reactivateCaptured
                )
            ]
        )
    }

    @Test("Remote dictation snapshots the BYOK configuration and delivers the API result")
    @MainActor
    func remoteDictationCompletesEndToEnd() async throws {
        var preferences = basePreferences()
        let configuration = RemoteProviderConfiguration(
            provider: .deepSeek,
            apiKey: "test-only-key",
            contextSharing: .full
        )
        preferences.remoteProvider = configuration
        preferences.intelligenceMode = .remote
        let remoteResult = IntelligenceResult(
            text: "整理后的云端文本",
            disposition: .insert,
            modelIdentifier: "deepseek-v4-flash",
            source: .remote
        )
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "呃这个是云端的原始文本",
                localeIdentifier: "zh_CN",
                duration: 1
            ),
            intelligenceResult: remoteResult,
            context: CapturedContext(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                windowTitle: "发布计划",
                cursorBefore: "上一句",
                cursorAfter: "下一句"
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil {
            harness.session.phase == .idle && harness.session.lastResult == remoteResult.text
        })

        let request = try #require(await harness.intelligence.requests().first)
        let history = try #require(await harness.history.entries().first)
        #expect(request.mode == .remote)
        #expect(request.remoteProvider == configuration)
        #expect(request.transcript == "呃这个是云端的原始文本")
        #expect(request.context.cursorBefore == "上一句")
        #expect(request.context.cursorAfter == "下一句")
        #expect(await harness.delivery.deliveries() == [
            DeliveryRecord(text: remoteResult.text, replacingSelection: false)
        ])
        #expect(history.finalText == remoteResult.text)
        #expect(history.wasEnhanced)
    }

    @Test("Saving and clearing a BYOK configuration persists the active mode")
    @MainActor
    func remoteConfigurationSaveAndClear() async throws {
        let initial = basePreferences()
        let repository = InMemoryPreferencesRepository(value: initial)
        let harness = makeHarness(
            preferences: initial,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 0
            ),
            preferencesRepository: repository
        )
        let configuration = RemoteProviderConfiguration(
            provider: .custom,
            baseURL: "https://gateway.example/v1",
            modelIdentifier: "model-a",
            apiKey: "test-only-key"
        )

        await harness.session.start()
        #expect(await harness.session.saveRemoteProvider(configuration))
        #expect(await waitUntil {
            let saved = await repository.load()
            return saved.intelligenceMode == .remote
                && saved.remoteProvider == configuration
        })

        #expect(await harness.session.clearRemoteProviderAPIKey())
        #expect(await waitUntil {
            let saved = await repository.load()
            return saved.intelligenceMode == .raw
                && saved.remoteProvider.apiKey.isEmpty
        })
        #expect(harness.session.preferences.intelligenceMode == .raw)
        #expect(harness.session.preferences.remoteProvider.apiKey.isEmpty)
    }

    @Test("Active capture rejects API configuration changes and connection probes")
    @MainActor
    func activeCaptureLocksRemoteConfiguration() async {
        var initial = basePreferences()
        initial.intelligenceMode = .remote
        initial.remoteProvider = RemoteProviderConfiguration(
            provider: .deepSeek,
            apiKey: "existing-test-key"
        )
        let repository = InMemoryPreferencesRepository(value: initial)
        let harness = makeHarness(
            preferences: initial,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "zh_CN",
                duration: 0
            ),
            preferencesRepository: repository
        )
        let replacement = RemoteProviderConfiguration(
            provider: .custom,
            baseURL: "https://gateway.example/v1",
            modelIdentifier: "model-b",
            apiKey: "replacement-test-key"
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        #expect(!harness.session.canModifyIntelligenceConfiguration)

        #expect(await harness.session.saveRemoteProvider(replacement) == false)
        #expect(await harness.session.clearRemoteProviderAPIKey() == false)
        let probe = await harness.session.testRemoteProviderConnection(replacement)
        #expect(!probe.succeeded)
        #expect(probe.message == "请在当前听写完成后测试 API 连接")
        #expect(await repository.load() == initial)
        #expect(harness.session.preferences == initial)

        harness.session.cancelCapture()
        #expect(await waitUntil { harness.session.phase == .idle })
    }

    @Test("Delivery probe requires a valid one-time UUID token")
    @MainActor
    func deliveryProbeRequiresValidToken() throws {
        #expect(AppSession.deliveryProbeConfiguration(arguments: ["Lerro"]) == nil)
        #expect(
            AppSession.deliveryProbeConfiguration(
                arguments: ["Lerro", AppSession.deliveryProbeArgument, "invalid"]
            ) == nil
        )
        let token = UUID().uuidString
        let configuration = try #require(
            AppSession.deliveryProbeConfiguration(
                arguments: ["Lerro", AppSession.deliveryProbeArgument, token]
            )
        )
        #expect(configuration.payload == AppSession.syntheticDeliveryProbeText)
        #expect(
            configuration.notificationName.rawValue
                == AppSession.deliveryProbeNotificationPrefix + token
        )
    }

    @Test("Secure focus blocks capture before the microphone starts")
    @MainActor
    func secureFocusFailsClosed() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "sensitive",
                localeIdentifier: "en_US",
                duration: 1
            ),
            context: CapturedContext(applicationName: "Passwords", isSecureField: true)
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil {
            harness.session.captureError == LerroError.secureField.localizedDescription
        })
        #expect(harness.session.currentError == nil)

        #expect(await harness.speech.startRequests().isEmpty)
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(await harness.history.entries().isEmpty)
    }

    @Test("Delivery failure preserves a recoverable result and failed history")
    @MainActor
    func deliveryFailureCannotLookSuccessful() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "cannot deliver",
                localeIdentifier: "en_US",
                duration: 1
            ),
            deliveryFails: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .failed })

        #expect(harness.session.captureError != nil)
        #expect(harness.session.currentError == nil)
        #expect(harness.session.lastResult == "cannot deliver")
        let history = await harness.history.entries()
        #expect(history.count == 1)
        #expect(history.first?.status == .failed)
        #expect(history.first?.finalText == "cannot deliver")
        #expect(await harness.delivery.deliveries().count == 1)
    }

    @Test("Cancellation stops speech and leaves delivery and history untouched")
    @MainActor
    func cancellationCleansTheActiveCapture() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "cancelled",
                localeIdentifier: "en_US",
                duration: 1
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.cancelCapture()
        #expect(await waitUntil { harness.session.phase == .idle })

        #expect(await harness.speech.cancelCount() == 1)
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(await harness.history.entries().isEmpty)
    }

    @Test("Cancellation remains available before text delivery commits")
    @MainActor
    func cancellationStopsPreCommitDelivery() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "pre-commit delivery",
                localeIdentifier: "en_US",
                duration: 1
            ),
            deliverySuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil {
            let deliveryCount = await harness.delivery.deliveries().count
            return harness.session.phase == .inserting && deliveryCount == 1
        })

        #expect(harness.session.isCaptureCancellationAvailable)
        harness.session.cancelCapture()
        #expect(harness.session.phase == .cancelled)
        await harness.deliveryGate.open()
        #expect(await waitUntil { harness.session.phase == .idle })

        #expect(await harness.delivery.commitCount() == 0)
        #expect(await harness.history.entries().isEmpty)
    }

    @Test("Cancellation is ignored after text delivery commits")
    @MainActor
    func cancellationCannotSplitCommittedDelivery() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "committed delivery",
                localeIdentifier: "en_US",
                duration: 1
            ),
            deliveryCompletionSuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil {
            let commitCount = await harness.delivery.commitCount()
            return harness.session.phase == .inserting && commitCount == 1
        })

        #expect(!harness.session.isCaptureCancellationAvailable)
        #expect(harness.session.isHUDSuppressed)
        #expect(CaptureHUDVisualState.resolve(
            phase: harness.session.phase,
            isStartingCapture: harness.session.isStartingCapture,
            isHandsFreeCapture: harness.session.isHandsFreeCapture,
            isSuppressed: harness.session.isHUDSuppressed
        ) == .idleHidden)
        harness.session.cancelCapture()
        #expect(harness.session.phase == .inserting)
        await harness.deliveryCompletionGate.open()
        #expect(await waitUntil {
            harness.session.phase == .idle
                && harness.session.lastResult == "committed delivery"
        })

        #expect(await harness.speech.cancelCount() == 0)
        #expect(await harness.history.entries().first?.status == .completed)
    }

    @Test("Committed completion hides the HUD without a pointer-tracking state")
    @MainActor
    func committedCompletionHidesHUDImmediately() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "completed delivery",
                localeIdentifier: "en_US",
                duration: 1
            ),
            deliveryCompletionSuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { await harness.delivery.commitCount() == 1 })
        await harness.deliveryCompletionGate.open()
        #expect(await waitUntil { harness.session.phase == .idle })

        #expect(!harness.session.isHUDSuppressed)
        #expect(CaptureHUDVisualState.resolve(
            phase: harness.session.phase,
            isStartingCapture: harness.session.isStartingCapture,
            isHandsFreeCapture: harness.session.isHandsFreeCapture,
            isSuppressed: harness.session.isHUDSuppressed
        ) == .idleHidden)
    }

    @Test("Dictation over a captured selection still uses plain insertion")
    @MainActor
    func selectedTextDoesNotChangeDictationSemantics() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "new spoken words",
                localeIdentifier: "en_US",
                duration: 1
            ),
            context: CapturedContext(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                selectedText: "existing selection"
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .idle && !harness.session.lastResult.isEmpty })

        #expect(
            await harness.delivery.deliveries() == [
                DeliveryRecord(text: "new spoken words", replacingSelection: false)
            ]
        )
    }

    @Test("Cancelling while speech starts cannot create a ghost recording")
    @MainActor
    func cancelDuringSpeechStartIsGenerationSafe() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "late transcription",
                localeIdentifier: "en_US",
                duration: 1
            ),
            speechStartSuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { await harness.speech.startRequests().count == 1 })
        harness.session.toggleCapture(.dictation)
        harness.session.toggleCapture(.dictation)
        await harness.speechStartGate.open()
        #expect(await waitUntil { harness.session.phase == .idle })

        #expect(await harness.speech.startRequests().count == 1)
        #expect(await harness.speech.cancelCount() >= 1)
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(await harness.history.entries().isEmpty)
    }

    @Test("Cancelling model enhancement never falls back and inserts text")
    @MainActor
    func cancelDuringEnhancementHasNoSideEffects() async {
        var preferences = basePreferences()
        preferences.enhancementEnabled = true
        preferences.hasApprovedModelDownload = true
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "cancel this enhancement",
                localeIdentifier: "en_US",
                duration: 1
            ),
            intelligenceSuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil {
            let requestCount = await harness.intelligence.requests().count
            return harness.session.phase == .enhancing && requestCount == 1
        })
        harness.session.cancelCapture()
        await harness.intelligenceGate.open()
        #expect(await waitUntil { harness.session.phase == .idle })

        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(await harness.history.entries().isEmpty)
        #expect(harness.session.lastResult.isEmpty)
    }

    @Test("Repeated capture shortcuts during processing do not stop speech twice")
    @MainActor
    func repeatedToggleDuringProcessingIsIgnored() async {
        var preferences = basePreferences()
        preferences.enhancementEnabled = true
        preferences.hasApprovedModelDownload = true
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "one stop only",
                localeIdentifier: "en_US",
                duration: 1
            ),
            intelligenceSuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .enhancing })
        harness.session.toggleCapture(.dictation)
        harness.session.toggleCapture(.dictation)
        #expect(await harness.speech.stopCount() == 1)

        await harness.intelligenceGate.open()
        #expect(await waitUntil { harness.session.phase == .idle && !harness.session.lastResult.isEmpty })
        #expect(await harness.speech.stopCount() == 1)
    }

    @Test("Idle cancellation leaves the app idle and never touches speech")
    @MainActor
    func idleCancelIsNoop() async {
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(rawText: "unused", localeIdentifier: "en_US", duration: 1)
        )

        await harness.session.start()
        harness.session.cancelCapture()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(harness.session.phase == .idle)
        #expect(await harness.speech.cancelCount() == 0)
    }

    @Test("Cancelling a streaming Ask closes the answer and prevents history")
    @MainActor
    func cancelStreamingAskHasNoLateResult() async {
        var preferences = basePreferences()
        preferences.hasApprovedModelDownload = true
        preferences.intelligenceMode = .local
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "answer later",
                localeIdentifier: "en_US",
                duration: 1
            ),
            streamResults: [
                IntelligenceResult(
                    text: "late answer",
                    disposition: .showAnswer,
                    modelIdentifier: "test-qwen"
                )
            ],
            intelligenceSuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.answerText != nil })
        harness.session.cancelCapture()
        await harness.intelligenceGate.open()
        #expect(await waitUntil { harness.session.phase == .idle })

        #expect(harness.session.answerText == nil)
        #expect(await harness.history.entries().isEmpty)
        #expect(await harness.delivery.deliveries().isEmpty)
    }

    @Test("Any Command with a selection transforms the captured selection")
    @MainActor
    func askRewriteReplacesSelection() async {
        var preferences = basePreferences()
        preferences.hasApprovedModelDownload = true
        preferences.intelligenceMode = .local
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "翻译成法语并保留产品名",
                localeIdentifier: "zh_CN",
                duration: 1
            ),
            intelligenceResult: IntelligenceResult(
                text: "简洁文本",
                disposition: .replaceSelection,
                modelIdentifier: "test-qwen"
            ),
            context: CapturedContext(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                selectedText: "需要改写的原文"
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .idle && harness.session.lastResult == "简洁文本" })

        #expect(await harness.intelligence.requests().first?.task == .rewriteSelection)
        #expect(
            await harness.delivery.deliveries() == [
                DeliveryRecord(text: "简洁文本", replacingSelection: true)
            ]
        )
    }

    @Test("Capture freezes the app style selected at recording start")
    @MainActor
    func captureFreezesAppStyle() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            baseURL: "https://api.example.com/v1",
            modelIdentifier: "test-model",
            apiKey: "test-key"
        )
        preferences.appToneProfiles = [
            AppToneProfile(
                bundleIdentifier: "com.apple.Notes",
                applicationName: "Notes",
                instruction: "Use short paragraphs."
            )
        ]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "project update",
                localeIdentifier: "en_US",
                duration: 1
            ),
            intelligenceSuspended: true
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.preferences.appToneProfiles[0].instruction = "Use a long memo."
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { await harness.intelligence.requests().count == 1 })

        #expect(await harness.intelligence.requests().first?.toneInstruction == "Use short paragraphs.")
        await harness.intelligenceGate.open()
        #expect(await waitUntil { harness.session.phase == .idle })
    }

    @Test("An exact Dictation snippet expands locally without model work")
    @MainActor
    func dictationExpandsSnippet() async {
        let snippets = InMemoryDictionaryRepository(entries: [
            DictionaryEntry(
                phrase: "meeting link",
                replacement: "https://example.com/meet",
                applicationBundleIdentifier: "com.apple.Notes"
            )
        ])
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "meeting link",
                localeIdentifier: "en_US",
                duration: 1
            ),
            dictionaryRepository: snippets
        )

        await harness.session.start()
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil {
            harness.session.phase == .idle && harness.session.lastResult == "https://example.com/meet"
        })

        #expect(await harness.intelligence.requests().isEmpty)
        #expect(await harness.delivery.deliveries() == [
            DeliveryRecord(text: "https://example.com/meet", replacingSelection: false)
        ])
    }

    @Test("History corrections update output and learn an app-scoped replacement")
    @MainActor
    func historyCorrectionLearnsReplacement() async throws {
        let entry = HistoryEntry(
            mode: .dictation,
            rawText: "larrow",
            finalText: "larrow",
            duration: 1,
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes"
        )
        let history = InMemoryHistoryRepository(entries: [entry])
        let dictionary = InMemoryDictionaryRepository()
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 1
            ),
            historyRepository: history,
            dictionaryRepository: dictionary
        )

        await harness.session.start()
        let saved = await harness.session.saveHistoryCorrection(
            entry,
            correctedText: "Lerro",
            phrase: "larrow",
            replacement: "Lerro"
        )

        #expect(saved)
        let corrected = try #require(await history.entries().first)
        #expect(corrected.finalText == "Lerro")
        #expect(corrected.processedText == "larrow")
        let learned = try #require(await dictionary.entries().first)
        #expect(learned.source == .learned)
        #expect(learned.applicationBundleIdentifier == "com.apple.Notes")
        #expect(learned.phrase == "larrow")
        #expect(learned.replacement == "Lerro")
    }

    @Test("A blocked remote Rewrite leaves the captured selection untouched")
    @MainActor
    func blockedRemoteRewriteDoesNotDeliver() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(
            apiKey: "test-key",
            contextSharing: RemoteContextSharing(
                application: true,
                windowTitle: true,
                nearbyText: true,
                selectedText: false,
                dictionary: true,
                tone: true
            )
        )
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "请改写得更简洁",
                localeIdentifier: "zh_CN",
                duration: 1
            ),
            intelligenceError: LerroError.remoteUnavailable(
                "API 改写需要允许发送选中文字"
            ),
            context: CapturedContext(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                selectedText: "需要保留的原文"
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .failed })

        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(await harness.history.entries().isEmpty)
        #expect(harness.session.lastResult.isEmpty)
    }

    @Test("Oversized captured selections stop before Rewrite generation")
    @MainActor
    func oversizedRewriteSelectionStopsBeforeGeneration() async {
        var preferences = basePreferences()
        preferences.intelligenceMode = .remote
        preferences.remoteProvider = RemoteProviderConfiguration(apiKey: "test-key")
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "请改写得更简洁",
                localeIdentifier: "zh_CN",
                duration: 1
            ),
            context: CapturedContext(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                selectedText: String(
                    repeating: "S",
                    count: CapturedContext.maximumSelectedTextCharacters
                ),
                selectedTextWasTruncated: true
            )
        )

        await harness.session.start()
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .listening })
        harness.session.toggleCapture(.ask)
        #expect(await waitUntil { harness.session.phase == .failed })

        #expect(await harness.intelligence.requests().isEmpty)
        #expect(await harness.delivery.deliveries().isEmpty)
        #expect(harness.session.captureError?.contains("4096") == true)
    }

    @Test("Returning to the foreground refreshes all permission state")
    @MainActor
    func foregroundRefreshesPermissions() async {
        let permissions = MutablePermissions(granted: false)
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 1
            ),
            permissions: permissions
        )
        await harness.session.start()
        #expect(!harness.session.requiredPermissionsGranted)

        permissions.setGranted(true)
        await harness.session.applicationDidBecomeActive()

        #expect(harness.session.requiredPermissionsGranted)
    }

    @Test("Incomplete insertion permissions keep the hotkey monitor stopped")
    @MainActor
    func incompleteInsertionPermissionsDoNotStartHotkeyMonitor() async {
        let permissions = IndependentPermissions(
            microphone: true,
            accessibility: false
        )
        let monitor = RecordingHotkeyMonitor()
        let harness = makeHarness(
            preferences: basePreferences(),
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 1
            ),
            permissions: permissions,
            hotkeys: monitor
        )

        await harness.session.start()
        let stopCountAfterStartup = monitor.stopCount
        harness.session.toggleCapture(.dictation)

        #expect(await waitUntil { harness.session.captureError != nil })
        #expect(harness.session.currentError == nil)
        #expect(monitor.startCount == 0)
        #expect(monitor.stopCount > stopCountAfterStartup)
        #expect(await harness.speech.startRequests().isEmpty)
    }

    @Test("Permission revocation cancels an active hold and stops monitoring")
    @MainActor
    func permissionRevocationCancelsActiveHold() async throws {
        let permissions = IndependentPermissions(
            microphone: true,
            accessibility: true
        )
        let monitor = RecordingHotkeyMonitor()
        let definition = HotkeyDefinition(
            action: .dictate,
            modifiers: 1 << 23,
            usesFunctionKey: true,
            activation: .hold,
            displayName: "Fn"
        )
        var preferences = basePreferences()
        preferences.hotkeys = [definition]
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 1
            ),
            permissions: permissions,
            hotkeys: monitor
        )
        let definitionID = definition.id

        await harness.session.start()
        monitor.emit([HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .began,
            definitionID: definitionID
        )])
        #expect(await waitUntil { harness.session.phase == .listening })

        permissions.setAccessibility(false)
        await harness.session.applicationDidBecomeActive()

        #expect(await waitUntil {
            let cancelCount = await harness.speech.cancelCount()
            return harness.session.phase == .idle && cancelCount == 1
        })
        #expect(!harness.session.accessibilityPermission)
        #expect(monitor.startCount == 1)
        #expect(monitor.stopCount >= 1)

        monitor.emitFromStart(0, triggers: [HotkeyTrigger(
            action: .dictate,
            activation: .hold,
            phase: .ended,
            definitionID: definitionID
        )])
        try? await Task.sleep(for: .milliseconds(80))
        #expect(harness.session.phase == .idle)
        #expect(await harness.speech.startRequests().count == 1)
    }

    @Test("A migrated launch-at-login preference reconciles once and closes its receipt")
    @MainActor
    func migratedLoginItemIsReconciled() async throws {
        var preferences = basePreferences()
        preferences.launchAtLogin = true
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "LerroLoginMigration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let receiptURL = directory.appending(path: "receipt.json")
        let receipt = ApplicationDataMigrationReceipt(
            version: ApplicationDataMigrationReceipt.schemaVersion,
            migrationIdentifier: UUID(),
            sourceBundleIdentifier: ApplicationIdentity.legacyBundleIdentifier,
            destinationBundleIdentifier: ApplicationIdentity.bundleIdentifier,
            completedAt: Date(timeIntervalSince1970: 1_000),
            rootDeviceIdentifier: 1,
            rootFileIdentifier: 2,
            loginItemStatus: .pending
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(receipt).write(to: receiptURL, options: .atomic)
        let loginItem = RecordingLoginItemManager()
        let harness = makeHarness(
            preferences: preferences,
            transcription: SpeechTranscription(
                rawText: "unused",
                localeIdentifier: "en_US",
                duration: 1
            ),
            dataMigrationResult: ApplicationDataMigrationResult(
                state: .migrated,
                receiptURL: receiptURL,
                loginItemStatus: .pending
            ),
            loginItem: loginItem
        )

        await harness.session.start()

        #expect(loginItem.values() == [true])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let updated = try decoder.decode(
            ApplicationDataMigrationReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        #expect(updated.loginItemStatus == .completed)
    }

    @MainActor
    private func makeHarness(
        preferences: UserPreferences,
        transcription: SpeechTranscription,
        intelligenceResult: IntelligenceResult = IntelligenceResult(
            text: "generated",
            disposition: .insert,
            modelIdentifier: "test-qwen"
        ),
        streamResults: [IntelligenceResult]? = nil,
        intelligenceError: (any Error & Sendable)? = nil,
        modelStatus: LocalModelStatus = LocalModelStatus(
            state: .ready,
            modelIdentifier: "test-qwen",
            progress: 1,
            message: "Ready"
        ),
        context: CapturedContext = CapturedContext(
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes"
        ),
        deliveryFails: Bool = false,
        deliverySuspended: Bool = false,
        deliveryCompletionSuspended: Bool = false,
        speechStartSuspended: Bool = false,
        intelligenceSuspended: Bool = false,
        applicationPaths: ApplicationPaths? = nil,
        dataMigrationResult: ApplicationDataMigrationResult? = nil,
        permissions: any PermissionChecking = AllowedPermissions(),
        loginItem: any LoginItemManaging = NoopLoginItemManager(),
        identityMonitor: any ApplicationIdentityMonitoring = NoopApplicationIdentityMonitor(),
        hotkeys: any HotkeyMonitoring = NoopHotkeyMonitor(),
        preferencesRepository: (any PreferencesRepository)? = nil,
        historyRepository: (any HistoryRepository)? = nil,
        dictionaryRepository: (any DictionaryRepository)? = nil,
        translation: any TranslationServicing = StubTranslation()
    ) -> Harness {
        _ = NSApplication.shared
        let speechStartGate = AsyncGate(isOpen: !speechStartSuspended)
        let intelligenceGate = AsyncGate(isOpen: !intelligenceSuspended)
        let deliveryGate = AsyncGate(isOpen: !deliverySuspended)
        let deliveryCompletionGate = AsyncGate(isOpen: !deliveryCompletionSuspended)
        let speech = StubSpeech(transcription: transcription, startGate: speechStartGate)
        let delivery = RecordingTextDeliverer(
            shouldFail: deliveryFails,
            deliveryGate: deliveryGate,
            completionGate: deliveryCompletionGate
        )
        let history = InMemoryHistoryRepository()
        let intelligence = StubIntelligence(
            result: intelligenceResult,
            streamResults: streamResults,
            error: intelligenceError,
            processGate: intelligenceGate,
            modelStatus: modelStatus
        )
        let dependencies = AppDependencies(
            applicationPaths: applicationPaths,
            dataMigrationResult: dataMigrationResult,
            startupStorageError: nil,
            speech: speech,
            microphoneTest: SilentMicrophoneTester(),
            context: FixedContextCapture(context: context),
            textDelivery: delivery,
            hotkeys: hotkeys,
            permissions: permissions,
            loginItem: loginItem,
            identityMonitor: identityMonitor,
            history: historyRepository ?? history,
            dictionary: dictionaryRepository ?? InMemoryDictionaryRepository(),
            preferences: preferencesRepository ?? InMemoryPreferencesRepository(value: preferences),
            intelligence: intelligence,
            translation: translation,
            deviceCapabilities: StubDeviceCapabilityAssessor()
        )
        return Harness(
            session: AppSession(
                dependencies: dependencies,
                presentsFloatingPanels: false
            ),
            speech: speech,
            delivery: delivery,
            history: history,
            intelligence: intelligence,
            speechStartGate: speechStartGate,
            intelligenceGate: intelligenceGate,
            deliveryGate: deliveryGate,
            deliveryCompletionGate: deliveryCompletionGate
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
    let delivery: RecordingTextDeliverer
    let history: InMemoryHistoryRepository
    let intelligence: StubIntelligence
    let speechStartGate: AsyncGate
    let intelligenceGate: AsyncGate
    let deliveryGate: AsyncGate
    let deliveryCompletionGate: AsyncGate
}

private struct SpeechStartRecord: Equatable, Sendable {
    let localeIdentifier: String
    let microphoneDeviceUID: String?
    let muteOtherAudio: Bool
    let saveAudio: Bool
    let detectSpeechEndpoint: Bool
}

private actor StubSpeech: SpeechTranscribing {
    private var transcription: SpeechTranscription
    private var recordedStarts: [SpeechStartRecord] = []
    private var continuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation?
    private var cancellations = 0
    private var stops = 0
    private let startGate: AsyncGate

    init(transcription: SpeechTranscription, startGate: AsyncGate) {
        self.transcription = transcription
        self.startGate = startGate
    }

    func availableInputDevices() -> [AudioInputDevice] { [] }

    func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        muteOtherAudio: Bool,
        saveAudio: Bool,
        detectSpeechEndpoint: Bool
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error> {
        recordedStarts.append(SpeechStartRecord(
            localeIdentifier: localeIdentifier,
            microphoneDeviceUID: microphoneDeviceUID,
            muteOtherAudio: muteOtherAudio,
            saveAudio: saveAudio,
            detectSpeechEndpoint: detectSpeechEndpoint
        ))
        await startGate.wait()
        try Task.checkCancellation()
        let pair = AsyncThrowingStream<SpeechEvent, any Error>.makeStream()
        continuation = pair.continuation
        continuation?.yield(.partial(transcription.rawText))
        return pair.stream
    }

    func stop() -> SpeechTranscription {
        stops += 1
        continuation?.finish()
        continuation = nil
        return transcription
    }

    func cancel() {
        cancellations += 1
        continuation?.finish(throwing: LerroError.cancelled)
        continuation = nil
    }

    func startRequests() -> [SpeechStartRecord] { recordedStarts }
    func cancelCount() -> Int { cancellations }
    func setTranscription(_ transcription: SpeechTranscription) {
        self.transcription = transcription
    }
    func emit(_ event: SpeechEvent) {
        continuation?.yield(event)
    }
    func stopCount() -> Int { stops }
}

private actor StubTranslation: TranslationServicing {
    func resourceStatus(
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) -> LanguageResourceStatus {
        LanguageResourceStatus(
            state: .ready,
            sourceLanguageIdentifier: sourceLanguageIdentifier,
            targetLanguageIdentifier: targetLanguageIdentifier
        )
    }

    func translate(
        _ text: String,
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) -> String {
        "translated: \(text)"
    }
}

private actor UnavailableTranslation: TranslationServicing {
    func resourceStatus(
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) -> LanguageResourceStatus {
        LanguageResourceStatus(
            state: .available,
            sourceLanguageIdentifier: sourceLanguageIdentifier,
            targetLanguageIdentifier: targetLanguageIdentifier,
            message: "需要准备翻译资源"
        )
    }

    func translate(
        _ text: String,
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) throws -> String {
        throw LerroError.translationUnavailable("需要准备翻译资源")
    }
}

private actor BlockingTranslation: TranslationServicing {
    private var continuation: CheckedContinuation<String, any Error>?
    private var didStart = false
    private var cancellations = 0

    func resourceStatus(
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) -> LanguageResourceStatus {
        LanguageResourceStatus(
            state: .ready,
            sourceLanguageIdentifier: sourceLanguageIdentifier,
            targetLanguageIdentifier: targetLanguageIdentifier
        )
    }

    func translate(
        _ text: String,
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) async throws -> String {
        didStart = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        cancellations += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func hasStarted() -> Bool { didStart }
    func cancelCount() -> Int { cancellations }
}

private struct DeliveryRecord: Equatable, Sendable {
    let text: String
    let replacingSelection: Bool
    let targetPolicy: TextDeliveryTargetPolicy

    init(
        text: String,
        replacingSelection: Bool,
        targetPolicy: TextDeliveryTargetPolicy = .requireCurrent
    ) {
        self.text = text
        self.replacingSelection = replacingSelection
        self.targetPolicy = targetPolicy
    }
}

private actor RecordingTextDeliverer: TextDelivering {
    private let shouldFail: Bool
    private let deliveryGate: AsyncGate
    private let completionGate: AsyncGate
    private var records: [DeliveryRecord] = []
    private var commits = 0
    private var undos = 0
    private var corrections = 0
    private var submissions = 0

    init(
        shouldFail: Bool,
        deliveryGate: AsyncGate,
        completionGate: AsyncGate
    ) {
        self.shouldFail = shouldFail
        self.deliveryGate = deliveryGate
        self.completionGate = completionGate
    }

    func deliver(
        _ text: String,
        to context: CapturedContext,
        replacingSelection: Bool,
        targetPolicy: TextDeliveryTargetPolicy,
        onCommit: @escaping TextDeliveryCommitHandler
    ) async throws -> TextDeliveryReceipt {
        records.append(DeliveryRecord(
            text: text,
            replacingSelection: replacingSelection,
            targetPolicy: targetPolicy
        ))
        await deliveryGate.wait()
        try Task.checkCancellation()
        if shouldFail { throw StubError.deliveryFailed }
        await onCommit()
        commits += 1
        await completionGate.wait()
        return TextDeliveryReceipt(
            context: context,
            focusedValueFingerprint: text.hashValue,
            focusedElementFingerprint: context.hashValue
        )
    }

    func undo(_ receipt: TextDeliveryReceipt) async throws { undos += 1 }
    func correct(
        _ text: String,
        using receipt: TextDeliveryReceipt
    ) async throws -> TextDeliveryReceipt {
        corrections += 1
        records.append(DeliveryRecord(
            text: text,
            replacingSelection: false,
            targetPolicy: .reactivateCaptured
        ))
        return TextDeliveryReceipt(
            context: receipt.context,
            focusedValueFingerprint: text.hashValue,
            focusedElementFingerprint: receipt.focusedElementFingerprint
        )
    }
    func submit(_ receipt: TextDeliveryReceipt) async throws { submissions += 1 }

    func deliveries() -> [DeliveryRecord] { records }
    func commitCount() -> Int { commits }
    func undoCount() -> Int { undos }
    func correctionCount() -> Int { corrections }
    func submitCount() -> Int { submissions }
}

private actor StubIntelligence: IntelligenceProcessing {
    private let result: IntelligenceResult
    private let streamResults: [IntelligenceResult]?
    private let error: (any Error & Sendable)?
    private let processGate: AsyncGate
    private var statusValue: LocalModelStatus
    private var recordedRequests: [IntelligenceRequest] = []
    private var pauseRequests = 0

    init(
        result: IntelligenceResult,
        streamResults: [IntelligenceResult]?,
        error: (any Error & Sendable)?,
        processGate: AsyncGate,
        modelStatus: LocalModelStatus
    ) {
        self.result = result
        self.streamResults = streamResults
        self.error = error
        self.processGate = processGate
        self.statusValue = modelStatus
    }

    func prepare(modelIdentifier: String) throws {
        if let error { throw error }
    }

    func pauseLocalModelPreparation() {
        pauseRequests += 1
        statusValue.state = .paused
        statusValue.message = "Paused"
        statusValue.bytesPerSecond = nil
    }

    func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult {
        recordedRequests.append(request)
        await processGate.wait()
        try Task.checkCancellation()
        if let error { throw error }
        return result
    }

    func processStream(
        _ request: IntelligenceRequest
    ) async throws -> AsyncThrowingStream<IntelligenceResult, any Error> {
        recordedRequests.append(request)
        await processGate.wait()
        try Task.checkCancellation()
        if let error { throw error }
        let values = streamResults ?? [result]
        return AsyncThrowingStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }

    func modelStatus() -> LocalModelStatus {
        statusValue
    }

    func requests() -> [IntelligenceRequest] { recordedRequests }
    func pauseCount() -> Int { pauseRequests }
}

private struct StubDeviceCapabilityAssessor: DeviceCapabilityAssessing {
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

private enum StubError: LocalizedError, Sendable {
    case generationFailed
    case deliveryFailed
    case preferenceSaveFailed

    var errorDescription: String? {
        switch self {
        case .generationFailed: "Synthetic generation failure"
        case .deliveryFailed: "Synthetic delivery failure"
        case .preferenceSaveFailed: "Synthetic preference save failure"
        }
    }
}

private actor FailingPreferencesRepository: PreferencesRepository {
    private let value: UserPreferences

    init(value: UserPreferences) {
        self.value = value
    }

    func load() -> UserPreferences { value }

    func save(_ preferences: UserPreferences) throws {
        throw StubError.preferenceSaveFailed
    }
}

private actor GatedPreferencesRepository: PreferencesRepository {
    private var value: UserPreferences
    private var saves = 0
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?

    init(value: UserPreferences) {
        self.value = value
    }

    func load() -> UserPreferences { value }

    func save(_ preferences: UserPreferences) async {
        saves += 1
        if saves == 1 {
            await withCheckedContinuation { continuation in
                firstSaveContinuation = continuation
            }
        }
        value = preferences
    }

    func saveCount() -> Int { saves }

    func currentValue() -> UserPreferences { value }

    func releaseFirstSave() {
        let continuation = firstSaveContinuation
        firstSaveContinuation = nil
        continuation?.resume()
    }
}

private struct FixedContextCapture: ContextCapturing {
    let context: CapturedContext
    func captureCurrentContext() -> CapturedContext { context }
}

private struct AllowedPermissions: PermissionChecking {
    func microphoneAuthorized() -> Bool { true }
    func requestMicrophone() -> Bool { true }
    func accessibilityAuthorized(prompt: Bool) -> Bool { true }
}

private final class MutablePermissions: PermissionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var granted: Bool

    init(granted: Bool) {
        self.granted = granted
    }

    func setGranted(_ value: Bool) {
        lock.withLock { granted = value }
    }

    func microphoneAuthorized() -> Bool { lock.withLock { granted } }
    func requestMicrophone() -> Bool { lock.withLock { granted } }
    func accessibilityAuthorized(prompt: Bool) -> Bool { lock.withLock { granted } }
}

private final class IndependentPermissions: PermissionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var microphone: Bool
    private var accessibility: Bool

    init(
        microphone: Bool,
        accessibility: Bool
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
    }

    func setAccessibility(_ accessibility: Bool) {
        lock.withLock {
            self.accessibility = accessibility
        }
    }

    func microphoneAuthorized() -> Bool { lock.withLock { microphone } }
    func requestMicrophone() -> Bool { lock.withLock { microphone } }
    func accessibilityAuthorized(prompt: Bool) -> Bool { lock.withLock { accessibility } }
}

private struct SilentMicrophoneTester: MicrophoneLevelTesting {
    func availableInputDevices() -> [AudioInputDevice] { [] }

    func start(microphoneDeviceUID: String?) -> MicrophoneLevelTestSession {
        MicrophoneLevelTestSession(
            id: UUID(),
            levels: AsyncThrowingStream { $0.finish() }
        )
    }

    func stop(sessionID: UUID) {}
}

private struct NoopLoginItemManager: LoginItemManaging {
    func isEnabled() -> Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

private final class CountingLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEnabled = false
    private var storedStatusReadCount = 0

    var enabled: Bool { lock.withLock { storedEnabled } }
    var statusReadCount: Int { lock.withLock { storedStatusReadCount } }

    func isEnabled() -> Bool {
        lock.withLock {
            storedStatusReadCount += 1
            return storedEnabled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        lock.withLock { storedEnabled = enabled }
    }
}

private final class RecordingLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var reconciledValues: [Bool] = []

    func isEnabled() -> Bool { false }
    func setEnabled(_ enabled: Bool) throws {}

    func reconcileAfterIdentityMigration(
        enabled: Bool
    ) throws -> LoginItemIdentityMigrationStatus {
        lock.withLock { reconciledValues.append(enabled) }
        return .completed
    }

    func values() -> [Bool] { lock.withLock { reconciledValues } }
}

private struct NoopApplicationIdentityMonitor: ApplicationIdentityMonitoring {
    func legacyApplicationIsRunning() -> Bool { false }
}

private final class NoopHotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    func start(handler: @escaping @Sendable (HotkeyTrigger) -> Void) throws {}
    func update(definitions: [HotkeyDefinition]) {}
    func resetTransientState() {}
    func stop() {}
}

private final class RecordingHotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (HotkeyTrigger) -> Void)?
    private var handlerHistory: [@Sendable (HotkeyTrigger) -> Void] = []
    private var starts = 0
    private var stops = 0
    private var updates: [[HotkeyDefinition]] = []

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    var updateCount: Int { lock.withLock { updates.count } }
    var latestDefinitions: [HotkeyDefinition]? { lock.withLock { updates.last } }

    func start(handler: @escaping @Sendable (HotkeyTrigger) -> Void) throws {
        lock.withLock {
            self.handler = handler
            handlerHistory.append(handler)
            starts += 1
        }
    }

    func update(definitions: [HotkeyDefinition]) {
        lock.withLock { updates.append(definitions) }
    }
    func resetTransientState() {}
    func stop() {
        lock.withLock {
            handler = nil
            stops += 1
        }
    }

    func emit(_ triggers: [HotkeyTrigger]) {
        let callback = lock.withLock { handler }
        for trigger in triggers { callback?(trigger) }
    }

    func emitFromStart(_ index: Int, triggers: [HotkeyTrigger]) {
        let callback = lock.withLock {
            handlerHistory.indices.contains(index) ? handlerHistory[index] : nil
        }
        for trigger in triggers { callback?(trigger) }
    }
}

private actor ControlledHistoryRepository: HistoryRepository {
    private var values: [HistoryEntry]
    private let suspendedSearchText: String?
    private let suspendedSignal = AsyncGate(isOpen: false)
    private let suspendedPageGate = AsyncGate(isOpen: false)
    private var hasSuspendedPage = false
    private var entriesReads = 0
    private var pageReads = 0

    init(entries: [HistoryEntry], suspendedSearchText: String? = nil) {
        self.values = entries
        self.suspendedSearchText = suspendedSearchText
    }

    func entries() -> [HistoryEntry] {
        entriesReads += 1
        return sortedEntries()
    }

    func page(_ request: HistoryPageRequest) async -> HistoryPage {
        pageReads += 1
        if request.searchText == suspendedSearchText, !hasSuspendedPage {
            hasSuspendedPage = true
            await suspendedSignal.open()
            await suspendedPageGate.wait()
        }
        let matches = sortedEntries().filter { entry in
            let modeMatches = request.mode.map { entry.mode == $0 } ?? true
            let searchMatches = request.searchText.isEmpty
                || entry.finalText.localizedCaseInsensitiveContains(request.searchText)
                || entry.applicationName.localizedCaseInsensitiveContains(request.searchText)
            return modeMatches && searchMatches
        }
        let start = min(request.offset, matches.count)
        let end = min(matches.count, start + request.limit)
        return HistoryPage(
            entries: Array(matches[start..<end]),
            totalCount: matches.count,
            hasMore: end < matches.count
        )
    }

    func save(_ entry: HistoryEntry) {
        values.removeAll { $0.id == entry.id }
        values.append(entry)
    }

    func delete(id: UUID) {
        values.removeAll { $0.id == id }
    }

    func deleteAll() {
        values.removeAll()
    }

    func applyRetention(_ retention: HistoryRetention, now: Date) {
        guard retention != .forever, retention != .never else { return }
        values.removeAll { !retention.retains(createdAt: $0.createdAt, now: now) }
    }

    func waitUntilSuspended() async {
        await suspendedSignal.wait()
    }

    func resumeSuspendedPage() async {
        await suspendedPageGate.open()
    }

    func readCounts() -> DataSourceReadCounts {
        DataSourceReadCounts(entries: entriesReads, pages: pageReads)
    }

    private func sortedEntries() -> [HistoryEntry] {
        values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

private struct DataSourceReadCounts: Equatable, Sendable {
    var entries: Int
    var pages: Int
}

private actor CountingDictionaryRepository: DictionaryRepository {
    private var values: [DictionaryEntry] = []
    private var reads = 0

    func entries() -> [DictionaryEntry] {
        reads += 1
        return values
    }

    func save(_ entry: DictionaryEntry) {
        values.removeAll { $0.id == entry.id }
        values.append(entry)
    }

    func delete(id: UUID) {
        values.removeAll { $0.id == id }
    }

    func importEntries(_ entries: [DictionaryEntry]) {
        values.append(contentsOf: entries)
    }

    func entriesReadCount() -> Int {
        reads
    }
}

private actor AsyncGate {
    private var isOpen: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(isOpen: Bool) {
        self.isOpen = isOpen
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
