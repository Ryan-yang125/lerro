import Foundation
import LerroCore
import LerroIntelligence
import LerroMac

struct AppDependencies: Sendable {
    let applicationPaths: ApplicationPaths?
    let startupStorageError: String?
    let speech: any SpeechTranscribing
    let soundPlayer: any CaptureSoundPlaying
    let microphoneTest: any MicrophoneLevelTesting
    let context: any ContextCapturing
    let textDelivery: any TextDelivering
    let recoveryText: any RecoveryTextCopying
    let deliveredTextObserver: any DeliveredTextObserving
    let applicationCatalog: any ApplicationCataloging
    let hotkeys: any HotkeyMonitoring
    let permissions: any PermissionChecking
    let loginItem: any LoginItemManaging
    let history: any HistoryRepository
    let dictionary: any DictionaryRepository
    let dictionarySuggestions: any DictionarySuggestionRepository
    let preferences: any PreferencesRepository
    let aiUsage: any AIUsageRepository
    let dailyUsage: any DailyUsageRepository
    let intelligence: any IntelligenceProcessing
    let captureTrace: any CaptureTraceObserving

    static func live() -> AppDependencies {
        if ProcessInfo.processInfo.environment["LERRO_FIXTURE_MODE"] == "1" {
            return fixture()
        }

        let paths = ApplicationPaths.live()
        do {
            try paths.prepareDirectories()
        } catch {
            return fixture(startupStorageError: error.localizedDescription)
        }

        let preferences = FilePreferencesRepository(fileURL: paths.preferencesFile)
        let aiUsage = FileAIUsageRepository(fileURL: paths.aiUsageFile)
        return AppDependencies(
            applicationPaths: paths,
            startupStorageError: nil,
            speech: AppleSpeechService(applicationPaths: paths),
            soundPlayer: CaptureSoundPlayer(),
            microphoneTest: MicrophoneLevelTester(),
            context: AccessibilityContextService(),
            textDelivery: AccessibilityTextDeliverer(),
            recoveryText: PasteboardRecoveryTextCopier(),
            deliveredTextObserver: AccessibilityDeliveredTextObserver(),
            applicationCatalog: MacApplicationCatalog(),
            hotkeys: GlobalHotkeyMonitor(),
            permissions: MacPermissionService(),
            loginItem: MacLoginItemManager(),
            history: FileHistoryRepository(fileURL: paths.historyFile),
            dictionary: FileDictionaryRepository(fileURL: paths.dictionaryFile),
            dictionarySuggestions: FileDictionarySuggestionRepository(fileURL: paths.dictionarySuggestionsFile),
            preferences: preferences,
            aiUsage: aiUsage,
            dailyUsage: FileDailyUsageRepository(fileURL: paths.dailyUsageFile),
            intelligence: PipelineIntelligenceService(
                remoteRuntime: OpenAICompatibleRemoteLanguageModelRuntime(),
                usageRecorder: aiUsage
            ),
            captureTrace: OSLogCaptureTraceObserver()
        )
    }

    private static func fixture(startupStorageError: String? = nil) -> AppDependencies {
        let history = fixtureHistory()
        let dictionary = fixtureDictionary()
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
        var preferences = UserPreferences(
            appToneProfiles: fixtureAppToneProfiles(),
            defaultToneInstruction: "自然、简洁，保留我的原意",
            hasCompletedOnboarding: !onboardingRequested,
            onboardingStepIndex: onboardingRequested ? onboardingStepIndex : nil
        )
        if !onboardingRequested {
            preferences.intelligenceMode = .remote
            preferences.remoteProvider = .preset(.deepSeek, apiKey: "fixture-not-a-real-key")
        }

        return AppDependencies(
            applicationPaths: nil,
            startupStorageError: startupStorageError,
            speech: FixtureSpeechTranscriber(),
            soundPlayer: FixtureSoundPlayer(),
            microphoneTest: FixtureMicrophoneLevelTester(),
            context: FixtureContextCapture(),
            textDelivery: FixtureTextDeliverer(),
            recoveryText: FixtureRecoveryTextCopier(),
            deliveredTextObserver: FixtureDeliveredTextObserver(),
            applicationCatalog: FixtureApplicationCatalog(),
            hotkeys: FixtureHotkeyMonitor(),
            permissions: FixturePermissionChecker(),
            loginItem: FixtureLoginItemManager(),
            history: InMemoryHistoryRepository(entries: history),
            dictionary: InMemoryDictionaryRepository(entries: dictionary),
            dictionarySuggestions: InMemoryDictionarySuggestionRepository(value: fixtureDictionarySuggestions()),
            preferences: InMemoryPreferencesRepository(value: preferences),
            aiUsage: InMemoryAIUsageRepository(records: fixtureAIUsageRecords(history: history)),
            dailyUsage: InMemoryDailyUsageRepository(days: fixtureDailyUsage()),
            intelligence: FixtureIntelligence(),
            captureTrace: DiscardingCaptureTraceObserver()
        )
    }

