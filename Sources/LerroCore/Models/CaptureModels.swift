import Foundation

public enum SidebarDestination: String, CaseIterable, Codable, Sendable {
    case home
    case history
    case dictionary
    case appTones
}

public enum CaptureMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case dictation
    case translation

    public var id: String { rawValue }

    /// History files written by older versions may hold modes that no longer exist
    /// ("ask"). They decode as `.dictation`.
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .dictation
    }
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

public struct UTF16TextRange: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }
}

public struct ScreenRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
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
    public var subrole: String?
    public var isSecureField: Bool
    public var focusedElementAvailable: Bool
    public var focusedElementFingerprint: Int?
    public var focusedValueFingerprint: Int?
    public var selectedRange: UTF16TextRange?
    public var focusedElementScreenFrame: ScreenRect?

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
        subrole: String? = nil,
        isSecureField: Bool = false,
        focusedElementAvailable: Bool = false,
        focusedElementFingerprint: Int? = nil,
        focusedValueFingerprint: Int? = nil,
        selectedRange: UTF16TextRange? = nil,
        focusedElementScreenFrame: ScreenRect? = nil
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
        self.subrole = subrole
        self.isSecureField = isSecureField
        self.focusedElementAvailable = focusedElementAvailable
        self.focusedElementFingerprint = focusedElementFingerprint
        self.focusedValueFingerprint = focusedValueFingerprint
        self.selectedRange = selectedRange
        self.focusedElementScreenFrame = focusedElementScreenFrame
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
        case subrole
        case isSecureField
        case focusedElementAvailable
        case focusedElementFingerprint
        case focusedValueFingerprint
        case selectedRange
        case focusedElementScreenFrame
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
        subrole = try container.decodeIfPresent(String.self, forKey: .subrole)
        isSecureField = try container.decode(Bool.self, forKey: .isSecureField)
        focusedElementAvailable = try container.decodeIfPresent(
            Bool.self,
            forKey: .focusedElementAvailable
        ) ?? false
        focusedElementFingerprint = try container.decodeIfPresent(
            Int.self,
            forKey: .focusedElementFingerprint
        )
        focusedValueFingerprint = try container.decodeIfPresent(
            Int.self,
            forKey: .focusedValueFingerprint
        )
        selectedRange = try container.decodeIfPresent(UTF16TextRange.self, forKey: .selectedRange)
        focusedElementScreenFrame = try container.decodeIfPresent(
            ScreenRect.self,
            forKey: .focusedElementScreenFrame
        )
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
        try container.encodeIfPresent(subrole, forKey: .subrole)
        try container.encode(isSecureField, forKey: .isSecureField)
        try container.encode(focusedElementAvailable, forKey: .focusedElementAvailable)
        try container.encodeIfPresent(focusedElementFingerprint, forKey: .focusedElementFingerprint)
        try container.encodeIfPresent(focusedValueFingerprint, forKey: .focusedValueFingerprint)
        try container.encodeIfPresent(selectedRange, forKey: .selectedRange)
        try container.encodeIfPresent(focusedElementScreenFrame, forKey: .focusedElementScreenFrame)
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
    public let toneInstruction: String?
    public let toneProfileApplicationName: String?

    public init(
        id: UUID = UUID(),
        mode: CaptureMode,
        startedAt: Date = .now,
        context: CapturedContext,
        targetLanguage: String? = nil,
        intelligenceMode: IntelligenceMode = .raw,
        remoteProvider: RemoteProviderConfiguration? = nil,
        toneInstruction: String? = nil,
        toneProfileApplicationName: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.context = context
        self.targetLanguage = targetLanguage
        self.intelligenceMode = intelligenceMode
        self.remoteProvider = remoteProvider
        self.toneInstruction = toneInstruction
        self.toneProfileApplicationName = toneProfileApplicationName
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
    case pasteLastResult
    case cancel
}

public enum ShortcutActivation: String, CaseIterable, Codable, Sendable {
    case hold
    case toggle
}

public enum HotkeyGesturePhase: String, Codable, Sendable {
    /// A modifier-only capture shortcut is physically pressed and may still
    /// turn out to be part of a combo. Followed by `began` or `disarmed`.
    case armed
    /// The armed press turned out to be a combo, was held too long or was
    /// interrupted. No `began` follows for it.
    case disarmed
    case began
    case ended
}

public struct HotkeyTrigger: Equatable, Sendable {
    public let action: HotkeyAction
    public let activation: ShortcutActivation
    public let phase: HotkeyGesturePhase
    public let definitionID: String?
    /// When the physical key event that started this gesture was received.
    /// Diagnostics only, so it is excluded from equality.
    public let pressedAt: ContinuousClock.Instant?

    public init(
        action: HotkeyAction,
        activation: ShortcutActivation,
        phase: HotkeyGesturePhase,
        definitionID: String? = nil,
        pressedAt: ContinuousClock.Instant? = nil
    ) {
        self.action = action
        self.activation = activation
        self.phase = phase
        self.definitionID = definitionID
        self.pressedAt = pressedAt
    }

    public static func == (lhs: HotkeyTrigger, rhs: HotkeyTrigger) -> Bool {
        lhs.action == rhs.action
            && lhs.activation == rhs.activation
            && lhs.phase == rhs.phase
            && lhs.definitionID == rhs.definitionID
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
        ) ?? .toggle
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
