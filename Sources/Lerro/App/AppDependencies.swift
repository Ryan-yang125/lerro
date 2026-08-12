import Foundation
import LerroCore
import LerroIntelligence
import LerroMac

struct AppDependencies: Sendable {
    let applicationPaths: ApplicationPaths?
    let dataMigrationResult: ApplicationDataMigrationResult?
    let startupStorageError: String?
    let speech: any SpeechTranscribing
    let microphoneTest: any MicrophoneLevelTesting
    let context: any ContextCapturing
    let textDelivery: any TextDelivering
    let recoveryText: any RecoveryTextCopying
    let deliveredTextObserver: any DeliveredTextObserving
    let applicationCatalog: any ApplicationCataloging
    let hotkeys: any HotkeyMonitoring
    let permissions: any PermissionChecking
    let loginItem: any LoginItemManaging
    let identityMonitor: any ApplicationIdentityMonitoring
    let history: any HistoryRepository
    let dictionary: any DictionaryRepository
    let preferences: any PreferencesRepository
    let intelligence: any IntelligenceProcessing
    let deviceCapabilities: any DeviceCapabilityAssessing

    static func live() -> AppDependencies {
        if ProcessInfo.processInfo.environment["LERRO_FIXTURE_MODE"] == "1" {
            return fixture()
        }

        let paths = ApplicationPaths.live()
        let identityMonitor = MacApplicationIdentityMonitor()
        guard !identityMonitor.legacyApplicationIsRunning() else {
            return fixture(
                startupStorageError: "旧版 Lerro 工程身份仍在运行。请退出旧版后重新启动 Lerro，以安全迁移本地数据。"
            )
        }
        let migrationResult: ApplicationDataMigrationResult
        do {
            migrationResult = try ApplicationDataMigrator().migrateIfNeeded(
                from: .legacy(),
                to: paths
            )
            try paths.prepareDirectories()
        } catch {
            return fixture(startupStorageError: error.localizedDescription)
        }

        // The file repositories and MLX runtime are intentionally initialized
        // only after identity migration and directory preparation succeed.
        let preferences = FilePreferencesRepository(fileURL: paths.preferencesFile)
        let defaultPreferences = UserPreferences()
        let modelRuntime = MLXLanguageModelRuntime(
            defaultModelIdentifier: defaultPreferences.localModelIdentifier,
            modelCacheDirectory: paths.modelsDirectory
        )
        let remoteModelRuntime = OpenAICompatibleRemoteLanguageModelRuntime()
        return AppDependencies(
            applicationPaths: paths,
            dataMigrationResult: migrationResult,
            startupStorageError: nil,
            speech: AppleSpeechService(applicationPaths: paths),
            microphoneTest: MicrophoneLevelTester(),
            context: AccessibilityContextService(),
            textDelivery: AccessibilityTextDeliverer(),
            recoveryText: PasteboardRecoveryTextCopier(),
            deliveredTextObserver: AccessibilityDeliveredTextObserver(),
            applicationCatalog: MacApplicationCatalog(),
            hotkeys: GlobalHotkeyMonitor(),
            permissions: MacPermissionService(),
            loginItem: MacLoginItemManager(),
            identityMonitor: identityMonitor,
            history: FileHistoryRepository(fileURL: paths.historyFile),
            dictionary: FileDictionaryRepository(fileURL: paths.dictionaryFile),
            preferences: preferences,
            intelligence: PipelineIntelligenceService(
                runtime: modelRuntime,
                remoteRuntime: remoteModelRuntime,
                modelIdentifier: defaultPreferences.localModelIdentifier
            ),
            deviceCapabilities: MacDeviceCapabilityAssessor(storageURL: paths.rootDirectory)
        )
    }

    private static func fixture(startupStorageError: String? = nil) -> AppDependencies {
        let now = Date(timeIntervalSince1970: 1_785_283_200)
        let history = [
            HistoryEntry(
                createdAt: now,
                mode: .dictation,
                rawText: "这是一段用于视觉回归的合成口述。",
                finalText: "这是一段用于视觉回归的合成口述。",
                duration: 18,
                applicationName: "Notes",
                wasEnhanced: true
            ),
            HistoryEntry(
                createdAt: now.addingTimeInterval(-3_600),
                mode: .translation,
                rawText: "请把这段合成文本翻译成英文。",
                finalText: "Please translate this synthetic text into English.",
                targetLanguage: "en_US",
                duration: 11,
                applicationName: "Mail",
                wasEnhanced: true
            )
        ]
        let dictionary = [
            DictionaryEntry(
                phrase: "meeting link",
                replacement: "https://meet.example.com/lerro",
                useCount: 8
            ),
            DictionaryEntry(phrase: "code x", replacement: "Codex", source: .learned, useCount: 5),
            DictionaryEntry(phrase: "swift ui", replacement: "SwiftUI", useCount: 3)
        ]
        let onboardingRequested = ProcessInfo.processInfo.environment["LERRO_FIXTURE_ONBOARDING"] == "1"
        let onboardingStepIndex: Int? = switch ProcessInfo.processInfo.environment["LERRO_FIXTURE_ONBOARDING_STEP"] {
        case "privacy": 0
        case "speech": 1
        case "ai": 2
        case "shortcut": 3
        case "dictation": 4
        case "recovery": 5
        case "dictionary": 6
        case "tone": 7
        default: nil
        }
        let preferences = UserPreferences(
            appToneProfiles: [
                AppToneProfile(
                    bundleIdentifier: "com.apple.mail",
                    applicationName: "Mail",
                    instruction: "表达清楚、友好、简洁"
                )
            ],
            hasCompletedOnboarding: !onboardingRequested,
            onboardingStepIndex: onboardingRequested ? onboardingStepIndex : nil
        )

        return AppDependencies(
            applicationPaths: nil,
            dataMigrationResult: nil,
            startupStorageError: startupStorageError,
            speech: FixtureSpeechTranscriber(),
            microphoneTest: FixtureMicrophoneLevelTester(),
            context: FixtureContextCapture(),
            textDelivery: FixtureTextDeliverer(),
            recoveryText: FixtureRecoveryTextCopier(),
            deliveredTextObserver: FixtureDeliveredTextObserver(),
            applicationCatalog: FixtureApplicationCatalog(),
            hotkeys: FixtureHotkeyMonitor(),
            permissions: FixturePermissionChecker(),
            loginItem: FixtureLoginItemManager(),
            identityMonitor: FixtureApplicationIdentityMonitor(),
            history: InMemoryHistoryRepository(entries: history),
            dictionary: InMemoryDictionaryRepository(entries: dictionary),
            preferences: InMemoryPreferencesRepository(value: preferences),
            intelligence: RuleBasedIntelligenceService(),
            deviceCapabilities: FixtureDeviceCapabilityAssessor()
        )
    }
}

