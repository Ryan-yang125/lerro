import AppKit
import SwiftUI
import LerroCore

private extension SettingsDestination {
    var title: String {
        switch self {
        case .account: "Lerro"
        case .settings: "设置"
        case .intelligence: "智能处理"
        case .personal: "个性化"
        case .about: "关于"
        case .help: "帮助"
        case .releaseNotes: "版本说明"
        }
    }

    var icon: String {
        switch self {
        case .account: "waveform"
        case .settings: "gearshape"
        case .intelligence: "sparkles"
        case .personal: "person.crop.circle"
        case .about: "info.circle"
        case .help: "questionmark.circle"
        case .releaseNotes: "doc.text"
        }
    }
}

struct SettingsOverlayView: View {
    @Bindable var session: AppSession
    @FocusState private var focusedDestination: SettingsDestination?

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: LerroTheme.settingsSidebarWidth)

            Divider()
                .overlay(LerroTheme.thinBorder)

            ZStack(alignment: .topTrailing) {
                settingsPage

                LerroIconButton(systemName: "xmark", help: "关闭设置") {
                    session.dismissSettings()
                }
                .keyboardShortcut("w", modifiers: .command)
                .padding(.top, 14)
                .padding(.trailing, 14)

                Button("关闭设置") {
                    session.dismissSettings()
                }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LerroTheme.main)
        }
        .tracking(LerroTheme.uiTracking)
        .tint(LerroTheme.accent)
        .accentColor(LerroTheme.accent)
        .background(LerroTheme.main)
        .onAppear { focusedDestination = session.settingsDestination }
        .onChange(of: session.preferences) { previous, updated in
            session.savePreferences(from: previous, to: updated)
        }
        .task { await session.refreshPermissions(prompt: false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lerro 设置")
    }

    @ViewBuilder
    private var settingsPage: some View {
        switch session.settingsDestination {
        case .account: AccountSettingsPage(session: session)
        case .settings: MainSettingsPage(session: session)
        case .intelligence: IntelligenceSettingsPage(session: session)
        case .personal: PersonalSettingsPage(session: session)
        case .about: AboutSettingsPage(session: session)
        case .help: HelpSettingsPage()
        case .releaseNotes: ReleaseNotesPage()
        }
    }

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                navigationGroup([.account, .settings])

                navigationGroup([.intelligence], title: "智能")

                navigationGroup([.personal, .about])

                navigationGroup([.help, .releaseNotes])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(LerroTheme.sidebar)
    }

    private func navigationGroup(
        _ items: [SettingsDestination],
        title: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .lerroTypography(.captionMedium)
                    .foregroundStyle(LerroTheme.metadataText)
                    .padding(.horizontal, 10)
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(items, id: \.self) { item in
                navigationButton(item)
            }
        }
    }

    private func navigationButton(_ item: SettingsDestination) -> some View {
        let selected = session.settingsDestination == item

        return Button {
            session.settingsDestination = item
            focusedDestination = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: LerroTheme.navigationIconSize, weight: .medium))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(item.title)
                    .lerroTypography(.label)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(LerroNavigationButtonStyle(selected: selected))
        .focused($focusedDestination, equals: item)
        .onMoveCommand { direction in
            moveNavigationFocus(from: item, direction: direction)
        }
        .accessibilityLabel(item.title)
        .accessibilityValue(selected ? "已选择" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func moveNavigationFocus(
        from item: SettingsDestination,
        direction: MoveCommandDirection
    ) {
        let destinations: [SettingsDestination] = [
            .account,
            .settings,
            .intelligence,
            .personal,
            .about,
            .help,
            .releaseNotes
        ]
        guard let index = destinations.firstIndex(of: item) else { return }

        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(destinations.startIndex, index - 1)
        case .down:
            nextIndex = min(destinations.index(before: destinations.endIndex), index + 1)
        case .left, .right:
            return
        @unknown default:
            return
        }

        let destination = destinations[nextIndex]
        session.settingsDestination = destination
        focusedDestination = destination
    }
}

