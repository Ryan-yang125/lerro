import AppKit
import SwiftUI
import LerroCore

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case privacy
    case localMode
    case permissions
    case shortcuts
    case practice

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .privacy: "隐私从这台 Mac 开始"
        case .localMode: "选择初始处理方式"
        case .permissions: "连接 macOS 权限"
        case .shortcuts: "设置快捷键"
        case .practice: "完成一次语音输入"
        }
    }

    var detail: String {
        switch self {
        case .privacy:
            "了解收音、历史与本地处理，再按自己的节奏完成设置。"
        case .localMode:
            "基础听写可直接使用 Apple 语音识别；本地 AI 可整理表达。完成引导后，也能在“智能处理”中配置自己的 API。"
        case .permissions:
            "两项权限分别负责收音、全局快捷键和文字写入。您也可以稍后在设置中继续。"
        case .shortcuts:
            "选择顺手的按键和触发方式，实时确认这块键盘是否成功送出按下与松开事件。"
        case .practice:
            "将光标放进练习编辑器，使用刚设置的快捷键或下方按钮开始听写。"
        }
    }

    var icon: String {
        switch self {
        case .privacy: "hand.raised.fill"
        case .localMode: "cpu.fill"
        case .permissions: "lock.shield.fill"
        case .shortcuts: "keyboard.fill"
        case .practice: "waveform"
        }
    }

    var shortTitle: String {
        switch self {
        case .privacy: "隐私"
        case .localMode: "处理"
        case .permissions: "权限"
        case .shortcuts: "快捷键"
        case .practice: "练习"
        }
    }
}