/// Fixture adapters intentionally avoid every macOS integration point. They
/// keep screenshot and launch-smoke runs deterministic without touching audio,
/// Accessibility, pasteboard, TCC, login items, or disk.
private actor FixtureSpeechTranscriber: SpeechTranscribing {
    func availableInputDevices() async -> [AudioInputDevice] {
        [AudioInputDevice(uid: "fixture-input", name: "Fixture Microphone", isDefault: true)]
    }

    func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        muteOtherAudio: Bool,
        saveAudio: Bool,
        vocabulary: [SpeechVocabularyTerm],
        detectSpeechEndpoint: Bool
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.availability("Fixture speech adapter"))
        }
    }

    func stop() async throws -> SpeechTranscription {
        SpeechTranscription(
            rawText: "这是一段用于视觉回归的合成口述。",
            localeIdentifier: "zh_CN",
            duration: 1
        )
    }

    func cancel() async {}
}

private struct FixtureMicrophoneLevelTester: MicrophoneLevelTesting {
    func availableInputDevices() async -> [AudioInputDevice] {
        [AudioInputDevice(uid: "fixture-input", name: "Fixture Microphone", isDefault: true)]
    }

    func start(microphoneDeviceUID: String?) async throws -> MicrophoneLevelTestSession {
        let stream = AsyncThrowingStream<Float, any Error> { continuation in
            continuation.yield(0.36)
            continuation.finish()
        }
        return MicrophoneLevelTestSession(id: UUID(), levels: stream)
    }

    func stop(sessionID: UUID) async {}
}

private struct FixtureContextCapture: ContextCapturing {
    func captureCurrentContext() async -> CapturedContext {
        CapturedContext(
            applicationName: "Fixture App",
            bundleIdentifier: "app.lerro.mac.fixture",
            windowTitle: "Visual Regression Fixture",
            selectionState: .knownEmpty,
            role: "AXTextArea"
        )
    }
}

private struct FixtureTextDeliverer: TextDelivering {
    func deliver(
        _ text: String,
        to context: CapturedContext,
        replacingSelection: Bool,
        targetPolicy: TextDeliveryTargetPolicy,
        onCommit: @escaping TextDeliveryCommitHandler
    ) async throws -> TextDeliveryReceipt {
        await onCommit()
        return TextDeliveryReceipt(
            context: context,
            focusedValueFingerprint: text.hashValue,
            focusedElementFingerprint: context.hashValue
        )
    }

}

private actor FixtureRecoveryTextCopier: RecoveryTextCopying {
    func copyForRecovery(_ text: String) async throws {}
}

private actor FixtureDeliveredTextObserver: DeliveredTextObserving {
    func observe(
        text: String,
        receipt: TextDeliveryReceipt,
        timeout: Duration
    ) async throws -> AsyncThrowingStream<DeliveredTextEdit, any Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func stopObserving() async {}
}

private struct FixtureApplicationCatalog: ApplicationCataloging {
    func applications() async -> [ApplicationDescriptor] {
        [
            ApplicationDescriptor(
                bundleIdentifier: "com.apple.mail",
                name: "Mail",
                isRunning: true
            ),
            ApplicationDescriptor(
                bundleIdentifier: "com.openai.chat",
                name: "ChatGPT",
                isRunning: true
            ),
        ]
    }
}

private final class FixtureHotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    func start(handler: @escaping @Sendable (HotkeyTrigger) -> Void) throws {}
    func update(definitions: [HotkeyDefinition]) {}
    func resetTransientState() {}
    func stop() {}
}

private struct FixturePermissionChecker: PermissionChecking {
    func microphoneAuthorized() async -> Bool { true }
    func requestMicrophone() async -> Bool { true }
    func accessibilityAuthorized(prompt: Bool) -> Bool { true }
}

private struct FixtureLoginItemManager: LoginItemManaging {
    func isEnabled() -> Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

private struct FixtureApplicationIdentityMonitor: ApplicationIdentityMonitoring {
    func legacyApplicationIsRunning() -> Bool { false }
}

private struct FixtureDeviceCapabilityAssessor: DeviceCapabilityAssessing {
    func snapshot() -> DeviceCapabilitySnapshot {
        DeviceCapabilitySnapshot(
            chipName: "Apple M4",
            isAppleSilicon: true,
            supportsMetal: true,
            physicalMemoryBytes: 24 * 1_024 * 1_024 * 1_024,
            availableStorageBytes: 80 * 1_024 * 1_024 * 1_024
        )
    }
}