    private static func fixtureHistory() -> [HistoryEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        func at(_ day: Date, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let fullReceipt = HistoryContextReceipt(
            capturedCategories: [.application, .windowTitle, .nearbyText, .dictionary, .tone],
            remoteSharedCategories: [.application, .nearbyText, .dictionary, .tone]
        )
        let timings = HistoryPhaseTimings(
            recording: 8.6,
            transcription: 0.4,
            processing: 1.1,
            delivery: 0.1,
            milestones: [
                .hotkeyPressed: 0,
                .contextCaptured: 0.06,
                .speechStartRequested: 0.08,
                .listening: 0.42,
                .firstPartial: 0.9
            ]
        )
        let dictionary = fixtureDictionary().filter { !$0.isSnippet }
        var callIndex = 0
        func aiCall(
            mode: CaptureMode,
            createdAt: Date,
            raw: String,
            final: String,
            app: String,
            bundle: String,
            window: String?,
            cursorBefore: String?,
            target: String?,
            fixes: [[String]]
        ) -> AICallTrace? {
            let task: IntelligenceTask = mode == .translation ? .translate : .polish
            let request = IntelligenceRequest(
                task: task,
                transcript: raw,
                targetLanguage: target,
                context: CapturedContext(
                    applicationName: app,
                    bundleIdentifier: bundle,
                    windowTitle: window,
                    cursorBefore: cursorBefore
                ),
                dictionary: dictionary,
                toneInstruction: "自然、简洁，保留我的原意"
            )
            guard let userPrompt = (try? CloudPromptComposer().prompts(for: request))?.user else { return nil }
            let response: String
            if mode == .translation {
                response = final
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                let payload = FixtureDictateResponse(fixes: fixes, text: final)
                response = (try? encoder.encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? final
            }
            defer { callIndex += 1 }
            return AICallTrace(
                prompt: mode == .translation ? .translate : .dictate,
                promptVersion: mode == .translation
                    ? CloudPromptComposer.translatePromptVersion
                    : CloudPromptComposer.dictatePromptVersion,
                provider: .deepSeek,
                modelIdentifier: "deepseek-flash",
                userPrompt: userPrompt,
                response: response,
                tokens: AITokenUsage(
                    inputTokens: 2_400,
                    outputTokens: 60 + (callIndex * 7) % 31,
                    cachedInputTokens: 2_048
                ),
                latencyMilliseconds: 900 + (callIndex * 137) % 501,
                startedAt: createdAt
            )
        }
        func entry(
            _ day: Date,
            _ hour: Int,
            _ minute: Int,
            mode: CaptureMode = .dictation,
            raw: String,
            final: String,
            duration: TimeInterval,
            app: String,
            bundle: String,
            window: String? = nil,
            cursorBefore: String? = nil,
            status: HistoryStatus = .completed,
            enhanced: Bool = true,
            target: String? = nil,
            fixes: [[String]] = []
        ) -> HistoryEntry {
            var item = HistoryEntry(
                createdAt: at(day, hour, minute),
                mode: mode,
                rawText: raw,
                finalText: final,
                targetLanguage: target,
                duration: duration,
                applicationName: app,
                bundleIdentifier: bundle,
                windowTitle: window,
                status: status,
                wasEnhanced: enhanced,
                processedText: enhanced ? final : nil,
                processingRoute: enhanced ? .remote : .raw,
                modelIdentifier: enhanced ? "deepseek-flash" : nil,
                contextReceipt: enhanced ? fullReceipt : nil,
                phaseTimings: timings
            )
            if enhanced {
                item.aiCall = aiCall(
                    mode: mode,
                    createdAt: item.createdAt,
                    raw: raw,
                    final: final,
                    app: app,
                    bundle: bundle,
                    window: window,
                    cursorBefore: cursorBefore,
                    target: target,
                    fixes: fixes
                )
            }
            return item
        }
        return [
            entry(today, 9, 5, raw: "嗯我想把这个 App 的主界面整体重构一下，就是现在的那个太不高级了。",
                  final: "我想把这个 App 的主界面整体重构一下，现在的太不高级了。",
                  duration: 8.6, app: "Claude", bundle: "com.anthropic.claudefordesktop", window: "Lerro 重构"),
            entry(today, 9, 48, raw: "那个明天下午三点把新版发布清单发给设计和那个工程团队。",
                  final: "明天下午三点把新版发布清单发给设计和工程团队。",
                  duration: 6.2, app: "邮件", bundle: "com.apple.mail", window: "新版发布"),
            entry(today, 11, 20, raw: "这个 PR 嗯先不合，等 CI 跑完再看一下签名那一步。",
                  final: "这个 PR 先不合，等 CI 跑完再看一下签名那一步。",
                  duration: 7.4, app: "Slack", bundle: "com.tinyspeck.slackmacgap", window: "#release"),
            entry(today, 13, 42, raw: "周五之前把词典导入的 CSV 格式整理成文档，就是顺便补上示例。",
                  final: "周五之前把词典导入的 CSV 格式整理成文档，顺便补上示例。",
                  duration: 9.1, app: "备忘录", bundle: "com.apple.Notes"),
            entry(today, 15, 10, mode: .translation,
                  raw: "晚上一起吃饭吗，我大概八点到，你们先点。",
                  final: "Want to grab dinner tonight? I'll get there around eight, so go ahead and order.",
                  duration: 5.8, app: "微信", bundle: "com.tencent.xinWeChat", target: "en_US"),
            entry(today, 16, 35, raw: "嗯把哈德结尾的那个标识直接去掉吧开头的话保持现在这个速度",
                  final: "把 HUD 结尾的标志直接去掉，开头保持现在的速度。",
                  duration: 7.0, app: "Claude", bundle: "com.anthropic.claudefordesktop",
                  cursorBefore: "关于启动动画，我的想法是：",
                  status: .failed,
                  fixes: [["哈德", "HUD"], ["标识", "标志"]]),
            entry(yesterday, 10, 2, raw: "今天上午先把设置窗口的几个标签页过一遍。",
                  final: "今天上午先把设置窗口的几个标签页过一遍。",
                  duration: 5.0, app: "备忘录", bundle: "com.apple.Notes", enhanced: false),
            entry(yesterday, 14, 30, raw: "那个周报我晚点补，先把本周的数据导出来。",
                  final: "周报我晚点补，先把本周的数据导出来。",
                  duration: 6.4, app: "邮件", bundle: "com.apple.mail"),
            entry(yesterday, 18, 15, raw: "可以，就按刚才说的方案来，明早我再确认一遍。",
                  final: "可以，就按刚才说的方案来，明早我再确认一遍。",
                  duration: 5.5, app: "微信", bundle: "com.tencent.xinWeChat"),
            entry(yesterday, 21, 40, raw: "嗯这个构建在我这边是通过的，你再拉一下最新的分支试试。",
                  final: "这个构建在我这边是通过的，你再拉一下最新的分支试试。",
                  duration: 7.7, app: "Slack", bundle: "com.tinyspeck.slackmacgap")
        ]
    }

    /// About six months of dictation ending today, weekdays heavier. Built
    /// through `DailyUsage.seed` from synthetic entries (one per app per day),
    /// then the per-day counts and hour distribution are set directly.
    private static func fixtureDailyUsage() -> [DailyUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var state: UInt64 = 7
        func random() -> Double {
            state = (state &* 16_807) % 2_147_483_647
            return Double(state) / 2_147_483_647
        }
        let apps: [(name: String, bundle: String, weight: Double)] = [
            ("Claude", "com.anthropic.claudefordesktop", 48_210),
            ("ChatGPT", "com.openai.chat", 17_120),
            ("微信", "com.tencent.xinWeChat", 9_630),
            ("备忘录", "com.apple.Notes", 4_210),
            ("Slack", "com.tinyspeck.slackmacgap", 2_180)
        ]
        let appTotal = apps.reduce(0) { $0 + $1.weight }
        let hourWeights: [Double] = [
            8, 0, 0, 0, 0, 0, 0, 0, 0, 30, 64, 71,
            22, 18, 58, 80, 77, 61, 34, 25, 40, 52, 46, 20
        ]
        let hourTotal = hourWeights.reduce(0, +)

        func dayKey(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }

        var entries: [HistoryEntry] = []
        var extras: [String: (dictations: Int, duration: TimeInterval)] = [:]
        for offset in 0..<190 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let base = (weekday == 1 || weekday == 7) ? 0.45 : 0.86
            if offset != 0, random() > base { continue }
            let words = Int(((300 + pow(random(), 1.6) * 5_200) * (offset < 40 ? 1.25 : 1)).rounded())
            let dictations = max(1, Int((Double(words) / 55).rounded()))
            var remaining = words
            for (index, app) in apps.enumerated() {
                let share = index == apps.count - 1
                    ? remaining
                    : min(remaining, Int(Double(words) * app.weight / appTotal * (0.7 + random() * 0.6)))
                guard share > 0 else { continue }
                remaining -= share
                entries.append(HistoryEntry(
                    createdAt: day.addingTimeInterval(12 * 3_600),
                    mode: .dictation,
                    rawText: "",
                    finalText: String(repeating: "字", count: share),
                    duration: 1,
                    applicationName: app.name,
                    bundleIdentifier: app.bundle,
                    status: .completed
                ))
            }
            extras[dayKey(day)] = (dictations, Double(words) / 175 * 60)
        }

        return DailyUsage.seed(from: entries, calendar: calendar).map { usage in
            var usage = usage
            if let extra = extras[usage.day] {
                usage.dictations = extra.dictations
                usage.duration = extra.duration
                usage.hours = hourWeights.map { Int((Double(extra.dictations) * $0 / hourTotal).rounded()) }
            }
            return usage
        }
    }

    private struct FixtureDictateResponse: Encodable {
        var fixes: [[String]]
        var text: String
    }

    private static func fixtureAIUsageRecords(history: [HistoryEntry]) -> [AIUsageRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var records: [AIUsageRecord] = []
        for dayOffset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dictateCount = 3 + (dayOffset * 7) % 6
            for index in 0..<dictateCount {
                let input = 1_500 + ((dayOffset * 131 + index * 223) % 1_501)
                let output = 30 + ((dayOffset * 17 + index * 41) % 171)
                let date = calendar.date(
                    bySettingHour: 9 + (index * 2) % 12,
                    minute: (index * 13 + dayOffset) % 60,
                    second: 0,
                    of: day
                ) ?? day
                guard date <= .now else { continue }
                records.append(AIUsageRecord(
                    date: date,
                    feature: .dictate,
                    provider: .deepSeek,
                    modelIdentifier: "deepseek-flash",
                    tokens: AITokenUsage(
                        inputTokens: input,
                        outputTokens: output,
                        cachedInputTokens: input * 4 / 5
                    ),
                    latencyMilliseconds: 700 + (index * 90) % 600,
                    succeeded: true
                ))
            }
            if dayOffset % 3 == 0 {
                let date = calendar.date(bySettingHour: 15, minute: 20, second: 0, of: day) ?? day
                if date <= .now {
                    records.append(AIUsageRecord(
                        date: date,
                        feature: .translate,
                        provider: .deepSeek,
                        modelIdentifier: "deepseek-flash",
                        tokens: AITokenUsage(inputTokens: 1_620, outputTokens: 95, cachedInputTokens: 1_400),
                        latencyMilliseconds: 950,
                        succeeded: true
                    ))
                }
            }
            if dayOffset % 5 == 0 {
                let date = calendar.date(bySettingHour: 17, minute: 5, second: 0, of: day) ?? day
                if date <= .now {
                    records.append(AIUsageRecord(
                        date: date,
                        feature: .dictionaryLearning,
                        provider: .deepSeek,
                        modelIdentifier: "deepseek-flash",
                        tokens: AITokenUsage(inputTokens: 1_850, outputTokens: 60, cachedInputTokens: 1_700),
                        latencyMilliseconds: 820,
                        succeeded: true
                    ))
                }
            }
        }
        // Records tied to fixture history entries, so the usage list can jump to them.
        for entry in history {
            guard let call = entry.aiCall else { continue }
            records.append(AIUsageRecord(
                date: min(call.startedAt.addingTimeInterval(2), .now),
                feature: entry.mode == .translation ? .translate : .dictate,
                provider: call.provider,
                modelIdentifier: call.modelIdentifier,
                tokens: call.tokens,
                latencyMilliseconds: call.latencyMilliseconds,
                succeeded: true,
                historyEntryID: entry.id
            ))
        }
        let learnedFrom = history.filter { $0.aiCall != nil && $0.mode == .dictation }
        if learnedFrom.count > 3 {
            records.append(AIUsageRecord(
                date: min(learnedFrom[3].createdAt.addingTimeInterval(45), .now),
                feature: .dictionaryLearning,
                provider: .deepSeek,
                modelIdentifier: "deepseek-flash",
                tokens: AITokenUsage(inputTokens: 1_850, outputTokens: 60, cachedInputTokens: 1_700),
                latencyMilliseconds: 820,
                succeeded: true,
                historyEntryID: learnedFrom[3].id
            ))
        }
        let fallbackEntry = history.first { $0.mode == .dictation && !$0.wasEnhanced }
        records.append(AIUsageRecord(
            date: calendar.date(byAdding: .hour, value: -2, to: .now) ?? .now,
            feature: .tonePreview,
            provider: .deepSeek,
            modelIdentifier: "deepseek-flash",
            tokens: AITokenUsage(inputTokens: 1_540, outputTokens: 48, cachedInputTokens: 1_300),
            latencyMilliseconds: 880,
            succeeded: true
        ))
        records.append(AIUsageRecord(
            date: fallbackEntry?.createdAt ?? calendar.date(byAdding: .hour, value: -1, to: .now) ?? .now,
            feature: .dictate,
            provider: .deepSeek,
            modelIdentifier: "deepseek-flash",
            tokens: nil,
            latencyMilliseconds: 10_000,
            succeeded: false,
            historyEntryID: fallbackEntry?.id
        ))
        return records
    }

