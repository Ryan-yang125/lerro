import Foundation

public enum AppAppearance: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
}

/// Controls the language used by the Lerro interface. Speech recognition and
/// translation keep their independent locale preferences.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case simplifiedChinese
    case english

    public var localeIdentifier: String {
        switch self {
        case .system:
            Locale.autoupdatingCurrent.identifier
        case .simplifiedChinese:
            "zh-Hans"
        case .english:
            "en"
        }
    }
}

public enum HistoryRetention: String, CaseIterable, Codable, Sendable {
    case oneDay
    case oneWeek
    case oneMonth
    case forever
    case never

    public func retains(createdAt: Date, now: Date) -> Bool {
        let maximumAge: TimeInterval
        switch self {
        case .oneDay: maximumAge = 86_400
        case .oneWeek: maximumAge = 7 * 86_400
        case .oneMonth: maximumAge = 30 * 86_400
        case .forever, .never: return true
        }
        return now.timeIntervalSince(createdAt) <= maximumAge
    }
}

public struct UserPreferences: Codable, Equatable, Sendable {
    public var recognitionLocaleIdentifier: String
    public var translationLanguageIdentifiers: [String]
    public var appLanguage: AppLanguage
    public var microphoneDeviceUID: String?
    public var muteOtherAudio: Bool
    public var playsCaptureSounds: Bool
    public var appearance: AppAppearance
    public var launchAtLogin: Bool
    public var showInDock: Bool
    public var saveAudio: Bool
    public var historyRetention: HistoryRetention
    public var intelligenceMode: IntelligenceMode
    public var remoteProvider: RemoteProviderConfiguration
    public var hotkeys: [HotkeyDefinition]
    public var appToneProfiles: [AppToneProfile]
    public var defaultToneInstruction: String
    public var automaticDictionaryLearningEnabled: Bool
    public var hasCompletedOnboarding: Bool
    public var onboardingStepIndex: Int?
    public var handsFreeStopHintUseCount: Int
    /// User price overrides; they take precedence over `AIModelPrice.builtIn`.
    public var modelPrices: [AIModelPrice]

    public var shouldSaveCaptureAudio: Bool {
        saveAudio && historyRetention != .never
    }

    public var isAutomaticDictionaryLearningActive: Bool {
        automaticDictionaryLearningEnabled && intelligenceMode != .raw
    }

    public init(
        recognitionLocaleIdentifier: String = "zh_CN",
        translationLanguageIdentifiers: [String] = ["en_US"],
        appLanguage: AppLanguage = .system,
        microphoneDeviceUID: String? = nil,
        muteOtherAudio: Bool = true,
        playsCaptureSounds: Bool = true,
        appearance: AppAppearance = .system,
        launchAtLogin: Bool = false,
        showInDock: Bool = true,
        saveAudio: Bool = false,
        historyRetention: HistoryRetention = .forever,
        intelligenceMode: IntelligenceMode = .raw,
        remoteProvider: RemoteProviderConfiguration = RemoteProviderConfiguration(),
        hotkeys: [HotkeyDefinition] = UserPreferences.defaultHotkeys,
        appToneProfiles: [AppToneProfile] = [],
        defaultToneInstruction: String = "",
        automaticDictionaryLearningEnabled: Bool = true,
        hasCompletedOnboarding: Bool = false,
        onboardingStepIndex: Int? = nil,
        handsFreeStopHintUseCount: Int = 0,
        modelPrices: [AIModelPrice] = []
    ) {
        self.recognitionLocaleIdentifier = recognitionLocaleIdentifier
        self.translationLanguageIdentifiers = Array(translationLanguageIdentifiers.prefix(3))
        self.appLanguage = appLanguage
        self.microphoneDeviceUID = microphoneDeviceUID
        self.muteOtherAudio = muteOtherAudio
        self.playsCaptureSounds = playsCaptureSounds
        self.appearance = appearance
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.saveAudio = saveAudio
        self.historyRetention = historyRetention
        self.intelligenceMode = intelligenceMode
        self.remoteProvider = remoteProvider
        self.hotkeys = hotkeys
        self.appToneProfiles = appToneProfiles
        self.defaultToneInstruction = defaultToneInstruction
        self.automaticDictionaryLearningEnabled = automaticDictionaryLearningEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.onboardingStepIndex = onboardingStepIndex
        self.handsFreeStopHintUseCount = handsFreeStopHintUseCount
        self.modelPrices = modelPrices
    }

    private enum CodingKeys: String, CodingKey {
        case recognitionLocaleIdentifier
        case translationLanguageIdentifiers
        case appLanguage
        case microphoneDeviceUID
        case muteOtherAudio
        case playsCaptureSounds
        case appearance
        case launchAtLogin
        case showInDock
        case saveAudio
        case historyRetention
        case intelligenceMode
        case remoteProvider
        case hotkeys
        case appToneProfiles
        case defaultToneInstruction
        case automaticDictionaryLearningEnabled
        case hasCompletedOnboarding
        case onboardingStepIndex
        case handsFreeStopHintUseCount
        case modelPrices
    }

