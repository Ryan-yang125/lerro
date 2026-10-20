import AppKit
import Foundation
import SwiftUI
import LerroCore

extension RemoteProviderKind {
    var lerroDisplayName: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .custom: "Custom"
        }
    }

    var lerroModelPlaceholder: String {
        switch self {
        case .deepSeek: "deepseek-flash"
        case .openAI: "例如 gpt-4.1-mini"
        case .gemini: "例如 gemini-2.5-flash"
        case .custom: "输入兼容 Chat Completions 的 Model ID"
        }
    }
}

struct IntelligenceProviderDraft: Equatable {
    var provider: RemoteProviderKind
    var baseURL: String
    var modelIdentifier: String
    var apiKey: String
    var contextSharing: RemoteContextSharing

    init(configuration: RemoteProviderConfiguration = RemoteProviderConfiguration()) {
        provider = configuration.provider
        baseURL = configuration.baseURL
        modelIdentifier = configuration.modelIdentifier
        apiKey = configuration.apiKey
        contextSharing = configuration.contextSharing
    }

    mutating func selectProvider(_ newProvider: RemoteProviderKind) {
        provider = newProvider
        baseURL = newProvider.defaultBaseURL
        modelIdentifier = newProvider.defaultModelIdentifier
        apiKey = ""
    }

    @discardableResult
    mutating func updateBaseURL(_ newValue: String) -> Bool {
        let previousOrigin = RemoteProviderEndpointPolicy.credentialOrigin(baseURL)
        let nextOrigin = RemoteProviderEndpointPolicy.credentialOrigin(newValue)
        baseURL = newValue
        guard !apiKey.isEmpty, previousOrigin != nextOrigin else { return false }
        apiKey = ""
        return true
    }

    var validationMessage: String? {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedModel.isEmpty { return "请输入 Model ID。" }
        if trimmedBaseURL.isEmpty { return "请输入 API Base URL。" }
        switch RemoteProviderEndpointPolicy.validate(trimmedBaseURL) {
        case .valid:
            break
        case .invalid:
            return "API Base URL 需要是完整的 HTTP 或 HTTPS 地址。"
        case .insecure:
            return "远程 API 需要使用 HTTPS；localhost 与 loopback 地址可以使用 HTTP。"
        }
        if trimmedKey.isEmpty { return "请输入 API Key。" }
        return nil
    }

    var configuration: RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            provider: provider,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            modelIdentifier: modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            contextSharing: contextSharing
        )
    }
}

