import SwiftUI
import LerroCore

struct DictationSettingsTab: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @State private var recordingAction: HotkeyAction?
    @State private var editingShortcut: HotkeyDefinition?

    private static let shortcutLimit = 4

    var body: some View {
        Form {
            SettingsPermissionBanner(session: session)

            dictationSection
            translationSection

            Section {
                pasteLastResultRow
            }

            microphoneSection
        }
        .settingsForm(height: SettingsLayout.tallHeight)
        .task { await session.refreshAudioInputDevices() }
        .sheet(
            isPresented: shortcutRecorderPresented,
            onDismiss: { session.endShortcutConfiguration() }
        ) {
            if let action = recordingAction {
                ShortcutCaptureSheet(
                    action: action,
                    existing: editingShortcut,
                    onBeginRecording: { session.beginShortcutConfiguration() },
                    onEndRecording: { session.endShortcutConfiguration() },
                    onSave: { shortcut, activation in
                        session.currentError = nil
                        let saved = await session.commitHotkey(
                            for: action,
                            replacing: editingShortcut,
                            keyCode: shortcut.keyCode,
                            modifiers: shortcut.modifiers,
                            usesFunctionKey: shortcut.usesFunctionKey,
                            activation: activation,
                            displayName: shortcut.displayName
                        )
                        if saved {
                            recordingAction = nil
                            editingShortcut = nil
                            return nil
                        }
                        let message = session.currentError?.trimmingCharacters(in: .whitespacesAndNewlines)
                        session.currentError = nil
                        if let message, !message.isEmpty { return message }
                        return "快捷键保存失败，请重新选择后再试。"
                    },
                    onCancel: {
                        recordingAction = nil
                        editingShortcut = nil
                    }
                )
            }
        }
        .onDisappear { session.endShortcutConfiguration() }
    }

    // MARK: Dictation

    private var dictationSection: some View {
        let definitions = shortcuts(.dictate)
        let reachedLimit = definitions.count >= Self.shortcutLimit
        let configurationUnavailable = !session.shortcutConfigurationAvailable

        return Section {
            ForEach(definitions) { definition in
                shortcutRow(
                    definition,
                    actionTitle: "听写",
                    canDelete: definitions.count > 1,
                    configurationUnavailable: configurationUnavailable
                )
            }

            LabeledContent("触发方式") {
                Picker("触发方式", selection: dictationActivation) {
                    Text("按一下开始或结束").tag(ShortcutActivation.toggle)
                    Text("按住说话").tag(ShortcutActivation.hold)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(configurationUnavailable)
            }

            Picker("听写语言", selection: $session.preferences.recognitionLocaleIdentifier) {
                Text("简体中文").tag("zh_CN")
                Text("繁體中文").tag("zh_TW")
                Text("English (US)").tag("en_US")
                Text("English (UK)").tag("en_GB")
                Text("日本語").tag("ja_JP")
            }
        } header: {
            Text("听写")
        } footer: {
            Button("添加快捷键") {
                presentShortcutRecorder(for: .dictate, existing: nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LerroTheme.accentText)
            .disabled(reachedLimit || configurationUnavailable)
            .help(Text(verbatim: addShortcutHelp(unavailable: configurationUnavailable, reachedLimit: reachedLimit)))
        }
    }

    /// Activation of the first dictation shortcut; changing it applies to every dictation shortcut.
    private var dictationActivation: Binding<ShortcutActivation> {
        Binding {
            shortcuts(.dictate).first?.activation ?? .toggle
        } set: { activation in
            let definitions = shortcuts(.dictate).filter { $0.activation != activation }
            guard !definitions.isEmpty else { return }
            Task { @MainActor in
                for definition in definitions {
                    _ = await session.commitHotkey(
                        for: .dictate,
                        replacing: definition,
                        keyCode: definition.keyCode,
                        modifiers: definition.modifiers,
                        usesFunctionKey: definition.usesFunctionKey,
                        activation: activation,
                        displayName: definition.displayName
                    )
                }
            }
        }
    }

    // MARK: Translation

    private var translationSection: some View {
        let definitions = shortcuts(.translate)
        let configurationUnavailable = !session.shortcutConfigurationAvailable

        return Section("翻译") {
            ForEach(definitions) { definition in
                shortcutRow(
                    definition,
                    actionTitle: "翻译",
                    canDelete: definitions.count > 1,
                    configurationUnavailable: configurationUnavailable
                )
            }

            Picker("翻译成", selection: $session.preferences.translationLanguageIdentifier) {
                ForEach(TranslationLanguageOption.all) { option in
                    Text(verbatim: LerroInterfaceLocalization.string(option.title, locale: locale))
                        .tag(option.identifier)
                }
            }
        }
    }

    // MARK: Paste last result

    private var pasteLastResultRow: some View {
        let definition = shortcuts(.pasteLastResult).first
        let configurationUnavailable = !session.shortcutConfigurationAvailable

        return LabeledContent("粘贴上次结果") {
            HStack(spacing: 8) {
                if let definition {
                    LerroShortcutKeys(displayName: definition.displayName)
                } else {
                    Text("未设置")
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Button("更改") {
                    presentShortcutRecorder(for: .pasteLastResult, existing: definition)
                }
                .buttonStyle(LerroButtonStyle(.secondary))
                .disabled(configurationUnavailable)
                .help(Text(verbatim: configurationUnavailable
                    ? LerroInterfaceLocalization.string("请在语音输入结束后再修改快捷键", locale: locale)
                    : LerroInterfaceLocalization.string("更改", locale: locale)))
            }
        }
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        Section("麦克风") {
            LabeledContent("麦克风") {
                HStack(spacing: 10) {
                    MicrophoneLevelBars(level: session.audioLevel)
                    Picker("麦克风", selection: microphoneSelection) {
                        Text("跟随系统").tag("")
                        ForEach(session.audioInputDevices) { device in
                            Text(verbatim: device.isDefault
                                ? LerroInterfaceLocalization.format("%@（默认）", locale: locale, arguments: device.name)
                                : device.name)
                                .tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Toggle("录音时降低其他声音", isOn: $session.preferences.muteOtherAudio)
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding {
            session.preferences.microphoneDeviceUID ?? ""
        } set: { value in
            session.preferences.microphoneDeviceUID = value.isEmpty ? nil : value
        }
    }

    // MARK: Shortcut rows

    private func shortcutRow(
        _ definition: HotkeyDefinition,
        actionTitle: String,
        canDelete: Bool,
        configurationUnavailable: Bool
    ) -> some View {
        let localizedTitle = LerroInterfaceLocalization.string(actionTitle, locale: locale)

        return LabeledContent("快捷键") {
            HStack(spacing: 8) {
                LerroShortcutKeys(displayName: definition.displayName)

                Button("更改") {
                    presentShortcutRecorder(for: definition.action, existing: definition)
                }
                .buttonStyle(LerroButtonStyle(.secondary))
                .disabled(configurationUnavailable)
                .help(Text(verbatim: configurationUnavailable
                    ? LerroInterfaceLocalization.string("请在语音输入结束后再修改快捷键", locale: locale)
                    : LerroInterfaceLocalization.format("编辑 %@", locale: locale, arguments: definition.displayName)))
                .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                    "编辑%@快捷键 %@",
                    locale: locale,
                    arguments: localizedTitle, definition.displayName
                )))

                if canDelete {
                    Button("删除") {
                        session.removeHotkey(definition)
                    }
                    .buttonStyle(LerroButtonStyle(.destructive))
                    .disabled(configurationUnavailable)
                    .help(Text(verbatim: configurationUnavailable
                        ? LerroInterfaceLocalization.string("请在语音输入结束后再修改快捷键", locale: locale)
                        : LerroInterfaceLocalization.format("删除 %@", locale: locale, arguments: definition.displayName)))
                    .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                        "删除%@快捷键 %@",
                        locale: locale,
                        arguments: localizedTitle, definition.displayName
                    )))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func presentShortcutRecorder(for action: HotkeyAction, existing: HotkeyDefinition?) {
        editingShortcut = existing
        recordingAction = action
    }

    private func shortcuts(_ action: HotkeyAction) -> [HotkeyDefinition] {
        session.preferences.hotkeys.filter { $0.action == action }
    }

    private func addShortcutHelp(unavailable: Bool, reachedLimit: Bool) -> String {
        if unavailable { return LerroInterfaceLocalization.string("请在语音输入结束后再修改快捷键", locale: locale) }
        if reachedLimit { return LerroInterfaceLocalization.string("每项功能最多设置四个快捷键", locale: locale) }
        return LerroInterfaceLocalization.string("添加快捷键", locale: locale)
    }

    private var shortcutRecorderPresented: Binding<Bool> {
        Binding {
            recordingAction != nil
        } set: { presented in
            if !presented { recordingAction = nil }
        }
    }
}

/// Six bars that follow the live microphone level; all dim while idle.
private struct MicrophoneLevelBars: View {
    let level: Float

    private static let barCount = 6

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(isLit(index) ? LerroTheme.success : LerroTheme.fillContainerTough)
                    .frame(width: 3, height: 6 + CGFloat(index) * 2)
            }
        }
        .frame(height: 16, alignment: .bottom)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }

    private func isLit(_ index: Int) -> Bool {
        Float(index + 1) / Float(Self.barCount) <= min(max(level, 0), 1) + 0.0001
    }
}

private struct TranslationLanguageOption: Identifiable, Hashable {
    let identifier: String
    let title: String
    var id: String { identifier }

    static let all = [
        TranslationLanguageOption(identifier: "en_US", title: "English"),
        TranslationLanguageOption(identifier: "zh_CN", title: "简体中文"),
        TranslationLanguageOption(identifier: "zh_TW", title: "繁體中文"),
        TranslationLanguageOption(identifier: "ja_JP", title: "日本語"),
        TranslationLanguageOption(identifier: "es_ES", title: "Español")
    ]
}

struct ShortcutCaptureSheet: View {
    let action: HotkeyAction
    let existing: HotkeyDefinition?
    let onBeginRecording: () -> Bool
    let onEndRecording: () -> Void
    let onSave: (ShortcutBindingDraft, ShortcutActivation) async -> String?
    let onCancel: () -> Void

    @State private var shortcut: ShortcutBindingDraft?
    @State private var activation: ShortcutActivation
    @State private var validationMessage = ""
    @State private var isSaving = false
    @State private var isConfigurationPrepared = false
    @Environment(\.locale) private var locale

    init(
        action: HotkeyAction,
        existing: HotkeyDefinition?,
        onBeginRecording: @escaping () -> Bool,
        onEndRecording: @escaping () -> Void,
        onSave: @escaping (ShortcutBindingDraft, ShortcutActivation) async -> String?,
        onCancel: @escaping () -> Void
    ) {
        self.action = action
        self.existing = existing
        self.onBeginRecording = onBeginRecording
        self.onEndRecording = onEndRecording
        self.onSave = onSave
        self.onCancel = onCancel
        _shortcut = State(initialValue: existing.map(ShortcutBindingDraft.init))
        _activation = State(initialValue: existing?.activation ?? .hold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: LerroInterfaceLocalization.format(
                    existing == nil ? "为%@添加快捷键" : "编辑%@快捷键",
                    locale: locale,
                    arguments: localized(actionTitle)
                ))
                .font(LerroFont.pageTitle)
                Text("直接按下想使用的键，界面会立即显示按下与松开状态。")
                    .font(LerroFont.body)
                    .foregroundStyle(LerroTheme.secondaryText)
            }

            if isConfigurationPrepared {
                ShortcutRecorderCard(
                    shortcut: $shortcut,
                    activation: $activation,
                    onEscape: onCancel
                )
            } else {
                ProgressView("正在准备按键检测…")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityHint("正在暂停当前快捷键并准备录制")
            }

            if !validationMessage.isEmpty {
                Text(verbatim: localized(validationMessage))
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.warning)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(LerroButtonStyle(.secondary))
                    .disabled(isSaving)
                Button("保存") {
                    guard let shortcut else { return }
                    isSaving = true
                    Task { @MainActor in
                        if let message = await onSave(shortcut, activation) {
                            validationMessage = message
                            isSaving = false
                        }
                    }
                }
                .buttonStyle(LerroButtonStyle(.primary))
                .disabled(shortcut == nil || isSaving)
                .overlay(alignment: .leading) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .offset(x: -24)
                            .accessibilityLabel("正在保存快捷键")
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 390)
        .onAppear {
            guard !isConfigurationPrepared else { return }
            if onBeginRecording() {
                isConfigurationPrepared = true
            } else {
                onCancel()
            }
        }
        .onDisappear {
            if isConfigurationPrepared {
                onEndRecording()
            }
        }
        .onChange(of: shortcut) { _, _ in
            validationMessage = ""
        }
        .onChange(of: activation) { _, _ in
            validationMessage = ""
        }
    }

    private var actionTitle: String {
        switch action {
        case .dictate:
            "听写"
        case .translate:
            "翻译"
        case .pasteLastResult:
            "粘贴上次结果"
        case .cancel:
            "取消"
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}