private enum OnboardingPermission: String, CaseIterable, Identifiable {
    case microphone
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "麦克风"
        case .accessibility: "辅助功能"
        }
    }

    var detail: String {
        switch self {
        case .microphone: "录制您主动发起的语音"
        case .accessibility: "响应全局 Fn 快捷键并写入当前应用"
        }
    }

    var icon: String {
        switch self {
        case .microphone: "mic.fill"
        case .accessibility: "accessibility"
        }
    }

    var systemSettingsURLString: String {
        switch self {
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

private enum OnboardingAccessibilityFocus: Hashable {
    case heading
}

struct OnboardingView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var accessibilityFocus: OnboardingAccessibilityFocus?
    @FocusState private var practiceEditorFocused: Bool

    @State private var step: OnboardingStep = .privacy
    @State private var sampleText = "把光标放在这里，然后按住 Fn 说一句话。"
    @State private var showShortcutHelp = false
    @State private var dictateShortcutDraft: ShortcutBindingDraft?
    @State private var translateShortcutDraft: ShortcutBindingDraft?
    @State private var dictateShortcutActivation: ShortcutActivation = .toggle
    @State private var translateShortcutActivation: ShortcutActivation = .toggle
    @State private var selectedShortcutAction: HotkeyAction = .dictate
    @State private var shortcutSaveError = ""
    @State private var isShortcutSaving = false
    @State private var shortcutConfigurationPrepared = false
    @State private var hasCompletedPracticeCapture = false

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
                .frame(height: 72)

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if step != .privacy {
                                Button(action: previous) {
                                    Label("返回", systemImage: "chevron.left")
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.regular)
                                .accessibilityHint("返回上一步")
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(LocalizedStringKey(step.title))
                                    .font(LerroTheme.font(24, weight: .medium))
                                    .tracking(LerroTheme.uiTracking)
                                    .foregroundStyle(.primary)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityFocused($accessibilityFocus, equals: .heading)

                                Text(LocalizedStringKey(step.detail))
                                    .font(LerroTheme.font(14))
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            pageContent
                                .id(step)
                                .transition(reduceMotion ? .identity : .opacity)

                            HStack(spacing: 12) {
                                if step == .permissions && !canAdvanceFromPermissions {
                                    Text("完成以上项目后可继续")
                                        .font(LerroTheme.font(12))
                                        .foregroundStyle(LerroTheme.orange)
                                }
                                if step == .practice && !hasCompletedPracticeCapture {
                                    Label {
                                        Text("请先完成一次成功的听写")
                                    } icon: {
                                        Image(systemName: "exclamationmark.circle.fill")
                                    }
                                        .font(LerroTheme.font(12))
                                        .foregroundStyle(LerroTheme.orange)
                                }
                                Spacer()
                                Button(action: next) {
                                    Text(verbatim: localized(primaryActionTitle))
                                }
                                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                                    .controlSize(.large)
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(
                                        isShortcutSaving
                                        || (step == .permissions && !canAdvanceFromPermissions)
                                        || (step == .practice && !hasCompletedPracticeCapture)
                                    )
                            }
                        }
                        .frame(maxWidth: 620, minHeight: 520, alignment: .topLeading)
                        .padding(.vertical, 30)
                        .padding(.horizontal, 56)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(width: geometry.size.width * 0.60, height: geometry.size.height)
                    .background(LerroTheme.main)

                    visualPanel
                        .frame(width: geometry.size.width * 0.40, height: geometry.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LerroTheme.main)
        .task(id: step) {
            switch step {
            case .permissions:
                await session.refreshPermissions(prompt: false)
                await session.refreshLanguageResources()
            case .practice:
                await session.refreshPermissions(prompt: false)
                await session.refreshAudioInputDevices()
            case .shortcuts:
                prepareShortcutDraftsIfNeeded()
                shortcutConfigurationPrepared = session.beginShortcutConfiguration()
                if !shortcutConfigurationPrepared {
                    shortcutSaveError = session.currentError ?? "请完成当前语音输入后再设置快捷键。"
                }
            case .privacy, .localMode:
                break
            }
        }
        .onChange(of: step) { oldStep, newStep in
            if oldStep == .shortcuts {
                session.endShortcutConfiguration()
                shortcutConfigurationPrepared = false
            }
            if newStep != .practice {
                session.stopOnboardingMicrophoneTest()
            }
            session.preferences.onboardingStepIndex = newStep.rawValue
            session.savePreferences()
            Task { @MainActor in
                accessibilityFocus = .heading
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, step == .permissions || step == .practice else { return }
            Task { await session.refreshPermissions(prompt: false) }
        }
        .onChange(of: locale.identifier) { _, _ in
            localizeDefaultSampleTextIfNeeded()
        }
        .onChange(of: session.phase) { oldPhase, newPhase in
            guard step == .practice else { return }
            // Success path: inserting → idle means text was delivered
            if oldPhase == .inserting, newPhase == .idle {
                hasCompletedPracticeCapture = true
            }
            // Reset when user starts a new capture attempt
            if newPhase == .listening {
                hasCompletedPracticeCapture = false
            }
        }
        .alert("快捷键没有反应", isPresented: $showShortcutHelp) {
            Button("打开辅助功能设置") {
                openSystemSettings(for: .accessibility)
            }
            Button("重新检查") {
                Task { await session.refreshPermissions(prompt: false) }
            }
            Button("继续练习", role: .cancel) {}
        } message: {
            Text("开启辅助功能后，回到 Lerro 即会自动刷新状态。")
        }
        .onAppear {
            if let index = session.preferences.onboardingStepIndex,
               let restoredStep = OnboardingStep(rawValue: index) {
                step = restoredStep
            }
            accessibilityFocus = .heading
            localizeDefaultSampleTextIfNeeded()
        }
        .onDisappear {
            session.stopOnboardingMicrophoneTest()
            session.endShortcutConfiguration()
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 9) {
            HStack(spacing: 14) {
                LerroBrandBadge(compact: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(step.shortTitle))
                        .font(LerroTheme.font(13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(verbatim: onboardingProgressText)
                        .font(LerroTheme.font(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 7) {
                    ForEach(OnboardingStep.allCases) { item in
                        Circle()
                            .fill(item.rawValue <= step.rawValue ? LerroTheme.accent : LerroTheme.fillContainerTough)
                            .frame(width: item == step ? 9 : 7, height: item == step ? 9 : 7)
                            .accessibilityHidden(true)
                    }
                }
            }

            ProgressView(
                value: Double(step.rawValue + 1),
                total: Double(OnboardingStep.allCases.count)
            )
            .progressViewStyle(.linear)
            .accessibilityLabel("设置进度")
            .accessibilityValue(Text(verbatim: onboardingProgressText))
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .background(LerroTheme.topLayer)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch step {
        case .privacy:
            privacyContent
        case .localMode:
            localModeContent
        case .permissions:
            permissionsContent
        case .shortcuts:
            shortcutsContent
        case .practice:
            practiceContent
        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            informationRow(
                title: "无需账户",
                detail: "Lerro 可直接使用，个人资料保存在当前 Mac。",
                icon: "person.crop.circle.badge.checkmark"
            )
            informationRow(
                title: "本地数据保留在当前 Mac",
                detail: "历史、词典、偏好与本地模型结果写入 Lerro 的 Application Support 目录。",
                icon: "internaldrive.fill"
            )
            informationRow(
                title: "API 模式由您控制",
                detail: "启用后，只会按“智能处理”中的开关发送原始转写和允许的上下文。",
                icon: "network"
            )
            informationRow(
                title: "系统语音识别",
                detail: "Apple Speech 按 macOS 当前语言资源与隐私设置处理语音。",
                icon: "captions.bubble.fill"
            )

            Divider()
                .padding(.vertical, 4)

            Toggle(isOn: saveAudioBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("保存原始录音")
                        .font(LerroTheme.font(14, weight: .medium))
                    Text("默认关闭；开启后，完成的录音会随历史保存在这台 Mac。")
                        .font(LerroTheme.font(12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .accessibilityHint("可以随时在设置中更改")
        }
        .padding(18)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
    }

    private var localModeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("听写处理", selection: intelligenceModeBinding) {
                Text("原始听写").tag(IntelligenceMode.raw)
                Text("本地 AI").tag(IntelligenceMode.local)
                Text("API 模型").tag(IntelligenceMode.remote)
            }
            .pickerStyle(.segmented)
            .accessibilityHint("选择原始听写、本地 AI 或已配置的 API 模型")

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: onboardingIntelligenceIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(LerroTheme.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(onboardingIntelligenceTitle))
                            .font(LerroTheme.font(14, weight: .medium))
                        Text(LocalizedStringKey(localModeDetail))
                            .font(LerroTheme.font(13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if session.preferences.intelligenceMode == .local {
                    Divider()

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("模型状态")
                                .font(LerroTheme.font(12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(LocalizedStringKey(localModelStatusText))
                                .font(LerroTheme.font(13, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        Button {
                            if session.preferences.hasApprovedModelDownload {
                                session.activateIntelligenceMode(.local)
                            } else {
                                session.requestLocalModelPreparation()
                            }
                        } label: {
                            Text(verbatim: localized(localModelActionTitle))
                        }
                        .buttonStyle(.bordered)
                        .disabled(localModelActionDisabled)
                    }

                    if showsLocalModelProgress {
                        ProgressView(value: min(1, max(0, session.modelStatus.progress)))
                            .accessibilityLabel("本地模型准备进度")
                    }

                    Text("首次准备会在您确认后下载约 3.03 GB。本地模型或 API 可用于增强听写、指令和改写。")
                        .font(LerroTheme.font(12))
                        .foregroundStyle(.secondary)
                } else if session.preferences.intelligenceMode == .remote {
                    Divider()
                    Label {
                        Text(verbatim: "\(session.preferences.remoteProvider.provider.lerroDisplayName) · \(session.preferences.remoteProvider.modelIdentifier)")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .font(LerroTheme.font(13, weight: .medium))
                    .foregroundStyle(LerroTheme.green)

                    Text("API Key 与上下文发送项可在“设置 → 智能处理”中测试和调整。")
                        .font(LerroTheme.font(12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                    .stroke(LerroTheme.thinBorder)
            }
        }
    }

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(OnboardingPermission.allCases) { permission in
                permissionCard(permission, granted: permissionGranted(permission))
            }

            languageResourceCard(
                title: "语音资源",
                detail: "用于设备端听写",
                icon: "waveform",
                status: session.speechResourceStatus,
                prepare: session.prepareSpeechResources
            )
            languageResourceCard(
                title: "翻译资源",
                detail: "用于设备端翻译",
                icon: "character.bubble",
                status: session.translationResourceStatus,
                prepare: session.prepareTranslationResources
            )

            HStack(spacing: 10) {
                if session.requiredPermissionsGranted {
                    Label("两项权限均已就绪", systemImage: "checkmark.circle.fill")
                        .font(LerroTheme.font(13, weight: .medium))
                        .foregroundStyle(LerroTheme.green)
                        .accessibilityLabel("两项权限均已授权")
                } else {
                    Button("请求系统权限") {
                        Task { await session.refreshPermissions(prompt: true) }
                    }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                    .controlSize(.large)
                    .help("由 macOS 依次显示尚未决定的权限提示")
                }

                Spacer()

                Button("重新检查") {
                    Task { await session.refreshPermissions(prompt: false) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if !canAdvanceFromPermissions {
                VStack(spacing: 8) {
                    if !session.microphonePermission {
                        blockingHintCard(
                            icon: "mic.slash.fill",
                            message: "需要麦克风权限才能录音。点击上方「请求系统权限」，在系统弹窗中选择「允许」。"
                        )
                    }
                    if !session.accessibilityPermission {
                        blockingHintCard(
                            icon: "hand.raised.slash.fill",
                            message: "需要辅助功能权限才能使用全局快捷键。点击上方「请求系统权限」并开启 Lerro 开关。"
                        )
                    }
                    if session.speechResourceStatus.state != .ready {
                        let speechHint: String = {
                            switch session.speechResourceStatus.state {
                            case .available:
                                return "需要下载语音资源才能进行设备端听写。点击上方语音资源卡片的「准备」按钮。"
                            case .downloading:
                                return "语音资源正在下载中，请等待完成。"
                            case .failed:
                                return "语音资源准备失败，请点击上方语音资源卡片的「准备」按钮重试。"
                            default:
                                return "语音资源尚未就绪，请先准备语音资源。"
                            }
                        }()
                        blockingHintCard(
                            icon: "waveform.slash",
                            message: speechHint
                        )
                    }
                }
            }
        }
    }

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                onboardingShortcutActionCard(
                    action: .dictate,
                    title: "听写",
                    detail: "说话后写入当前光标",
                    icon: "waveform"
                )
                onboardingShortcutActionCard(
                    action: .translate,
                    title: "翻译",
                    detail: "说话后输出目标语言",
                    icon: "character.bubble"
                )
            }

            if shortcutConfigurationPrepared {
                ShortcutRecorderCard(
                    shortcut: selectedShortcutDraft,
                    activation: selectedShortcutActivation
                )
            } else {
                ProgressView("正在准备按键检测…")
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .accessibilityHint("正在暂停生产快捷键并准备录制")
            }

            if !shortcutSaveError.isEmpty {
                Label {
                    Text(verbatim: localized(shortcutSaveError))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.orange)
            }

            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(LerroTheme.accent)
                Text("分别设置听写与翻译的快捷键，完成后立刻试按确认。")
                    .font(LerroTheme.font(12))
                    .foregroundStyle(.secondary)
            }

            Button("快捷键没有反应？") {
                showShortcutHelp = true
            }
            .buttonStyle(.link)
            .accessibilityHint("查看辅助功能权限帮助")
        }
    }

    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Picker("输入设备", selection: microphoneSelection) {
                    Text("系统默认麦克风").tag("")
                    ForEach(session.audioInputDevices) { device in
                        Text(verbatim: device.isDefault
                            ? LerroInterfaceLocalization.format("%@（默认）", locale: locale, arguments: device.name)
                            : device.name)
                            .tag(device.uid)
                    }
                }
                .disabled(session.isOnboardingMicrophoneTestRunning)

                Button {
                    session.toggleOnboardingMicrophoneTest()
                } label: {
                    Text(verbatim: localized(microphoneTestButtonTitle))
                }
                .buttonStyle(.bordered)
                .disabled(!session.microphonePermission)
            }

            WaveLevelMeter(
                level: session.onboardingMicrophoneLevel,
                reduceMotion: reduceMotion,
                isRunning: session.isOnboardingMicrophoneTestRunning
            )

            HStack(spacing: 8) {
                Image(systemName: microphoneTestStatusIcon)
                    .foregroundStyle(microphoneTestStatusColor)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(microphoneTestStatusText))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("麦克风测试")
            .accessibilityValue(Text(verbatim: localized(microphoneTestStatusText)))

            if let error = session.onboardingMicrophoneTestError {
                Label {
                    Text(verbatim: localized(error))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.red)
                    .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                        "麦克风测试错误：%@",
                        locale: locale,
                        arguments: localized(error)
                    )))
            }

            TextEditor(text: $sampleText)
                .font(LerroTheme.font(14))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 132)
                .background(LerroTheme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                        .stroke(practiceEditorFocused ? LerroTheme.focusBorder : LerroTheme.border)
                }
                .focused($practiceEditorFocused)
                .accessibilityLabel("练习编辑器")
                .accessibilityHint("将光标放在这里，然后使用刚设置的快捷键听写")

            HStack(spacing: 10) {
                Button(action: togglePracticeCapture) {
                    Text(verbatim: localized(practiceCaptureButtonTitle))
                }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                    .controlSize(.large)
                    .disabled(practiceCaptureButtonDisabled)

                Button("快捷键帮助") {
                    showShortcutHelp = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Text(LocalizedStringKey(practicePhaseText))
                    .font(LerroTheme.font(12, weight: .medium))
                    .foregroundStyle(practicePhaseColor)
                    .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                        "听写状态：%@",
                        locale: locale,
                        arguments: localized(practicePhaseText)
                    )))
            }

            if session.phase == .failed, let error = session.captureError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(LerroTheme.orange)
                        Text("听写未成功")
                            .font(LerroTheme.font(13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Text(verbatim: localized(error))
                        .font(LerroTheme.font(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("重试") {
                            togglePracticeCapture()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("返回上一步") {
                            if let permissionsStep = OnboardingStep.allCases.first(where: { $0 == .permissions }) {
                                navigate(to: permissionsStep)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .background(LerroTheme.fillContainerThin)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                        .stroke(LerroTheme.orange.opacity(0.3))
                }
            }
        }
    }

    private func onboardingShortcutActionCard(
        action: HotkeyAction,
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        let definition = session.preferences.hotkeys.first { $0.action == action }
        let isSelected = selectedShortcutAction == action
        return Button {
            selectedShortcutAction = action
            shortcutSaveError = ""
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                    Spacer()
                    if let definition { ShortcutBadge(title: definition.displayName) }
                }
                Text(verbatim: localized(title)).font(LerroTheme.font(14, weight: .medium))
                Text(verbatim: localized(detail))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(isSelected ? LerroTheme.fillContainerTough : LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                    .stroke(isSelected ? LerroTheme.focusBorder : LerroTheme.thinBorder)
            }
        }
        .buttonStyle(LerroPressButtonStyle())
        .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
            "设置%@快捷键",
            locale: locale,
            arguments: localized(title)
        )))
        .accessibilityValue(Text(verbatim: definition?.displayName ?? localized("尚未设置")))
    }

    private var visualPanel: some View {
        ZStack {
            LerroTheme.fillContainerThin

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LerroTheme.accent)
                    Image(systemName: step.icon)
                        .font(.system(size: 48, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(LerroTheme.pivotText)
                        .accessibilityHidden(true)
                }
                .frame(width: 116, height: 116)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 9)

                VStack(spacing: 6) {
                    Text(verbatim: localized(visualTitle))
                        .font(LerroTheme.font(14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(verbatim: localizedVisualCaption)
                        .font(LerroTheme.font(13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 250)
                }
            }
            .padding(32)
        }
        .overlay(alignment: .leading) {
            Divider()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
            "%@。%@",
            locale: locale,
            arguments: localized(visualTitle), localizedVisualCaption
        )))
    }

    private func informationRow(title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(LerroTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: localized(title))
                    .font(LerroTheme.font(14, weight: .medium))
                Text(verbatim: localized(detail))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func permissionCard(_ permission: OnboardingPermission, granted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: permission.icon)
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(granted ? LerroTheme.green : LerroTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(LocalizedStringKey(permission.title))
                        .font(LerroTheme.font(14, weight: .medium))
                    Label {
                        Text(verbatim: localized(granted ? "已授权" : "等待授权"))
                    } icon: {
                        Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                    }
                        .font(LerroTheme.font(12, weight: .medium))
                        .foregroundStyle(granted ? LerroTheme.green : LerroTheme.orange)
                }
                Text(LocalizedStringKey(permission.detail))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("系统设置") {
                openSystemSettings(for: permission)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                "打开%@系统设置",
                locale: locale,
                arguments: localized(permission.title)
            )))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
    }

    private func languageResourceCard(
        title: String,
        detail: String,
        icon: String,
        status: LanguageResourceStatus,
        prepare: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(status.state == .ready ? LerroTheme.green : (status.state == .failed ? LerroTheme.orange : LerroTheme.accent))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: localized(title)).font(LerroTheme.font(14, weight: .medium))
                Text(verbatim: localizedStatus(status.message.isEmpty ? detail : status.message))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status.state == .available {
                Button("准备", action: prepare)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if status.state == .failed {
                Button("重试", action: prepare)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(LerroTheme.orange)
            } else if status.state == .downloading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
    }

    private func blockingHintCard(icon: String, message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LerroTheme.orange)
                .frame(width: 20)
            Text(verbatim: localized(message))
                .font(LerroTheme.font(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                .stroke(LerroTheme.orange.opacity(0.3))
        }
    }

    private func shortcutRow(
        title: String,
        detail: String,
        icon: String,
        shortcut: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(LerroTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: localized(title))
                    .font(LerroTheme.font(14, weight: .medium))
                Text(verbatim: localized(detail))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShortcutBadge(title: shortcut)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
            "快捷键 %@：%@",
            locale: locale,
            arguments: localized(title), shortcut
        )))
        .accessibilityValue(Text(verbatim: localized(detail)))
    }

    private func permissionGranted(_ permission: OnboardingPermission) -> Bool {
        switch permission {
        case .microphone: session.microphonePermission
        case .accessibility: session.accessibilityPermission
        }
    }

    private func openSystemSettings(for permission: OnboardingPermission) {
        guard let url = URL(string: permission.systemSettingsURLString),
              NSWorkspace.shared.open(url) else {
            session.currentError = LerroInterfaceLocalization.format(
                "无法打开%@设置，请在系统设置的隐私与安全性中手动打开。",
                locale: locale,
                arguments: localized(permission.title)
            )
            return
        }
    }

    private func next() {
        if step == .permissions {
            guard canAdvanceFromPermissions else { return }
            guard session.beginShortcutConfiguration() else {
                session.currentError = session.currentError ?? "暂时无法进入快捷键设置。"
                return
            }
            shortcutConfigurationPrepared = true
        }
        if step == .practice {
            guard hasCompletedPracticeCapture else { return }
        }
        if step == .shortcuts {
            guard !isShortcutSaving else { return }
            isShortcutSaving = true
            Task { @MainActor in
                guard await saveOnboardingShortcut() else {
                    isShortcutSaving = false
                    return
                }
                isShortcutSaving = false
                advanceFromCurrentStep()
            }
            return
        }
        advanceFromCurrentStep()
    }

    private func advanceFromCurrentStep() {
        session.savePreferences()
        guard step != .practice else {
            session.completeOnboarding()
            return
        }
        guard let nextStep = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        navigate(to: nextStep)
    }

    private func previous() {
        guard let previousStep = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        if previousStep == .shortcuts {
            Task { @MainActor in
                guard await session.prepareShortcutConfigurationAfterCancellingCapture() else {
                    shortcutSaveError = session.currentError ?? "暂时无法进入快捷键设置。"
                    return
                }
                shortcutConfigurationPrepared = true
                navigate(to: previousStep)
            }
            return
        }
        navigate(to: previousStep)
    }

    private func navigate(to destination: OnboardingStep) {
        if reduceMotion {
            step = destination
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                step = destination
            }
        }
    }

    private var selectedShortcutDraft: Binding<ShortcutBindingDraft?> {
        selectedShortcutAction == .dictate ? $dictateShortcutDraft : $translateShortcutDraft
    }

    private var selectedShortcutActivation: Binding<ShortcutActivation> {
        selectedShortcutAction == .dictate ? $dictateShortcutActivation : $translateShortcutActivation
    }

    private func prepareShortcutDraftsIfNeeded() {
        if dictateShortcutDraft == nil,
           let definition = session.preferences.hotkeys.first(where: { $0.action == .dictate }) {
            dictateShortcutDraft = ShortcutBindingDraft(definition: definition)
            dictateShortcutActivation = definition.activation.resolved
        }
        if translateShortcutDraft == nil,
           let definition = session.preferences.hotkeys.first(where: { $0.action == .translate }) {
            translateShortcutDraft = ShortcutBindingDraft(definition: definition)
            translateShortcutActivation = definition.activation.resolved
        }
    }

    private func saveOnboardingShortcut() async -> Bool {
        guard let dictateShortcutDraft, let translateShortcutDraft else {
            shortcutSaveError = "请完成听写和翻译快捷键。"
            return false
        }
        let changes: [(HotkeyAction, ShortcutBindingDraft, ShortcutActivation)] = [
            (.dictate, dictateShortcutDraft, dictateShortcutActivation),
            (.translate, translateShortcutDraft, translateShortcutActivation)
        ]
        for (action, draft, activation) in changes {
            let existing = session.preferences.hotkeys.first(where: { $0.action == action })
            guard await session.commitHotkey(
                for: action,
                replacing: existing,
                keyCode: draft.keyCode,
                modifiers: draft.modifiers,
                usesFunctionKey: draft.usesFunctionKey,
                activation: activation,
                displayName: draft.displayName
            ) else {
                shortcutSaveError = "\(action == .dictate ? "听写" : "翻译")快捷键与已有按键冲突，请重新选择。"
                return false
            }
        }
        shortcutSaveError = ""
        sampleText = dictateShortcutActivation.resolved == .hold
            ? LerroInterfaceLocalization.format(
                "把光标放在这里，然后按住 %@ 说一句话。",
                locale: locale,
                arguments: dictateShortcutDraft.displayName
            )
            : LerroInterfaceLocalization.format(
                "把光标放在这里，按一下 %@ 开始，再按一下完成。",
                locale: locale,
                arguments: dictateShortcutDraft.displayName
            )
        return true
    }

    private func togglePracticeCapture() {
        practiceEditorFocused = true
        Task { @MainActor in
            await Task.yield()
            session.toggleCapture(.dictation)
        }
    }

    private var onboardingProgressText: String {
        LerroInterfaceLocalization.format(
            "第 %lld 步，共 %lld 步",
            locale: locale,
            arguments: Int64(step.rawValue + 1), Int64(OnboardingStep.allCases.count)
        )
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }

    private func localizedStatus(_ message: String) -> String {
        LerroInterfaceLocalization.statusString(message, locale: locale)
    }

    private func localizeDefaultSampleTextIfNeeded() {
        let key = "把光标放在这里，然后按住 Fn 说一句话。"
        let knownDefaults = [
            key,
            LerroInterfaceLocalization.string(key, locale: Locale(identifier: "en")),
            LerroInterfaceLocalization.string(key, locale: Locale(identifier: "zh-Hans"))
        ]
        if knownDefaults.contains(sampleText) {
            sampleText = localized(key)
        }
    }

    private var canAdvanceFromPermissions: Bool {
        session.requiredPermissionsGranted && session.speechResourceStatus.state == .ready
    }

    private var primaryActionTitle: String {
        switch step {
        case .shortcuts where isShortcutSaving:
            "正在保存…"
        case .permissions where !session.requiredPermissionsGranted:
            "稍后继续"
        case .practice:
            "完成设置"
        default:
            "继续"
        }
    }

    private var saveAudioBinding: Binding<Bool> {
        Binding {
            session.preferences.saveAudio
        } set: { value in
            session.preferences.saveAudio = value
            session.savePreferences()
        }
    }

    private var intelligenceModeBinding: Binding<IntelligenceMode> {
        Binding {
            session.preferences.intelligenceMode
        } set: { mode in
            if mode == .remote,
               session.preferences.remoteProvider.apiKey
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.currentError = "请先在“设置 → 智能处理”中填写并测试 API 配置"
                return
            }
            session.activateIntelligenceMode(mode)
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding {
            session.preferences.microphoneDeviceUID ?? ""
        } set: { value in
            session.stopOnboardingMicrophoneTest(resetResult: true)
            session.preferences.microphoneDeviceUID = value.isEmpty ? nil : value
            session.savePreferences()
        }
    }

    private var localModeDetail: String {
        switch session.preferences.intelligenceMode {
        case .raw:
            "完成语音识别后直接插入原始文字，无需准备语言模型。"
        case .local:
            "听写完成后在本机整理语句；指令与改写也可使用本地模型。"
        case .remote:
            "使用您在设置中保存的 API 模型整理文字；发送内容由六项上下文开关控制。"
        }
    }

    private var onboardingIntelligenceIcon: String {
        switch session.preferences.intelligenceMode {
        case .raw: "waveform"
        case .local: "cpu.fill"
        case .remote: "network"
        }
    }

    private var onboardingIntelligenceTitle: String {
        switch session.preferences.intelligenceMode {
        case .raw: "Apple Speech 原始听写"
        case .local: "Qwen3.5 4B 本地 AI"
        case .remote: "自带 Key 的 API 模型"
        }
    }

    private var localModelStatusText: String {
        guard session.preferences.hasApprovedModelDownload else {
            return "等待您的下载确认"
        }
        if !session.modelStatus.message.isEmpty {
            return localizedStatus(session.modelStatus.message)
        }
        return switch session.modelStatus.state {
        case .unavailable: "等待准备"
        case .downloading: "正在下载"
        case .ready: "已下载"
        case .loading: "正在加载"
        case .loaded: "已就绪"
        case .failed: "准备失败"
        }
    }

    private var localModelActionTitle: String {
        guard session.preferences.hasApprovedModelDownload else { return "准备本地模型" }
        return switch session.modelStatus.state {
        case .loaded: "已就绪"
        case .downloading, .loading: "准备中"
        case .failed: "重试"
        case .ready: "加载"
        case .unavailable: "准备本地模型"
        }
    }

    private var localModelActionDisabled: Bool {
        switch session.modelStatus.state {
        case .loaded, .downloading, .loading:
            true
        case .unavailable, .ready, .failed:
            false
        }
    }

    private var showsLocalModelProgress: Bool {
        session.preferences.hasApprovedModelDownload
            && (session.modelStatus.state == .downloading || session.modelStatus.state == .loading)
    }

    private var microphoneTestButtonTitle: String {
        if session.isOnboardingMicrophoneTestRunning { return "停止测试" }
        return session.onboardingMicrophoneTestPassed ? "重新测试" : "测试麦克风"
    }

    private var microphoneTestStatusIcon: String {
        if !session.microphonePermission { return "exclamationmark.circle.fill" }
        if session.onboardingMicrophoneTestPassed { return "checkmark.circle.fill" }
        if session.isOnboardingMicrophoneTestRunning { return "waveform.circle.fill" }
        return "circle"
    }

    private var microphoneTestStatusColor: Color {
        if !session.microphonePermission { return LerroTheme.orange }
        if session.onboardingMicrophoneTestPassed { return LerroTheme.green }
        return session.isOnboardingMicrophoneTestRunning ? LerroTheme.accent : LerroTheme.tertiaryText
    }

    private var microphoneTestStatusText: String {
        if !session.microphonePermission { return "开启麦克风权限后可以测试输入设备" }
        if session.onboardingMicrophoneTestPassed { return "检测到清晰的麦克风输入" }
        if session.isOnboardingMicrophoneTestRunning { return "请对着麦克风说几句话" }
        return "可选：先测试麦克风，再完成一次真实听写"
    }

    private var practiceCaptureButtonTitle: String {
        switch session.phase {
        case .listening: "结束听写"
        case .transcribing, .enhancing, .inserting: "正在处理"
        default: "开始听写"
        }
    }

    private var practiceCaptureButtonDisabled: Bool {
        switch session.phase {
        case .transcribing, .enhancing, .inserting:
            true
        case .idle, .listening, .success, .failed, .cancelled:
            false
        }
    }

    private var practicePhaseText: String {
        if hasCompletedPracticeCapture { return "已完成" }
        return switch session.phase {
        case .idle: "准备就绪"
        case .listening: "正在聆听"
        case .transcribing: "正在转写"
        case .enhancing: "正在整理"
        case .inserting: "正在写入"
        case .success: "已完成"
        case .failed: "需要重试"
        case .cancelled: "已取消"
        }
    }

    private var practicePhaseColor: Color {
        if hasCompletedPracticeCapture { return LerroTheme.green }
        return switch session.phase {
        case .success: LerroTheme.green
        case .failed: LerroTheme.red
        case .listening, .transcribing, .enhancing, .inserting: LerroTheme.accent
        case .idle, .cancelled: LerroTheme.secondaryText
        }
    }

    private var visualTitle: String {
        switch step {
        case .privacy: "由您掌控"
        case .localMode: "本地优先"
        case .permissions: "按用途授权"
        case .shortcuts: "随处开口"
        case .practice: "声音成为文字"
        }
    }

    private var visualCaption: String {
        switch step {
        case .privacy: "清楚了解数据去向，并随时调整保存选项。"
        case .localMode: "基础听写即时可用，本地增强按需准备。"
        case .permissions: "每项权限都有明确用途和独立设置入口。"
        case .shortcuts:
            "\(selectedShortcutDraft.wrappedValue?.displayName ?? "Fn") · \(selectedShortcutActivation.wrappedValue.resolved == .hold ? "按住说话" : "按一下开关")"
        case .practice: "自在说，清楚写。"
        }
    }

    private var localizedVisualCaption: String {
        guard step == .shortcuts else { return localized(visualCaption) }
        let shortcut = selectedShortcutDraft.wrappedValue?.displayName ?? "Fn"
        let activation = selectedShortcutActivation.wrappedValue.resolved == .hold
            ? localized("按住说话")
            : localized("按一下开关")
        return "\(shortcut) · \(activation)"
    }
}

private struct WaveLevelMeter: View {
    let level: Float
    let reduceMotion: Bool
    let isRunning: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: 8) {
                    Image(systemName: detectedSound ? "waveform.circle.fill" : "waveform.circle")
                        .foregroundStyle(detectedSound ? LerroTheme.accent : LerroTheme.tertiaryText)
                    Text(verbatim: localized(detectedSound ? "检测到声音" : (isRunning ? "等待声音" : "麦克风测试未开始")))
                        .font(LerroTheme.font(12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<24, id: \.self) { index in
                        Capsule()
                            .fill(index < Int(level * 24) ? LerroTheme.accent : LerroTheme.fillContainerTough)
                            .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
                    }
                }
            }
        }
        .padding(12)
        .frame(minHeight: 40)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("麦克风音量")
        .accessibilityValue(Text(verbatim: localized(accessibilityValue)))
    }

    private var detectedSound: Bool {
        isRunning && level >= 0.12
    }

    private var accessibilityValue: String {
        if !isRunning { return "测试未开始" }
        return detectedSound ? "检测到声音" : "等待声音"
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}
