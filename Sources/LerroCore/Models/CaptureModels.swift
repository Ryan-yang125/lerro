import Foundation

public enum SidebarDestination: String, CaseIterable, Codable, Sendable {
    case home
    case history
    case dictionary
}

public enum SettingsDestination: String, CaseIterable, Codable, Sendable {
    case account
    case settings
    case intelligence
    case personal
    case about
    case help
    case releaseNotes
}

public enum SettingsEntryPoint: String, CaseIterable, Codable, Sendable {
    case account
    case settings
    case intelligence
    case personalization
    case upgrade
    case invitation
    case recommendation

    public var destination: SettingsDestination {
        switch self {
        case .account, .upgrade, .invitation, .recommendation:
            .account
        case .settings:
            .settings
        case .intelligence:
            .intelligence
        case .personalization:
            .personal
        }
    }
}

public enum CaptureMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case dictation
    case translation
    case ask

    public var id: String { rawValue }
}

public enum CapturePhase: String, Codable, Sendable {
    case idle
    case listening
    case transcribing
    case enhancing
    case inserting
    case success
    case failed
    case cancelled
}

public enum TextSelectionState: String, Codable, Hashable, Sendable {
    case knownEmpty
    case knownSelection
    case unavailable
}

public struct CapturedContext: Codable, Hashable, Sendable {
    public static let maximumSelectedTextCharacters = 4_096

    public var applicationName: String
    public var processIdentifier: Int32?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var selectedText: String?
    public var selectedTextWasTruncated: Bool
    public var selectedTextFingerprint: Int?
    public var selectionState: TextSelectionState
    public var focusedText: String?
    public var cursorBefore: String?
    public var cursorAfter: String?
    public var role: String?
    public var isSecureField: Bool

    public init(
        applicationName: String = "Unknown",
        processIdentifier: Int32? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        selectedText: String? = nil,
        selectedTextWasTruncated: Bool = false,
        selectedTextFingerprint: Int? = nil,
        selectionState: TextSelectionState? = nil,
        focusedText: String? = nil,
        cursorBefore: String? = nil,
        cursorAfter: String? = nil,
        role: String? = nil,
        isSecureField: Bool = false
    ) {
        self.applicationName = applicationName
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.selectedText = selectedText
        self.selectedTextWasTruncated = selectedTextWasTruncated
        self.selectedTextFingerprint = selectedTextFingerprint
        self.selectionState = selectionState
            ?? (selectedText?.isEmpty == false ? .knownSelection : .unavailable)
        self.focusedText = focusedText
        self.cursorBefore = cursorBefore
        self.cursorAfter = cursorAfter
        self.role = role
        self.isSecureField = isSecureField
    }

    private enum CodingKeys: String, CodingKey {
        case applicationName
        case processIdentifier
        case bundleIdentifier
        case windowTitle
        case selectedText
        case selectedTextWasTruncated
        case selectedTextFingerprint
        case selectionState
        case focusedText
        case cursorBefore
        case cursorAfter
        case role
        case isSecureField
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applicationName = try container.decode(String.self, forKey: .applicationName)
        processIdentifier = try container.decodeIfPresent(Int32.self, forKey: .processIdentifier)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        selectedText = try container.decodeIfPresent(String.self, forKey: .selectedText)
        selectedTextWasTruncated = try container.decodeIfPresent(
            Bool.self,
            forKey: .selectedTextWasTruncated
        ) ?? false
        selectedTextFingerprint = try container.decodeIfPresent(
            Int.self,
            forKey: .selectedTextFingerprint
        )
        selectionState = try container.decodeIfPresent(
            TextSelectionState.self,
            forKey: .selectionState
        ) ?? (selectedText?.isEmpty == false ? .knownSelection : .unavailable)
        focusedText = try container.decodeIfPresent(String.self, forKey: .focusedText)
        cursorBefore = try container.decodeIfPresent(String.self, forKey: .cursorBefore)
        cursorAfter = try container.decodeIfPresent(String.self, forKey: .cursorAfter)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        isSecureField = try container.decode(Bool.self, forKey: .isSecureField)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(applicationName, forKey: .applicationName)
        try container.encodeIfPresent(processIdentifier, forKey: .processIdentifier)
        try container.encodeIfPresent(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
        try container.encodeIfPresent(selectedText, forKey: .selectedText)
        try container.encode(selectedTextWasTruncated, forKey: .selectedTextWasTruncated)
        try container.encodeIfPresent(selectedTextFingerprint, forKey: .selectedTextFingerprint)
        try container.encode(selectionState, forKey: .selectionState)
        try container.encodeIfPresent(focusedText, forKey: .focusedText)
        try container.encodeIfPresent(cursorBefore, forKey: .cursorBefore)
        try container.encodeIfPresent(cursorAfter, forKey: .cursorAfter)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(isSecureField, forKey: .isSecureField)
    }
}

public struct CaptureSession: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let mode: CaptureMode
    public let startedAt: Date
    public let context: CapturedContext
    public let targetLanguage: String?
    public let intelligenceMode: IntelligenceMode
    public let remoteProvider: RemoteProviderConfiguration?

