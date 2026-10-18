import SwiftUI
import LerroCore

struct ShortcutsSettingsTab: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @State private var recordingAction: HotkeyAction?
    @State private var editingShortcut: HotkeyDefinition?

    private static let shortcutLimit = 4

    var body: some View {
        Form {
            shortcutSection(.dictate, title: "听写")
            shortcutSection(.translate, title: "翻译")

            Section("其他") {
                LabeledContent("粘贴上一次结果") {
                    if let definition = shortcuts(.pasteLastResult).first {
                        LerroShortcutKeys(displayName: definition.displayName)
                    } else {
                        Text("未设置")
                            .foregroundStyle(LerroTheme.secondaryText)
                    }
                }
                Toggle("说完自动结束", isOn: $session.preferences.quickDictateEnabled)
            }
        }
        .settingsForm(height: SettingsLayout.tallHeight)
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

    private func shortcutSection(_ action: HotkeyAction, title: String) -> some View {
        let definitions = shortcuts(action)
        let reachedLimit = definitions.count >= Self.shortcutLimit
        let configurationUnavailable = !session.shortcutConfigurationAvailable

        return Section(LocalizedStringKey(title)) {
            ForEach(definitions) { definition in
                shortcutRow(
                    definition,
                    actionTitle: title,
                    isOnlyBinding: definitions.count == 1,
                    configurationUnavailable: configurationUnavailable
                )
            }

            Button {
                presentShortcutRecorder(for: action, existing: nil)
            } label: {
                Label("添加快捷键", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(LerroTheme.accentText)
            .disabled(reachedLimit || configurationUnavailable)
            .help(Text(verbatim: addShortcutHelp(unavailable: configurationUnavailable, reachedLimit: reachedLimit)))
            .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                "为%@添加快捷键",
                locale: locale,
                arguments: LerroInterfaceLocalization.string(title, locale: locale)
            )))
        }
    }

    private func shortcutRow(
        _ definition: HotkeyDefinition,
        actionTitle: String,
        isOnlyBinding: Bool,
        configurationUnavailable: Bool
    ) -> some View {
        let localizedTitle = LerroInterfaceLocalization.string(actionTitle, locale: locale)

        return HStack(spacing: 10) {
            LerroShortcutKeys(displayName: definition.displayName)
            Text(LocalizedStringKey(
                definition.activation.resolved == .hold ? "按住说话" : "按一下开始，再按一下结束"
            ))
            .font(LerroFont.caption)
            .foregroundStyle(LerroTheme.secondaryText)
            Spacer(minLength: 8)

            Button("更改") {
                presentShortcutRecorder(for: definition.action, existing: definition)
            }
            .buttonStyle(LerroButtonStyle(.secondary))
            .disabled(configurationUnavailable)
            .help(Text(verbatim: configurationUnavailable
                ? LerroInterfaceLocalization.string("完成当前语音输入后可以修改快捷键", locale: locale)
                : LerroInterfaceLocalization.format("编辑 %@", locale: locale, arguments: definition.displayName)))
            .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                "编辑%@快捷键 %@",
                locale: locale,
                arguments: localizedTitle, definition.displayName
            )))

            Button("删除") {
                session.removeHotkey(definition)
            }
            .buttonStyle(LerroButtonStyle(.destructive))
            .disabled(isOnlyBinding || configurationUnavailable)
            .help(Text(verbatim: configurationUnavailable
                ? LerroInterfaceLocalization.string("完成当前语音输入后可以修改快捷键", locale: locale)
                : isOnlyBinding
                    ? LerroInterfaceLocalization.string("每项功能至少保留一个快捷键", locale: locale)
                    : LerroInterfaceLocalization.format("删除 %@", locale: locale, arguments: definition.displayName)))
            .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                "删除%@快捷键 %@",
                locale: locale,
                arguments: localizedTitle, definition.displayName
            )))
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
        if unavailable { return LerroInterfaceLocalization.string("完成当前语音输入后可以修改快捷键", locale: locale) }
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
        _activation = State(initialValue: existing?.activation.resolved ?? .hold)
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
                    .accessibilityHint("正在暂停生产快捷键并准备录制")
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
                        if let message = await onSave(shortcut, activation.resolved) {
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
        case .dictate, .dictateHandsFree:
            "听写"
        case .translate, .translateHandsFree:
            "翻译"
        case .ask, .askHandsFree:
            "指令"
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
