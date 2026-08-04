import AppKit
import Foundation
import SwiftUI
import LerroCore

extension IntelligenceMode {
    var lerroDisplayName: String {
        switch self {
        case .raw: "原始听写"
        case .local: "本地 AI"
        case .remote: "API 模型"
        }
    }

    fileprivate var lerroIcon: String {
        switch self {
        case .raw: "waveform"
        case .local: "cpu"
        case .remote: "network"
        }
    }

    fileprivate var lerroDetail: String {
        switch self {
        case .raw:
            "转写完成后直接写入，不调用语言模型。"
        case .local:
            "使用 Qwen3.5 4B 在当前 Mac 整理文本。"
        case .remote:
            "使用您自己的 API Key 调用云端模型。"
        }
    }
}

extension RemoteProviderKind {
    var lerroDisplayName: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        case .custom: "Custom"
        }
    }

    fileprivate var lerroModelPlaceholder: String {
        switch self {
        case .deepSeek: "deepseek-v4-flash"
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

    @State private var providerDraft = IntelligenceProviderDraft()
    @State private var connectionOutcome: RemoteConnectionTestOutcome?
    @State private var inlineMessage: String?
    @State private var isTestingConnection = false
    @State private var isPersistingConfiguration = false
    @State private var isClearKeyConfirmationPresented = false

    init(session: AppSession) {
        self.session = session
        _providerDraft = State(initialValue: IntelligenceProviderDraft(
            configuration: session.preferences.remoteProvider
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("智能处理")
                    .lerroTypography(.title)
                    .foregroundStyle(LerroTheme.text)
                    .frame(height: 32, alignment: .leading)
                    .padding(.bottom, 20)

                currentModeHeader
                    .padding(.bottom, 20)

                modePicker
                    .padding(.bottom, 30)

                settingsSection("本地模型") {
                    localModelCard
                }
                .padding(.bottom, 30)

                settingsSection("API 模型") {
                    remoteProviderCard
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var currentModeHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: session.preferences.intelligenceMode.lerroIcon)
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(LerroTheme.accent)
                .frame(width: 48, height: 48)
                .background(LerroTheme.fillSelected)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.navigationRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("当前模式")
                    .font(LerroTheme.font(12, weight: .medium))
                    .foregroundStyle(LerroTheme.secondaryText)
                Text(LocalizedStringKey(session.preferences.intelligenceMode.lerroDisplayName))
                    .lerroTypography(.title)
                    .foregroundStyle(LerroTheme.text)
                Text(LocalizedStringKey(session.preferences.intelligenceMode.lerroDetail))
                    .font(LerroTheme.font(13))
                    .foregroundStyle(LerroTheme.secondaryText)
            }

            Spacer(minLength: 16)

            Label {
                Text(LocalizedStringKey(currentModeStatusText))
            } icon: {
                Image(systemName: currentModeStatusIcon)
            }
                .font(LerroTheme.font(12, weight: .medium))
                .foregroundStyle(currentModeStatusColor)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim:
            String(
                format: localized("当前智能处理模式：%@"),
                locale: locale,
                localized(session.preferences.intelligenceMode.lerroDisplayName)
            )
        ))
        .accessibilityValue(Text(verbatim: localized(currentModeStatusText)))
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(IntelligenceMode.allCases) { mode in
                modeButton(mode)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: localized("选择智能处理模式")))
    }

    private func modeButton(_ mode: IntelligenceMode) -> some View {
        let selected = session.preferences.intelligenceMode == mode

        return Button {
            inlineMessage = nil
            selectMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: mode.lerroIcon)
                        .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                        .foregroundStyle(selected ? LerroTheme.accent : LerroTheme.secondaryText)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? LerroTheme.accent : LerroTheme.tertiaryText)
                }
                Text(LocalizedStringKey(mode.lerroDisplayName))
                    .lerroTypography(.heading)
                    .foregroundStyle(LerroTheme.text)
                Text(LocalizedStringKey(mode.lerroDetail))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        }
        .buttonStyle(LerroCardButtonStyle(selected: selected))
        .accessibilityLabel(Text(verbatim: localized(mode.lerroDisplayName)))
        .accessibilityValue(Text(verbatim: localized(selected ? "当前模式" : "未选择")))
        .accessibilityHint(Text(verbatim: localized(mode.lerroDetail)))
    }

    private var localModelCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "cpu")
                    .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .frame(width: 38, height: 38)
                    .background(LerroTheme.fillContainerTough)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("Qwen3.5 4B")
                            .lerroTypography(.heading)
                        if session.preferences.intelligenceMode == .local {
                            Text("已开启")
                                .font(LerroTheme.font(12, weight: .medium))
                                .foregroundStyle(LerroTheme.green)
                        }
                    }
                    Text("约 3.03 GB · 下载后在当前 Mac 运行")
                        .font(LerroTheme.font(13))
                        .foregroundStyle(LerroTheme.secondaryText)
                    Label {
                        Text(LocalizedStringKey(localModelStatusText))
                    } icon: {
                        Image(systemName: localModelStatusIcon)
                    }
                        .font(LerroTheme.font(12))
                        .foregroundStyle(localModelStatusColor)
                }

                Spacer(minLength: 12)

                Button {
                    if session.preferences.hasApprovedModelDownload {
                        session.activateIntelligenceMode(.local)
                    } else {
                        session.requestLocalModelPreparation()
                    }
                } label: {
                    Text(LocalizedStringKey(localModelActionTitle))
                }
                .buttonStyle(LerroPillButtonStyle(prominent: true))
                .disabled(localModelActionDisabled)
            }

            if showsLocalModelProgress {
                ProgressView(value: min(1, max(0, session.modelStatus.progress)))
                    .accessibilityLabel(Text(verbatim: localized("本地模型准备进度")))
            }

            Text("听写内容、上下文与生成结果留在这台 Mac；模型缓存可在停用后继续保留。")
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.tertiaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .intelligenceSettingsBlock()
    }

    private var remoteProviderCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("使用自己的 API Key")
                    .lerroTypography(.heading)
                Text("支持 OpenAI Chat Completions 兼容接口。配置只在点击“保存并启用”后写入。")
                    .font(LerroTheme.font(13))
                    .foregroundStyle(LerroTheme.secondaryText)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    fieldLabel("Provider")
                    Picker("Provider", selection: $providerDraft.provider) {
                        ForEach(RemoteProviderKind.allCases) { provider in
                            Text(LocalizedStringKey(provider.lerroDisplayName)).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GridRow {
                    fieldLabel("Model ID")
                    TextField(LocalizedStringKey(providerDraft.provider.lerroModelPlaceholder), text: $providerDraft.modelIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(localized("Model ID"))
                }

                GridRow {
                    fieldLabel("API Base URL")
                    if providerDraft.provider == .custom {
                        TextField("https://example.com/v1", text: customBaseURLBinding)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(localized("自定义 API Base URL"))
                    } else {
                        HStack(spacing: 8) {
                            Text(verbatim: providerDraft.baseURL)
                                .font(LerroTheme.font(13))
                                .foregroundStyle(LerroTheme.secondaryText)
                                .textSelection(.enabled)
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.system(size: LerroTheme.navigationIconSize, weight: .medium))
                                .foregroundStyle(LerroTheme.tertiaryText)
                        }
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(LerroTheme.fillContainerTough)
                        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.navigationRadius, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(verbatim:
                            String(
                                format: localized("API Base URL，预设只读，%@"),
                                locale: locale,
                                providerDraft.baseURL
                            )
                        ))
                    }
                }

                GridRow {
                    fieldLabel("API Key")
                    SecureField("输入 API Key", text: $providerDraft.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(localized("API Key"))
                        .privacySensitive()
                }
            }

            Divider().overlay(LerroTheme.thinBorder)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("发送给 API")
                        .font(LerroTheme.font(14, weight: .medium))
                    Text("原始语音转写始终发送；以下上下文可逐项关闭。")
                        .font(LerroTheme.font(12))
                        .foregroundStyle(LerroTheme.secondaryText)
                }

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        contextToggle("应用类型", value: $providerDraft.contextSharing.application)
                        contextToggle("窗口标题", value: $providerDraft.contextSharing.windowTitle)
                    }
                    GridRow {
                        contextToggle("光标附近文字", value: $providerDraft.contextSharing.nearbyText)
                        contextToggle("选中文字（改写必需）", value: $providerDraft.contextSharing.selectedText)
                    }
                    GridRow {
                        contextToggle("个人词典", value: $providerDraft.contextSharing.dictionary)
                        contextToggle("应用语气", value: $providerDraft.contextSharing.tone)
                    }
                }
            }

            Label {
                Text("API Key、Provider、Model ID、Base URL 与上下文设置会以明文保存在这台 Mac 的 Lerro 设置 JSON 中。请仅在受信任的个人设备使用。")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(LerroTheme.font(12))
            .foregroundStyle(LerroTheme.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LerroTheme.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            remoteFeedback

            HStack(spacing: 10) {
                Button("清除已保存的 Key", role: .destructive) {
                    isClearKeyConfirmationPresented = true
                }
                .buttonStyle(LerroPillButtonStyle(destructive: true))
                .disabled(
                    session.preferences.remoteProvider.apiKey.isEmpty
                        || isTestingConnection
                        || isPersistingConfiguration
                        || !session.canModifyIntelligenceConfiguration
                )

                Button {
                    testConnection()
                } label: {
                    Group {
                        if isTestingConnection {
                            Label("正在测试", systemImage: "clock")
                        } else {
                            Label("测试连接", systemImage: "bolt.horizontal.circle")
                        }
                    }
                    .frame(minWidth: 86)
                }
                .buttonStyle(LerroPillButtonStyle())
                .disabled(
                    isTestingConnection
                        || isPersistingConfiguration
                        || providerDraft.validationMessage != nil
                        || !session.canModifyIntelligenceConfiguration
                )

                Spacer()

                Button("保存并启用") {
                    saveAndActivateRemoteProvider()
                }
                .buttonStyle(LerroPillButtonStyle(prominent: true))
                .disabled(
                    isTestingConnection
                        || isPersistingConfiguration
                        || providerDraft.validationMessage != nil
                        || !session.canModifyIntelligenceConfiguration
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .intelligenceSettingsBlock()
    }

    @ViewBuilder
    private var remoteFeedback: some View {
        if let validationMessage = providerDraft.validationMessage {
            Label {
                Text(LocalizedStringKey(validationMessage))
            } icon: {
                Image(systemName: "info.circle")
            }
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.secondaryText)
                .accessibilityLabel(Text(verbatim:
                    String(
                        format: localized("配置提示：%@"),
                        locale: locale,
                        localized(validationMessage)
                    )
                ))
        } else if let connectionOutcome {
            HStack(spacing: 8) {
                Image(systemName: connectionOutcome.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(verbatim: localized(connectionOutcome.message))
                if let latency = connectionOutcome.latencyMilliseconds {
                    Text(verbatim: "· \(latency) ms")
                        .monospacedDigit()
                }
                if let model = connectionOutcome.modelIdentifier, !model.isEmpty {
                    Text(verbatim: "· \(model)")
                        .lineLimit(1)
                }
            }
            .font(LerroTheme.font(12, weight: .medium))
            .foregroundStyle(connectionOutcome.succeeded ? LerroTheme.green : LerroTheme.red)
            .accessibilityElement(children: .combine)
        } else if let inlineMessage {
            Label {
                Text(LocalizedStringKey(inlineMessage))
            } icon: {
                Image(systemName: "info.circle.fill")
            }
                .font(LerroTheme.font(12, weight: .medium))
                .foregroundStyle(LerroTheme.accent)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(LerroTheme.font(13, weight: .medium))
            .foregroundStyle(LerroTheme.secondaryText)
            .frame(width: 102, alignment: .leading)
    }

    private func contextToggle(_ title: String, value: Binding<Bool>) -> some View {
        Toggle(LocalizedStringKey(title), isOn: value)
            .toggleStyle(.switch)
            .tint(LerroTheme.accent)
            .font(LerroTheme.font(13))
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey(title))
                .lerroTypography(.label)
                .foregroundStyle(LerroTheme.metadataText)
            content()
        }
    }

    private var localModelStatusText: String {
        if !session.modelStatus.message.isEmpty {
            return LerroInterfaceLocalization.statusString(session.modelStatus.message, locale: locale)
        }
        return switch session.modelStatus.state {
        case .unavailable: "等待下载"
        case .ready: "模型已缓存"
        case .downloading: "正在下载"
        case .loading: "正在加载"
        case .loaded: "模型已加载"
        case .failed: "准备失败"
        }
    }

    private var currentModeIsReady: Bool {
        switch session.preferences.intelligenceMode {
        case .raw:
            true
        case .local:
            session.preferences.hasApprovedModelDownload
        case .remote:
            IntelligenceProviderDraft(
                configuration: session.preferences.remoteProvider
            ).validationMessage == nil
        }
    }

    private var currentModeStatusText: String {
        if currentModeIsReady { return "已启用" }
        return session.preferences.intelligenceMode == .local ? "等待下载" : "需要配置"
    }

    private var currentModeStatusIcon: String {
        currentModeIsReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var currentModeStatusColor: Color {
        currentModeIsReady ? LerroTheme.green : LerroTheme.orange
    }

    private var localModelStatusIcon: String {
        switch session.modelStatus.state {
        case .loaded: "checkmark.circle.fill"
        case .downloading, .loading: "clock.fill"
        case .failed: "exclamationmark.circle.fill"
        case .ready: "internaldrive.fill"
        case .unavailable: "arrow.down.circle"
        }
    }

    private var localModelStatusColor: Color {
        switch session.modelStatus.state {
        case .loaded: LerroTheme.green
        case .failed: LerroTheme.red
        case .downloading, .loading: LerroTheme.accent
        case .ready, .unavailable: LerroTheme.secondaryText
        }
    }

    private var localModelActionTitle: String {
        switch session.modelStatus.state {
        case .loaded where session.preferences.intelligenceMode == .local: "已启用"
        case .loaded: "启用本地 AI"
        case .downloading, .loading: "准备中"
        case .failed: "重试"
        case .ready where session.modelStatus.progress >= 1: "加载并启用"
        case .ready, .unavailable: "下载并启用"
        }
    }

    private var localModelActionDisabled: Bool {
        switch session.modelStatus.state {
        case .loaded:
            session.preferences.intelligenceMode == .local
        case .downloading, .loading:
            true
        case .unavailable, .ready, .failed:
            false
        }
    }

    private var showsLocalModelProgress: Bool {
        session.modelStatus.state == .downloading || session.modelStatus.state == .loading
    }

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
        case .local:
            if session.preferences.hasApprovedModelDownload {
                session.activateIntelligenceMode(.local)
            } else {
                session.requestLocalModelPreparation()
            }
        case .remote:
            guard providerDraft.validationMessage == nil else {
                inlineMessage = "请先在下方填写完整的 API 配置。"
                return
            }
            guard providerDraft.configuration == session.preferences.remoteProvider else {
                inlineMessage = "配置有未保存的更改，请点击下方“保存并启用”。"
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

private extension View {
    func intelligenceSettingsBlock() -> some View {
        background(LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                    .stroke(LerroTheme.thinBorder, lineWidth: 1)
            }
            .shadow(color: LerroTheme.cardShadow, radius: 2, x: 0, y: 1)
    }
}