    public init(
        id: UUID = UUID(),
        mode: CaptureMode,
        startedAt: Date = .now,
        context: CapturedContext,
        targetLanguage: String? = nil,
        intelligenceMode: IntelligenceMode = .local,
        remoteProvider: RemoteProviderConfiguration? = nil
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.context = context
        self.targetLanguage = targetLanguage
        self.intelligenceMode = intelligenceMode
        self.remoteProvider = remoteProvider
    }
}

public enum SpeechEvent: Sendable, Equatable {
    case audioLevel(Float)
    case partial(String)
    case final(String)
    case availability(String)
}

public struct SpeechTranscription: Sendable, Equatable {
    public var rawText: String
    public var localeIdentifier: String
    public var duration: TimeInterval
    public var audioRelativePath: String?

    public init(
        rawText: String,
        localeIdentifier: String,
        duration: TimeInterval,
        audioRelativePath: String? = nil
    ) {
        self.rawText = rawText
        self.localeIdentifier = localeIdentifier
        self.duration = duration
        self.audioRelativePath = audioRelativePath
    }
}

public struct AudioInputDevice: Codable, Hashable, Identifiable, Sendable {
    public var id: String { uid }
    public let uid: String
    public let name: String
    public let isDefault: Bool

    public init(uid: String, name: String, isDefault: Bool = false) {
        self.uid = uid
        self.name = name
        self.isDefault = isDefault
    }
}

public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case dictate
    case translate
    case ask
    case dictateHandsFree
    case translateHandsFree
    case askHandsFree
    case pasteLastResult
    case cancel
}

public enum ShortcutActivation: String, CaseIterable, Codable, Sendable {
    case hold
    case toggle

    // Kept for decoding preferences written before the shortcut recorder
    // exposed an explicit interaction mode.
    case press
    case doublePress

    public var resolved: ShortcutActivation {
        switch self {
        case .hold:
            .hold
        case .toggle, .press, .doublePress:
            .toggle
        }
    }
}

public enum HotkeyGesturePhase: String, Codable, Sendable {
    case began
    case ended
}

public struct HotkeyTrigger: Equatable, Sendable {
    public let action: HotkeyAction
    public let activation: ShortcutActivation
    public let phase: HotkeyGesturePhase
    public let definitionID: String?

    public init(
        action: HotkeyAction,
        activation: ShortcutActivation,
        phase: HotkeyGesturePhase,
        definitionID: String? = nil
    ) {
        self.action = action
        self.activation = activation.resolved
        self.phase = phase
        self.definitionID = definitionID
    }
}

/// The physical key identity used for conflict detection and runtime matching.
/// AppKit and CoreGraphics expose aggregate modifier flags, so left and right
/// variants intentionally share one signature.
public struct HotkeySignature: Hashable, Sendable {
    public let keyCode: Int64?
    public let modifiers: UInt64

    public init(keyCode: Int64?, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct HotkeyDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: String {
        [
            action.rawValue,
            keyCode.map(String.init) ?? "modifier",
            String(modifiers),
            usesFunctionKey ? "fn" : "plain",
            activation.rawValue
        ].joined(separator: ":")
    }
    public var action: HotkeyAction
    public var keyCode: Int64?
    public var modifiers: UInt64
    public var usesFunctionKey: Bool
    public var activation: ShortcutActivation
    public var displayName: String

    public var signature: HotkeySignature {
        var normalizedKeyCode = keyCode
        var normalizedModifiers = modifiers & Self.primaryModifierMask
        if usesFunctionKey {
            normalizedModifiers |= Self.functionModifier
        }
        if let keyCode, let modifier = Self.modifierFlag(forLegacyKeyCode: keyCode) {
            normalizedKeyCode = nil
            normalizedModifiers |= modifier
        }
        return HotkeySignature(
            keyCode: normalizedKeyCode,
            modifiers: normalizedModifiers & Self.primaryModifierMask
        )
    }

    public init(
        action: HotkeyAction,
        keyCode: Int64? = nil,
        modifiers: UInt64 = 0,
        usesFunctionKey: Bool = false,
        activation: ShortcutActivation = .toggle,
        displayName: String
    ) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.usesFunctionKey = usesFunctionKey
        self.activation = activation
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case keyCode
        case modifiers
        case usesFunctionKey
        case activation
        case displayName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(HotkeyAction.self, forKey: .action)
        keyCode = try container.decodeIfPresent(Int64.self, forKey: .keyCode)
        modifiers = try container.decodeIfPresent(UInt64.self, forKey: .modifiers) ?? 0
        usesFunctionKey = try container.decodeIfPresent(Bool.self, forKey: .usesFunctionKey) ?? false
        activation = try container.decodeIfPresent(
            ShortcutActivation.self,
            forKey: .activation
        ) ?? .press
        displayName = try container.decode(String.self, forKey: .displayName)
    }

    private static let functionModifier: UInt64 = 1 << 23
    private static let primaryModifierMask: UInt64 = (1 << 17)
        | (1 << 18)
        | (1 << 19)
        | (1 << 20)
        | functionModifier

    private static func modifierFlag(forLegacyKeyCode keyCode: Int64) -> UInt64? {
        switch keyCode {
        case 54, 55: 1 << 20
        case 56, 60: 1 << 17
        case 58, 61: 1 << 19
        case 59, 62: 1 << 18
        case 63: functionModifier
        default: nil
        }
    }
}
