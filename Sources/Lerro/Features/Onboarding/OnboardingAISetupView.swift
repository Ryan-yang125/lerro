import SwiftUI
import LerroCore

private enum OnboardingAIRoute: String, CaseIterable, Identifiable {
    case apple
    case remote

    var id: String { rawValue }
}

struct OnboardingAISetupView: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale

    @State private var selectedRoute: OnboardingAIRoute
    @State private var providerDraft: IntelligenceProviderDraft
    @State private var connectionOutcome: RemoteConnectionTestOutcome?
    @State private var isTestingConnection = false
    @State private var isSavingProvider = false

    init(session: AppSession) {
        self.session = session
        let selectedRoute: OnboardingAIRoute = switch session.preferences.intelligenceMode {
        case .raw: .apple
        case .remote: .remote
        }
        _selectedRoute = State(initialValue: selectedRoute)
        _providerDraft = State(initialValue: IntelligenceProviderDraft(
            configuration: session.preferences.remoteProvider
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            routePicker

            switch selectedRoute {
            case .remote:
                remoteSetup
            case .apple:
                appleSetup
            }
        }
        .onChange(of: providerDraft.provider) { previous, updated in
            guard previous != updated else { return }
            providerDraft.selectProvider(updated)
            connectionOutcome = nil
        }
        .onChange(of: providerDraft.modelIdentifier) { _, _ in connectionOutcome = nil }
        .onChange(of: providerDraft.apiKey) { _, _ in connectionOutcome = nil }
        .onChange(of: providerDraft.contextSharing) { _, _ in connectionOutcome = nil }
        .onAppear {
            keepIncompleteRouteOnBaseDictation()
        }
    }

    private var routePicker: some View {
        HStack(spacing: 8) {
            routeButton(
                .apple,
                title: "Apple 听写",
                detail: "默认 · 立即开始"
            )
            routeButton(
                .remote,
                title: "远端 AI",
                detail: "快速启用 · 使用自己的 Key"
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func routeButton(
        _ route: OnboardingAIRoute,
        title: String,
        detail: String
    ) -> some View {
        let selected = selectedRoute == route
        return Button {
            selectedRoute = route
            if route == .apple || !providerDraft.configuration.isReadyForUse {
                session.activateIntelligenceMode(.raw)
            } else {
                session.activateIntelligenceMode(.remote)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LerroTheme.text)
                Text(LocalizedStringKey(detail))
                    .font(LerroFont.footnote)
                    .foregroundStyle(LerroTheme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .background(
                selected ? LerroTheme.accentSoft : LerroTheme.fillContainerThin,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? LerroTheme.accent : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(LerroPressButtonStyle())
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(LocalizedStringKey(selected ? "已选择" : "未选择")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var remoteSetup: some View {
        VStack(alignment: .leading, spacing: 13) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    fieldLabel("Provider")
                    Picker("Provider", selection: $providerDraft.provider) {
                        ForEach(RemoteProviderKind.allCases) { provider in
                            Text(LocalizedStringKey(provider.lerroDisplayName)).tag(provider)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    fieldLabel("Model ID")
                    TextField(
                        LocalizedStringKey(providerDraft.provider.lerroModelPlaceholder),
                        text: $providerDraft.modelIdentifier
                    )
                    .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    fieldLabel("API URL")
                    TextField("https://example.com/v1", text: customBaseURLBinding)
                        .textFieldStyle(.roundedBorder)
                        .disabled(providerDraft.provider != .custom)
                }
                GridRow {
                    fieldLabel("API Key")
                    SecureField("输入 API Key", text: $providerDraft.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .privacySensitive()
                }
            }

            DisclosureGroup("选择发送给 API 的上下文") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Toggle("应用名称", isOn: $providerDraft.contextSharing.application)
                        Toggle("窗口标题", isOn: $providerDraft.contextSharing.windowTitle)
                    }
                    GridRow {
                        Toggle("光标附近文字", isOn: $providerDraft.contextSharing.nearbyText)
                        Toggle("选中文字", isOn: $providerDraft.contextSharing.selectedText)
                    }
                    GridRow {
                        Toggle("个人词典", isOn: $providerDraft.contextSharing.dictionary)
                        Toggle("应用语气", isOn: $providerDraft.contextSharing.tone)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.top, 8)
            }
            .font(LerroFont.caption)
            .tint(LerroTheme.accent)

            if let validation = providerDraft.validationMessage {
                Label(LocalizedStringKey(validation), systemImage: "info.circle")
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
            } else if let connectionOutcome {
                Label {
                    Text(LocalizedStringKey(connectionOutcome.message))
                } icon: {
                    Image(systemName: connectionOutcome.succeeded
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill")
                }
                .font(LerroFont.caption)
                .foregroundStyle(connectionOutcome.succeeded ? LerroTheme.success : LerroTheme.danger)
            }

            HStack {
                Text("连接测试只发送固定合成文字。API Key 会保存在本机 Lerro 设置 JSON 中。")
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
                Spacer()
                Button(LocalizedStringKey(isTestingConnection ? "正在测试" : "测试连接")) {
                    testConnection()
                }
                .buttonStyle(LerroButtonStyle(.secondary))
                .disabled(providerDraft.validationMessage != nil || isTestingConnection || isSavingProvider)
                Button(LocalizedStringKey(isSavingProvider ? "正在保存" : "保存并启用")) {
                    saveProvider()
                }
                .buttonStyle(LerroButtonStyle(.primary))
                .disabled(
                    providerDraft.validationMessage != nil
                        || connectionOutcome?.succeeded != true
                        || isTestingConnection
                        || isSavingProvider
                )
            }
        }
        .padding(14)
        .onboardingSurface(radius: 12)
    }

    private var appleSetup: some View {
        Label {
            Text("Apple Speech 会完成实时转写和文字写入，并使用个人词典提升专名识别。AI 高级能力可随时从设置启用。")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LerroTheme.success)
        }
        .font(LerroFont.body)
        .foregroundStyle(LerroTheme.secondaryText)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingSurface(radius: 12)
        .onAppear {
            session.activateIntelligenceMode(.raw)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(LerroFont.caption)
            .foregroundStyle(LerroTheme.secondaryText)
            .frame(width: 68, alignment: .leading)
    }

    private func testConnection() {
        guard providerDraft.validationMessage == nil else { return }
        let configuration = providerDraft.configuration
        connectionOutcome = nil
        isTestingConnection = true
        Task { @MainActor in
            connectionOutcome = await session.testRemoteProviderConnection(configuration)
            isTestingConnection = false
        }
    }

    private func saveProvider() {
        guard providerDraft.validationMessage == nil,
              connectionOutcome?.succeeded == true else { return }
        let configuration = providerDraft.configuration
        isSavingProvider = true
        Task { @MainActor in
            let saved = await session.saveRemoteProvider(configuration)
            isSavingProvider = false
            if saved {
                providerDraft = IntelligenceProviderDraft(configuration: configuration)
                connectionOutcome = .success(message: "API 模型已启用")
            } else {
                connectionOutcome = .failure("配置保存失败，请重试")
            }
        }
    }

    private func keepIncompleteRouteOnBaseDictation() {
        switch selectedRoute {
        case .remote where !providerDraft.configuration.isReadyForUse:
            session.activateIntelligenceMode(.raw)
        case .apple:
            session.activateIntelligenceMode(.raw)
        case .remote:
            session.activateIntelligenceMode(.remote)
        }
    }

    private var customBaseURLBinding: Binding<String> {
        Binding {
            providerDraft.baseURL
        } set: { updated in
            _ = providerDraft.updateBaseURL(updated)
            connectionOutcome = nil
        }
    }
}