    public init(from decoder: any Decoder) throws {
        let defaults = UserPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown saved mode (for example a removed one) falls back to raw.
        let intelligenceMode = (try? container.decode(
            IntelligenceMode.self,
            forKey: .intelligenceMode
        )) ?? defaults.intelligenceMode
        self.init(
            recognitionLocaleIdentifier: try container.decodeIfPresent(
                String.self,
                forKey: .recognitionLocaleIdentifier
            ) ?? defaults.recognitionLocaleIdentifier,
            translationLanguageIdentifiers: try container.decodeIfPresent(
                [String].self,
                forKey: .translationLanguageIdentifiers
            ) ?? defaults.translationLanguageIdentifiers,
            appLanguage: try container.decodeIfPresent(
                AppLanguage.self,
                forKey: .appLanguage
            ) ?? defaults.appLanguage,
            microphoneDeviceUID: try container.decodeIfPresent(
                String.self,
                forKey: .microphoneDeviceUID
            ),
            muteOtherAudio: try container.decodeIfPresent(
                Bool.self,
                forKey: .muteOtherAudio
            ) ?? defaults.muteOtherAudio,
            playsCaptureSounds: try container.decodeIfPresent(
                Bool.self,
                forKey: .playsCaptureSounds
            ) ?? defaults.playsCaptureSounds,
            appearance: try container.decodeIfPresent(
                AppAppearance.self,
                forKey: .appearance
            ) ?? defaults.appearance,
            launchAtLogin: try container.decodeIfPresent(
                Bool.self,
                forKey: .launchAtLogin
            ) ?? defaults.launchAtLogin,
            showInDock: try container.decodeIfPresent(
                Bool.self,
                forKey: .showInDock
            ) ?? defaults.showInDock,
            saveAudio: try container.decodeIfPresent(
                Bool.self,
                forKey: .saveAudio
            ) ?? defaults.saveAudio,
            historyRetention: try container.decodeIfPresent(
                HistoryRetention.self,
                forKey: .historyRetention
            ) ?? defaults.historyRetention,
            intelligenceMode: intelligenceMode,
            remoteProvider: try container.decodeIfPresent(
                RemoteProviderConfiguration.self,
                forKey: .remoteProvider
            ) ?? defaults.remoteProvider,
            hotkeys: Self.normalizeHotkeys(
                try container.decodeIfPresent(
                    [HotkeyDefinition].self,
                    forKey: .hotkeys
                ) ?? defaults.hotkeys
            ),
            appToneProfiles: try container.decodeIfPresent(
                [AppToneProfile].self,
                forKey: .appToneProfiles
            ) ?? defaults.appToneProfiles,
            defaultToneInstruction: try container.decodeIfPresent(
                String.self,
                forKey: .defaultToneInstruction
            ) ?? defaults.defaultToneInstruction,
            automaticDictionaryLearningEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .automaticDictionaryLearningEnabled
            ) ?? defaults.automaticDictionaryLearningEnabled,
            hasCompletedOnboarding: try container.decodeIfPresent(
                Bool.self,
                forKey: .hasCompletedOnboarding
            ) ?? defaults.hasCompletedOnboarding,
            onboardingStepIndex: try container.decodeIfPresent(
                Int.self,
                forKey: .onboardingStepIndex
            ),
            handsFreeStopHintUseCount: try container.decodeIfPresent(
                Int.self,
                forKey: .handsFreeStopHintUseCount
            ) ?? defaults.handsFreeStopHintUseCount,
            modelPrices: try container.decodeIfPresent(
                [AIModelPrice].self,
                forKey: .modelPrices
            ) ?? defaults.modelPrices
        )
    }

    public static let defaultHotkeys: [HotkeyDefinition] = [
        HotkeyDefinition(
            action: .dictate,
            modifiers: 1 << 23,
            usesFunctionKey: true,
            activation: .toggle,
            displayName: "Fn"
        ),
        HotkeyDefinition(
            action: .translate,
            modifiers: (1 << 23) | (1 << 17),
            usesFunctionKey: true,
            activation: .toggle,
            displayName: "Fn ⇧"
        ),
        HotkeyDefinition(
            action: .pasteLastResult,
            keyCode: 9,
            modifiers: (1 << 18) | (1 << 20),
            activation: .toggle,
            displayName: "⌃⌘V"
        )
    ]

    private static func normalizeHotkeys(_ hotkeys: [HotkeyDefinition]) -> [HotkeyDefinition] {
        let normalized = hotkeys.map { saved in
            var definition = saved

            if definition.usesFunctionKey {
                definition.modifiers |= 1 << 23
            }

            if let modifierFlag = modifierFlag(forLegacyKeyCode: definition.keyCode) {
                definition.keyCode = nil
                definition.modifiers |= modifierFlag
            }

            return definition
        }
        var signatures = Set<HotkeySignature>()
        return normalized.filter { definition in
            guard definition.action != .ask else { return false }
            return signatures.insert(definition.signature).inserted
        }
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
}
