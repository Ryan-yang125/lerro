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
    public var localProfileEmail: String
    public var localInvitationCode: String
    public var recognitionLocaleIdentifier: String
    public var translationLanguageIdentifiers: [String]
    public var appLanguage: AppLanguage
    public var microphoneDeviceUID: String?
    public var muteOtherAudio: Bool
    public var appearance: AppAppearance
    public var launchAtLogin: Bool
    public var showInDock: Bool
    public var saveAudio: Bool
    public var historyRetention: HistoryRetention
    public var enhancementEnabled: Bool {
        didSet {
            let resolvedMode: IntelligenceMode = enhancementEnabled
                ? (intelligenceMode == .raw ? .local : intelligenceMode)
                : .raw
            if intelligenceMode != resolvedMode {
                intelligenceMode = resolvedMode
            }
        }
    }
    public var intelligenceMode: IntelligenceMode {
        didSet {
            let resolvedEnhancement = intelligenceMode != .raw
            if enhancementEnabled != resolvedEnhancement {
                enhancementEnabled = resolvedEnhancement
            }
        }
    }
    public var localModelIdentifier: String
    public var remoteProvider: RemoteProviderConfiguration
    public var hotkeys: [HotkeyDefinition]
    public var appToneProfiles: [AppToneProfile]
    public var automaticDictionaryLearningEnabled: Bool
    public var quickDictateEnabled: Bool
    public var hasApprovedModelDownload: Bool
    public var hasCompletedOnboarding: Bool
    public var onboardingStepIndex: Int?

    public var shouldSaveCaptureAudio: Bool {
        saveAudio && historyRetention != .never
    }

    public var isAutomaticDictionaryLearningActive: Bool {
        automaticDictionaryLearningEnabled && intelligenceMode != .raw
    }

    public init(
        localProfileEmail: String = "",
        localInvitationCode: String = "",
        recognitionLocaleIdentifier: String = "zh_CN",
        translationLanguageIdentifiers: [String] = ["en_US"],
        appLanguage: AppLanguage = .system,
        microphoneDeviceUID: String? = nil,
        muteOtherAudio: Bool = true,
        appearance: AppAppearance = .system,
        launchAtLogin: Bool = false,
        showInDock: Bool = true,
        saveAudio: Bool = false,
        historyRetention: HistoryRetention = .forever,
        enhancementEnabled: Bool = false,
        intelligenceMode: IntelligenceMode? = nil,
        localModelIdentifier: String = "mlx-community/Qwen3.5-4B-MLX-4bit",
        remoteProvider: RemoteProviderConfiguration = RemoteProviderConfiguration(),
        hotkeys: [HotkeyDefinition] = UserPreferences.defaultHotkeys,
        appToneProfiles: [AppToneProfile] = [],
        automaticDictionaryLearningEnabled: Bool = true,
        quickDictateEnabled: Bool = false,
        hasApprovedModelDownload: Bool = false,
        hasCompletedOnboarding: Bool = false,
        onboardingStepIndex: Int? = nil
    ) {
        self.localProfileEmail = localProfileEmail
        self.localInvitationCode = localInvitationCode
        self.recognitionLocaleIdentifier = recognitionLocaleIdentifier
        self.translationLanguageIdentifiers = Array(translationLanguageIdentifiers.prefix(3))
        self.appLanguage = appLanguage
        self.microphoneDeviceUID = microphoneDeviceUID
        self.muteOtherAudio = muteOtherAudio
        self.appearance = appearance
        self.launchAtLogin = launchAtLogin
        self.showInDock = showInDock
        self.saveAudio = saveAudio
        self.historyRetention = historyRetention
        let resolvedMode = intelligenceMode ?? (enhancementEnabled ? .local : .raw)
        self.enhancementEnabled = resolvedMode != .raw
        self.intelligenceMode = resolvedMode
        self.localModelIdentifier = localModelIdentifier
        self.remoteProvider = remoteProvider
        self.hotkeys = hotkeys
        self.appToneProfiles = appToneProfiles
        self.automaticDictionaryLearningEnabled = automaticDictionaryLearningEnabled
        self.quickDictateEnabled = quickDictateEnabled
        self.hasApprovedModelDownload = hasApprovedModelDownload
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.onboardingStepIndex = onboardingStepIndex
    }

    private enum CodingKeys: String, CodingKey {
        case localProfileEmail
        case localInvitationCode
        case recognitionLocaleIdentifier
        case translationLanguageIdentifiers
        case appLanguage
        case microphoneDeviceUID
        case muteOtherAudio
        case appearance
        case launchAtLogin
        case showInDock
        case saveAudio
        case historyRetention
        case enhancementEnabled
        case intelligenceMode
        case localModelIdentifier
        case remoteProvider
        case hotkeys
        case appToneProfiles
        case automaticDictionaryLearningEnabled
        case quickDictateEnabled
        case hasApprovedModelDownload
        case hasCompletedOnboarding
        case onboardingStepIndex
    }

    public init(from decoder: any Decoder) throws {
        let defaults = UserPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyEnhancementEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .enhancementEnabled
        ) ?? defaults.enhancementEnabled
        let intelligenceMode = try container.decodeIfPresent(
            IntelligenceMode.self,
            forKey: .intelligenceMode
        ) ?? (legacyEnhancementEnabled ? .local : .raw)
        self.init(
            localProfileEmail: try container.decodeIfPresent(
                String.self,
                forKey: .localProfileEmail
            ) ?? defaults.localProfileEmail,
            localInvitationCode: try container.decodeIfPresent(
                String.self,
                forKey: .localInvitationCode
            ) ?? defaults.localInvitationCode,
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
            enhancementEnabled: intelligenceMode != .raw,
            intelligenceMode: intelligenceMode,
            localModelIdentifier: try container.decodeIfPresent(
                String.self,
                forKey: .localModelIdentifier
            ) ?? defaults.localModelIdentifier,
            remoteProvider: try container.decodeIfPresent(
                RemoteProviderConfiguration.self,
                forKey: .remoteProvider
            ) ?? defaults.remoteProvider,
            hotkeys: Self.migrateHotkeys(
                try container.decodeIfPresent(
                    [HotkeyDefinition].self,
                    forKey: .hotkeys
                ) ?? defaults.hotkeys
            ),
            appToneProfiles: try container.decodeIfPresent(
                [AppToneProfile].self,
                forKey: .appToneProfiles
            ) ?? defaults.appToneProfiles,
            automaticDictionaryLearningEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .automaticDictionaryLearningEnabled
            ) ?? defaults.automaticDictionaryLearningEnabled,
            quickDictateEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .quickDictateEnabled
            ) ?? defaults.quickDictateEnabled,
            hasApprovedModelDownload: try container.decodeIfPresent(
                Bool.self,
                forKey: .hasApprovedModelDownload
            ) ?? defaults.hasApprovedModelDownload,
            hasCompletedOnboarding: try container.decodeIfPresent(
                Bool.self,
                forKey: .hasCompletedOnboarding
            ) ?? defaults.hasCompletedOnboarding,
            onboardingStepIndex: try container.decodeIfPresent(
                Int.self,
                forKey: .onboardingStepIndex
            )
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

    private static func migrateHotkeys(_ hotkeys: [HotkeyDefinition]) -> [HotkeyDefinition] {
        let migrated = hotkeys.map { saved in
            var definition = saved

            if let baseAction = definition.action.legacyHandsFreeBaseAction {
                definition.action = baseAction
                definition.activation = .toggle
            } else {
                switch definition.activation {
                case .press:
                    definition.activation = definition.usesFunctionKey && definition.action.isCaptureAction
                        ? .hold
                        : .toggle
                case .doublePress:
                    definition.activation = .toggle
                case .hold, .toggle:
                    break
                }
            }

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
        return migrated.filter { definition in
            guard definition.action != .ask, definition.action != .askHandsFree else {
                return false
            }
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

private extension HotkeyAction {
    var legacyHandsFreeBaseAction: HotkeyAction? {
        switch self {
        case .dictateHandsFree: .dictate
        case .translateHandsFree: .translate
        case .askHandsFree: .ask
        case .dictate, .translate, .ask, .pasteLastResult, .cancel: nil
        }
    }

    var isCaptureAction: Bool {
        switch self {
        case .dictate, .translate, .ask,
             .dictateHandsFree, .translateHandsFree, .askHandsFree:
            true
        case .pasteLastResult, .cancel:
            false
        }
    }
}