private struct SettingsPageContainer<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .lerroTypography(.title)
                    .foregroundStyle(LerroTheme.text)
                    .frame(height: 32, alignment: .leading)
                    .padding(.bottom, 28)
                content
                    .frame(maxWidth: 655, alignment: .leading)
            }
            .padding(.top, 24)
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MainSettingsPage: View {
    @Bindable var session: AppSession
    @State private var recordingAction: HotkeyAction?
    @State private var editingShortcut: HotkeyDefinition?
    @State private var editingTranslationLanguages = false

    var body: some View {
        SettingsPageContainer("设置") {
            VStack(alignment: .leading, spacing: 32) {
                settingsGroup("键盘快捷键") {
                    VStack(spacing: 12) {
                        shortcutBlock(.dictate, title: "听写", detail: shortcutDetail(
                            for: .dictate,
                            primary: "将语音整理后插入当前光标"
                        ))
                        shortcutBlock(.translate, title: "翻译", detail: "说话并输出目标语言")
                        shortcutBlock(.ask, title: "问答", detail: "结合选中文字和当前应用回答")
                    }
                }

                settingsGroup("语言") {
                    VStack(spacing: 0) {
                        settingsRow("界面与听写语言", detail: "识别语言与首选地区变体") {
                            Picker("界面与听写语言", selection: $session.preferences.recognitionLocaleIdentifier) {
                                Text("简体中文").tag("zh_CN")
                                Text("繁體中文").tag("zh_TW")
                                Text("English (US)").tag("en_US")
                                Text("English (UK)").tag("en_GB")
                                Text("日本語").tag("ja_JP")
                            }
                            .labelsHidden()
                            .accessibilityLabel("界面与听写语言")
                            .frame(width: 170)
                        }
                        Divider().overlay(LerroTheme.thinBorder)
                        settingsRow("翻译目标语言", detail: "最多可配置三个，当前显示第一个") {
                            HStack(spacing: 8) {
                                Picker("翻译目标语言", selection: primaryTranslationLanguage) {
                                    ForEach(TranslationLanguageOption.all) { language in
                                        Text(language.title).tag(language.identifier)
                                    }
                                }
                                .labelsHidden()
                                .accessibilityLabel("翻译目标语言")
                                .frame(width: 138)
                                Button(session.preferences.translationLanguageIdentifiers.count > 1
                                    ? "\(session.preferences.translationLanguageIdentifiers.count)/3"
                                    : "添加") {
                                    editingTranslationLanguages = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .settingsBlock()
                }

                settingsGroup("音频") {
                    VStack(spacing: 0) {
                        settingsRow("麦克风", detail: "选择听写与翻译使用的输入设备") {
                            Picker("麦克风", selection: microphoneSelection) {
                                Text("系统默认").tag("")
                                ForEach(session.audioInputDevices) { device in
                                    Text(device.isDefault ? "\(device.name)（默认）" : device.name)
                                        .tag(device.uid)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("麦克风")
                            .frame(width: 190)
                        }
                        Divider().overlay(LerroTheme.thinBorder)
                        settingsToggle("录音时静音其他音频", detail: "降低媒体音量，让录音更清晰", value: $session.preferences.muteOtherAudio)
                        Divider().overlay(LerroTheme.thinBorder)
                        settingsToggle(
                            "保留原始录音",
                            detail: "默认关闭；开启后随历史保存在当前 Mac",
                            value: $session.preferences.saveAudio
                        )
                    }
                    .settingsBlock()
                }

                settingsGroup("常规") {
                    VStack(spacing: 0) {
                        settingsRow("外观", detail: "选择系统、浅色或深色") {
                            Picker("外观", selection: $session.preferences.appearance) {
                                Text("系统").tag(AppAppearance.system)
                                Text("浅色").tag(AppAppearance.light)
                                Text("深色").tag(AppAppearance.dark)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityLabel("外观")
                            .frame(width: 190)
                        }
                        Divider().overlay(LerroTheme.thinBorder)
                        settingsToggle("登录时启动", detail: "登录这台 Mac 后自动运行", value: $session.preferences.launchAtLogin)
                        Divider().overlay(LerroTheme.thinBorder)
                        settingsToggle("在 Dock 中显示", detail: "隐藏后仍可使用菜单栏与快捷键", value: $session.preferences.showInDock)
                    }
                    .settingsBlock()
                }

                permissionSummary
            }
        }
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
        .sheet(isPresented: $editingTranslationLanguages) {
            TranslationLanguagesSheet(languages: $session.preferences.translationLanguageIdentifiers)
        }
    }

    private func shortcutBlock(_ action: HotkeyAction, title: String, detail: String) -> some View {
        let definitions = shortcuts(action)
        let reachedLimit = definitions.count >= 4
        let configurationUnavailable = !session.shortcutConfigurationAvailable

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(LerroTheme.font(14, weight: .medium))
                        .foregroundStyle(LerroTheme.text)
                    Text(detail)
                        .font(LerroTheme.font(13))
                        .foregroundStyle(LerroTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text("\(definitions.count)/4")
                    .font(LerroTheme.font(12, weight: .medium))
                    .foregroundStyle(reachedLimit ? LerroTheme.secondaryText : LerroTheme.tertiaryText)
                    .monospacedDigit()
                    .accessibilityLabel("\(title)已设置 \(definitions.count) 个快捷键，最多四个")
            }
            .padding(12)

            Divider().overlay(LerroTheme.thinBorder)

            if definitions.isEmpty {
                Text("尚未设置快捷键")
                    .font(LerroTheme.font(13))
                    .foregroundStyle(LerroTheme.tertiaryText)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            } else {
                ForEach(Array(definitions.enumerated()), id: \.element.id) { index, definition in
                    shortcutBindingRow(
                        definition,
                        actionTitle: title,
                        isOnlyBinding: definitions.count == 1
                    )
                    if index < definitions.count - 1 {
                        Divider()
                            .overlay(LerroTheme.thinBorder)
                            .padding(.leading, 12)
                    }
                }
            }

            Divider().overlay(LerroTheme.thinBorder)

            HStack(spacing: 10) {
                Button {
                    guard definitions.count < 4 else { return }
                    presentShortcutRecorder(for: action, existing: nil)
                } label: {
                    Label("添加快捷键", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(LerroTheme.font(12, weight: .medium))
                .disabled(reachedLimit || configurationUnavailable)
                .help(
                    configurationUnavailable
                        ? "完成当前语音输入后可以修改快捷键"
                        : reachedLimit
                            ? "每项功能最多设置四个快捷键"
                            : "为\(title)添加另一个快捷键"
                )
                .accessibilityLabel("为\(title)添加快捷键")
                .accessibilityHint(
                    configurationUnavailable
                        ? "完成当前语音输入后可以修改"
                        : reachedLimit
                            ? "已达到四个快捷键上限"
                            : "打开快捷键录制界面"
                )

                Spacer()

                Text(reachedLimit ? "已达到 4 个上限" : "还可添加 \(4 - definitions.count) 个")
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
        }
        .settingsBlock()
    }

    private func shortcutBindingRow(
        _ definition: HotkeyDefinition,
        actionTitle: String,
        isOnlyBinding: Bool
    ) -> some View {
        let mode = definition.activation.resolved == .hold ? "按住说话" : "按一下开关"
        let modeIcon = definition.activation.resolved == .hold ? "hand.raised" : "switch.2"
        let configurationUnavailable = !session.shortcutConfigurationAvailable

        return HStack(spacing: 12) {
            ShortcutBadge(title: definition.displayName)
                .accessibilityLabel("快捷键 \(definition.displayName)")

            Label(mode, systemImage: modeIcon)
                .font(LerroTheme.font(12, weight: .medium))
                .foregroundStyle(LerroTheme.secondaryText)
                .accessibilityLabel("触发方式：\(mode)")

            Spacer(minLength: 8)

            Button {
                presentShortcutRecorder(
                    for: definition.action,
                    existing: definition
                )
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(configurationUnavailable)
            .help(
                configurationUnavailable
                    ? "完成当前语音输入后可以修改快捷键"
                    : "编辑 \(definition.displayName)"
            )
            .accessibilityLabel("编辑\(actionTitle)快捷键 \(definition.displayName)")
            .accessibilityHint("可重新录制按键并更改触发方式")

            Button {
                session.removeHotkey(definition)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(
                isOnlyBinding || configurationUnavailable
                    ? LerroTheme.tertiaryText
                    : LerroTheme.secondaryText
            )
            .disabled(isOnlyBinding || configurationUnavailable)
            .help(
                configurationUnavailable
                    ? "完成当前语音输入后可以修改快捷键"
                    : isOnlyBinding
                        ? "每项功能至少保留一个快捷键"
                        : "删除 \(definition.displayName)"
            )
            .accessibilityLabel("删除\(actionTitle)快捷键 \(definition.displayName)")
            .accessibilityHint(isOnlyBinding ? "每项功能至少保留一个快捷键" : "从\(actionTitle)中移除此快捷键")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func presentShortcutRecorder(
        for action: HotkeyAction,
        existing: HotkeyDefinition?
    ) {
        editingShortcut = existing
        recordingAction = action
    }

    private var permissionSummary: some View {
        settingsGroup("系统权限") {
            VStack(spacing: 0) {
                permissionRow("麦克风", granted: session.microphonePermission, settingsAnchor: "Privacy_Microphone")
                Divider().overlay(LerroTheme.thinBorder)
                permissionRow("语音识别", granted: session.speechPermission, settingsAnchor: "Privacy_SpeechRecognition")
                Divider().overlay(LerroTheme.thinBorder)
                permissionRow("辅助功能", granted: session.accessibilityPermission, settingsAnchor: "Privacy_Accessibility")
                Divider().overlay(LerroTheme.thinBorder)
                permissionRow("输入监控", granted: session.inputMonitoringPermission, settingsAnchor: "Privacy_ListenEvent")
                Divider().overlay(LerroTheme.thinBorder)
                HStack {
                    Button("重新检查权限") { Task { await session.refreshPermissions(prompt: true) } }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(12)
            }
            .settingsBlock()
        }
    }

    private func shortcuts(_ action: HotkeyAction) -> [HotkeyDefinition] {
        session.preferences.hotkeys.filter { $0.action == action }
    }

    private func shortcutDetail(for action: HotkeyAction, primary: String) -> String {
        guard let definition = shortcuts(action).first else { return primary }
        let mode = definition.activation.resolved == .hold
            ? "按下开始，松开完成"
            : "按一下开始，再按一下完成"
        return "\(primary)；\(mode)"
    }

    private var primaryTranslationLanguage: Binding<String> {
        Binding {
            session.preferences.translationLanguageIdentifiers.first ?? "en_US"
        } set: { value in
            if session.preferences.translationLanguageIdentifiers.isEmpty {
                session.preferences.translationLanguageIdentifiers = [value]
            } else {
                session.preferences.translationLanguageIdentifiers[0] = value
            }
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding {
            session.preferences.microphoneDeviceUID ?? ""
        } set: { value in
            session.preferences.microphoneDeviceUID = value.isEmpty ? nil : value
        }
    }

    private var shortcutRecorderPresented: Binding<Bool> {
        Binding {
            recordingAction != nil
        } set: { presented in
            if !presented { recordingAction = nil }
        }
    }
}

private struct AccountSettingsPage: View {
    @Bindable var session: AppSession

    var body: some View {
        SettingsPageContainer("Lerro") {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LerroTheme.brandInk)
                        .frame(width: 56, height: 56)
                        .overlay {
                            LerroMark(size: 40, foregroundStyle: LerroTheme.brandLight)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(LerroTheme.brandOutline, lineWidth: 1)
                        }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("本地优先的语音写作")
                            .font(LerroTheme.font(14, weight: .medium))
                        Text("无需登录，数据与模型保存在当前 Mac。")
                            .font(LerroTheme.font(14))
                            .foregroundStyle(LerroTheme.tertiaryText)
                    }
                }

                VStack(spacing: 0) {
                    settingsRow("运行方式", detail: "听写、翻译、问答与个性化") { Text("本地优先").foregroundStyle(LerroTheme.secondaryText) }
                    Divider().overlay(LerroTheme.thinBorder)
                    settingsRow("账户", detail: "功能可直接使用") { Text("无需登录").foregroundStyle(LerroTheme.secondaryText) }
                    Divider().overlay(LerroTheme.thinBorder)
                    settingsRow("开源许可证", detail: "代码可审查、修改与自行构建") { Text("Apache-2.0").foregroundStyle(LerroTheme.secondaryText) }
                    Divider().overlay(LerroTheme.thinBorder)
                    settingsRow("数据位置", detail: "设置、词典、历史与模型") { Text("当前 Mac").foregroundStyle(LerroTheme.secondaryText) }
                }
                .settingsBlock()

                HStack {
                    Spacer()
                    Button("重新开始引导") { session.restartOnboarding() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 230, alignment: .bottomTrailing)
            }
        }
    }
}

private struct PersonalSettingsPage: View {
    @Bindable var session: AppSession

    var body: some View {
        SettingsPageContainer("个性化") {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                    Text("个人词典与应用语气保存在本机。使用 API 模型时，共享内容遵循“智能处理”中的上下文设置。")
                        .font(LerroTheme.font(14))
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(LerroTheme.fillContainerThin)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("总体个性化")
                                .font(LerroTheme.font(14, weight: .medium))
                            Text("根据词典、应用语气与编辑习惯生成")
                                .font(LerroTheme.font(14))
                                .foregroundStyle(LerroTheme.secondaryText)
                        }
                        Spacer()
                        Text("\(session.usage.personalizationPercent)%")
                            .font(LerroTheme.font(24, weight: .medium))
                    }
                    ProgressView(value: Double(session.usage.personalizationPercent), total: 100)

                    Divider().overlay(LerroTheme.thinBorder)
                    reportLine("个人词典", value: "\(session.dictionaryEntries.count) 个词条")
                    reportLine("应用语气", value: "\(session.preferences.appToneProfiles.count) 个配置")
                    reportLine("智能处理", value: session.preferences.intelligenceMode.lerroDisplayName)

                    Divider().overlay(LerroTheme.thinBorder)
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: intelligenceModeIcon)
                            .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                            .foregroundStyle(LerroTheme.accent)
                            .frame(width: 36, height: 36)
                            .background(LerroTheme.fillSelected)
                            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.navigationRadius, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前使用：\(session.preferences.intelligenceMode.lerroDisplayName)")
                                .font(LerroTheme.font(14, weight: .medium))
                            Text(intelligenceModeDetail)
                                .font(LerroTheme.font(12))
                                .foregroundStyle(LerroTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 12)
                        Button("打开智能处理") {
                            session.settingsDestination = .intelligence
                        }
                        .buttonStyle(LerroPillButtonStyle(prominent: true))
                        .controlSize(.small)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 310, alignment: .topLeading)
                .background(LerroTheme.fillContainerThin)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var intelligenceModeIcon: String {
        switch session.preferences.intelligenceMode {
        case .raw: "waveform"
        case .local: "cpu"
        case .remote: "network"
        }
    }

    private var intelligenceModeDetail: String {
        switch session.preferences.intelligenceMode {
        case .raw:
            "转写完成后直接输出原始文本。"
        case .local:
            session.modelStatus.message.isEmpty
                ? "Qwen3.5 4B 在当前 Mac 运行。"
                : session.modelStatus.message
        case .remote:
            "\(session.preferences.remoteProvider.provider.lerroDisplayName) · \(session.preferences.remoteProvider.modelIdentifier)"
        }
    }
}

private struct AboutSettingsPage: View {
    @Bindable var session: AppSession

    var body: some View {
        SettingsPageContainer("关于") {
            VStack(spacing: 0) {
                settingsRow("Lerro for Mac", detail: "版本 \(AppMetadata.version) · Swift 原生") {
                    Button("检查更新") {
                        if !AppExternalLinks.openReleases() {
                            session.currentError = AppExternalLinks.releasesOpenFailureMessage
                        }
                    }
                        .buttonStyle(LerroPillButtonStyle(prominent: true))
                }
                Divider().overlay(LerroTheme.thinBorder)
                bundledDocumentRow("隐私政策", resource: "PrivacyPolicy")
                Divider().overlay(LerroTheme.thinBorder)
                bundledDocumentRow("服务条款", resource: "TermsOfUse")
            }
            .settingsBlock()
        }
    }
}

private struct HelpSettingsPage: View {
    var body: some View {
        SettingsPageContainer("帮助") {
            VStack(spacing: 0) {
                helpRow("开始听写", detail: "使用已设置的快捷键；支持按住说话和按一下开关。", icon: "waveform")
                Divider().overlay(LerroTheme.thinBorder)
                helpRow("翻译", detail: "使用翻译快捷键说出内容，并输出首选目标语言。", icon: "character.bubble")
                Divider().overlay(LerroTheme.thinBorder)
                helpRow("问答", detail: "使用问答快捷键，结合当前上下文提问。", icon: "sparkles")
            }
            .settingsBlock()
        }
    }
}

private struct ReleaseNotesPage: View {
    var body: some View {
        SettingsPageContainer("版本说明") {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(AppMetadata.version)（构建 \(AppMetadata.build)）")
                    .font(LerroTheme.font(14, weight: .medium))
                Text("强化核心链路：录音准备与取消隔离、快捷键精确匹配、焦点安全交付、失败结果恢复、并发存储，以及可追溯的 Release 验证。")
                    .font(LerroTheme.font(14))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineSpacing(5)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

@MainActor
private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 16) {
        Text(title)
            .font(LerroTheme.font(13, weight: .medium))
            .foregroundStyle(LerroTheme.metadataText)
        content()
    }
}

@MainActor
private func settingsRow<Content: View>(
    _ title: String,
    detail: String,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(LerroTheme.font(14, weight: .medium))
                .foregroundStyle(LerroTheme.text)
            Text(detail)
                .font(LerroTheme.font(14))
                .foregroundStyle(LerroTheme.secondaryText)
                .lineLimit(1)
        }
        Spacer(minLength: 12)
        content()
            .font(LerroTheme.font(14))
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 64)
}

@MainActor
private func settingsToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
    settingsRow(title, detail: detail) {
        Toggle(title, isOn: value)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(LerroTheme.accent)
    }
}

@MainActor
private func permissionRow(_ title: String, granted: Bool, settingsAnchor: String) -> some View {
    settingsRow(title, detail: granted ? "已获得系统授权" : "需要在系统设置中开启") {
        HStack(spacing: 10) {
            Label(granted ? "已开启" : "待开启", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? LerroTheme.green : LerroTheme.orange)
            if !granted {
                Button("打开系统设置") {
                    openPrivacySettings(settingsAnchor)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("为\(title)打开系统设置")
            }
        }
    }
}

@MainActor
private func openPrivacySettings(_ anchor: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
    NSWorkspace.shared.open(url)
}

@MainActor
private func reportLine(_ title: String, value: String) -> some View {
    HStack {
        Text(title).font(LerroTheme.font(14))
        Spacer()
        Text(value).font(LerroTheme.font(14)).foregroundStyle(LerroTheme.secondaryText)
    }
}

@MainActor
private func bundledDocumentRow(_ title: String, resource: String) -> some View {
    Button {
        if let url = Bundle.main.url(forResource: resource, withExtension: "html") {
            NSWorkspace.shared.open(url)
        }
    } label: {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "arrow.up.right")
        }
        .font(LerroTheme.font(14, weight: .medium))
        .foregroundStyle(LerroTheme.text)
        .padding(.horizontal, 12)
        .frame(height: 52)
    }
    .buttonStyle(LerroPressButtonStyle())
}

@MainActor
private func helpRow(_ title: String, detail: String, icon: String) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
            .frame(width: 28)
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(LerroTheme.font(14, weight: .medium))
            Text(detail).font(LerroTheme.font(14)).foregroundStyle(LerroTheme.secondaryText)
        }
        Spacer()
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 72)
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

private struct TranslationLanguagesSheet: View {
    @Binding var languages: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("翻译目标语言")
                    .font(LerroTheme.font(24, weight: .medium))
                Text("最多保留三个目标语言；列表第一项用于快捷翻译。")
                    .font(LerroTheme.font(14))
                    .foregroundStyle(LerroTheme.secondaryText)
            }

            VStack(spacing: 10) {
                ForEach(Array(languages.enumerated()), id: \.offset) { index, language in
                    HStack(spacing: 12) {
                        Text(index == 0 ? "首选" : "备选 \(index)")
                            .font(LerroTheme.font(14, weight: .medium))
                            .frame(width: 56, alignment: .leading)
                        Picker(index == 0 ? "首选翻译语言" : "备选翻译语言 \(index)", selection: languageBinding(at: index)) {
                            ForEach(TranslationLanguageOption.all) { option in
                                Text(option.title).tag(option.identifier)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel(index == 0 ? "首选翻译语言" : "备选翻译语言 \(index)")
                        .frame(maxWidth: .infinity)
                        Button {
                            removeLanguage(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(LerroPressButtonStyle())
                        .foregroundStyle(LerroTheme.secondaryText)
                        .disabled(languages.count == 1)
                        .accessibilityLabel("移除\(index == 0 ? "首选" : "备选 \(index)")翻译语言")
                    }
                }
            }

            HStack {
                Button("添加语言") { addLanguage() }
                    .buttonStyle(.bordered)
                    .disabled(languages.count >= 3 || nextAvailableLanguage == nil)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 460, height: 330)
        .background(LerroTheme.main)
    }

    private var nextAvailableLanguage: String? {
        TranslationLanguageOption.all
            .map(\.identifier)
            .first { !languages.contains($0) }
    }

    private func languageBinding(at index: Int) -> Binding<String> {
        Binding {
            guard languages.indices.contains(index) else { return "en_US" }
            return languages[index]
        } set: { value in
            guard languages.indices.contains(index) else { return }
            let oldValue = languages[index]
            if let duplicateIndex = languages.indices.first(where: { $0 != index && languages[$0] == value }) {
                languages[duplicateIndex] = oldValue
            }
            languages[index] = value
        }
    }

    private func addLanguage() {
        guard languages.count < 3, let nextAvailableLanguage else { return }
        languages.append(nextAvailableLanguage)
    }

    private func removeLanguage(at index: Int) {
        guard languages.count > 1, languages.indices.contains(index) else { return }
        languages.remove(at: index)
    }
}

private struct ShortcutCaptureSheet: View {
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
                Text(existing == nil ? "为\(actionTitle)添加快捷键" : "编辑\(actionTitle)快捷键")
                    .font(LerroTheme.font(24, weight: .medium))
                Text("直接按下想使用的键，界面会立即显示按下与松开状态。")
                    .font(LerroTheme.font(14))
                    .foregroundStyle(LerroTheme.secondaryText)
            }

            if isConfigurationPrepared {
                ShortcutRecorderCard(
                    shortcut: $shortcut,
                    activation: $activation,
                    onEscape: cancel
                )
            } else {
                ProgressView("正在准备按键检测…")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityHint("正在暂停生产快捷键并准备录制")
            }

            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.orange)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
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
                .buttonStyle(LerroPillButtonStyle(prominent: true))
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
        .background(LerroTheme.main)
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

    private func cancel() {
        onCancel()
    }

    private var actionTitle: String {
        switch action {
        case .dictate, .dictateHandsFree:
            "听写"
        case .translate, .translateHandsFree:
            "翻译"
        case .ask, .askHandsFree:
            "问答"
        case .pasteLastResult:
            "粘贴上次结果"
        case .cancel:
            "取消"
        }
    }
}

private extension View {
    func settingsBlock() -> some View {
        background(LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                    .stroke(LerroTheme.thinBorder, lineWidth: 1)
            }
            .shadow(color: LerroTheme.cardShadow, radius: 2, x: 0, y: 1)
    }
}
