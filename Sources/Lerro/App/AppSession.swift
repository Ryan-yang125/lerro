import AppKit
import Foundation
import Observation
import SwiftUI
import LerroCore
import LerroMac

@MainActor
@Observable
final class AppSession {
    static let syntheticDeliveryProbeText = "Lerro delivery probe 7F3C2A"
    static let deliveryProbeArgument = "--lerro-delivery-probe-token"
    static let deliveryProbeNotificationPrefix = "app.lerro.mac.delivery-probe."

    struct DeliveryProbeConfiguration: Equatable {
        var payload: String
        var notificationName: Notification.Name
    }

    var destination: SidebarDestination = .home
    var phase: CapturePhase = .idle
    var activeMode: CaptureMode = .dictation
    var partialTranscript = ""
    var audioLevel: Float = 0
    var captureElapsed: TimeInterval = 0
    var isHandsFreeCapture = false
    private(set) var isHUDSuppressed = false
    private(set) var captureError: String?
    var currentError: String?
    var lastResult = ""
    var answerText: String?
    var answerQuestion = ""
    private(set) var historyEntries: [HistoryEntry] = []
    private(set) var historyTotalCount = 0
    private(set) var historyHasMore = false
    private(set) var isLoadingHistoryPage = false
    private(set) var historyListRevision: UInt64 = 0
    var dictionaryEntries: [DictionaryEntry] = []
    var audioInputDevices: [AudioInputDevice] = []
    var preferences = UserPreferences()
    var usage = UsageSummary()
    var modelStatus = LocalModelStatus(
        state: .unavailable,
        modelIdentifier: "",
        message: "正在检查本地模型"
    )
    var isModelDownloadConsentPresented = false
    var visualFixturePresentation: String?
    var isPanelOnlyVisualFixture = false
    var visualFixtureReduceMotion = false
    var visualFixtureIncreaseContrast = false
    var visualFixtureReduceTransparency = false
    var isSettingsPresented = false
    var settingsDestination: SettingsDestination = .settings
    var isOnboardingPresented = false
    var historySearch = ""
    var historyModeFilter: CaptureMode?
    var dictionarySearch = ""
    var dictionarySourceFilter: DictionaryEntrySource?
    var isStarted = false
    var microphonePermission = false
    var accessibilityPermission = false
    private(set) var speechResourceStatus = LanguageResourceStatus(
        state: .available,
        sourceLanguageIdentifier: "zh_CN",
        message: "正在检查语音资源"
    )
    private(set) var translationResourceStatus = LanguageResourceStatus(
        state: .available,
        sourceLanguageIdentifier: "zh_CN",
        targetLanguageIdentifier: "en_US",
        message: "正在检查翻译资源"
    )
    private(set) var translationPreparationRequestID: UUID?
    private(set) var translationPreparationSourceLanguageIdentifier = "zh_CN"
    private(set) var translationPreparationTargetLanguageIdentifier = "en_US"
    var onboardingMicrophoneLevel: Float = 0
    var isOnboardingMicrophoneTestRunning = false
    var onboardingMicrophoneTestPassed = false
    var onboardingMicrophoneTestError: String?

    var activeToneProfileApplicationName: String? {
        activeSession?.toneProfileApplicationName
    }

    var preferredDictationActivation: ShortcutActivation {
        preferences.hotkeys.first(where: { $0.action == .dictate })?.activation.resolved ?? .hold
    }

    func preferredActivation(for mode: CaptureMode) -> ShortcutActivation {
        let action: HotkeyAction = switch mode {
        case .dictation: .dictate
        case .translation: .translate
        case .ask: .ask
        }
        return preferences.hotkeys.first(where: { $0.action == action })?.activation.resolved ?? .hold
    }

    var shortcutConfigurationAvailable: Bool {
        !hasActiveCapture && !isCleaningCapture
    }

    private let dependencies: AppDependencies
    private let presentsFloatingPanels: Bool
    private let audioFileStore: AppSessionAudioFileStore?
    private let hudController = FloatingPanelController(role: .passiveHUD)
    private let answerController = FloatingPanelController(role: .interactiveCard)
    private var activeSession: CaptureSession?
    private var answerContext: CapturedContext?
    private var eventTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var captureGeneration: UUID?
    private var committedTextDeliverySessionID: UUID?
    private(set) var isStartingCapture = false
    private var isCleaningCapture = false
    private var modelLoadTask: Task<Void, Never>?
    private var captureTimerTask: Task<Void, Never>?
    private var microphoneTestTask: Task<Void, Never>?
    private var speechPreparationTask: Task<Void, Never>?
    private var speechPreparationRequestID: UUID?
    private var languageResourceRefreshRequestID = UUID()
    private var microphoneTestGeneration: UUID?
    private var microphoneTestSessionID: UUID?
    private var preferenceSaveQueue = PreferenceSaveQueue(confirmed: UserPreferences())
    private var preferenceSaveTask: Task<Void, Never>?
    private var preferenceSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastAppliedSystemPreferences: UserPreferences?
    private var pendingModelCaptureMode: CaptureMode?
    private var pendingRetentionApplication: HistoryRetention?
    private var historyUsageEntries: [HistoryEntry] = []
    private var historyPageGeneration = UUID()
    private var historyUsageGeneration = UUID()
    private var loadedHistorySearch: String?
    private var loadedHistoryMode: CaptureMode?
    private var hasLoadedHistoryPage = false
    private let historyPageSize = 50
    private var deliveryProbeObserver: NSObjectProtocol?
    private struct HotkeyCaptureOrigin {
        var definitionID: String?
        var mode: CaptureMode
    }
    private struct PendingCaptureHotkey {
        var trigger: HotkeyTrigger
        var mode: CaptureMode
    }
    private struct QueuedHotkeyTrigger: Sendable {
        let trigger: HotkeyTrigger
        let dispatchEpoch: UInt64
    }
    private var activeHotkeyOrigin: HotkeyCaptureOrigin?
    private var pendingHotkeysAfterCancellation: [PendingCaptureHotkey] = []
    private var hotkeyTriggerContinuation: AsyncStream<QueuedHotkeyTrigger>.Continuation?
    private var hotkeyTriggerTask: Task<Void, Never>?
    private var hotkeyDispatchEpoch: UInt64 = 0
    private var isShortcutConfigurationActive = false
    private var isHotkeyMonitorStarted = false

    init(
        dependencies: AppDependencies = .live(),
        presentsFloatingPanels: Bool = true
    ) {
        self.dependencies = dependencies
        self.presentsFloatingPanels = presentsFloatingPanels
        self.audioFileStore = dependencies.applicationPaths.map {
            AppSessionAudioFileStore(audioDirectory: $0.audioDirectory)
        }
    }

    var requiredPermissionsGranted: Bool {
        microphonePermission
            && accessibilityPermission
    }

    var canContinueWithBaseDictation: Bool {
        pendingModelCaptureMode == .dictation
    }

    private var hasActiveCapture: Bool {
        isStartingCapture
            || activeSession != nil
            || phase == .listening
            || phase == .transcribing
            || phase == .enhancing
            || phase == .inserting
    }

    var canModifyIntelligenceConfiguration: Bool {
        !hasActiveCapture
    }

    var isCaptureCancellationAvailable: Bool {
        switch phase {
        case .listening, .transcribing, .enhancing:
            true
        case .inserting:
            committedTextDeliverySessionID != activeSession?.id
        case .idle, .success, .failed, .cancelled:
            false
        }
    }

    func presentSettings(_ entryPoint: SettingsEntryPoint) {
        presentSettings(entryPoint.destination)
    }

    func presentSettings(_ destination: SettingsDestination) {
        settingsDestination = destination
        isOnboardingPresented = false
        isSettingsPresented = true
    }

    func dismissSettings() {
        endShortcutConfiguration()
        isSettingsPresented = false
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        if let startupStorageError = dependencies.startupStorageError {
            currentError = LerroError.localData(
                "应用目录准备失败：\(startupStorageError)"
            ).localizedDescription
            isOnboardingPresented = false
            return
        }
        do {
            preferences = try await dependencies.preferences.load()
        } catch {
            preferences = UserPreferences()
            currentError = "设置文件读取失败，已使用安全默认值。原文件保持不变：\(error.localizedDescription)"
        }
        preferenceSaveQueue.reset(confirmed: preferences)
        reconcileLoginItemAfterIdentityMigrationIfNeeded()
        let audioInputDevicesTask = Task { [dependencies] in
            await dependencies.microphoneTest.availableInputDevices()
        }
        do {
            try await applyRetentionAndClean(preferences.historyRetention, now: .now)
        } catch {
            currentError = userFacingError(error, context: "本地数据处理失败")
        }
        await refreshData()
        await refreshLanguageResources()
        audioInputDevices = await audioInputDevicesTask.value
        if let selectedUID = preferences.microphoneDeviceUID,
           !audioInputDevices.contains(where: { $0.uid == selectedUID }) {
            preferences.microphoneDeviceUID = nil
            savePreferences()
        }
        await reconcileOrphanedAudioFiles()
        await refreshPermissions(prompt: false)
        configureApplicationPresentation()
        lastAppliedSystemPreferences = preferences
        isOnboardingPresented = !preferences.hasCompletedOnboarding

        updateHUD()
        configureDeliveryProbeIfRequested()
        configureVisualFixtureIfRequested()
    }

    func refreshData() async {
        let dictionaryTask = Task { [dependencies] in
            try await dependencies.dictionary.entries()
        }
        let modelStatusTask = Task { [dependencies] in
            await dependencies.intelligence.modelStatus()
        }

        await refreshHistoryAndUsage()
        do {
            dictionaryEntries = try await dictionaryTask.value
        } catch {
            currentError = LerroError.localData(
                "词典读取失败：\(error.localizedDescription)"
            ).localizedDescription
        }
        updateUsageSummary()
        modelStatus = await modelStatusTask.value
    }