struct IntelligenceSettingsPage: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow

    @State private var shownMode: IntelligenceMode
    @State private var providerDraft = IntelligenceProviderDraft()
    @State private var connectionOutcome: RemoteConnectionTestOutcome?
    @State private var inlineMessage: String?
    @State private var isTestingConnection = false
    @State private var isPersistingConfiguration = false
    @State private var isClearKeyConfirmationPresented = false

    init(session: AppSession) {
        self.session = session
        _shownMode = State(initialValue: session.preferences.intelligenceMode)
        _providerDraft = State(initialValue: IntelligenceProviderDraft(
            configuration: session.preferences.remoteProvider
        ))
    }

    var body: some View {
        Form {
            Section {
                modeTiles
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            switch shownMode {
            case .raw:
                EmptyView()
            case .remote:
                remoteSections
            }

            Section {
                Toggle(
                    "修正后自动学词",
                    isOn: $session.preferences.automaticDictionaryLearningEnabled
                )
                .disabled(session.preferences.intelligenceMode == .raw)
            }
        }
        .formStyle(.grouped)
        .onChange(of: session.preferences.intelligenceMode) { _, updated in
            shownMode = updated
        }
        .onChange(of: providerDraft.provider) { previous, updated in
            guard previous != updated else { return }
            providerDraft.selectProvider(updated)
            connectionOutcome = nil
            inlineMessage = nil
        }
        .onChange(of: providerDraft.modelIdentifier) { _, _ in clearRemoteFeedback() }
        .onChange(of: providerDraft.apiKey) { _, _ in clearRemoteFeedback() }
        .onChange(of: providerDraft.contextSharing) { _, _ in clearRemoteFeedback() }
        .confirmationDialog(
            "清除已保存的 API Key？",
            isPresented: $isClearKeyConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清除 API Key", role: .destructive) {
                clearSavedAPIKey()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清除后，API 模型需要重新填写并保存 Key 才能启用。")
        }
    }

    // MARK: Mode tiles

    private var modeTiles: some View {
        HStack(spacing: 10) {
            ForEach(IntelligenceMode.allCases) { mode in
                modeTile(mode)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: localized("选择智能处理模式")))
    }

    private func modeTile(_ mode: IntelligenceMode) -> some View {
        let selected = shownMode == mode
        let active = session.preferences.intelligenceMode == mode
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return Button {
            inlineMessage = nil
            shownMode = mode
            selectMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(tileTitle(mode)))
                        .font(LerroFont.bodyEmphasis)
                        .foregroundStyle(LerroTheme.text)
                    Spacer(minLength: 0)
                    if active {
                        LerroStatusDot(color: LerroTheme.success)
                    }
                }
                Text(verbatim: tileDetail(mode))
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(selected ? LerroTheme.accentSoft : LerroTheme.fillContainerThin, in: shape)
            .overlay {
                shape.strokeBorder(
                    selected ? LerroTheme.accent : LerroTheme.thinBorder,
                    lineWidth: selected ? 1.5 : 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: localized(tileTitle(mode))))
        .accessibilityValue(Text(verbatim: tileDetail(mode)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tileTitle(_ mode: IntelligenceMode) -> String {
        switch mode {
        case .raw: "不用 AI"
        case .remote: "API"
        }
    }

    private func tileDetail(_ mode: IntelligenceMode) -> String {
        switch mode {
        case .raw:
            return localized("直接写入苹果识别结果")
        case .remote:
            let configuration = session.preferences.remoteProvider
            let state: String
            if !configuration.isReadyForUse {
                state = "未配置"
            } else if session.preferences.intelligenceMode == .remote {
                state = "已启用"
            } else {
                state = "已配置"
            }
            return "\(configuration.provider.lerroDisplayName) · \(localized(state))"
        }
    }

    // MARK: API

    @ViewBuilder
    private var remoteSections: some View {
        Section {
            Picker("服务商", selection: $providerDraft.provider) {
                ForEach(RemoteProviderKind.allCases) { provider in
                    Text(LocalizedStringKey(provider.lerroDisplayName)).tag(provider)
                }
            }

            TextField(
                "模型",
                text: $providerDraft.modelIdentifier,
                prompt: Text(LocalizedStringKey(providerDraft.provider.lerroModelPlaceholder))
            )
            .multilineTextAlignment(.trailing)

            SecureField("API Key", text: $providerDraft.apiKey, prompt: Text("输入 API Key"))
                .multilineTextAlignment(.trailing)
                .privacySensitive()

            if providerDraft.provider == .custom {
                TextField("地址", text: customBaseURLBinding, prompt: Text(verbatim: "https://example.com/v1"))
                    .multilineTextAlignment(.trailing)
            }

            remoteActionRow
        } footer: {
            Text("API Key 以明文保存在这台 Mac 的设置文件中。")
                .font(LerroFont.footnote)
        }

        Section("提示词") {
            ForEach(AIPromptKind.allCases) { kind in
                promptRow(kind)
            }
        }

        Section("发送给 AI 的上下文") {
            Toggle("应用名", isOn: $providerDraft.contextSharing.application)
            Toggle("窗口标题", isOn: $providerDraft.contextSharing.windowTitle)
            Toggle("光标附近文字", isOn: $providerDraft.contextSharing.nearbyText)
            Toggle("选中文字", isOn: $providerDraft.contextSharing.selectedText)
            Toggle("词典", isOn: $providerDraft.contextSharing.dictionary)
            Toggle("应用语气", isOn: $providerDraft.contextSharing.tone)
        }
    }

    private func promptRow(_ kind: AIPromptKind) -> some View {
        let version = AIPromptDocument.document(for: kind).version
        return Button {
            openWindow(id: "prompt", value: kind)
        } label: {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(kind.lerroTitle))
                    .foregroundStyle(LerroTheme.text)
                Spacer(minLength: 8)
                Text(verbatim: version)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LerroTheme.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LerroTheme.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(localized(kind.lerroTitle)) \(version)"))
        .accessibilityAddTraits(.isButton)
    }

    private var remoteActionRow: some View {
        let busy = isTestingConnection
            || isPersistingConfiguration
            || !session.canModifyIntelligenceConfiguration
        let invalid = providerDraft.validationMessage != nil

        return HStack(spacing: 8) {
            remoteStatus
            Spacer(minLength: 8)

            if !session.preferences.remoteProvider.apiKey.isEmpty {
                Button("清除 Key", role: .destructive) {
                    isClearKeyConfirmationPresented = true
                }
                .buttonStyle(LerroButtonStyle(.destructive))
                .disabled(busy)
            }

            Button {
                testConnection()
            } label: {
                Text(LocalizedStringKey(isTestingConnection ? "正在测试" : "测试连接"))
            }
            .buttonStyle(LerroButtonStyle(.secondary))
            .disabled(busy || invalid)

            Button("保存") {
                saveAndActivateRemoteProvider()
            }
            .buttonStyle(LerroButtonStyle(.primary))
            .disabled(busy || invalid)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var remoteStatus: some View {
        if let validationMessage = providerDraft.validationMessage {
            statusLabel(color: LerroTheme.warning) {
                Text(LocalizedStringKey(validationMessage))
            }
            .accessibilityLabel(Text(verbatim:
                String(
                    format: localized("配置提示：%@"),
                    locale: locale,
                    localized(validationMessage)
                )
            ))
        } else if let connectionOutcome {
            statusLabel(color: connectionOutcome.succeeded ? LerroTheme.success : LerroTheme.danger) {
                HStack(spacing: 4) {
                    Text(verbatim: localized(connectionOutcome.message))
                    if let latency = connectionOutcome.latencyMilliseconds {
                        Text(verbatim: "\(latency) ms")
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else if let inlineMessage {
            statusLabel(color: LerroTheme.accent) {
                Text(LocalizedStringKey(inlineMessage))
            }
        }
    }

    private func statusLabel<Content: View>(
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            LerroStatusDot(color: color)
            content()
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var customBaseURLBinding: Binding<String> {
        Binding {
            providerDraft.baseURL
        } set: { updated in
            let didClearKey = providerDraft.updateBaseURL(updated)
            clearRemoteFeedback()
            if didClearKey {
                inlineMessage = "API 地址的站点已改变，请重新填写 API Key。"
            }
        }
    }

    // MARK: Actions

    private func clearRemoteFeedback() {
        connectionOutcome = nil
        inlineMessage = nil
    }

    private func saveAndActivateRemoteProvider() {
        guard providerDraft.validationMessage == nil else { return }
        let configuration = providerDraft.configuration
        isPersistingConfiguration = true
        Task { @MainActor in
            let saved = await session.saveRemoteProvider(configuration)
            isPersistingConfiguration = false
            guard saved else {
                inlineMessage = "配置尚未保存，请查看上方提示后重试。"
                return
            }
            providerDraft = IntelligenceProviderDraft(configuration: configuration)
            connectionOutcome = .success(message: "配置已保存，API 模型已启用。")
            inlineMessage = nil
        }
    }

    private func selectMode(_ mode: IntelligenceMode) {
        switch mode {
        case .raw:
            session.activateIntelligenceMode(.raw)
        case .remote:
            guard providerDraft.validationMessage == nil else {
                inlineMessage = "请先填写完整的 API 配置。"
                return
            }
            guard providerDraft.configuration == session.preferences.remoteProvider else {
                inlineMessage = "配置有未保存的更改，请点击“保存”。"
                return
            }
            session.activateIntelligenceMode(.remote)
        }
    }

    private func testConnection() {
        guard providerDraft.validationMessage == nil,
              session.canModifyIntelligenceConfiguration else { return }
        let configuration = providerDraft.configuration
        connectionOutcome = nil
        inlineMessage = nil
        isTestingConnection = true

        Task { @MainActor in
            let outcome = await session.testRemoteProviderConnection(configuration)
            guard !Task.isCancelled else { return }
            connectionOutcome = outcome
            isTestingConnection = false
        }
    }

    private func clearSavedAPIKey() {
        guard session.canModifyIntelligenceConfiguration else { return }
        isPersistingConfiguration = true
        Task { @MainActor in
            let cleared = await session.clearRemoteProviderAPIKey()
            isPersistingConfiguration = false
            guard cleared else {
                inlineMessage = "API Key 尚未清除，请查看上方提示后重试。"
                return
            }
            providerDraft.apiKey = ""
            connectionOutcome = nil
            inlineMessage = "已从 preferences.json 清除 API Key，并切换到原始听写。"
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}
