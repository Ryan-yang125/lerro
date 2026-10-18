import AppKit
import SwiftUI
import LerroCore

struct GeneralSettingsTab: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                Picker("听写语言", selection: $session.preferences.recognitionLocaleIdentifier) {
                    Text("简体中文").tag("zh_CN")
                    Text("繁體中文").tag("zh_TW")
                    Text("English (US)").tag("en_US")
                    Text("English (UK)").tag("en_GB")
                    Text("日本語").tag("ja_JP")
                }

                translationLanguageRows

                Picker("麦克风", selection: microphoneSelection) {
                    Text("跟随系统").tag("")
                    ForEach(session.audioInputDevices) { device in
                        Text(verbatim: device.isDefault
                            ? LerroInterfaceLocalization.format("%@（默认）", locale: locale, arguments: device.name)
                            : device.name)
                            .tag(device.uid)
                    }
                }

                Toggle("录音时降低其他声音", isOn: $session.preferences.muteOtherAudio)
            }

            Section {
                Picker("外观", selection: $session.preferences.appearance) {
                    Text("跟随系统").tag(AppAppearance.system)
                    Text("浅色").tag(AppAppearance.light)
                    Text("深色").tag(AppAppearance.dark)
                }

                Picker("界面语言", selection: $session.preferences.appLanguage) {
                    Text("跟随系统").tag(AppLanguage.system)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese)
                    Text("English").tag(AppLanguage.english)
                }

                Toggle("在 Dock 中显示", isOn: $session.preferences.showInDock)
                Toggle("登录时启动", isOn: $session.preferences.launchAtLogin)
            }

            Section {
                PermissionRow(
                    title: "麦克风权限",
                    granted: session.microphonePermission,
                    settingsAnchor: "Privacy_Microphone"
                )
                PermissionRow(
                    title: "辅助功能权限",
                    granted: session.accessibilityPermission,
                    settingsAnchor: "Privacy_Accessibility"
                )
                speechResourceRow
                if !session.microphonePermission || !session.accessibilityPermission {
                    Button("重新检查权限") {
                        Task { await session.refreshPermissions(prompt: true) }
                    }
                }
            }
        }
        .settingsForm(height: SettingsLayout.tallHeight)
        .task {
            await session.refreshAudioInputDevices()
            await session.refreshLanguageResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await session.refreshPermissions(prompt: false) }
        }
    }

    // MARK: Translation languages

    @ViewBuilder
    private var translationLanguageRows: some View {
        let languages = session.preferences.translationLanguageIdentifiers

        ForEach(Array(languages.enumerated()), id: \.offset) { index, _ in
            if index == 0 {
                Picker("翻译成", selection: languageBinding(at: 0)) {
                    languageOptions
                }
            } else {
                HStack(spacing: 8) {
                    Picker(
                        LerroInterfaceLocalization.format("备选 %lld", locale: locale, arguments: Int64(index)),
                        selection: languageBinding(at: index)
                    ) {
                        languageOptions
                    }
                    LerroIconButton(systemImage: "minus.circle", help: "移除这个语言") {
                        removeLanguage(at: index)
                    }
                }
            }
        }

        if languages.count < 3, nextAvailableLanguage != nil {
            Button {
                addLanguage()
            } label: {
                Label("添加语言", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(LerroTheme.accentText)
        }
    }

    private var languageOptions: some View {
        ForEach(TranslationLanguageOption.all) { option in
            Text(verbatim: LerroInterfaceLocalization.string(option.title, locale: locale))
                .tag(option.identifier)
        }
    }

    private var nextAvailableLanguage: String? {
        let languages = session.preferences.translationLanguageIdentifiers
        return TranslationLanguageOption.all.map(\.identifier).first { !languages.contains($0) }
    }

    private func languageBinding(at index: Int) -> Binding<String> {
        Binding {
            let languages = session.preferences.translationLanguageIdentifiers
            guard languages.indices.contains(index) else { return "en_US" }
            return languages[index]
        } set: { value in
            var languages = session.preferences.translationLanguageIdentifiers
            guard languages.indices.contains(index) else { return }
            let oldValue = languages[index]
            if let duplicateIndex = languages.indices.first(where: { $0 != index && languages[$0] == value }) {
                languages[duplicateIndex] = oldValue
            }
            languages[index] = value
            session.preferences.translationLanguageIdentifiers = languages
        }
    }

    private func addLanguage() {
        guard session.preferences.translationLanguageIdentifiers.count < 3,
              let nextAvailableLanguage else { return }
        session.preferences.translationLanguageIdentifiers.append(nextAvailableLanguage)
    }

    private func removeLanguage(at index: Int) {
        let languages = session.preferences.translationLanguageIdentifiers
        guard languages.count > 1, languages.indices.contains(index) else { return }
        session.preferences.translationLanguageIdentifiers.remove(at: index)
    }

    private var microphoneSelection: Binding<String> {
        Binding {
            session.preferences.microphoneDeviceUID ?? ""
        } set: { value in
            session.preferences.microphoneDeviceUID = value.isEmpty ? nil : value
        }
    }

    // MARK: Speech resources

    private var speechResourceRow: some View {
        let status = session.speechResourceStatus
        return LabeledContent("语音资源") {
            switch status.state {
            case .ready:
                HStack(spacing: 6) {
                    LerroStatusDot(color: LerroTheme.success)
                    Text("已准备")
                }
            case .available, .downloading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在准备语音资源")
                }
            case .failed:
                HStack(spacing: 8) {
                    LerroStatusDot(color: LerroTheme.warning)
                    Button("重试", action: session.prepareSpeechResources)
                        .buttonStyle(LerroButtonStyle(.secondary))
                }
                .help(Text(verbatim: LerroInterfaceLocalization.string(status.message, locale: locale)))
            case .unsupported:
                Text("当前不可用")
                    .foregroundStyle(LerroTheme.secondaryText)
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let settingsAnchor: String
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent(LocalizedStringKey(title)) {
            if granted {
                HStack(spacing: 6) {
                    LerroStatusDot(color: LerroTheme.success)
                    Text("已允许")
                }
            } else {
                Button("打开系统设置") {
                    guard let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)"
                    ) else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(LerroButtonStyle(.secondary))
                .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                    "为%@打开系统设置",
                    locale: locale,
                    arguments: LerroInterfaceLocalization.string(title, locale: locale)
                )))
            }
        }
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
