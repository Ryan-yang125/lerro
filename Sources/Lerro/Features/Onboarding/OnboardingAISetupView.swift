import SwiftUI
import LerroCore

private enum OnboardingAIRoute: String, CaseIterable, Identifiable {
    case local
    case remote
    case basic

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
    @State private var isDiscardConfirmationPresented = false

    init(session: AppSession) {
        self.session = session
        let selectedRoute: OnboardingAIRoute = if session.preferences.intelligenceMode == .local,
                                                  !session.preferences.hasApprovedModelDownload,
                                                  session.localAIReadiness?.recommendation != .localRecommended {
            .remote
        } else {
            switch session.preferences.intelligenceMode {
            case .raw: .basic
            case .local: .local
            case .remote: .remote
            }
        }
        _selectedRoute = State(initialValue: selectedRoute)
        _providerDraft = State(initialValue: IntelligenceProviderDraft(
            configuration: session.preferences.remoteProvider
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            deviceSummary
            routePicker

            switch selectedRoute {
            case .local:
                localSetup
            case .remote:
                remoteSetup
            case .basic:
                basicSetup
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
        .confirmationDialog(
            "停止本地模型下载？",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("停止并删除断点", role: .destructive) {
                session.discardLocalModelDownload()
            }
            Button("保留下载", role: .cancel) {}
        } message: {
            Text("已完成的模型文件会继续保留，未完成文件和下载断点将被删除。")
        }
    }

    private var deviceSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: recommendationIcon)
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(recommendationColor)
                .frame(width: 34, height: 34)
                .background(LerroTheme.fillContainerTough)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(recommendationTitle))
                    .font(LerroTheme.font(14, weight: .medium))
                if let readiness = session.localAIReadiness {
                    Text(verbatim: deviceFacts(readiness.device))
                        .font(LerroTheme.font(12))
                        .foregroundStyle(LerroTheme.secondaryText)
                    Text(LocalizedStringKey(recommendationDetail))
                        .font(LerroTheme.font(12))
                        .foregroundStyle(LerroTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView("正在检测这台 Mac…")
                        .controlSize(.small)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
        .accessibilityElement(children: .combine)
    }

    private var routePicker: some View {
        HStack(spacing: 10) {
            routeButton(
                .local,
                title: "本地 AI",
                detail: "隐私优先 · 约 3.03 GB",
                icon: "cpu"
            )
            routeButton(
                .remote,
                title: "API 模型",
                detail: "快速启用 · 使用自己的 Key",
                icon: "network"
            )
            routeButton(
                .basic,
                title: "基础听写",
                detail: "立即开始 · 随后启用 AI",
                icon: "waveform"
            )
        }
    }

    private func routeButton(
        _ route: OnboardingAIRoute,
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        let selected = selectedRoute == route
        let disabled = route == .local
            && session.localAIReadiness?.recommendation == .localUnavailable
        return Button {
            selectedRoute = route
            if route == .basic
                || (route == .local && !session.preferences.hasApprovedModelDownload)
                || (route == .remote && !providerDraft.configuration.isReadyForUse) {
                session.activateIntelligenceMode(.raw)
            } else if route == .local, session.preferences.hasApprovedModelDownload {
                session.activateIntelligenceMode(.local)
            } else if route == .remote {
                session.activateIntelligenceMode(.remote)
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: icon)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                }
                Text(LocalizedStringKey(title))
                    .font(LerroTheme.font(13, weight: .medium))
                Text(LocalizedStringKey(detail))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(selected ? LerroTheme.fillContainerTough : LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                    .stroke(selected ? LerroTheme.focusBorder : LerroTheme.thinBorder)
            }
        }
        .buttonStyle(LerroPressButtonStyle())
        .disabled(disabled)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(Text(LocalizedStringKey(selected ? "已选择" : "未选择")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var localSetup: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Qwen3.5 4B")
                        .font(LerroTheme.font(14, weight: .medium))
                    Text(LocalizedStringKey(localStatusText))
                        .font(LerroTheme.font(12))
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Spacer()

                if session.modelStatus.state == .downloading
                    || session.modelStatus.state == .loading {
                    Button("暂停") { session.pauseLocalModelPreparation() }
                        .buttonStyle(LerroPillButtonStyle())
                } else {
                    Button(LocalizedStringKey(localActionTitle)) {
                        session.requestLocalModelPreparation()
                    }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                    .disabled(session.localAIIsReady)
                }

                if session.modelStatus.state == .paused
                    || session.modelStatus.state == .downloading
                    || session.modelStatus.state == .loading {
                    Button("停止", role: .destructive) {
                        isDiscardConfirmationPresented = true
                    }
                    .buttonStyle(LerroPillButtonStyle(destructive: true))
                }
            }

            if showsLocalProgress {
                ProgressView(value: max(0, min(1, session.modelStatus.progress)))
                    .accessibilityLabel("本地模型下载进度")
                HStack {
                    Text(verbatim: progressText)
                    Spacer()
                    Text("可关闭此页面，Lerro 运行期间会继续下载")
                }
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.secondaryText)
            }

            Text("下载完成前，基础 Quick Dictate 继续使用 Apple Speech。模型就绪后自动启用增强听写、Ask 和语义改写。")
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
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
            .font(LerroTheme.font(12, weight: .medium))

            if let validation = providerDraft.validationMessage {
                Label(LocalizedStringKey(validation), systemImage: "info.circle")
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.secondaryText)
            } else if let connectionOutcome {
                Label {
                    Text(LocalizedStringKey(connectionOutcome.message))
                } icon: {
                    Image(systemName: connectionOutcome.succeeded
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill")
                }
                .font(LerroTheme.font(12, weight: .medium))
                .foregroundStyle(connectionOutcome.succeeded ? LerroTheme.green : LerroTheme.red)
            }

            HStack {
                Text("连接测试只发送固定合成文字。API Key 会保存在本机 Lerro 设置 JSON 中。")
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.secondaryText)
                Spacer()
                Button(LocalizedStringKey(isTestingConnection ? "正在测试" : "测试连接")) {
                    testConnection()
                }
                .buttonStyle(LerroPillButtonStyle())
                .disabled(providerDraft.validationMessage != nil || isTestingConnection || isSavingProvider)
                Button(LocalizedStringKey(isSavingProvider ? "正在保存" : "保存并启用")) {
                    saveProvider()
                }
                .buttonStyle(LerroPillButtonStyle(prominent: true))
                .disabled(
                    providerDraft.validationMessage != nil
                        || connectionOutcome?.succeeded != true
                        || isTestingConnection
                        || isSavingProvider
                )
            }
        }
        .padding(16)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
    }

    private var basicSetup: some View {
        Label {
            Text("Apple Speech、Quick Dictate、设备端翻译、回执撤销和精确语音修改都可以先使用。稍后从设置继续准备 AI。")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(LerroTheme.font(13))
        .foregroundStyle(LerroTheme.secondaryText)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .onAppear {
            session.activateIntelligenceMode(.raw)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(LerroTheme.font(12, weight: .medium))
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
        case .local where !session.preferences.hasApprovedModelDownload:
            session.activateIntelligenceMode(.raw)
        case .remote where !providerDraft.configuration.isReadyForUse:
            session.activateIntelligenceMode(.raw)
        case .basic:
            session.activateIntelligenceMode(.raw)
        case .local:
            session.activateIntelligenceMode(.local)
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

    private var recommendationTitle: String {
        switch session.localAIReadiness?.recommendation {
        case .localRecommended: "这台 Mac 适合本地 AI"
        case .remoteRecommended: "推荐使用 API 模型"
        case .localUnavailable: "这台 Mac 需要 API 模型"
        case nil: "正在检测这台 Mac"
        }
    }

    private var recommendationDetail: String {
        guard let readiness = session.localAIReadiness else { return "" }
        return switch readiness.recommendation {
        case .localRecommended:
            "内存与磁盘空间充足，本地模型可以兼顾隐私和离线使用。"
        case .remoteRecommended:
            readiness.hasEnoughStorage
                ? "当前内存配置更适合 API 模型，本地模式仍可手动选择。"
                : "可用磁盘空间低于建议值，API 模型可以节省本机空间。"
        case .localUnavailable:
            "当前硬件缺少本地模型运行条件，请配置 OpenAI-compatible API。"
        }
    }

    private var recommendationIcon: String {
        switch session.localAIReadiness?.recommendation {
        case .localRecommended: "checkmark.seal.fill"
        case .remoteRecommended: "speedometer"
        case .localUnavailable: "exclamationmark.triangle.fill"
        case nil: "ellipsis.circle"
        }
    }

    private var recommendationColor: Color {
        switch session.localAIReadiness?.recommendation {
        case .localRecommended: LerroTheme.green
        case .remoteRecommended, .localUnavailable: LerroTheme.orange
        case nil: LerroTheme.accent
        }
    }

    private func deviceFacts(_ device: DeviceCapabilitySnapshot) -> String {
        let memory = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: device.physicalMemoryBytes),
            countStyle: .memory
        )
        let storage = ByteCountFormatter.string(
            fromByteCount: device.availableStorageBytes,
            countStyle: .file
        )
        return LerroInterfaceLocalization.format(
            "%@ · %@ 内存 · %@ 可用空间",
            locale: locale,
            arguments: device.chipName, memory, storage
        )
    }

    private var localStatusText: String {
        session.modelStatus.message.isEmpty ? "等待准备" : session.modelStatus.message
    }

    private var localActionTitle: String {
        if session.localAIIsReady { return "已就绪" }
        return switch session.modelStatus.state {
        case .paused: "继续下载"
        case .failed: "重试"
        case .ready where session.modelStatus.progress >= 1: "加载模型"
        case .unavailable, .ready: "下载并启用"
        case .downloading, .loading: "准备中"
        case .loaded: "已就绪"
        }
    }

    private var showsLocalProgress: Bool {
        session.modelStatus.state == .downloading
            || session.modelStatus.state == .loading
            || session.modelStatus.state == .paused
    }

    private var progressText: String {
        let status = session.modelStatus
        guard status.downloadedBytes > 0, status.totalBytes > 0 else {
            return "\(Int(status.progress * 100))%"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: status.downloadedBytes)) / \(formatter.string(fromByteCount: status.totalBytes))"
    }
}