    private static func fixtureDictionary() -> [DictionaryEntry] {
        let now = Date.now
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        return [
            DictionaryEntry(phrase: "Lerro", createdAt: ago(40), updatedAt: ago(40), useCount: 31),
            DictionaryEntry(phrase: "DeepSeek", createdAt: ago(30), updatedAt: ago(30), useCount: 12),
            DictionaryEntry(
                phrase: "meeting link",
                replacement: "https://meet.example.com/lerro",
                createdAt: ago(25),
                updatedAt: ago(25),
                useCount: 8
            ),
            DictionaryEntry(
                phrase: "我的邮箱",
                replacement: "hello@example.com",
                createdAt: ago(22),
                updatedAt: ago(22),
                useCount: 5
            ),
            DictionaryEntry(
                phrase: "CI",
                applicationBundleIdentifier: "com.tinyspeck.slackmacgap",
                createdAt: ago(18),
                updatedAt: ago(18),
                useCount: 9
            ),
            DictionaryEntry(
                phrase: "HUD",
                applicationBundleIdentifier: "com.anthropic.claudefordesktop",
                createdAt: ago(15),
                updatedAt: ago(15),
                useCount: 4
            ),
            DictionaryEntry(
                phrase: "SwiftPM",
                source: .learned,
                createdAt: ago(20),
                updatedAt: ago(20),
                useCount: 3
            ),
            DictionaryEntry(
                phrase: "code x",
                replacement: "Codex",
                source: .learned,
                createdAt: ago(1),
                updatedAt: ago(1),
                useCount: 5
            ),
            DictionaryEntry(
                phrase: "乐若",
                replacement: "Lerro",
                source: .learned,
                createdAt: ago(2),
                updatedAt: ago(2),
                useCount: 2
            ),
            DictionaryEntry(
                phrase: "swift ui",
                replacement: "SwiftUI",
                source: .learned,
                createdAt: ago(5),
                updatedAt: ago(5),
                useCount: 3
            )
        ]
    }

