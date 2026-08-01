import AppKit
import SwiftUI
import LerroCore

enum ShortcutRecorderPolicy {
    static let maximumKeyCount = 3
    static let primaryModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
        .function
    ]

    static func normalizedModifiers(
        _ flags: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        flags.intersection(primaryModifiers)
    }

    static func modifierValidationMessage(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> String? {
        if keyCode == 57 {
            return "Caps Lock 具有锁定状态，请选择其他按键。"
        }
        if normalizedModifiers(flags).rawValue.nonzeroBitCount > maximumKeyCount {
            return "快捷键最多使用三个按键。"
        }
        return nil
    }

    static func keyValidationMessage(
        keyName: String,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> String? {
        let primary = normalizedModifiers(flags)
        if primary.rawValue.nonzeroBitCount + 1 > maximumKeyCount {
            return "快捷键最多使用三个按键。"
        }
        if isUnsafeBareKey(keyName, keyCode: keyCode, flags: primary) {
            return "单独字母、数字、空格和重音符会影响日常输入，请选择修饰键或组合键。"
        }
        if isSystemReserved(keyCode: keyCode, flags: primary) {
            return "这个组合由 macOS 或常用编辑命令使用，请选择其他快捷键。"
        }
        return nil
    }

    static func displayName(
        flags: NSEvent.ModifierFlags,
        keyName: String?
    ) -> String {
        let primary = normalizedModifiers(flags)
        var parts: [String] = []
        if primary.contains(.function) { parts.append("Fn") }
        if primary.contains(.control) { parts.append("⌃") }
        if primary.contains(.option) { parts.append("⌥") }
        if primary.contains(.shift) { parts.append("⇧") }
        if primary.contains(.command) { parts.append("⌘") }
        if let keyName { parts.append(keyName) }
        return parts.joined(separator: primary.contains(.function) ? " " : "")
    }

    private static func isUnsafeBareKey(
        _ keyName: String,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        guard flags.isEmpty else { return false }
        if keyCode == 49 || keyCode == 50 { return true }
        guard keyName.count == 1 else { return false }
        return keyName.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func isSystemReserved(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> Bool {
        let hasCommand = flags.contains(.command)
        let hasControl = flags.contains(.control)
        let hasOption = flags.contains(.option)
        let hasShift = flags.contains(.shift)

        // App lifecycle, navigation, editing, search, save, and window commands.
        let commonCommandKeys: Set<UInt16> = [
            0,   // A
            1,   // S
            3,   // F
            4,   // H
            6,   // Z
            7,   // X
            8,   // C
            9,   // V
            12,  // Q
            13,  // W
            31,  // O
            35,  // P
            43,  // comma
            45,  // N
            46,  // M
            48,  // Tab
            49,  // Space
            50   // grave accent
        ]
        let commandExtras = flags.subtracting([.command, .shift])
        if hasCommand,
           commandExtras.isEmpty,
           commonCommandKeys.contains(keyCode) { return true }

        // Input source and Spotlight shortcuts.
        if keyCode == 49, hasCommand || hasControl { return true }

        // Force Quit, Lock Screen, Full Screen, Dock, and Hide Others.
        if keyCode == 53, hasCommand, hasOption { return true }
        if keyCode == 12, hasCommand, hasControl { return true }
        if keyCode == 3, hasCommand, hasControl { return true }
        if [2, 4, 46].contains(keyCode), hasCommand, hasOption { return true }

        // Screenshot shortcuts.
        if [20, 21, 23].contains(keyCode), hasCommand, hasShift { return true }

        // Mission Control and Spaces navigation.
        if [123, 124, 125, 126].contains(keyCode), hasControl { return true }

        return false
    }
}

struct ShortcutBindingDraft: Equatable {
    let keyCode: Int64?
    let modifiers: UInt64
    let usesFunctionKey: Bool
    let displayName: String

    init(
        keyCode: Int64?,
        modifiers: UInt64,
        usesFunctionKey: Bool,
        displayName: String
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.usesFunctionKey = usesFunctionKey
        self.displayName = displayName
    }

    init(definition: HotkeyDefinition) {
        self.init(
            keyCode: definition.keyCode,
            modifiers: definition.modifiers,
            usesFunctionKey: definition.usesFunctionKey,
            displayName: definition.displayName
        )
    }
}

enum ShortcutRecorderInput: Equatable {
    case startRecording
    case stopRecording
    case flagsChanged(keyCode: UInt16, modifiers: UInt64)
    case keyDown(keyCode: UInt16, modifiers: UInt64, keyName: String?)
    case keyUp(keyCode: UInt16, modifiers: UInt64)
}

struct ShortcutRecorderState: Equatable {
    var isRecording = false
    var isPressed = false
    var liveShortcut: ShortcutBindingDraft?
    var validatedShortcut: ShortcutBindingDraft?
    var validationMessage = ""
    var announcement = ""

    fileprivate var sequence: ShortcutPhysicalKeySequence?

    init(
        validatedShortcut: ShortcutBindingDraft? = nil,
        startsRecording: Bool = false
    ) {
        self.validatedShortcut = validatedShortcut
        isRecording = startsRecording
        if startsRecording {
            announcement = "快捷键检测已开始"
        }
    }
}

private struct ShortcutPhysicalKeySequence: Equatable {
    var peakModifiers: UInt64 = 0
    var currentModifiers: UInt64 = 0
    var keyCode: UInt16?
    var keyName: String?
    var pressedKeyCodes: Set<UInt16> = []
    var validationMessage: String?
}

enum ShortcutRecorderReducer {
    static func reduce(
        state: inout ShortcutRecorderState,
        input: ShortcutRecorderInput
    ) {
        switch input {
        case .startRecording:
            state.isRecording = true
            state.isPressed = false
            state.liveShortcut = nil
            state.validationMessage = ""
            state.announcement = "快捷键检测已开始"
            state.sequence = nil

        case .stopRecording:
            state.isRecording = false
            state.isPressed = false
            state.liveShortcut = nil
            state.validationMessage = ""
            state.announcement = "快捷键检测已停止"
            state.sequence = nil

        case let .flagsChanged(keyCode, rawModifiers):
            guard state.isRecording else { return }
            handleFlagsChanged(
                state: &state,
                keyCode: keyCode,
                modifiers: modifiers(from: rawModifiers)
            )

        case let .keyDown(keyCode, rawModifiers, keyName):
            guard state.isRecording else { return }
            handleKeyDown(
                state: &state,
                keyCode: keyCode,
                modifiers: modifiers(from: rawModifiers),
                keyName: keyName
            )

        case let .keyUp(keyCode, rawModifiers):
            guard state.isRecording else { return }
            handleKeyUp(
                state: &state,
                keyCode: keyCode,
                modifiers: modifiers(from: rawModifiers)
            )
        }
    }

    private static func handleFlagsChanged(
        state: inout ShortcutRecorderState,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) {
        if keyCode == 57 {
            state.sequence = ShortcutPhysicalKeySequence(
                validationMessage: ShortcutRecorderPolicy.modifierValidationMessage(
                    keyCode: keyCode,
                    flags: modifiers
                )
            )
            finishSequence(state: &state)
            return
        }

        guard state.sequence != nil || !modifiers.isEmpty else { return }
        beginSequenceIfNeeded(state: &state)
        state.sequence?.currentModifiers = UInt64(modifiers.rawValue)
        state.sequence?.peakModifiers |= UInt64(modifiers.rawValue)
        if state.sequence?.validationMessage == nil,
           let peakModifiers = state.sequence?.peakModifiers {
            state.sequence?.validationMessage = ShortcutRecorderPolicy.modifierValidationMessage(
                keyCode: keyCode,
                flags: NSEvent.ModifierFlags(rawValue: UInt(peakModifiers))
            )
        }
        refreshLiveState(state: &state)

        if modifiers.isEmpty, state.sequence?.pressedKeyCodes.isEmpty == true {
            finishSequence(state: &state)
        }
    }

    private static func handleKeyDown(
        state: inout ShortcutRecorderState,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        keyName: String?
    ) {
        beginSequenceIfNeeded(state: &state)
        guard var sequence = state.sequence else { return }

        sequence.currentModifiers = UInt64(modifiers.rawValue)
        sequence.peakModifiers |= UInt64(modifiers.rawValue)

        if sequence.pressedKeyCodes.contains(keyCode) {
            state.sequence = sequence
            refreshLiveState(state: &state)
            return
        }

        sequence.pressedKeyCodes.insert(keyCode)
        if let existingKeyCode = sequence.keyCode, existingKeyCode != keyCode {
            sequence.validationMessage = "一组快捷键只能包含一个普通按键。"
        } else {
            sequence.keyCode = keyCode
            sequence.keyName = keyName
            if let keyName, !keyName.isEmpty {
                sequence.validationMessage = ShortcutRecorderPolicy.keyValidationMessage(
                    keyName: keyName,
                    keyCode: keyCode,
                    flags: NSEvent.ModifierFlags(rawValue: UInt(sequence.peakModifiers))
                )
            } else {
                sequence.validationMessage = "这个按键暂时无法识别，请换一个键。"
            }
        }

        state.sequence = sequence
        refreshLiveState(state: &state)
    }

    private static func handleKeyUp(
        state: inout ShortcutRecorderState,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) {
        guard var sequence = state.sequence else { return }
        sequence.currentModifiers = UInt64(modifiers.rawValue)
        sequence.peakModifiers |= UInt64(modifiers.rawValue)
        sequence.pressedKeyCodes.remove(keyCode)
        state.sequence = sequence
        refreshLiveState(state: &state)

        if sequence.pressedKeyCodes.isEmpty, modifiers.isEmpty {
            finishSequence(state: &state)
        }
    }

    private static func beginSequenceIfNeeded(state: inout ShortcutRecorderState) {
        if state.sequence == nil {
            state.sequence = ShortcutPhysicalKeySequence()
            state.validationMessage = ""
            state.announcement = ""
        }
    }

    private static func refreshLiveState(state: inout ShortcutRecorderState) {
        guard let sequence = state.sequence else {
            state.isPressed = false
            state.liveShortcut = nil
            return
        }
        let peakModifiers = NSEvent.ModifierFlags(rawValue: UInt(sequence.peakModifiers))
        state.liveShortcut = makeDraft(
            keyCode: sequence.keyCode,
            keyName: sequence.keyName,
            modifiers: peakModifiers
        )
        state.isPressed = !sequence.pressedKeyCodes.isEmpty
            || !NSEvent.ModifierFlags(rawValue: UInt(sequence.currentModifiers)).isEmpty
        state.validationMessage = sequence.validationMessage ?? ""
    }

    private static func finishSequence(state: inout ShortcutRecorderState) {
        guard let sequence = state.sequence else { return }
        let peakModifiers = NSEvent.ModifierFlags(rawValue: UInt(sequence.peakModifiers))
        let candidate = makeDraft(
            keyCode: sequence.keyCode,
            keyName: sequence.keyName,
            modifiers: peakModifiers
        )

        var message = sequence.validationMessage
        if message == nil {
            if let keyCode = sequence.keyCode, let keyName = sequence.keyName {
                message = ShortcutRecorderPolicy.keyValidationMessage(
                    keyName: keyName,
                    keyCode: keyCode,
                    flags: peakModifiers
                )
            } else {
                message = ShortcutRecorderPolicy.modifierValidationMessage(
                    keyCode: 0,
                    flags: peakModifiers
                )
            }
        }

        if let message {
            state.validationMessage = message
            state.announcement = "快捷键无法使用：\(message)"
        } else if let candidate, !candidate.displayName.isEmpty {
            state.validatedShortcut = candidate
            state.validationMessage = ""
            state.announcement = "已识别快捷键 \(candidate.displayName)"
        }

        state.sequence = nil
        state.liveShortcut = nil
        state.isPressed = false
    }

    private static func makeDraft(
        keyCode: UInt16?,
        keyName: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> ShortcutBindingDraft? {
        guard keyCode != nil || !modifiers.isEmpty else { return nil }
        let displayKeyName = keyName ?? keyCode.map { "Key \($0)" }
        return ShortcutBindingDraft(
            keyCode: keyCode.map(Int64.init),
            modifiers: UInt64(modifiers.rawValue),
            usesFunctionKey: modifiers.contains(.function),
            displayName: ShortcutRecorderPolicy.displayName(
                flags: modifiers,
                keyName: displayKeyName
            )
        )
    }

    private static func modifiers(from rawValue: UInt64) -> NSEvent.ModifierFlags {
        ShortcutRecorderPolicy.normalizedModifiers(
            NSEvent.ModifierFlags(rawValue: UInt(rawValue))
        )
    }
}

struct ShortcutRecorderCard: View {
    @Binding var shortcut: ShortcutBindingDraft?
    @Binding var activation: ShortcutActivation
    var onEscape: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recorderState: ShortcutRecorderState

    init(
        shortcut: Binding<ShortcutBindingDraft?>,
        activation: Binding<ShortcutActivation>,
        onEscape: @escaping () -> Void = {}
    ) {
        _shortcut = shortcut
        _activation = activation
        self.onEscape = onEscape
        _recorderState = State(
            initialValue: ShortcutRecorderState(
                validatedShortcut: shortcut.wrappedValue,
                startsRecording: true
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("触发方式", selection: activationBinding) {
                Text("按住说话").tag(ShortcutActivation.hold)
                Text("按一下开关").tag(ShortcutActivation.toggle)
            }
            .pickerStyle(.segmented)
            .accessibilityHint("选择松开后完成，或再次按下后完成")

            HStack(spacing: 10) {
                Label(
                    recorderState.isRecording ? "按键检测中" : "按键检测已暂停",
                    systemImage: recorderState.isRecording ? "record.circle" : "keyboard"
                )
                .font(LerroTheme.font(12, weight: .medium))
                .foregroundStyle(recorderState.isRecording ? LerroTheme.accent : LerroTheme.secondaryText)

                Spacer()

                Button(recorderState.isRecording ? "停止检测" : "开始检测") {
                    setRecordingActive(!recorderState.isRecording)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(
                    recorderState.isRecording
                        ? "恢复 Tab 和 Return 的标准键盘导航"
                        : "开始读取按键，麦克风保持关闭"
                )
            }

            ZStack {
                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                    .fill(recorderState.isPressed ? LerroTheme.accent.opacity(0.14) : LerroTheme.fillContainerThin)
                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                    .stroke(
                        recorderState.isPressed ? LerroTheme.accent : LerroTheme.border,
                        lineWidth: recorderState.isPressed ? 2 : 1
                    )

                VStack(spacing: 10) {
                    ShortcutLiveKeycap(
                        title: displayedShortcut?.displayName ?? "尚未选择快捷键",
                        isPressed: recorderState.isPressed,
                        reduceMotion: reduceMotion
                    )

                    Label(statusText, systemImage: statusIcon)
                        .font(LerroTheme.font(12, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                ShortcutEventRecorder(
                    isActive: recorderState.isRecording,
                    onEvent: receive
                )
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .accessibilityHidden(true)
            }
            .frame(height: 112)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("快捷键录制")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(
                recorderState.isRecording
                    ? "按下并松开快捷键完成识别，检测会继续运行"
                    : "选择开始检测后可以读取按键"
            )

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: recorderState.validationMessage.isEmpty ? "checkmark.shield" : "exclamationmark.triangle.fill")
                    .foregroundStyle(recorderState.validationMessage.isEmpty ? Color.secondary : LerroTheme.orange)
                    .accessibilityHidden(true)
                Text(recorderState.validationMessage.isEmpty ? guidanceText : recorderState.validationMessage)
                    .font(LerroTheme.font(12))
                    .foregroundStyle(recorderState.validationMessage.isEmpty ? LerroTheme.secondaryText : LerroTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .onChange(of: shortcut) { _, newValue in
            guard recorderState.validatedShortcut != newValue else { return }
            recorderState.validatedShortcut = newValue
            recorderState.validationMessage = ""
        }
        .onDisappear {
            if recorderState.isRecording {
                setRecordingActive(false, announce: false)
            }
        }
    }

    private var activationBinding: Binding<ShortcutActivation> {
        Binding {
            activation.resolved
        } set: { activation = $0.resolved }
    }

    private var displayedShortcut: ShortcutBindingDraft? {
        recorderState.liveShortcut ?? recorderState.validatedShortcut
    }

    private var statusText: String {
        if recorderState.isPressed {
            return "已检测到 \(recorderState.liveShortcut?.displayName ?? "按键") 按下"
        }
        if recorderState.isRecording {
            if let shortcut = recorderState.validatedShortcut {
                return "已识别 \(shortcut.displayName)，可以继续测试"
            }
            return "正在等待按键"
        }
        if let shortcut = recorderState.validatedShortcut {
            return "当前快捷键为 \(shortcut.displayName)"
        }
        return "点击开始检测"
    }

    private var statusIcon: String {
        if recorderState.isPressed { return "circle.inset.filled" }
        if recorderState.validatedShortcut != nil { return "checkmark.circle.fill" }
        return recorderState.isRecording ? "keyboard" : "pause.circle"
    }

    private var statusColor: Color {
        if recorderState.isPressed { return LerroTheme.accent }
        if recorderState.validatedShortcut != nil { return LerroTheme.green }
        return LerroTheme.secondaryText
    }

    private var guidanceText: String {
        if !recorderState.isRecording {
            return "开始检测后会即时显示按下与松开；当前 Tab 和 Return 用于标准键盘导航。"
        }
        if let shortcut = recorderState.validatedShortcut,
           shortcut.keyCode == nil,
           !shortcut.usesFunctionKey {
            return "单独使用系统修饰键时会短暂确认按键意图，常用系统组合键仍可正常使用。"
        }
        return "检测期间麦克风保持关闭。支持 Fn、Control、Option、Shift、Command、单键与组合键。"
    }

    private var accessibilityValue: String {
        let binding = displayedShortcut?.displayName ?? "尚未选择"
        let state: String
        if recorderState.isPressed {
            state = "当前按下"
        } else if recorderState.isRecording {
            state = "正在检测"
        } else {
            state = "检测已暂停"
        }
        let mode = activation.resolved == .hold ? "按住说话" : "按一下开关"
        return "\(binding)，\(state)，\(mode)"
    }

    private func setRecordingActive(_ active: Bool, announce: Bool = true) {
        ShortcutRecorderReducer.reduce(
            state: &recorderState,
            input: active ? .startRecording : .stopRecording
        )
        if announce { postAccessibilityAnnouncement(recorderState.announcement) }
    }

    private func receive(_ event: ShortcutRecorderEvent) {
        if event.kind == .keyDown, event.keyCode == 53 {
            onEscape()
            return
        }

        let input: ShortcutRecorderInput
        switch event.kind {
        case .flagsChanged:
            input = .flagsChanged(
                keyCode: event.keyCode,
                modifiers: UInt64(event.modifierFlags.rawValue)
            )
        case .keyDown:
            input = .keyDown(
                keyCode: event.keyCode,
                modifiers: UInt64(event.modifierFlags.rawValue),
                keyName: Self.keyName(for: event)
            )
        case .keyUp:
            input = .keyUp(
                keyCode: event.keyCode,
                modifiers: UInt64(event.modifierFlags.rawValue)
            )
        }

        let previousShortcut = recorderState.validatedShortcut
        let previousAnnouncement = recorderState.announcement
        ShortcutRecorderReducer.reduce(state: &recorderState, input: input)
        if recorderState.validatedShortcut != previousShortcut {
            shortcut = recorderState.validatedShortcut
        }
        if !recorderState.announcement.isEmpty,
           recorderState.announcement != previousAnnouncement {
            postAccessibilityAnnouncement(recorderState.announcement)
        }
    }

    private func postAccessibilityAnnouncement(_ message: String) {
        guard !message.isEmpty else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private static func keyName(for event: ShortcutRecorderEvent) -> String? {
        switch event.keyCode {
        case 36: "↩"
        case 48: "⇥"
        case 49: "Space"
        case 51: "⌫"
        case 71: "Clear"
        case 76: "Enter"
        case 117: "⌦"
        case 115: "Home"
        case 119: "End"
        case 116: "Page Up"
        case 121: "Page Down"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        case 122: "F1"
        case 120: "F2"
        case 99: "F3"
        case 118: "F4"
        case 96: "F5"
        case 97: "F6"
        case 98: "F7"
        case 100: "F8"
        case 101: "F9"
        case 109: "F10"
        case 103: "F11"
        case 111: "F12"
        default: event.charactersIgnoringModifiers?.uppercased()
        }
    }
}

private struct ShortcutLiveKeycap: View {
    let title: String
    let isPressed: Bool
    let reduceMotion: Bool

    var body: some View {
        Text(title)
            .font(LerroTheme.font(14, weight: .medium))
            .tracking(LerroTheme.uiTracking)
            .foregroundStyle(isPressed ? LerroTheme.pivotText : LerroTheme.text)
            .padding(.horizontal, 16)
            .frame(minWidth: 72, minHeight: 38)
            .background(isPressed ? LerroTheme.accent : LerroTheme.topLayer)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.navigationRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.navigationRadius, style: .continuous)
                    .stroke(isPressed ? LerroTheme.accent : LerroTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(isPressed ? 0.08 : 0.12), radius: isPressed ? 1 : 3, y: isPressed ? 1 : 2)
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
    }
}

private struct ShortcutEventRecorder: NSViewRepresentable {
    let isActive: Bool
    let onEvent: (ShortcutRecorderEvent) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onEvent = onEvent
        view.isRecording = isActive
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onEvent = onEvent
        nsView.isRecording = isActive
    }

    static func dismantleNSView(_ nsView: ShortcutCaptureNSView, coordinator: ()) {
        nsView.isRecording = false
        nsView.onEvent = nil
    }
}

struct ShortcutRecorderEvent {
    enum Kind: Equatable {
        case flagsChanged
        case keyDown
        case keyUp
    }

    let kind: Kind
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags
    let charactersIgnoringModifiers: String?

    init(kind: Kind, event: NSEvent) {
        self.kind = kind
        keyCode = event.keyCode
        modifierFlags = event.modifierFlags
        switch kind {
        case .keyDown, .keyUp:
            charactersIgnoringModifiers = event.charactersIgnoringModifiers
        case .flagsChanged:
            charactersIgnoringModifiers = nil
        }
    }
}

final class ShortcutCaptureNSView: NSView {
    var onEvent: ((ShortcutRecorderEvent) -> Void)?
    private var localEventMonitor: Any?

    var hasLocalEventMonitor: Bool { localEventMonitor != nil }

    var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            if isRecording {
                beginRecording()
            } else {
                endRecording()
            }
        }
    }

    override var acceptsFirstResponder: Bool { false }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            removeLocalEventMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isRecording {
            beginRecording()
        } else {
            removeLocalEventMonitor()
        }
    }

    private func beginRecording() {
        guard localEventMonitor == nil, window != nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            guard let self,
                  isRecording,
                  eventBelongsToRecordingWindow(event) else { return event }
            return handleRecordingEvent(event)
        }
    }

    private func endRecording() {
        removeLocalEventMonitor()
    }

    private func eventBelongsToRecordingWindow(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        if event.window === window || event.windowNumber == window.windowNumber {
            return true
        }
        return event.window == nil && NSApplication.shared.keyWindow === window
    }

    private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
        let kind: ShortcutRecorderEvent.Kind
        switch event.type {
        case .flagsChanged:
            kind = .flagsChanged
        case .keyDown:
            kind = .keyDown
        case .keyUp:
            kind = .keyUp
        default:
            return event
        }
        onEvent?(ShortcutRecorderEvent(kind: kind, event: event))
        return nil
    }

    private func removeLocalEventMonitor() {
        guard let localEventMonitor else { return }
        NSEvent.removeMonitor(localEventMonitor)
        self.localEventMonitor = nil
    }
}
