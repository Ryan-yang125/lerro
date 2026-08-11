import AppKit
import SwiftUI
import LerroCore

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case privacy
    case aiSetup
    case permissions
    case shortcuts
    case practice
    case receipt
    case voiceEdit
    case toolkit
    case ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .privacy: "隐私从这台 Mac 开始"
        case .aiSetup: "为这台 Mac 选择 AI"
        case .permissions: "连接 macOS 权限"
        case .shortcuts: "设置快捷键"
        case .practice: "完成第一次 Quick Dictate"
        case .receipt: "掌握写入后的安全操作"
        case .voiceEdit: "继续说，直接修改上一段"
        case .toolkit: "认识完整的语音工具箱"
        case .ready: "你的 Lerro 已准备完成"
        }
    }

    var detail: String {
        switch self {
        case .privacy:
            "了解收音、历史与本地处理，再按自己的节奏完成设置。"
        case .aiSetup:
            "Lerro 会读取本机硬件与可用磁盘，给出本地 AI 或 API 模型建议。下载可以在后台继续。"
        case .permissions:
            "两项权限分别负责收音、全局快捷键和文字写入。您也可以稍后在设置中继续。"
        case .shortcuts:
            "选择顺手的按键和触发方式，实时确认这块键盘是否成功送出按下与松开事件。"
        case .practice:
            "将光标放进练习编辑器，点按一次听写快捷键，说完后自然停顿，Lerro 会自动写入。"
        case .receipt:
            "每次写入后都有短暂回执，让你撤销、修正或确认发送，同时保护当前输入目标。"
        case .voiceEdit:
            "写入后的 60 秒内，再按一次听写并说出修改指令，Lerro 会安全更新同一段文字。"
        case .toolkit:
            "Quick Dictate、长听写、翻译、Ask、词典与应用语气覆盖不同工作场景。"
        case .ready:
            "最后确认快捷键和 AI 状态。你可以随时从设置重新打开这套教学。"
        }
    }

    var icon: String {
        switch self {
        case .privacy: "hand.raised.fill"
        case .aiSetup: "cpu.fill"
        case .permissions: "lock.shield.fill"
        case .shortcuts: "keyboard.fill"
        case .practice: "waveform"
        case .receipt: "checkmark.bubble.fill"
        case .voiceEdit: "arrow.trianglehead.2.clockwise.rotate.90"
        case .toolkit: "square.grid.2x2.fill"
        case .ready: "checkmark.seal.fill"
        }
    }

    var shortTitle: String {
        switch self {
        case .privacy: "隐私"
        case .aiSetup: "AI"
        case .permissions: "权限"
        case .shortcuts: "快捷键"
        case .practice: "练习"
        case .receipt: "回执"
        case .voiceEdit: "修改"
        case .toolkit: "工具"
        case .ready: "完成"
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
            case .privacy, .aiSetup, .receipt, .voiceEdit, .toolkit, .ready:
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
        case .aiSetup:
            OnboardingAISetupView(session: session)
        case .permissions:
            permissionsContent
        case .shortcuts:
            shortcutsContent
        case .practice:
            practiceContent
        case .receipt:
            receiptContent
        case .voiceEdit:
            voiceEditContent
        case .toolkit:
            toolkitContent
        case .ready:
            readyContent
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

    private var receiptContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("已写入 Notes", systemImage: "checkmark.circle.fill")
                        .font(LerroTheme.font(13, weight: .medium))
                        .foregroundStyle(LerroTheme.green)
                    Spacer()
                    Text("6 秒")
                        .font(LerroTheme.font(12, weight: .medium))
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Text("明天下午三点讨论 onboarding 的最终验收。")
                    .font(LerroTheme.font(14))
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                    Label("修正", systemImage: "pencil")
                    Label("继续说", systemImage: "waveform")
                }
                .font(LerroTheme.font(12, weight: .medium))
                .foregroundStyle(LerroTheme.secondaryText)
            }
            .padding(16)
            .background(LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                    .stroke(LerroTheme.thinBorder)
            }

            informationRow(
                title: "撤销",
                detail: "在回执出现时点按撤销，Lerro 会确认应用、输入框和文字仍然匹配，再发送 Command-Z。",
                icon: "arrow.uturn.backward.circle.fill"
            )
            informationRow(
                title: "修正",
                detail: "直接编辑回执中的结果。Lerro 会原子地撤回旧文字并写入新版本，同时学习这次纠正。",
                icon: "pencil.circle.fill"
            )
            informationRow(
                title: "焦点保护",
                detail: "切换应用、移动输入框或修改目标文字后，回执操作会安全停用，避免改到其他位置。",
                icon: "scope"
            )
        }
    }

    private var voiceEditContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            voiceCommandCard(
                phrase: "把产品名改成 Lerro",
                result: "精确替换刚写入的文字",
                requiresAI: false
            )
            voiceCommandCard(
                phrase: "删除第二句",
                result: "删除指定句子并保留其余内容",
                requiresAI: false
            )
            voiceCommandCard(
                phrase: "恢复上一版",
                result: "沿版本链回到上一次结果",
                requiresAI: false
            )
            voiceCommandCard(
                phrase: "说得更简洁一些",
                result: "使用已启用的本地 AI 或 API 模型改写",
                requiresAI: true
            )

            Label {
                Text("操作顺序：完成听写 → 保持光标不动 → 60 秒内再次点按听写 → 说出修改要求。")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "1.circle.fill")
            }
            .font(LerroTheme.font(13, weight: .medium))
            .foregroundStyle(LerroTheme.accent)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
        }
    }

    private var toolkitContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                toolkitCard(
                    title: "Quick Dictate",
                    detail: "点按一次 Fn，说完自然停顿，约 1.2 秒后自动写入。",
                    icon: "waveform"
                )
                toolkitCard(
                    title: "长听写",
                    detail: "按住说话，或从 HUD 锁定录音；再次操作时手动完成。",
                    icon: "timer"
                )
                toolkitCard(
                    title: "设备端翻译",
                    detail: "Fn + Shift 说话，使用已准备的 Apple Translation 资源。",
                    icon: "character.bubble.fill"
                )
                toolkitCard(
                    title: "Ask / Command",
                    detail: "Fn + Space 提问；选中文字时，口述要求会安全改写原选区。",
                    icon: "sparkles"
                )
                toolkitCard(
                    title: "词典与快捷语",
                    detail: "保存专有名词和整段模板；精确说出触发词即可展开。",
                    icon: "text.book.closed.fill"
                )
                toolkitCard(
                    title: "应用语气",
                    detail: "为 Mail、Slack 或其他应用设置不同表达方式，捕获开始时自动选择。",
                    icon: "slider.horizontal.3"
                )
            }

            Label {
                Text("“发送”与 “send it” 只在已确认的安全输入框和获准应用中执行；首次使用一定会询问。")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
            }
            .font(LerroTheme.font(12))
            .foregroundStyle(LerroTheme.secondaryText)
            .padding(.top, 4)
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: session.selectedAIIsReady ? "checkmark.circle.fill" : "clock.fill")
                    .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                    .foregroundStyle(session.selectedAIIsReady ? LerroTheme.green : LerroTheme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(session.selectedAIIsReady ? "AI 能力已就绪" : "基础听写已就绪"))
                        .font(LerroTheme.font(14, weight: .medium))
                    Text(LocalizedStringKey(finalAIStatusText))
                        .font(LerroTheme.font(12))
                        .foregroundStyle(LerroTheme.secondaryText)
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

            shortcutRow(
                title: "Quick Dictate",
                detail: "一次点按、开口说话、自然停顿后自动完成",
                icon: "waveform",
                shortcut: shortcutName(for: .dictate)
            )
            shortcutRow(
                title: "翻译",
                detail: "设备端翻译并写入当前光标",
                icon: "character.bubble",
                shortcut: shortcutName(for: .translate)
            )
            shortcutRow(
                title: "Ask / Command",
                detail: "提问或改写当前选区，需要 AI 就绪",
                icon: "sparkles",
                shortcut: shortcutName(for: .ask)
            )

            Text("提示：按 Escape 可取消当前录音或处理中任务；完整历史、词典、AI 和快捷键设置都在主窗口中。")
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func voiceCommandCard(phrase: String, result: String, requiresAI: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(LerroTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(verbatim: "“\(phrase)”")
                        .font(LerroTheme.font(14, weight: .medium))
                    if requiresAI {
                        Text("AI")
                            .font(LerroTheme.font(12, weight: .medium))
                            .foregroundStyle(LerroTheme.accent)
                    }
                }
                Text(LocalizedStringKey(result))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.secondaryText)
            }
            Spacer()
        }
        .padding(13)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
        .accessibilityElement(children: .combine)
    }

    private func toolkitCard(title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(LerroTheme.accent)
            Text(LocalizedStringKey(title))
                .font(LerroTheme.font(14, weight: .medium))
            Text(LocalizedStringKey(detail))
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
        .accessibilityElement(children: .combine)
    }

    private func shortcutName(for action: HotkeyAction) -> String {
        session.preferences.hotkeys.first(where: { $0.action == action })?.displayName ?? "—"
    }

    private var finalAIStatusText: String {
        if session.selectedAIIsReady {
            return session.preferences.intelligenceMode == .local
                ? "本地模型已准备，可以使用增强听写、Ask 和语义改写。"
                : "API 模型已配置，可以使用增强听写、Ask 和语义改写。"
        }
        if session.modelStatus.state == .downloading {
            return "本地模型正在后台下载；完成前 Quick Dictate 会直接交付 Apple Speech 转写。"
        }
        if session.modelStatus.state == .paused {
            return "本地模型下载已暂停；可从“设置 → 智能处理”继续。"
        }
        return "你可以立即使用 Quick Dictate，并从“设置 → 智能处理”继续启用 AI。"
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
        guard step != .ready else {
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
                "把光标放在这里，按一下 %@，说完自然停顿即可。",
                locale: locale,
                arguments: dictateShortcutDraft.displayName
            )
        return true
    }

    private func togglePracticeCapture() {
        practiceEditorFocused = true
        Task { @MainActor in
            await Task.yield()
            if session.preferredDictationActivation == .toggle {
                session.toggleQuickDictate()
            } else {
                session.toggleCapture(.dictation)
            }
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
            "继续学习"
        case .ready:
            "开始使用 Lerro"
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

    private var microphoneSelection: Binding<String> {
        Binding {
            session.preferences.microphoneDeviceUID ?? ""
        } set: { value in
            session.stopOnboardingMicrophoneTest(resetResult: true)
            session.preferences.microphoneDeviceUID = value.isEmpty ? nil : value
            session.savePreferences()
        }
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
        case .aiSetup: "适合这台 Mac"
        case .permissions: "按用途授权"
        case .shortcuts: "随处开口"
        case .practice: "声音成为文字"
        case .receipt: "每次写入都可恢复"
        case .voiceEdit: "接着说就能改"
        case .toolkit: "一套完整工作流"
        case .ready: "现在开始"
        }
    }

    private var visualCaption: String {
        switch step {
        case .privacy: "清楚了解数据去向，并随时调整保存选项。"
        case .aiSetup: "本地 AI、API 模型与基础听写都由你选择。"
        case .permissions: "每项权限都有明确用途和独立设置入口。"
        case .shortcuts:
            "\(selectedShortcutDraft.wrappedValue?.displayName ?? "Fn") · \(selectedShortcutActivation.wrappedValue.resolved == .hold ? "按住说话" : "一次点按")"
        case .practice: "一次点按，停顿后自动完成。"
        case .receipt: "撤销、修正、继续说，焦点变化时安全停用。"
        case .voiceEdit: "精确指令直接执行，语义修改使用已启用 AI。"
        case .toolkit: "听写、翻译、提问、改写和发送。"
        case .ready: "Fn 开口，Lerro 写入。"
        }
    }

    private var localizedVisualCaption: String {
        guard step == .shortcuts else { return localized(visualCaption) }
        let shortcut = selectedShortcutDraft.wrappedValue?.displayName ?? "Fn"
        let activation = selectedShortcutActivation.wrappedValue.resolved == .hold
            ? localized("按住说话")
            : localized("一次点按")
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