    func refreshLanguageResources(invalidatePreparations: Bool = false) async {
        let source = preferences.recognitionLocaleIdentifier
        let target = preferences.translationLanguageIdentifiers.first ?? "en_US"
        if invalidatePreparations {
            speechPreparationTask?.cancel()
            speechPreparationTask = nil
            speechPreparationRequestID = nil
            translationPreparationRequestID = nil
        }
        let requestID = UUID()
        languageResourceRefreshRequestID = requestID
        async let speech = dependencies.speech.resourceStatus(localeIdentifier: source)
        async let translation = dependencies.translation.resourceStatus(
            sourceLanguageIdentifier: source,
            targetLanguageIdentifier: target
        )
        let speechStatus = await speech
        let translationStatus = await translation
        guard languageResourceRefreshRequestID == requestID,
              preferences.recognitionLocaleIdentifier == source,
              (preferences.translationLanguageIdentifiers.first ?? "en_US") == target else { return }
        speechResourceStatus = speechStatus
        translationResourceStatus = translationStatus
    }

    func prepareSpeechResources() {
        let source = preferences.recognitionLocaleIdentifier
        languageResourceRefreshRequestID = UUID()
        speechPreparationTask?.cancel()
        let requestID = UUID()
        speechPreparationRequestID = requestID
        speechResourceStatus = LanguageResourceStatus(
            state: .downloading,
            sourceLanguageIdentifier: source,
            message: "正在准备语音资源"
        )
        speechPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let status = try await dependencies.speech.prepareResources(
                    localeIdentifier: source
                )
                guard speechPreparationRequestID == requestID,
                      preferences.recognitionLocaleIdentifier == source else { return }
                speechResourceStatus = status
            } catch {
                guard speechPreparationRequestID == requestID,
                      preferences.recognitionLocaleIdentifier == source else { return }
                speechResourceStatus = LanguageResourceStatus(
                    state: .failed,
                    sourceLanguageIdentifier: source,
                    message: userFacingError(error, context: "语音识别暂不可用")
                )
            }
            if speechPreparationRequestID == requestID {
                speechPreparationRequestID = nil
                speechPreparationTask = nil
            }
        }
    }

    func prepareTranslationResources() {
        let source = preferences.recognitionLocaleIdentifier
        let target = preferences.translationLanguageIdentifiers.first ?? "en_US"
        languageResourceRefreshRequestID = UUID()
        translationPreparationSourceLanguageIdentifier = source
        translationPreparationTargetLanguageIdentifier = target
        translationResourceStatus = LanguageResourceStatus(
            state: .downloading,
            sourceLanguageIdentifier: source,
            targetLanguageIdentifier: target,
            message: "正在准备翻译资源"
        )
        translationPreparationRequestID = UUID()
    }

    func completeTranslationResourcePreparation(
        requestID: UUID,
        errorMessage: String?
    ) {
        guard translationPreparationRequestID == requestID else { return }
        translationPreparationRequestID = nil
        guard preferences.recognitionLocaleIdentifier
                == translationPreparationSourceLanguageIdentifier,
              (preferences.translationLanguageIdentifiers.first ?? "en_US")
                == translationPreparationTargetLanguageIdentifier else { return }
        if let errorMessage {
            translationResourceStatus = LanguageResourceStatus(
                state: .failed,
                sourceLanguageIdentifier: translationPreparationSourceLanguageIdentifier,
                targetLanguageIdentifier: translationPreparationTargetLanguageIdentifier,
                message: errorMessage
            )
            return
        }
        Task { await refreshLanguageResources() }
    }

    func updateHistoryQuery(searchText: String, mode: CaptureMode?) async {
        historySearch = searchText
        historyModeFilter = mode
        let normalizedSearch = normalizedHistorySearch(searchText)
        guard !hasLoadedHistoryPage
                || normalizedSearch != loadedHistorySearch
                || mode != loadedHistoryMode else {
            return
        }
        await reloadHistory()
    }

    func reloadHistory() async {
        let generation = UUID()
        historyPageGeneration = generation
        isLoadingHistoryPage = true
        let searchText = normalizedHistorySearch(historySearch)
        let mode = historyModeFilter
        let request = HistoryPageRequest(
            offset: 0,
            limit: historyPageSize,
            searchText: searchText,
            mode: mode
        )

        do {
            let page = try await dependencies.history.page(request)
            guard historyPageGeneration == generation else { return }
            historyEntries = page.entries
            historyTotalCount = page.totalCount
            historyHasMore = page.hasMore
            loadedHistorySearch = searchText
            loadedHistoryMode = mode
            hasLoadedHistoryPage = true
            historyListRevision &+= 1
            isLoadingHistoryPage = false
        } catch {
            guard historyPageGeneration == generation else { return }
            historyEntries = []
            historyTotalCount = 0
            historyHasMore = false
            hasLoadedHistoryPage = false
            isLoadingHistoryPage = false
            currentError = LerroError.localData(
                "历史索引读取失败，录音目录保持不变：\(error.localizedDescription)"
            ).localizedDescription
        }
    }

    func loadNextHistoryPage() async {
        guard hasLoadedHistoryPage,
              historyHasMore,
              !isLoadingHistoryPage else {
            return
        }
        let generation = historyPageGeneration
        let searchText = loadedHistorySearch ?? normalizedHistorySearch(historySearch)
        let mode = loadedHistoryMode
        isLoadingHistoryPage = true
        let request = HistoryPageRequest(
            offset: historyEntries.count,
            limit: historyPageSize,
            searchText: searchText,
            mode: mode
        )

        do {
            let page = try await dependencies.history.page(request)
            guard historyPageGeneration == generation else { return }
            let existingIDs = Set(historyEntries.map(\.id))
            historyEntries.append(contentsOf: page.entries.filter { !existingIDs.contains($0.id) })
            historyTotalCount = page.totalCount
            historyHasMore = page.hasMore
            isLoadingHistoryPage = false
        } catch {
            guard historyPageGeneration == generation else { return }
            isLoadingHistoryPage = false
            currentError = LerroError.localData(
                "历史记录加载失败：\(error.localizedDescription)"
            ).localizedDescription
        }
    }

    func refreshAudioInputDevices() async {
        audioInputDevices = await dependencies.microphoneTest.availableInputDevices()
        if let selectedUID = preferences.microphoneDeviceUID,
           !audioInputDevices.contains(where: { $0.uid == selectedUID }) {
            preferences.microphoneDeviceUID = nil
            savePreferences()
        }
    }

    @discardableResult
    func addHotkey(
        for action: HotkeyAction,
        replacing existing: HotkeyDefinition? = nil,
        keyCode: Int64?,
        modifiers: UInt64,
        usesFunctionKey: Bool,
        activation: ShortcutActivation,
        displayName: String
    ) -> Bool {
        guard shortcutConfigurationAvailable else {
            currentError = "请先完成当前语音输入"
            return false
        }
        if existing == nil,
           preferences.hotkeys.filter({ $0.action == action }).count >= 4 {
            currentError = "每项功能最多设置四个快捷键"
            return false
        }
        let candidate = HotkeyDefinition(
            action: action,
            keyCode: keyCode,
            modifiers: modifiers,
            usesFunctionKey: usesFunctionKey,
            activation: activation.resolved,
            displayName: displayName
        )
        let conflict = preferences.hotkeys.contains {
            $0.id != existing?.id
                && $0.signature == candidate.signature
        }
        guard !conflict else {
            currentError = "这个快捷键已被使用"
            return false
        }
        if let existing,
           let index = preferences.hotkeys.firstIndex(where: { $0.id == existing.id }) {
            preferences.hotkeys[index] = candidate
        } else {
            preferences.hotkeys.append(candidate)
        }
        savePreferences()
        return true
    }

    @discardableResult
    func commitHotkey(
        for action: HotkeyAction,
        replacing existing: HotkeyDefinition? = nil,
        keyCode: Int64?,
        modifiers: UInt64,
        usesFunctionKey: Bool,
        activation: ShortcutActivation,
        displayName: String
    ) async -> Bool {
        let expectedDefinition = HotkeyDefinition(
            action: action,
            keyCode: keyCode,
            modifiers: modifiers,
            usesFunctionKey: usesFunctionKey,
            activation: activation.resolved,
            displayName: displayName
        )
        guard addHotkey(
            for: action,
            replacing: existing,
            keyCode: keyCode,
            modifiers: modifiers,
            usesFunctionKey: usesFunctionKey,
            activation: activation,
            displayName: displayName
        ) else { return false }
        let expectedActivation = activation.resolved
        await waitForPreferencePersistence()
        let confirmed = preferenceSaveQueue.confirmed.hotkeys.contains {
            $0.action == action
                && $0.signature == expectedDefinition.signature
                && $0.activation.resolved == expectedActivation
                && $0.displayName == displayName
        }
        guard confirmed else {
            if currentError == nil { currentError = "快捷键保存后未通过本地校验" }
            return false
        }
        return true
    }

    @discardableResult
    func beginShortcutConfiguration() -> Bool {
        guard shortcutConfigurationAvailable else {
            currentError = "请先完成当前语音输入"
            return false
        }
        guard !isShortcutConfigurationActive else { return true }
        isShortcutConfigurationActive = true
        stopHotkeyMonitoring()
        return true
    }

    func prepareShortcutConfigurationAfterCancellingCapture() async -> Bool {
        if hasActiveCapture {
            cancelCapture()
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while hasActiveCapture || isCleaningCapture {
            guard clock.now < deadline else {
                currentError = "语音输入仍在清理，请稍后再设置快捷键"
                return false
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return beginShortcutConfiguration()
    }

    func endShortcutConfiguration() {
        guard isShortcutConfigurationActive else { return }
        isShortcutConfigurationActive = false
        guard accessibilityPermission,
              !legacyApplicationIsRunning() else { return }
        configureHotkeys(reportError: false)
    }

    func removeHotkey(_ definition: HotkeyDefinition) {
        guard shortcutConfigurationAvailable else {
            currentError = "请先完成当前语音输入"
            return
        }
        let actionBindings = preferences.hotkeys.filter { $0.action == definition.action }
        guard actionBindings.count > 1 else {
            currentError = "每项功能至少保留一个快捷键"
            return
        }
        preferences.hotkeys.removeAll { $0.id == definition.id }
        savePreferences()
    }

    func refreshPermissions(prompt: Bool) async {
        microphonePermission = prompt
            ? await dependencies.permissions.requestMicrophone()
            : await dependencies.permissions.microphoneAuthorized()
        accessibilityPermission = dependencies.permissions.accessibilityAuthorized(prompt: prompt)
        if accessibilityPermission {
            if legacyApplicationIsRunning() {
                cancelCaptureBeforeStoppingHotkeysIfNeeded()
            } else {
                configureHotkeys(reportError: prompt)
            }
        } else {
            cancelCaptureBeforeStoppingHotkeysIfNeeded()
        }
        if !microphonePermission { stopOnboardingMicrophoneTest(resetResult: true) }
    }

    func applicationDidBecomeActive() async {
        guard isStarted, dependencies.startupStorageError == nil else { return }
        await refreshPermissions(prompt: false)
    }

    func toggleOnboardingMicrophoneTest() {
        if isOnboardingMicrophoneTestRunning {
            stopOnboardingMicrophoneTest()
        } else {
            startOnboardingMicrophoneTest()
        }
    }

    func startOnboardingMicrophoneTest() {
        guard phase == .idle || phase == .success || phase == .failed || phase == .cancelled else {
            onboardingMicrophoneTestError = "请先结束当前录音"
            return
        }
        let generation = UUID()
        let previousSessionID = microphoneTestSessionID
        microphoneTestGeneration = generation
        microphoneTestSessionID = nil
        microphoneTestTask?.cancel()
        onboardingMicrophoneLevel = 0
        onboardingMicrophoneTestPassed = false
        onboardingMicrophoneTestError = nil
        isOnboardingMicrophoneTestRunning = true

        microphoneTestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let previousSessionID {
                await dependencies.microphoneTest.stop(sessionID: previousSessionID)
            }

            microphonePermission = await dependencies.permissions.microphoneAuthorized()
            guard microphonePermission else {
                finishOnboardingMicrophoneTest(
                    generation: generation,
                    error: "请先开启麦克风权限"
                )
                return
            }

            do {
                let test = try await dependencies.microphoneTest.start(
                    microphoneDeviceUID: preferences.microphoneDeviceUID
                )
                guard microphoneTestGeneration == generation, !Task.isCancelled else {
                    await dependencies.microphoneTest.stop(sessionID: test.id)
                    return
                }
                microphoneTestSessionID = test.id

                do {
                    for try await rawLevel in test.levels {
                        guard microphoneTestGeneration == generation, !Task.isCancelled else { break }
                        let level = min(1, max(0, rawLevel))
                        onboardingMicrophoneLevel = level
                        if level >= 0.12 { onboardingMicrophoneTestPassed = true }
                    }
                } catch is CancellationError {
                    // Expected when the user leaves the microphone-test page.
                } catch {
                    onboardingMicrophoneTestError = userFacingError(error, context: "麦克风测试错误")
                }

                await dependencies.microphoneTest.stop(sessionID: test.id)
                if microphoneTestGeneration == generation {
                    microphoneTestSessionID = nil
                    isOnboardingMicrophoneTestRunning = false
                }
            } catch is CancellationError {
                finishOnboardingMicrophoneTest(generation: generation)
            } catch {
                finishOnboardingMicrophoneTest(
                    generation: generation,
                    error: userFacingError(error, context: "麦克风测试错误")
                )
            }
        }
    }

    func stopOnboardingMicrophoneTest(resetResult: Bool = false) {
        let sessionID = microphoneTestSessionID
        microphoneTestGeneration = nil
        microphoneTestSessionID = nil
        microphoneTestTask?.cancel()
        microphoneTestTask = nil
        isOnboardingMicrophoneTestRunning = false
        onboardingMicrophoneLevel = 0
        if resetResult {
            onboardingMicrophoneTestPassed = false
            onboardingMicrophoneTestError = nil
        }
        if let sessionID {
            Task { [dependencies] in
                await dependencies.microphoneTest.stop(sessionID: sessionID)
            }
        }
    }

    private func finishOnboardingMicrophoneTest(generation: UUID, error: String? = nil) {
        guard microphoneTestGeneration == generation else { return }
        microphoneTestGeneration = nil
        microphoneTestSessionID = nil
        microphoneTestTask = nil
        isOnboardingMicrophoneTestRunning = false
        onboardingMicrophoneLevel = 0
        onboardingMicrophoneTestError = error
    }

    func toggleCapture(_ mode: CaptureMode) {
        guard !isCleaningCapture else { return }
        if isStartingCapture {
            guard activeMode == mode else { return }
            cancelCapture()
            return
        }

        switch phase {
        case .idle, .success, .failed, .cancelled:
            startCapture(mode, handsFree: false)
        case .listening:
            guard activeMode == mode else { return }
            requestFinishCapture()
        case .transcribing, .enhancing, .inserting:
            return
        }
    }

    func requestLocalModelPreparation() {
        guard preferences.hasApprovedModelDownload else {
            presentModelDownloadConsent(for: nil)
            return
        }
        prepareLocalModel()
    }

    func activateIntelligenceMode(_ mode: IntelligenceMode) {
        guard !hasActiveCapture else {
            currentError = "请在当前听写完成后切换智能处理方式"
            return
        }
        preferences.intelligenceMode = mode
        savePreferences()
        if mode == .local, preferences.hasApprovedModelDownload {
            prepareLocalModel()
        }
    }

    func saveRemoteProvider(_ configuration: RemoteProviderConfiguration) async -> Bool {
        guard !hasActiveCapture else {
            currentError = "请在当前听写完成后保存 API 模型配置"
            return false
        }
        let normalized = normalizedRemoteProvider(configuration)
        preferences.remoteProvider = normalized
        preferences.intelligenceMode = .remote
        savePreferences()
        await waitForPreferencePersistence()
        return preferenceSaveQueue.confirmed.remoteProvider == normalized
            && preferenceSaveQueue.confirmed.intelligenceMode == .remote
            && preferences.remoteProvider == normalized
            && preferences.intelligenceMode == .remote
    }

    func clearRemoteProviderAPIKey() async -> Bool {
        guard !hasActiveCapture else {
            currentError = "请在当前听写完成后清除 API Key"
            return false
        }
        preferences.remoteProvider.apiKey = ""
        if preferences.intelligenceMode == .remote {
            preferences.intelligenceMode = .raw
        }
        savePreferences()
        await waitForPreferencePersistence()
        return preferenceSaveQueue.confirmed.remoteProvider.apiKey.isEmpty
            && preferences.remoteProvider.apiKey.isEmpty
            && preferences.intelligenceMode != .remote
    }

    func testRemoteProviderConnection(
        _ configuration: RemoteProviderConfiguration
    ) async -> RemoteConnectionTestOutcome {
        guard !hasActiveCapture else {
            return .failure("请在当前听写完成后测试 API 连接")
        }
        do {
            return try await dependencies.intelligence.testRemoteConnection(
                configuration: normalizedRemoteProvider(configuration)
            )
        } catch is CancellationError {
            return .failure("连接测试已取消")
        } catch {
            return .failure(userFacingError(error, context: "远程模型暂不可用"))
        }
    }

    func approveLocalModelDownload() {
        pendingModelCaptureMode = nil
        isModelDownloadConsentPresented = false
        preferences.hasApprovedModelDownload = true
        preferences.intelligenceMode = .local
        savePreferences()
        presentSettings(SettingsDestination.intelligence)
        NSApp.activate(ignoringOtherApps: true)
        prepareLocalModel()
    }

    func continueWithBaseDictation() {
        guard pendingModelCaptureMode == .dictation else {
            cancelModelDownloadConsent()
            return
        }
        pendingModelCaptureMode = nil
        isModelDownloadConsentPresented = false
        preferences.intelligenceMode = .raw
        savePreferences()
        startCapture(.dictation, handsFree: false)
    }

    func cancelModelDownloadConsent() {
        pendingModelCaptureMode = nil
        isModelDownloadConsentPresented = false
    }

    func cancelCapture(resetHotkeyState: Bool = true) {
        guard hasActiveCapture else { return }
        if phase == .inserting,
           committedTextDeliverySessionID == activeSession?.id {
            return
        }

        captureGeneration = nil
        committedTextDeliverySessionID = nil
        activeHotkeyOrigin = nil
        pendingHotkeysAfterCancellation.removeAll()
        isStartingCapture = false
        isCleaningCapture = true
        activeSession = nil
        answerController.hide()
        answerText = nil
        answerQuestion = ""
        answerContext = nil
        captureError = nil
        isHUDSuppressed = false
        phase = .cancelled
        updateHUD()
        completionTask?.cancel()
        if resetHotkeyState {
            dependencies.hotkeys.resetTransientState()
        }
        completionTask = Task { [weak self] in
            guard let self else { return }
            await dependencies.speech.cancel()
            await dependencies.translation.cancel()
            await reconcileOrphanedAudioFiles()
            eventTask?.cancel()
            captureTimerTask?.cancel()
            isHandsFreeCapture = false
            // Let any already-enqueued release for a more specific shortcut
            // clear the pending upgrade before a new capture generation starts.
            try? await Task.sleep(for: .milliseconds(20))
            isCleaningCapture = false
            if !pendingHotkeysAfterCancellation.isEmpty {
                let pending = pendingHotkeysAfterCancellation
                pendingHotkeysAfterCancellation.removeAll()
                phase = .idle
                partialTranscript = ""
                captureElapsed = 0
                updateHUD()
                for entry in pending {
                    handleCaptureHotkey(entry.trigger, mode: entry.mode)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard captureGeneration == nil, activeSession == nil, phase == .cancelled else { return }
            phase = .idle
            partialTranscript = ""
            captureElapsed = 0
            updateHUD()
        }
    }

    func pasteLastResult() {
        let result = lastResult
        guard !result.isEmpty else { return }
        Task { [weak self, result] in
            guard let self else { return }
            let context = await dependencies.context.captureCurrentContext()
            do {
                guard CapturePrivacyPolicy.permitsCapture(in: context) else {
                    throw LerroError.secureField
                }
                try await dependencies.textDelivery.deliver(
                    result,
                    to: context,
                    replacingSelection: false,
                    targetPolicy: .requireCurrent
                )
            } catch {
                currentError = userFacingError(error, context: "文本写入失败")
            }
        }
    }

    func savePreferences() {
        let previous = preferenceSaveQueue.queued
            ?? preferenceSaveQueue.inFlight
            ?? preferenceSaveQueue.confirmed
        savePreferences(from: previous, to: preferences)
    }

    func savePreferences(
        from previous: UserPreferences,
        to updated: UserPreferences
    ) {
        let snapshot = preferences == updated ? updated : preferences
        let systemBaseline = lastAppliedSystemPreferences ?? previous
        applySystemPreferenceChanges(from: systemBaseline, to: snapshot)
        lastAppliedSystemPreferences = snapshot
        guard let snapshot = preferenceSaveQueue.enqueue(snapshot) else { return }
        persistPreferences(snapshot)
    }

    func completeOnboarding() {
        stopOnboardingMicrophoneTest(resetResult: true)
        preferences.hasCompletedOnboarding = true
        preferences.onboardingStepIndex = nil
        isOnboardingPresented = false
        savePreferences()
    }

    func restartOnboarding() {
        stopOnboardingMicrophoneTest(resetResult: true)
        preferences.hasCompletedOnboarding = false
        preferences.onboardingStepIndex = nil
        dismissSettings()
        isOnboardingPresented = true
        savePreferences()
    }

    private func persistPreferences(_ snapshot: UserPreferences) {
        preferenceSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let changes = PreferenceSystemChanges(
                    from: preferenceSaveQueue.confirmed,
                    to: snapshot
                )
                if changes.loginItem,
                   dependencies.loginItem.isEnabled() != snapshot.launchAtLogin {
                    try dependencies.loginItem.setEnabled(snapshot.launchAtLogin)
                }
                try await dependencies.preferences.save(snapshot)
                let next = preferenceSaveQueue.didSave(snapshot)
                if pendingRetentionApplication == snapshot.historyRetention {
                    pendingRetentionApplication = nil
                    do {
                        try await applyRetentionAndClean(snapshot.historyRetention, now: .now)
                        await refreshHistoryAndUsage()
                    } catch {
                        currentError = userFacingError(error, context: "本地数据处理失败")
                    }
                }
                if let next {
                    persistPreferences(next)
                } else {
                    preferenceSaveTask = nil
                    resumePreferenceSaveWaiters()
                }
            } catch {
                preferenceSaveTask = nil
                guard let rollback = preferenceSaveQueue.didFail(snapshot) else {
                    resumePreferenceSaveWaiters()
                    return
                }
                if pendingRetentionApplication == snapshot.historyRetention {
                    pendingRetentionApplication = nil
                }
                let previous = preferences
                preferences = rollback
                let systemBaseline = lastAppliedSystemPreferences ?? previous
                applySystemPreferenceChanges(from: systemBaseline, to: rollback)
                lastAppliedSystemPreferences = rollback
                var loginItemRollbackError: String?
                if dependencies.loginItem.isEnabled() != rollback.launchAtLogin {
                    do {
                        try dependencies.loginItem.setEnabled(rollback.launchAtLogin)
                    } catch {
                        loginItemRollbackError = error.localizedDescription
                    }
                }
                currentError = if let loginItemRollbackError {
                    "设置保存失败：\(error.localizedDescription)；登录启动状态恢复失败：\(loginItemRollbackError)"
                } else {
                    "设置保存失败：\(error.localizedDescription)"
                }
                resumePreferenceSaveWaiters()
            }
        }
    }

    private func waitForPreferencePersistence() async {
        guard preferenceSaveTask != nil || preferenceSaveQueue.inFlight != nil else { return }
        await withCheckedContinuation { continuation in
            preferenceSaveWaiters.append(continuation)
        }
    }

    private func resumePreferenceSaveWaiters() {
        let waiters = preferenceSaveWaiters
        preferenceSaveWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func prepareLocalModel() {
        guard dependencies.startupStorageError == nil else {
            currentError = "本地数据目录尚未准备完成"
            return
        }
        guard preferences.hasApprovedModelDownload else {
            presentModelDownloadConsent(for: nil)
            return
        }
        guard modelLoadTask == nil else { return }
        currentError = nil
        modelLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let monitor = startModelStatusMonitor()

            defer {
                monitor.cancel()
                self.modelLoadTask = nil
            }

            do {
                try await dependencies.intelligence.prepare(
                    modelIdentifier: preferences.localModelIdentifier
                )
            } catch is CancellationError {
                return
            } catch {
                currentError = userFacingError(error, context: "本地模型暂不可用")
            }
            modelStatus = await dependencies.intelligence.modelStatus()
        }
    }

    @discardableResult
    func saveDictionaryEntry(_ entry: DictionaryEntry) async -> Bool {
        do {
            try await dependencies.dictionary.save(entry)
            await refreshDictionaryAndUsage()
            return true
        } catch {
            currentError = "词典保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func deleteDictionaryEntry(_ entry: DictionaryEntry) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await dependencies.dictionary.delete(id: entry.id)
                await refreshDictionaryAndUsage()
            } catch {
                currentError = "词条删除失败：\(error.localizedDescription)"
            }
        }
    }

    func saveAppToneProfile(
        _ profile: AppToneProfile,
        replacingBundleIdentifier: String? = nil
    ) {
        let bundleIdentifier = profile.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let applicationName = profile.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = profile.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty, !applicationName.isEmpty, !instruction.isEmpty else { return }
        let normalized = AppToneProfile(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            instruction: instruction,
            enabled: profile.enabled
        )
        if let replacingBundleIdentifier, replacingBundleIdentifier != bundleIdentifier {
            preferences.appToneProfiles.removeAll { $0.bundleIdentifier == replacingBundleIdentifier }
        }
        if let index = preferences.appToneProfiles.firstIndex(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            preferences.appToneProfiles[index] = normalized
        } else {
            preferences.appToneProfiles.append(normalized)
            preferences.appToneProfiles.sort {
                $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
            }
        }
        savePreferences()
    }

    func deleteAppToneProfile(_ profile: AppToneProfile) {
        preferences.appToneProfiles.removeAll { $0.bundleIdentifier == profile.bundleIdentifier }
        savePreferences()
    }

    @discardableResult
    func saveHistoryCorrection(
        _ entry: HistoryEntry,
        correctedText: String,
        phrase: String,
        replacement: String
    ) async -> Bool {
        let corrected = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { return false }
        do {
            var updated = entry
            updated.finalText = corrected
            updated.answerText = entry.mode == .ask ? corrected : entry.answerText
            try await dependencies.history.save(updated)

            let source = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty, !target.isEmpty, source != target {
                var learned = dictionaryEntries.first {
                    $0.source == .learned
                        && $0.phrase.caseInsensitiveCompare(source) == .orderedSame
                        && $0.applicationBundleIdentifier == entry.bundleIdentifier
                } ?? DictionaryEntry(
                    phrase: source,
                    replacement: target,
                    source: .learned,
                    applicationBundleIdentifier: entry.bundleIdentifier
                )
                learned.replacement = target
                learned.updatedAt = .now
                try await dependencies.dictionary.save(learned)
            }
            await refreshHistoryAndUsage()
            await refreshDictionaryAndUsage()
            return true
        } catch {
            currentError = "修正保存失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func importDictionaryCSV(_ contents: String) async -> Bool {
        do {
            let entries = try DictionaryCSVParser.parse(contents)
            try await dependencies.dictionary.importEntries(entries)
            await refreshDictionaryAndUsage()
            return true
        } catch {
            currentError = "词典导入失败：\(error.localizedDescription)"
            return false
        }
    }

    func deleteHistoryEntry(_ entry: HistoryEntry) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await deleteAudioFile(relativePath: entry.audioRelativePath)
                try await dependencies.history.delete(id: entry.id)
            } catch {
                currentError = userFacingError(error, context: "本地数据处理失败")
            }
            await refreshHistoryAndUsage()
        }
    }

    func deleteAllHistory() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let allEntries = try await dependencies.history.entries()
                try await deleteAudioFiles(relativePaths: allEntries.map(\.audioRelativePath))
                try await dependencies.history.deleteAll()
            } catch {
                currentError = userFacingError(error, context: "本地数据处理失败")
            }
            await refreshHistoryAndUsage()
        }
    }

    func setHistoryRetention(_ retention: HistoryRetention) {
        preferences.historyRetention = retention
        pendingRetentionApplication = retention
        savePreferences()
    }

    func showHistoryAnswer(_ entry: HistoryEntry) {
        guard let answer = entry.answerText, !answer.isEmpty else { return }
        answerQuestion = entry.rawText
        answerText = answer
        answerContext = nil
        showAnswerPanel()
    }

    func retryHistoryEntry(_ entry: HistoryEntry) {
        guard !entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            currentError = "这条记录没有可重试的转写文本"
            return
        }
        if entry.mode == .translation {
            guard let targetLanguage = entry.targetLanguage else {
                currentError = "这条翻译记录缺少目标语言"
                return
            }
            let sourceLanguage = entry.sourceLanguage ?? preferences.recognitionLocaleIdentifier
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let text = try await dependencies.translation.translate(
                        entry.rawText,
                        sourceLanguageIdentifier: sourceLanguage,
                        targetLanguageIdentifier: targetLanguage
                    )
                    var updated = entry
                    updated.finalText = text
                    updated.status = .completed
                    updated.wasEnhanced = false
                    try await dependencies.history.save(updated)
                    await refreshHistoryAndUsage()
                } catch {
                    currentError = userFacingError(error, context: "设备端翻译暂不可用")
                }
            }
            return
        }
        guard preferences.intelligenceMode != .raw else {
            currentError = "请先在“智能处理”中选择本地 AI 或 API 模型"
            return
        }
        guard authorizeIntelligenceIfNeeded(for: entry.mode) else {
            return
        }
        let intelligenceMode = preferences.intelligenceMode
        let remoteProvider = intelligenceMode == .remote
            ? normalizedRemoteProvider(preferences.remoteProvider)
            : nil
        Task { [weak self] in
            guard let self else { return }
            let context = CapturedContext(
                applicationName: entry.applicationName,
                bundleIdentifier: entry.bundleIdentifier,
                windowTitle: entry.windowTitle
            )
            let task = intelligenceTask(mode: entry.mode, transcript: entry.rawText, context: context)
            let request = IntelligenceRequest(
                task: task,
                mode: intelligenceMode,
                remoteProvider: remoteProvider,
                transcript: entry.rawText,
                targetLanguage: entry.targetLanguage,
                context: context,
                dictionary: dictionaryEntries.filter { !$0.isSnippet },
                toneInstruction: preferences.appToneProfiles.first {
                    $0.enabled && $0.bundleIdentifier == entry.bundleIdentifier
                }?.instruction
            )
            let monitor = intelligenceMode == .local ? startModelStatusMonitor() : nil
            defer { monitor?.cancel() }
            do {
                let result = try await dependencies.intelligence.process(request)
                var updated = entry
                updated.finalText = result.text
                updated.answerText = entry.mode == .ask ? result.text : nil
                updated.status = .completed
                updated.wasEnhanced = result.source != .raw
                try await dependencies.history.save(updated)
                await refreshHistoryAndUsage()
                if updated.mode == .ask { showHistoryAnswer(updated) }
            } catch {
                currentError = userFacingError(error, context: "智能处理失败")
            }
        }
    }

    func exportAudio(_ entry: HistoryEntry) {
        guard let sourceURL = audioFileURL(relativePath: entry.audioRelativePath),
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            currentError = "这条记录没有可下载的音频"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Lerro-\(entry.id.uuidString.prefix(8)).caf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            currentError = userFacingError(error, context: "音频导出失败")
        }
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func closeAnswer() {
        answerText = nil
        answerQuestion = ""
        answerContext = nil
        answerController.hide()
    }

    func resizeAnswerPanel(contentHeight: CGFloat) {
        guard answerText != nil else { return }
        answerController.resize(
            to: CGSize(width: 800, height: min(800, max(420, contentHeight))),
            animated: true
        )
    }

    func insertAnswer() {
        guard let answerText, let answerContext else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await dependencies.textDelivery.deliver(
                    answerText,
                    to: answerContext,
                    replacingSelection: false,
                    targetPolicy: .reactivateCaptured
                )
                await MainActor.run { self.closeAnswer() }
            } catch {
                await MainActor.run {
                    self.currentError = self.userFacingError(error, context: "文本写入失败")
                }
            }
        }
    }

    private func configureHotkeys(reportError: Bool) {
        guard !isShortcutConfigurationActive else { return }
        dependencies.hotkeys.update(definitions: preferences.hotkeys)
        guard !isHotkeyMonitorStarted else { return }
        let continuation = ensureHotkeyTriggerConsumer()
        hotkeyDispatchEpoch &+= 1
        let dispatchEpoch = hotkeyDispatchEpoch
        do {
            try dependencies.hotkeys.start { trigger in
                _ = continuation.yield(QueuedHotkeyTrigger(
                    trigger: trigger,
                    dispatchEpoch: dispatchEpoch
                ))
            }
            isHotkeyMonitorStarted = true
        } catch {
            hotkeyDispatchEpoch &+= 1
            isHotkeyMonitorStarted = false
            if reportError {
                currentError = userFacingError(error, context: "快捷键服务启动失败")
            }
        }
    }

    private func stopHotkeyMonitoring() {
        hotkeyDispatchEpoch &+= 1
        dependencies.hotkeys.stop()
        isHotkeyMonitorStarted = false
    }

    private func cancelCaptureBeforeStoppingHotkeysIfNeeded() {
        if hasActiveCapture {
            cancelCapture(resetHotkeyState: false)
        }
        stopHotkeyMonitoring()
    }

    private func ensureHotkeyTriggerConsumer() -> AsyncStream<QueuedHotkeyTrigger>.Continuation {
        if let hotkeyTriggerContinuation { return hotkeyTriggerContinuation }
        let pair = AsyncStream<QueuedHotkeyTrigger>.makeStream(
            bufferingPolicy: .unbounded
        )
        hotkeyTriggerContinuation = pair.continuation
        hotkeyTriggerTask = Task { @MainActor [weak self] in
            for await queued in pair.stream {
                guard let self, !Task.isCancelled else { return }
                guard queued.dispatchEpoch == self.hotkeyDispatchEpoch,
                      !self.isShortcutConfigurationActive,
                      self.isCurrentHotkeyTrigger(queued.trigger) else { continue }
                self.handleHotkey(queued.trigger)
            }
        }
        return pair.continuation
    }

    private func isCurrentHotkeyTrigger(_ trigger: HotkeyTrigger) -> Bool {
        if trigger.action == .cancel { return true }
        guard let definitionID = trigger.definitionID else { return false }
        return preferences.hotkeys.contains { definition in
            definition.action == trigger.action
                && definition.activation.resolved == trigger.activation.resolved
                && (definition.id == definitionID
                    || runtimeHotkeyDefinitionID(definition) == definitionID)
        }
    }

    private func runtimeHotkeyDefinitionID(_ saved: HotkeyDefinition) -> String {
        var definition = saved
        if definition.usesFunctionKey {
            definition.modifiers |= 1 << 23
        }
        if let modifier = Self.modifierFlag(forLegacyKeyCode: definition.keyCode) {
            definition.keyCode = nil
            definition.modifiers |= modifier
        }
        definition.activation = definition.activation.resolved
        return definition.id
    }

    private static func modifierFlag(forLegacyKeyCode keyCode: Int64?) -> UInt64? {
        switch keyCode {
        case 54, 55: 1 << 20
        case 56, 60: 1 << 17
        case 58, 61: 1 << 19
        case 59, 62: 1 << 18
        case 63: 1 << 23
        default: nil
        }
    }

    func handleHotkey(_ trigger: HotkeyTrigger) {
        guard !isShortcutConfigurationActive else { return }
        switch trigger.action {
        case .dictate:
            handleCaptureHotkey(trigger, mode: .dictation)
        case .translate:
            handleCaptureHotkey(trigger, mode: .translation)
        case .ask:
            handleCaptureHotkey(trigger, mode: .ask)
        case .dictateHandsFree:
            handleLegacyHandsFreeHotkey(trigger, mode: .dictation, action: .dictate)
        case .translateHandsFree:
            handleLegacyHandsFreeHotkey(trigger, mode: .translation, action: .translate)
        case .askHandsFree:
            handleLegacyHandsFreeHotkey(trigger, mode: .ask, action: .ask)
        case .pasteLastResult:
            if trigger.phase == .began { pasteLastResult() }
        case .cancel:
            guard trigger.phase == .began else { return }
            if isCleaningCapture {
                pendingHotkeysAfterCancellation.removeAll()
                return
            }
            if hasActiveCapture {
                cancelCapture(resetHotkeyState: false)
            } else if answerText != nil {
                closeAnswer()
            }
        }
    }

    private func handleLegacyHandsFreeHotkey(
        _ trigger: HotkeyTrigger,
        mode: CaptureMode,
        action: HotkeyAction
    ) {
        handleCaptureHotkey(
            HotkeyTrigger(
                action: action,
                activation: .toggle,
                phase: trigger.phase,
                definitionID: trigger.definitionID
            ),
            mode: mode
        )
    }

    private func handleCaptureHotkey(_ trigger: HotkeyTrigger, mode: CaptureMode) {
        if isCleaningCapture {
            reducePendingHotkeyAfterCancellation(trigger, mode: mode)
            return
        }

        switch trigger.activation.resolved {
        case .hold:
            switch trigger.phase {
            case .began:
                if hasActiveCapture {
                    guard activeMode == mode, isHandsFreeCapture else { return }
                    activeHotkeyOrigin = nil
                    toggleCapture(mode)
                    return
                }
                guard phase == .idle || phase == .success || phase == .failed || phase == .cancelled else {
                    return
                }
                activeHotkeyOrigin = HotkeyCaptureOrigin(
                    definitionID: trigger.definitionID,
                    mode: mode
                )
                startCapture(mode, handsFree: false)
                if !hasActiveCapture { activeHotkeyOrigin = nil }
            case .ended:
                guard let origin = activeHotkeyOrigin,
                      origin.definitionID == trigger.definitionID,
                      origin.mode == mode,
                      activeMode == mode else { return }
                activeHotkeyOrigin = nil
                if isStartingCapture || phase == .listening {
                    toggleCapture(mode)
                }
            }
        case .toggle, .press, .doublePress:
            guard trigger.phase == .began else { return }
            if hasActiveCapture {
                guard activeMode == mode else { return }
                activeHotkeyOrigin = nil
                toggleCapture(mode)
                return
            }
            if phase == .idle || phase == .success || phase == .failed || phase == .cancelled {
                activeHotkeyOrigin = nil
                startCapture(mode, handsFree: true)
                return
            }
        }
    }

    private func reducePendingHotkeyAfterCancellation(
        _ trigger: HotkeyTrigger,
        mode: CaptureMode
    ) {
        switch trigger.activation.resolved {
        case .hold:
            switch trigger.phase {
            case .began:
                let alreadyQueued = pendingHotkeysAfterCancellation.contains {
                    $0.mode == mode
                        && $0.trigger.action == trigger.action
                        && $0.trigger.activation.resolved == .hold
                        && $0.trigger.definitionID == trigger.definitionID
                }
                if !alreadyQueued {
                    pendingHotkeysAfterCancellation.append(PendingCaptureHotkey(
                        trigger: trigger,
                        mode: mode
                    ))
                }
            case .ended:
                pendingHotkeysAfterCancellation.removeAll {
                    $0.mode == mode
                        && $0.trigger.action == trigger.action
                        && $0.trigger.activation.resolved == .hold
                        && $0.trigger.definitionID == trigger.definitionID
                }
            }
        case .toggle, .press, .doublePress:
            guard trigger.phase == .began else { return }
            if let index = pendingHotkeysAfterCancellation.firstIndex(where: {
                $0.mode == mode
                    && $0.trigger.action == trigger.action
                    && $0.trigger.activation.resolved == .toggle
            }) {
                pendingHotkeysAfterCancellation.remove(at: index)
            } else {
                pendingHotkeysAfterCancellation.append(PendingCaptureHotkey(
                    trigger: trigger,
                    mode: mode
                ))
            }
        }
    }

    func enterHandsFreeCapture(_ mode: CaptureMode) {
        guard !isCleaningCapture else { return }
        if isStartingCapture, activeMode == mode {
            activeHotkeyOrigin = nil
            isHandsFreeCapture = true
            updateHUD()
            return
        }
        if phase == .listening, activeMode == mode {
            activeHotkeyOrigin = nil
            isHandsFreeCapture = true
            updateHUD()
            return
        }
        guard phase == .idle || phase == .success || phase == .failed || phase == .cancelled else {
            return
        }
        startCapture(mode, handsFree: true)
    }

    private func startCapture(_ mode: CaptureMode, handsFree: Bool) {
        guard !isShortcutConfigurationActive else {
            currentError = "快捷键测试期间不会开始录音"
            return
        }
        guard dependencies.startupStorageError == nil else {
            currentError = "本地数据目录尚未准备完成"
            return
        }
        guard !legacyApplicationIsRunning() else { return }
        guard !isCleaningCapture else { return }
        guard !hasActiveCapture else { return }
        guard mode == .translation || authorizeIntelligenceIfNeeded(for: mode) else { return }
        let intelligenceMode = preferences.intelligenceMode
        let remoteProvider = intelligenceMode == .remote
            ? normalizedRemoteProvider(preferences.remoteProvider)
            : nil
        let generation = UUID()
        captureGeneration = generation
        committedTextDeliverySessionID = nil
        activeMode = mode
        isHandsFreeCapture = handsFree
        isHUDSuppressed = false
        captureError = nil
        partialTranscript = ""
        audioLevel = 0
        captureElapsed = 0
        isStartingCapture = true
        updateHUD()
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            await self?.beginCapture(
                mode,
                generation: generation,
                intelligenceMode: intelligenceMode,
                remoteProvider: remoteProvider
            )
        }
    }

    private func beginCapture(
        _ mode: CaptureMode,
        generation: UUID,
        intelligenceMode: IntelligenceMode,
        remoteProvider: RemoteProviderConfiguration?
    ) async {
        stopOnboardingMicrophoneTest()
        answerController.hide()

        guard captureGeneration == generation, !Task.isCancelled else { return }
        guard await ensureCapturePermissions() else {
            if captureGeneration == generation {
                captureGeneration = nil
                activeHotkeyOrigin = nil
                isStartingCapture = false
                isHandsFreeCapture = false
            }
            return
        }
        guard captureGeneration == generation, !Task.isCancelled else { return }
        let context = await dependencies.context.captureCurrentContext()
        guard captureGeneration == generation, !Task.isCancelled else { return }
        guard CapturePrivacyPolicy.permitsCapture(in: context) else {
            fail(LerroError.secureField)
            return
        }
        let targetLanguage = mode == .translation ? preferences.translationLanguageIdentifiers.first : nil
        if mode == .translation, targetLanguage == nil {
            fail(LerroError.translationUnavailable("请先选择翻译目标语言"))
            return
        }

        do {
            let stream = try await dependencies.speech.start(
                localeIdentifier: preferences.recognitionLocaleIdentifier,
                microphoneDeviceUID: preferences.microphoneDeviceUID,
                muteOtherAudio: preferences.muteOtherAudio,
                saveAudio: preferences.shouldSaveCaptureAudio
            )
            guard captureGeneration == generation, !Task.isCancelled else {
                await dependencies.speech.cancel()
                return
            }
            let toneProfile = preferences.appToneProfiles.first {
                $0.enabled && $0.bundleIdentifier == context.bundleIdentifier
            }
            let session = CaptureSession(
                mode: mode,
                context: context,
                targetLanguage: targetLanguage,
                intelligenceMode: intelligenceMode,
                remoteProvider: remoteProvider,
                toneInstruction: toneProfile?.instruction,
                toneProfileApplicationName: toneProfile?.applicationName
            )
            activeSession = session
            isStartingCapture = false
            phase = .listening
            updateHUD()
            startCaptureTimer(for: session)
            eventTask?.cancel()
            eventTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await event in stream {
                        guard self.activeSession?.id == session.id else { return }
                        self.consumeSpeechEvent(event)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self.activeSession?.id == session.id else { return }
                    self.fail(error)
                }
            }
        } catch is CancellationError {
            if captureGeneration == generation {
                captureGeneration = nil
                activeHotkeyOrigin = nil
                isStartingCapture = false
                activeSession = nil
            }
        } catch {
            guard captureGeneration == generation else { return }
            fail(error)
        }
    }

    private func requestFinishCapture() {
        guard phase == .listening, activeSession != nil else { return }
        dependencies.hotkeys.resetTransientState()
        captureTimerTask?.cancel()
        captureTimerTask = nil
        // A stop gesture becomes visible in the same MainActor turn. The
        // listening -> transcribing transition also owns finalization, so the
        // recording timer and a physical stop gesture cannot stop Speech twice.
        phase = .transcribing
        audioLevel = 0
        updateHUD()
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            await self?.finishCapture()
        }
    }

    private func finishCapture() async {
        guard let session = activeSession else { return }
        var recordedAudioRelativePath: String?

        do {
            let transcription = try await dependencies.speech.stop()
            recordedAudioRelativePath = transcription.audioRelativePath
            guard activeSession?.id == session.id else {
                do {
                    try await deleteAudioFile(relativePath: recordedAudioRelativePath)
                } catch {
                    currentError = userFacingError(error, context: "本地数据处理失败")
                }
                return
            }
            partialTranscript = transcription.rawText
            phase = .enhancing
            updateHUD()
            try await complete(session: session, transcription: transcription)
        } catch {
            var reportedError: any Error = error
            if let recordedAudioRelativePath {
                let wasPersisted: Bool
                do {
                    wasPersisted = try await dependencies.history.entries()
                        .contains { $0.id == session.id }
                } catch {
                    wasPersisted = true
                    reportedError = LerroError.localData(
                        "无法确认录音索引状态，已保留文件等待下次对账：\(error.localizedDescription)"
                    )
                }
                if !wasPersisted {
                    do {
                        try await deleteAudioFile(relativePath: recordedAudioRelativePath)
                    } catch {
                        reportedError = error
                    }
                }
            }
            guard activeSession?.id == session.id else { return }
            fail(reportedError)
        }
    }

    private func complete(session: CaptureSession, transcription: SpeechTranscription) async throws {
        let task = intelligenceTask(mode: session.mode, transcript: transcription.rawText, context: session.context)
        if task == .rewriteSelection, session.context.selectedTextWasTruncated {
            throw LerroError.selectionTooLong(CapturedContext.maximumSelectedTextCharacters)
        }
        let request = IntelligenceRequest(
            task: task,
            mode: session.intelligenceMode,
            remoteProvider: session.remoteProvider,
            transcript: transcription.rawText,
            selectedText: session.context.selectedText,
            targetLanguage: session.targetLanguage,
            context: session.context,
            dictionary: dictionaryEntries.filter { !$0.isSnippet },
            toneInstruction: session.toneInstruction
        )

        let result: IntelligenceResult
        if session.mode == .dictation,
           let snippet = SnippetResolver.resolve(
               transcript: transcription.rawText,
               entries: dictionaryEntries,
               applicationBundleIdentifier: session.context.bundleIdentifier
           ) {
            result = IntelligenceResult(
                text: snippet.replacement,
                disposition: .insert,
                modelIdentifier: "local-snippet",
                source: .raw
            )
        } else if session.mode == .translation {
            guard let targetLanguage = session.targetLanguage else {
                throw LerroError.translationUnavailable("请先选择翻译目标语言")
            }
            let text = try await dependencies.translation.translate(
                transcription.rawText,
                sourceLanguageIdentifier: transcription.localeIdentifier,
                targetLanguageIdentifier: targetLanguage
            )
            result = IntelligenceResult(
                text: text,
                disposition: .insert,
                modelIdentifier: "apple-translation",
                source: .raw
            )
        } else if session.intelligenceMode == .raw {
            result = try rawResult(for: request, task: task)
        } else {
            let modelStatusMonitor = session.intelligenceMode == .local
                ? startModelStatusMonitor()
                : nil
            defer { modelStatusMonitor?.cancel() }
            do {
                if task == .answer {
                    result = try await processStreamingAnswer(request, session: session)
                } else {
                    result = try await dependencies.intelligence.process(request)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if session.mode == .dictation {
                    result = try rawResult(for: request, task: task)
                } else {
                    throw error
                }
            }
            if session.intelligenceMode == .local {
                modelStatus = await dependencies.intelligence.modelStatus()
            }
        }

        guard activeSession?.id == session.id else { throw CancellationError() }
        var history = HistoryEntry(
            id: session.id,
            createdAt: session.startedAt,
            mode: session.mode,
            rawText: transcription.rawText,
            finalText: result.text,
            answerText: result.disposition == .showAnswer ? result.text : nil,
            targetLanguage: session.targetLanguage,
            sourceLanguage: transcription.localeIdentifier,
            duration: transcription.duration,
            applicationName: session.context.applicationName,
            bundleIdentifier: session.context.bundleIdentifier,
            windowTitle: session.context.windowTitle,
            wasEnhanced: result.source != .raw,
            audioRelativePath: transcription.audioRelativePath
        )

        do {
            switch result.disposition {
            case .showAnswer:
                answerQuestion = transcription.rawText
                answerText = result.text
                answerContext = session.context
                showAnswerPanel()
            case .insert, .replaceSelection:
                phase = .inserting
                committedTextDeliverySessionID = nil
                updateHUD()
                try await dependencies.textDelivery.deliver(
                    result.text,
                    to: session.context,
                    replacingSelection: result.disposition == .replaceSelection,
                    targetPolicy: .requireCurrent,
                    onCommit: { [weak self] in
                        guard let self,
                              self.activeSession?.id == session.id else { return }
                        self.committedTextDeliverySessionID = session.id
                        self.suppressHUD(for: session.id)
                    }
                )
            case .openURL:
                if let url = result.url { NSWorkspace.shared.open(url) }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastResult = result.text
            history.status = .failed
            if preferences.historyRetention == .never {
                try await deleteAudioFile(relativePath: history.audioRelativePath)
            } else {
                try await dependencies.history.save(history)
            }
            await refreshHistoryAndUsage()
            throw error
        }

        guard activeSession?.id == session.id else { throw CancellationError() }
        suppressHUD(for: session.id)
        lastResult = result.text
        if preferences.historyRetention == .never {
            try await deleteAudioFile(relativePath: history.audioRelativePath)
        } else {
            try await dependencies.history.save(history)
        }
        let learnedDictionaryEntry = if result.source == .local {
            await learnDictionary(
                raw: transcription.rawText,
                final: result.text,
                context: session.context
            )
        } else {
            false
        }
        try await applyRetentionAndClean(preferences.historyRetention, now: .now)
        await refreshHistoryAndUsage()
        if learnedDictionaryEntry {
            await refreshDictionaryAndUsage()
        }

        activeSession = nil
        captureGeneration = nil
        committedTextDeliverySessionID = nil
        captureError = nil
        activeHotkeyOrigin = nil
        pendingHotkeysAfterCancellation.removeAll()
        isStartingCapture = false
        isHandsFreeCapture = false
        phase = .idle
        isHUDSuppressed = false
        partialTranscript = ""
        audioLevel = 0
        captureElapsed = 0
        updateHUD()
    }

    private func consumeSpeechEvent(_ event: SpeechEvent) {
        switch event {
        case .audioLevel(let level):
            audioLevel = level
        case .partial(let text), .final(let text):
            partialTranscript = text
        case .availability(let message):
            partialTranscript = message
        }
    }

    private func startCaptureTimer(for session: CaptureSession) {
        captureTimerTask?.cancel()
        captureTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.activeSession?.id == session.id else { return }
                let elapsed = Date.now.timeIntervalSince(session.startedAt)
                if elapsed >= 8 * 60 {
                    let wasCountdownVisible = self.captureElapsed >= 8 * 60
                    self.captureElapsed = elapsed
                    if !wasCountdownVisible {
                        self.updateHUD()
                    }
                }
                if elapsed >= 9 * 60 {
                    self.requestFinishCapture()
                    return
                }
                let pollingInterval: Duration = elapsed >= 8 * 60
                    ? .milliseconds(100)
                    : .seconds(1)
                try? await Task.sleep(for: pollingInterval)
            }
        }
    }

    private func ensureCapturePermissions() async -> Bool {
        if !microphonePermission {
            microphonePermission = await dependencies.permissions.requestMicrophone()
        }
        accessibilityPermission = dependencies.permissions.accessibilityAuthorized(prompt: true)
        if accessibilityPermission {
            configureHotkeys(reportError: true)
        } else {
            stopHotkeyMonitoring()
        }
        guard microphonePermission else {
            fail(LerroError.permissionRequired("麦克风"))
            return false
        }
        guard accessibilityPermission else {
            fail(LerroError.permissionRequired("辅助功能"))
            return false
        }
        return true
    }

    private func reconcileLoginItemAfterIdentityMigrationIfNeeded() {
        guard let migration = dependencies.dataMigrationResult,
              migration.requiresLoginItemReconciliation,
              let receiptURL = migration.receiptURL else {
            return
        }
        let migrator = ApplicationDataMigrator()
        do {
            let status = try dependencies.loginItem.reconcileAfterIdentityMigration(
                enabled: preferences.launchAtLogin
            )
            try migrator.recordLoginItemReconciliation(status, receiptURL: receiptURL)
            if status == .requiresUserReview {
                currentError = "请在系统设置的登录项中确认 Lerro，并移除仍显示的旧工程身份条目。"
            }
        } catch {
            try? migrator.recordLoginItemReconciliation(
                .requiresUserReview,
                receiptURL: receiptURL
            )
            currentError = "登录项迁移需要在系统设置中确认：\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func legacyApplicationIsRunning() -> Bool {
        guard dependencies.identityMonitor.legacyApplicationIsRunning() else { return false }
        currentError = "检测到旧版 Lerro 工程身份仍在运行。请退出旧版后继续使用，以避免两个全局 Fn 监听器同时生效。"
        return true
    }

    private func authorizeIntelligenceIfNeeded(for mode: CaptureMode) -> Bool {
        switch preferences.intelligenceMode {
        case .raw:
            guard mode == .dictation else {
                fail(LerroError.modelUnavailable("请在“智能处理”中选择本地 AI 或 API 模型"))
                return false
            }
            return true
        case .local:
            guard preferences.hasApprovedModelDownload else {
                presentModelDownloadConsent(for: mode)
                return false
            }
            return true
        case .remote:
            let configuration = normalizedRemoteProvider(preferences.remoteProvider)
            guard !configuration.baseURL.isEmpty,
                  !configuration.modelIdentifier.isEmpty,
                  !configuration.apiKey.isEmpty else {
                fail(LerroError.remoteUnavailable("请先在“智能处理”中填写完整的 API 配置"))
                return false
            }
            return true
        }
    }

    private func normalizedRemoteProvider(
        _ configuration: RemoteProviderConfiguration
    ) -> RemoteProviderConfiguration {
        var normalized = configuration
        normalized.baseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.modelIdentifier = configuration.modelIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        normalized.apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
    }

    private func presentModelDownloadConsent(for mode: CaptureMode?) {
        pendingModelCaptureMode = mode
        isModelDownloadConsentPresented = true
        NSApp.activate(ignoringOtherApps: true)
    }

    private func intelligenceTask(mode: CaptureMode, transcript: String, context: CapturedContext) -> IntelligenceTask {
        switch mode {
        case .dictation:
            return .polish
        case .translation:
            return .translate
        case .ask:
            if context.selectionState == .knownSelection,
               context.selectedText?.isEmpty == false {
                return .rewriteSelection
            }
            return .answer
        }
    }

    private func rawResult(
        for request: IntelligenceRequest,
        task: IntelligenceTask
    ) throws -> IntelligenceResult {
        guard !request.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LerroError.emptyTranscription
        }
        let output = task == .rewriteSelection
            ? request.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? request.transcript
            : request.transcript
        guard !output.isEmpty else { throw LerroError.emptyTranscription }
        return IntelligenceResult(
            text: output,
            disposition: task == .rewriteSelection ? .replaceSelection : .insert,
            modelIdentifier: "raw-apple-speech",
            source: .raw
        )
    }

    private func processStreamingAnswer(
        _ request: IntelligenceRequest,
        session: CaptureSession
    ) async throws -> IntelligenceResult {
        answerQuestion = request.transcript
        answerText = ""
        answerContext = session.context
        showAnswerPanel()

        let stream = try await dependencies.intelligence.processStream(request)
        var finalResult: IntelligenceResult?
        for try await partial in stream {
            try Task.checkCancellation()
            guard activeSession?.id == session.id else { throw CancellationError() }
            finalResult = partial
            answerText = partial.text
        }
        guard let finalResult else {
            throw LerroError.modelUnavailable("本地模型没有生成回答")
        }
        return finalResult
    }

    private func startModelStatusMonitor() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            var initialTerminalSamples = 0
            var observedActiveState = false
            while !Task.isCancelled {
                guard let self else { return }
                let status = await self.dependencies.intelligence.modelStatus()
                if self.modelStatus != status {
                    self.modelStatus = status
                }
                switch status.state {
                case .downloading, .loading:
                    observedActiveState = true
                case .loaded, .failed:
                    return
                case .ready, .unavailable:
                    if observedActiveState || initialTerminalSamples >= 2 {
                        return
                    }
                    initialTerminalSamples += 1
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    @discardableResult
    private func learnDictionary(
        raw: String,
        final: String,
        context: CapturedContext
    ) async -> Bool {
        let rawTokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let finalTokens = final.split(whereSeparator: \.isWhitespace).map(String.init)
        guard rawTokens.count == finalTokens.count, rawTokens.count <= 100 else { return false }
        var didSaveEntry = false

        for (source, replacement) in zip(rawTokens, finalTokens) where
            source.caseInsensitiveCompare(replacement) != .orderedSame
                && source.count >= 2 && replacement.count >= 2
                && source.count <= 48 && replacement.count <= 48 {
            let existing = dictionaryEntries.contains {
                $0.phrase.caseInsensitiveCompare(source) == .orderedSame
                    && $0.replacement == replacement
            }
            if !existing {
                let entry = DictionaryEntry(
                    phrase: source,
                    replacement: replacement,
                    source: .learned,
                    applicationBundleIdentifier: context.bundleIdentifier
                )
                do {
                    try await dependencies.dictionary.save(entry)
                    didSaveEntry = true
                } catch {
                    currentError = "自动词典保存失败：\(error.localizedDescription)"
                }
            }
        }
        return didSaveEntry
    }

    private func applyRetentionAndClean(_ retention: HistoryRetention, now: Date) async throws {
        guard retention != .forever, retention != .never else { return }
        let before = try await dependencies.history.entries()
        let expiring = before.filter { !retention.retains(createdAt: $0.createdAt, now: now) }
        guard !expiring.isEmpty else { return }
        try await deleteAudioFiles(relativePaths: expiring.map(\.audioRelativePath))
        try await dependencies.history.applyRetention(retention, now: now)
    }

    private func refreshHistoryAndUsage() async {
        let generation = UUID()
        historyUsageGeneration = generation
        do {
            let entries = try await dependencies.history.entries()
            guard historyUsageGeneration == generation else { return }
            historyUsageEntries = entries
            updateUsageSummary()
            await reloadHistory()
        } catch {
            guard historyUsageGeneration == generation else { return }
            currentError = LerroError.localData(
                "历史索引读取失败，录音目录保持不变：\(error.localizedDescription)"
            ).localizedDescription
        }
    }

    private func refreshDictionaryAndUsage() async {
        do {
            dictionaryEntries = try await dependencies.dictionary.entries()
            updateUsageSummary()
        } catch {
            currentError = LerroError.localData(
                "词典读取失败：\(error.localizedDescription)"
            ).localizedDescription
        }
    }

    private func updateUsageSummary() {
        usage = TextMetrics.usageSummary(entries: historyUsageEntries)
    }

    private func normalizedHistorySearch(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func audioFileURL(relativePath: String?) -> URL? {
        guard let audioDirectory = dependencies.applicationPaths?.audioDirectory,
              let relativePath,
              relativePath == URL(fileURLWithPath: relativePath).lastPathComponent else {
            return nil
        }
        return audioDirectory.appending(path: relativePath)
    }

    private func deleteAudioFile(relativePath: String?) async throws {
        try await audioFileStore?.delete(relativePath: relativePath)
    }

    private func deleteAudioFiles(relativePaths: [String?]) async throws {
        try await audioFileStore?.delete(relativePaths: relativePaths)
    }

    private func reconcileOrphanedAudioFiles() async {
        guard let audioFileStore else { return }
        let allEntries: [HistoryEntry]
        do {
            allEntries = try await dependencies.history.entries()
        } catch {
            currentError = LerroError.localData(
                "历史索引读取失败，录音目录保持不变：\(error.localizedDescription)"
            ).localizedDescription
            return
        }
        do {
            try await audioFileStore.reconcile(
                referencedRelativePaths: Set(allEntries.compactMap(\.audioRelativePath))
            )
        } catch {
            currentError = userFacingError(error, context: "本地数据处理失败")
        }
    }

    private func updateHUD() {
        guard presentsFloatingPanels else { return }
        guard currentHUDVisualState != .idleHidden else {
            hudController.hide(animated: false)
            return
        }
        let content = AnyView(
            CaptureHUDView(session: self)
                .environment(\.locale, LerroInterfaceLocalization.locale(for: preferences.appLanguage))
        )
        hudController.show(
            content: content,
            size: LerroTheme.hudPanelSize,
            interactionSize: hudInteractionSize,
            interactionBottomInset: LerroTheme.hudContentBottomInset,
            allowsInteraction: !isHUDSuppressed,
            animated: false
        )
    }

    private func showAnswerPanel() {
        guard presentsFloatingPanels else { return }
        let estimatedLines = ceil(Double((answerText?.count ?? 0) + answerQuestion.count) / 54)
        let height = min(800, max(500, 250 + estimatedLines * 25))
        answerController.show(
            content: AnyView(
                AskAnswerCardView(session: self)
                    .environment(\.locale, LerroInterfaceLocalization.locale(for: preferences.appLanguage))
            ),
            size: CGSize(width: 800, height: height)
        )
    }

    private func configureVisualFixtureIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LERRO_FIXTURE_MODE"] == "1",
              let presentation = environment["LERRO_FIXTURE_PRESENTATION"] else {
            return
        }
        visualFixturePresentation = presentation
        isPanelOnlyVisualFixture = environment["LERRO_FIXTURE_PANEL_ONLY"] == "1"
        visualFixtureReduceMotion = environment["LERRO_FIXTURE_REDUCE_MOTION"] == "1"
        visualFixtureIncreaseContrast = environment["LERRO_FIXTURE_INCREASE_CONTRAST"] == "1"
        visualFixtureReduceTransparency = environment["LERRO_FIXTURE_REDUCE_TRANSPARENCY"] == "1"
        switch environment["LERRO_FIXTURE_APPEARANCE"] {
        case "light": preferences.appearance = .light
        case "dark": preferences.appearance = .dark
        default: break
        }
        configureAppearance(preferences.appearance)
        lastAppliedSystemPreferences = preferences

        switch presentation {
        case "ask":
            if let entry = historyEntries.first(where: { $0.mode == .ask }) {
                if isPanelOnlyVisualFixture {
                    answerQuestion = entry.rawText
                    answerText = entry.answerText
                    answerContext = nil
                } else {
                    showHistoryAnswer(entry)
                }
            }
        case "settings":
            presentSettings(SettingsDestination.settings)
        case "settings-intelligence":
            presentSettings(SettingsDestination.intelligence)
        case "settings-personal", "settings-personal-editor":
            presentSettings(SettingsDestination.personal)
        case "hud-waiting":
            activeMode = .dictation
            phase = .idle
            isStartingCapture = true
            partialTranscript = ""
            audioLevel = 0
            captureElapsed = 0
            if !isPanelOnlyVisualFixture { updateHUD() }
        case "hud-recording":
            activeMode = .dictation
            phase = .listening
            partialTranscript = ""
            audioLevel = 0.72
            captureElapsed = 3
            if !isPanelOnlyVisualFixture { updateHUD() }
        case "hud-profile":
            activeMode = .dictation
            let context = CapturedContext(
                applicationName: "Mail",
                bundleIdentifier: "com.apple.mail"
            )
            activeSession = CaptureSession(
                mode: .dictation,
                context: context,
                toneInstruction: "Clear, friendly, and concise",
                toneProfileApplicationName: "Mail"
            )
            phase = .listening
            audioLevel = 0.72
            captureElapsed = 3
            if !isPanelOnlyVisualFixture { updateHUD() }
        case "hud-dictating":
            activeMode = .dictation
            phase = .listening
            partialTranscript = "合成转写"
            audioLevel = 0.72
            captureElapsed = 3
            if !isPanelOnlyVisualFixture { updateHUD() }
        case "hud-hands-free":
            activeMode = .dictation
            phase = .listening
            isHandsFreeCapture = true
            partialTranscript = ""
            audioLevel = 0.72
            captureElapsed = 3
            if !isPanelOnlyVisualFixture { updateHUD() }
        case "hud-processing":
            activeMode = .dictation
            phase = .enhancing
            isHandsFreeCapture = true
            partialTranscript = "合成转写"
            captureElapsed = 3
            if !isPanelOnlyVisualFixture { updateHUD() }
        case "hud-error":
            activeMode = .dictation
            phase = .failed
            captureError = "没有识别到语音"
            partialTranscript = "合成错误"
            if !isPanelOnlyVisualFixture { updateHUD() }
        default:
            break
        }

    }

    private func configureDeliveryProbeIfRequested() {
        if let configuration = Self.deliveryProbeConfiguration(
            arguments: ProcessInfo.processInfo.arguments
        ) {
            lastResult = configuration.payload
            deliveryProbeObserver = DistributedNotificationCenter.default().addObserver(
                forName: configuration.notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.consumeDeliveryProbe()
                }
            }
        }
    }

    private func consumeDeliveryProbe() {
        guard let deliveryProbeObserver else { return }
        DistributedNotificationCenter.default().removeObserver(deliveryProbeObserver)
        self.deliveryProbeObserver = nil
        pasteLastResult()
    }

    static func deliveryProbeConfiguration(
        arguments: [String]
    ) -> DeliveryProbeConfiguration? {
        guard let argumentIndex = arguments.firstIndex(of: deliveryProbeArgument),
              arguments.indices.contains(argumentIndex + 1) else {
            return nil
        }
        let token = arguments[argumentIndex + 1]
        guard UUID(uuidString: token) != nil else { return nil }
        return DeliveryProbeConfiguration(
            payload: syntheticDeliveryProbeText,
            notificationName: Notification.Name(deliveryProbeNotificationPrefix + token)
        )
    }

    private func userFacingError(_ error: any Error, context: String) -> String {
        if error is LerroError { return error.localizedDescription }
        return "\(context)：\(error.localizedDescription)"
    }

    private func fail(_ error: any Error) {
        answerController.hide()
        answerText = nil
        answerQuestion = ""
        answerContext = nil
        let message = userFacingError(error, context: "语音输入失败")
        captureError = message
        captureGeneration = nil
        committedTextDeliverySessionID = nil
        activeHotkeyOrigin = nil
        pendingHotkeysAfterCancellation.removeAll()
        isStartingCapture = false
        isCleaningCapture = true
        activeSession = nil
        isHandsFreeCapture = false
        isHUDSuppressed = false
        dependencies.hotkeys.resetTransientState()
        eventTask?.cancel()
        captureTimerTask?.cancel()
        captureTimerTask = nil
        captureElapsed = 0
        phase = .failed
        partialTranscript = message
        updateHUD()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await dependencies.speech.cancel()
            await dependencies.translation.cancel()
            await reconcileOrphanedAudioFiles()
            isCleaningCapture = false
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self else { return }
            while self.isCleaningCapture {
                guard self.phase == .failed, self.captureGeneration == nil else { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard self.phase == .failed,
                  self.captureGeneration == nil,
                  !self.isStartingCapture else { return }
            self.phase = .idle
            self.captureError = nil
            self.partialTranscript = ""
            self.updateHUD()
        }
    }

    private func configureApplicationPresentation() {
        configureAppearance(preferences.appearance)
        configureDockVisibility(preferences.showInDock)
    }

    private func applySystemPreferenceChanges(
        from previous: UserPreferences,
        to updated: UserPreferences
    ) {
        let changes = PreferenceSystemChanges(from: previous, to: updated)
        if changes.appearance {
            configureAppearance(updated.appearance)
        }
        if changes.dockVisibility {
            configureDockVisibility(updated.showInDock)
        }
        if changes.hotkeys {
            dependencies.hotkeys.update(definitions: updated.hotkeys)
        }
    }

    private func configureAppearance(_ appearance: AppAppearance) {
        NSApp.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private func configureDockVisibility(_ showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    private var hudInteractionSize: CGSize {
        let state = CaptureHUDVisualState.resolve(
            phase: phase,
            isStartingCapture: isStartingCapture,
            isHandsFreeCapture: isHandsFreeCapture,
            isSuppressed: isHUDSuppressed
        )
        var size = state.interactionSize(
            countdownVisible: phase == .listening && captureElapsed >= 8 * 60
        )
        if activeToneProfileApplicationName != nil,
           state == .waiting || state == .listening || state == .handsFree || state == .processing {
            size.width += 78
        }
        return size
    }

    private var currentHUDVisualState: CaptureHUDVisualState {
        CaptureHUDVisualState.resolve(
            phase: phase,
            isStartingCapture: isStartingCapture,
            isHandsFreeCapture: isHandsFreeCapture,
            isSuppressed: isHUDSuppressed
        )
    }

    private func suppressHUD(for sessionID: UUID) {
        guard activeSession?.id == sessionID, !isHUDSuppressed else { return }
        isHUDSuppressed = true
        audioLevel = 0
        updateHUD()
    }

}

private actor AppSessionAudioFileStore {
    private let audioDirectory: URL
    private let fileManager = FileManager.default

    init(audioDirectory: URL) {
        self.audioDirectory = audioDirectory
    }

    func delete(relativePath: String?) throws {
        guard let url = fileURL(relativePath: relativePath),
              fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw LerroError.localData(
                "无法删除录音 \(url.lastPathComponent)：\(error.localizedDescription)"
            )
        }
    }

    func delete(relativePaths: [String?]) throws {
        for relativePath in relativePaths {
            try delete(relativePath: relativePath)
        }
    }

    func reconcile(referencedRelativePaths: Set<String>) throws {
        guard fileManager.fileExists(atPath: audioDirectory.path) else { return }
        do {
            let files = try fileManager.contentsOfDirectory(
                at: audioDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for file in files where file.pathExtension.lowercased() == "caf"
                && !referencedRelativePaths.contains(file.lastPathComponent) {
                try fileManager.removeItem(at: file)
            }
        } catch {
            throw LerroError.localData(
                "无法完成录音目录清理：\(error.localizedDescription)"
            )
        }
    }

    private func fileURL(relativePath: String?) -> URL? {
        guard let relativePath,
              relativePath == URL(fileURLWithPath: relativePath).lastPathComponent else {
            return nil
        }
        return audioDirectory.appending(path: relativePath)
    }
}

struct PreferenceSystemChanges: Equatable {
    var appearance: Bool
    var dockVisibility: Bool
    var hotkeys: Bool
    var loginItem: Bool

    init(from previous: UserPreferences, to updated: UserPreferences) {
        appearance = previous.appearance != updated.appearance
        dockVisibility = previous.showInDock != updated.showInDock
        hotkeys = previous.hotkeys != updated.hotkeys
        loginItem = previous.launchAtLogin != updated.launchAtLogin
    }
}
