import AppKit
import Foundation
import Testing
import LerroCore
import LerroMac
@testable import Lerro

@Suite("App session V1.6 core flow", .serialized)
struct AppSessionCoreFlowTests {
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

    @Test("Apple Speech receives at most one hundred relevant vocabulary terms")
    @MainActor
    func speechVocabularyIsBoundedAndScoped() async {
        let entries = (0..<120).map { index in
            DictionaryEntry(
                phrase: "term-\(index)",
                source: .learned,
                applicationBundleIdentifier: index.isMultiple(of: 2) ? "com.example.Editor" : nil,
                useCount: index
            )
        } + [
            DictionaryEntry(
                phrase: "other-app",
                source: .learned,
                applicationBundleIdentifier: "com.example.Other",
                useCount: 999
            )
        ]
        let dictionary = InMemoryDictionaryRepository(entries: entries)
        let harness = makeHarness(text: "vocabulary", dictionary: dictionary)
        await harness.session.start()

        harness.session.toggleCapture(.dictation)
        #expect(await waitUntil { await harness.speech.starts().count == 1 })
        let start = await harness.speech.starts()[0]
        #expect(start.vocabulary.count == 100)
        #expect(!start.vocabulary.contains { $0.phrase == "other-app" })
        harness.session.cancelCapture()
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
        #expect(learned[0].applicationBundleIdentifier == "com.example.Editor")

        harness.session.undoDictionaryLearning()
        #expect(await waitUntil { await harness.dictionary.entries().isEmpty })
        #expect(harness.session.dictionaryLearningToast == nil)
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

    @Test("Application catalog and personalization entry are first-class session surfaces")
    @MainActor
    func personalizationSurfacesApplications() async {
        let applications = [ApplicationDescriptor(
            bundleIdentifier: "com.example.Editor",
            name: "Editor",
            isRunning: true
        )]
        let harness = makeHarness(text: "unused", applications: applications)
        await harness.session.start()
        harness.session.refreshAvailableApplications()
        #expect(await waitUntil { harness.session.availableApplications == applications })

        harness.session.presentSettings(.personalization)
        #expect(harness.session.settingsDestination == .personal)
        #expect(!harness.session.isOnboardingPresented)
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
        applications: [ApplicationDescriptor] = []
    ) -> Harness {
        _ = NSApplication.shared
        let speech = StubSpeech(text: text)
        let delivery = StubDelivery(fails: deliveryFails)
        let recovery = StubRecovery()
        let observer = StubObserver()
        let intelligence = StubIntelligence(
            resultText: intelligenceText ?? text,
            learningDecision: learningDecision
        )
        let history = InMemoryHistoryRepository()
        let dictionary = dictionary ?? InMemoryDictionaryRepository()
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
            preferences: InMemoryPreferencesRepository(value: preferences),
            intelligence: intelligence,
            deviceCapabilities: StubDeviceCapabilities()
        )
        return Harness(
            session: AppSession(dependencies: dependencies, presentsFloatingPanels: false),
            speech: speech,
            delivery: delivery,
            recovery: recovery,
            observer: observer,
            intelligence: intelligence,
            history: history,
            dictionary: dictionary
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
}

private struct SpeechStart: Sendable {
    let vocabulary: [SpeechVocabularyTerm]
    let detectSpeechEndpoint: Bool
}

private actor StubSpeech: SpeechTranscribing {
    private let text: String
    private var records: [SpeechStart] = []
    private var continuation: AsyncThrowingStream<SpeechEvent, any Error>.Continuation?

    init(text: String) { self.text = text }

    func availableInputDevices() async -> [AudioInputDevice] { [] }

    func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        muteOtherAudio: Bool,
        saveAudio: Bool,
        vocabulary: [SpeechVocabularyTerm],
        detectSpeechEndpoint: Bool
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error> {
        records.append(SpeechStart(
            vocabulary: vocabulary,
            detectSpeechEndpoint: detectSpeechEndpoint
        ))
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
    private var recordedRequests: [IntelligenceRequest] = []
    private var classifications = 0

    init(resultText: String, learningDecision: DictionaryLearningDecision) {
        self.resultText = resultText
        self.learningDecision = learningDecision
    }

    func prepare(modelIdentifier: String) async throws {}
    func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult {
        recordedRequests.append(request)
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
}