    private static func fixtureDictionarySuggestions() -> DictionarySuggestionState {
        let now = Date.now
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        var state = DictionarySuggestionState()
        state.suggestions = [
            DictionarySuggestion(
                phrase: "糊涂", replacement: "富途", occurrences: 3,
                lastSeen: ago(1), applicationName: "Claude"
            ),
            DictionarySuggestion(
                phrase: "史册", replacement: "实测", occurrences: 2,
                lastSeen: ago(2), applicationName: "Slack"
            ),
            DictionarySuggestion(
                phrase: "畅巧", replacement: "长桥", occurrences: 2,
                lastSeen: ago(4), applicationName: "备忘录"
            ),
            DictionarySuggestion(
                phrase: "折腾死命而", replacement: "Druckenmiller", occurrences: 1,
                lastSeen: ago(6), applicationName: "Claude"
            )
        ]
        return state
    }

    private static func fixtureAppToneProfiles() -> [AppToneProfile] {
        [
            AppToneProfile(
                bundleIdentifier: "com.tencent.xinWeChat",
                applicationName: "微信",
                instruction: "口语化、简短，保留语气词"
            ),
            AppToneProfile(
                bundleIdentifier: "com.apple.mail",
                applicationName: "邮件",
                instruction: "表达清楚、友好、简洁，使用完整句子"
            ),
            AppToneProfile(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                applicationName: "Slack",
                instruction: "直接、专业，适合工作群沟通"
            ),
            AppToneProfile(
                bundleIdentifier: "com.anthropic.claudefordesktop",
                applicationName: "Claude",
                instruction: "把口述整理成清晰的指令，保留技术名词",
                enabled: false
            )
        ]
    }
}

/// Fixture adapters intentionally avoid every macOS integration point. They
/// keep screenshot and launch-smoke runs deterministic without touching audio,
/// Accessibility, pasteboard, TCC, login items, or disk.
private actor FixtureSpeechTranscriber: SpeechTranscribing {
    func availableInputDevices() async -> [AudioInputDevice] {
        [AudioInputDevice(uid: "fixture-input", name: "MacBook Pro 麦克风", isDefault: true)]
    }

    func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        saveAudio: Bool,
        milestones: @escaping CaptureMilestoneReporter
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.availability("Fixture speech adapter"))
        }
    }

    func lowerOtherAudio() async {}

    func endAudioCapture() async {}

    func stop() async throws -> SpeechTranscription {
        SpeechTranscription(
            rawText: "这是一段用于视觉回归的合成口述。",
            localeIdentifier: "zh_CN",
            duration: 1
        )
    }

    func cancel() async {}
}

private struct FixtureSoundPlayer: CaptureSoundPlaying {
    func prepare() async {}
    func play(_ sound: CaptureSound) async {}
}

private struct FixtureMicrophoneLevelTester: MicrophoneLevelTesting {
    func availableInputDevices() async -> [AudioInputDevice] {
        [AudioInputDevice(uid: "fixture-input", name: "MacBook Pro 麦克风", isDefault: true)]
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
            ApplicationDescriptor(
                bundleIdentifier: "com.tencent.xinWeChat",
                name: "微信",
                isRunning: true
            ),
            ApplicationDescriptor(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                name: "Slack",
                isRunning: true
            ),
            ApplicationDescriptor(
                bundleIdentifier: "com.anthropic.claudefordesktop",
                name: "Claude",
                isRunning: false
            ),
            ApplicationDescriptor(bundleIdentifier: "com.apple.Notes", name: "备忘录"),
            ApplicationDescriptor(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode"),
            ApplicationDescriptor(bundleIdentifier: "notion.id", name: "Notion"),
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

private struct FixtureIntelligence: IntelligenceProcessing {
    func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult {
        guard !request.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LerroError.emptyTranscription
        }
        guard request.task == .polish else {
            throw LerroError.modelUnavailable("Fixture intelligence does not translate")
        }
        return IntelligenceResult(
            text: request.transcript,
            disposition: .insert,
            modelIdentifier: "fixture",
            source: .raw
        )
    }
}
