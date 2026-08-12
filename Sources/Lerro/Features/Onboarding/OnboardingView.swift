import AppKit
import SwiftUI
import LerroCore

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case privacy
    case speech
    case ai
    case shortcut
    case dictation
    case recovery
    case dictionary
    case tone

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .privacy: "选择数据保存方式"
        case .speech: "准备 Apple 听写"
        case .ai: "选择 AI 能力"
        case .shortcut: "设置听写快捷键"
        case .dictation: "完成第一次听写"
        case .recovery: "练习写入失败恢复"
        case .dictionary: "让 Lerro 学会你的修正"
        case .tone: "设置第一个应用语气"
        }
    }

    var shortTitle: String {
        switch self {
        case .privacy: "隐私"
        case .speech: "听写"
        case .ai: "AI"
        case .shortcut: "快捷键"
        case .dictation: "练习"
        case .recovery: "恢复"
        case .dictionary: "词典"
        case .tone: "语气"
        }
    }

    var icon: String {
        switch self {
        case .privacy: "hand.raised.fill"
        case .speech: "waveform"
        case .ai: "sparkles"
        case .shortcut: "keyboard.fill"
        case .dictation: "text.cursor"
        case .recovery: "doc.on.clipboard.fill"
        case .dictionary: "character.book.closed.fill"
        case .tone: "slider.horizontal.3"
        }
    }
}

private enum OnboardingPermission: String, CaseIterable, Identifiable {
    case microphone
    case accessibility

    var id: String { rawValue }
    var title: String { self == .microphone ? "麦克风" : "辅助功能" }
    var icon: String { self == .microphone ? "mic.fill" : "accessibility" }
    var settingsURL: String {
        self == .microphone
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
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
    @FocusState private var editorFocused: Bool

    @State private var step: OnboardingStep = .privacy
    @State private var privacyConfirmed = false
    @State private var dictateShortcutDraft: ShortcutBindingDraft?
    @State private var dictateShortcutActivation: ShortcutActivation = .toggle
    @State private var shortcutConfigurationPrepared = false
    @State private var shortcutSaveError = ""
    @State private var isShortcutSaving = false
    @State private var hasCompletedDictation = false
    @State private var dictationText = "把光标放在这里，按快捷键开始说话。"
    @State private var hasCopiedRecoveryText = false
    @State private var dictionaryPracticeText = "我正在使用乐若完成语音写作。"
    @State private var learnedEntryIDsAtStart = Set<UUID>()
    @State private var dictionaryPracticeLearned = false
    @State private var isLearningDictionaryCorrection = false
    @State private var toneApplication: ApplicationDescriptor?
    @State private var toneInstruction = "简洁、自然，适合团队沟通"
    @State private var tonePreview = ""
    @State private var isTonePreviewing = false

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
                .frame(height: 72)

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if step != .privacy {
                                Button(action: previous) {
                                    Label("返回", systemImage: "chevron.left")
                                }
                                .buttonStyle(.borderless)
                            }

                            Text(LocalizedStringKey(step.title))
                                .font(LerroTheme.font(24, weight: .medium))
                                .tracking(LerroTheme.uiTracking)
                                .foregroundStyle(LerroTheme.text)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($accessibilityFocus, equals: .heading)

                            pageContent
                                .id(step)
                                .transition(reduceMotion ? .identity : .opacity)

                            HStack(spacing: 12) {
                                if let blockingMessage {
                                    Label {
                                        Text(verbatim: blockingMessage)
                                    } icon: {
                                        Image(systemName: "exclamationmark.circle.fill")
                                    }
                                        .font(LerroTheme.font(12))
                                        .foregroundStyle(LerroTheme.orange)
                                }
                                Spacer()
                                Button(action: next) {
                                    Text(verbatim: primaryActionTitle)
                                }
                                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                                    .controlSize(.large)
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(!canAdvance || isShortcutSaving || isTonePreviewing)
                            }
                        }
                        .frame(maxWidth: 650, minHeight: 520, alignment: .topLeading)
                        .padding(.vertical, 30)
                        .padding(.horizontal, 50)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(width: geometry.size.width * 0.68, height: geometry.size.height)
                    .background(LerroTheme.main)

                    visualPanel
                        .frame(width: geometry.size.width * 0.32, height: geometry.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LerroTheme.main)
        .task(id: step) {
            await prepareCurrentStep()
        }
        .onChange(of: step) { previous, current in
            if previous == .shortcut {
                session.endShortcutConfiguration()
                shortcutConfigurationPrepared = false
            }
            if current != .speech {
                session.stopOnboardingMicrophoneTest()
            }
            session.preferences.onboardingStepIndex = current.rawValue
            session.savePreferences()
            Task { @MainActor in accessibilityFocus = .heading }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, step == .speech else { return }
            Task { await session.refreshPermissions(prompt: false) }
        }
        .onChange(of: session.phase) { previous, current in
            guard step == .dictation || step == .dictionary else { return }
            if previous == .inserting, current == .idle {
                hasCompletedDictation = step == .dictation
            }
        }
        .onAppear {
            if let rawStep = session.preferences.onboardingStepIndex,
               let restored = OnboardingStep(rawValue: rawStep) {
                step = restored
            }
            prepareShortcutDraftIfNeeded()
            accessibilityFocus = .heading
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
                    Text(verbatim: progressText)
                        .font(LerroTheme.font(12))
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach(OnboardingStep.allCases) { item in
                        Circle()
                            .fill(item.rawValue <= step.rawValue
                                ? LerroTheme.accent
                                : LerroTheme.fillContainerTough)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            ProgressView(value: Double(step.rawValue + 1), total: 8)
                .progressViewStyle(.linear)
                .accessibilityLabel("设置进度")
                .accessibilityValue(Text(verbatim: progressText))
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .background(LerroTheme.topLayer)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch step {
        case .privacy: privacyContent
        case .speech: speechContent
        case .ai: OnboardingAISetupView(session: session)
        case .shortcut: shortcutContent
        case .dictation: dictationContent
        case .recovery: recoveryContent
        case .dictionary: dictionaryContent
        case .tone: toneContent
        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("历史保留", selection: historyRetentionBinding) {
                Text("不保存").tag(HistoryRetention.never)
                Text("一天").tag(HistoryRetention.oneDay)
                Text("一周").tag(HistoryRetention.oneWeek)
                Text("一个月").tag(HistoryRetention.oneMonth)
                Text("永久").tag(HistoryRetention.forever)
            }
            .pickerStyle(.segmented)

            Toggle("保存原始录音", isOn: saveAudioBinding)
                .toggleStyle(.switch)
                .disabled(session.preferences.historyRetention == .never)

            Button {
                privacyConfirmed = true
                session.savePreferences()
            } label: {
                Label {
                    Text(LocalizedStringKey(privacyConfirmed ? "设置已确认" : "确认这些设置"))
                } icon: {
                    Image(systemName: privacyConfirmed ? "checkmark.circle.fill" : "checkmark.circle")
                }
            }
            .buttonStyle(LerroPillButtonStyle(prominent: !privacyConfirmed))
        }
        .onChange(of: session.preferences.historyRetention) { _, _ in privacyConfirmed = false }
        .onChange(of: session.preferences.saveAudio) { _, _ in privacyConfirmed = false }
        .onAppear {
            if isFixture { privacyConfirmed = true }
        }
    }

    private var speechContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(OnboardingPermission.allCases) { permission in
                permissionRow(permission)
            }

            statusRow(
                title: "Apple 听写资源",
                icon: "waveform",
                ready: session.speechResourceStatus.state == .ready,
                status: session.speechResourceStatus.message.isEmpty
                    ? "等待检查"
                    : session.speechResourceStatus.message
            ) {
                if session.speechResourceStatus.state == .available
                    || session.speechResourceStatus.state == .failed {
                    Button("准备") { session.prepareSpeechResources() }
                        .buttonStyle(LerroPillButtonStyle())
                }
            }

            Picker("输入设备", selection: microphoneSelection) {
                Text("系统默认麦克风").tag("")
                ForEach(session.audioInputDevices) { device in
                    Text(verbatim: device.name).tag(device.uid)
                }
            }
            .disabled(session.isOnboardingMicrophoneTestRunning)

            WaveLevelMeter(
                level: session.onboardingMicrophoneLevel,
                reduceMotion: reduceMotion,
                isRunning: session.isOnboardingMicrophoneTestRunning
            )

            HStack {
                Label {
                    Text(verbatim: microphoneStatus)
                } icon: {
                    Image(systemName: session.onboardingMicrophoneTestPassed
                        ? "checkmark.circle.fill"
                        : "mic.circle")
                }
                .font(LerroTheme.font(12))
                .foregroundStyle(session.onboardingMicrophoneTestPassed
                    ? LerroTheme.green
                    : LerroTheme.secondaryText)
                Spacer()
                Button {
                    session.toggleOnboardingMicrophoneTest()
                } label: {
                    Text(LocalizedStringKey(
                        session.isOnboardingMicrophoneTestRunning ? "停止测试" : "测试麦克风"
                    ))
                }
                .buttonStyle(LerroPillButtonStyle(prominent: !session.onboardingMicrophoneTestPassed))
                .disabled(!session.microphonePermission)
            }
        }
    }

    private var shortcutContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if shortcutConfigurationPrepared {
                ShortcutRecorderCard(
                    shortcut: $dictateShortcutDraft,
                    activation: $dictateShortcutActivation
                )
            } else {
                ProgressView("正在准备按键检测…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            }

            Label("录制后，按一下开始，再按一下结束。", systemImage: "keyboard")
            .font(LerroTheme.font(12))
            .foregroundStyle(LerroTheme.secondaryText)

            if !shortcutSaveError.isEmpty {
                Label {
                    Text(verbatim: shortcutSaveError)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.orange)
            }
        }
    }

    private var dictationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text(verbatim: dictationPhaseText)
                } icon: {
                    Image(systemName: hasCompletedDictation
                        ? "checkmark.circle.fill"
                        : "waveform")
                }
                    .font(LerroTheme.font(12, weight: .medium))
                    .foregroundStyle(hasCompletedDictation ? LerroTheme.green : LerroTheme.accent)
                Spacer()
                ShortcutBadge(title: dictationShortcutName)
            }

            TextEditor(text: $dictationText)
                .font(LerroTheme.font(14))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 150)
                .background(LerroTheme.topLayer)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                        .stroke(editorFocused ? LerroTheme.focusBorder : LerroTheme.thinBorder)
                }
                .focused($editorFocused)

            Button(action: togglePracticeCapture) {
                Text(verbatim: dictationButtonTitle)
            }
                .buttonStyle(LerroPillButtonStyle(prominent: true))
                .disabled(isCaptureProcessing)
        }
        .onAppear { editorFocused = true }
    }

    private var recoveryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(LerroTheme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("未能写入练习编辑器")
                        .font(LerroTheme.font(14, weight: .medium))
                    Text("内容已复制到剪贴板")
                        .font(LerroTheme.font(12))
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Spacer()
                Button("再次复制") {
                    session.copyText(recoverySample)
                    hasCopiedRecoveryText = NSPasteboard.general.string(forType: .string)
                        == recoverySample
                }
                .buttonStyle(LerroPillButtonStyle(prominent: !hasCopiedRecoveryText))
            }
            .padding(16)
            .background(LerroTheme.fillContainerThin)
            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))

            if hasCopiedRecoveryText {
                Label("恢复文本已再次复制", systemImage: "checkmark.circle.fill")
                    .font(LerroTheme.font(12, weight: .medium))
                    .foregroundStyle(LerroTheme.green)
            }
        }
        .onAppear {
            if isFixture {
                hasCopiedRecoveryText = true
            } else {
                session.copyText(recoverySample)
            }
        }
    }

    private var dictionaryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("把“乐若”改成“Lerro”，再让 AI 判断这次修正。")
                .font(LerroTheme.font(13))

            TextEditor(text: $dictionaryPracticeText)
                .font(LerroTheme.font(14))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 150)
                .background(LerroTheme.topLayer)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                        .stroke(editorFocused ? LerroTheme.focusBorder : LerroTheme.thinBorder)
                }
                .focused($editorFocused)

            HStack {
                Button {
                    learnDictionaryCorrection()
                } label: {
                    Text(LocalizedStringKey(
                        isLearningDictionaryCorrection ? "AI 正在判断" : "检测这次修正"
                    ))
                }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                    .disabled(
                        dictionaryPracticeText == dictionaryPracticeOriginal
                            || isLearningDictionaryCorrection
                    )
                Spacer()
                if hasLearnedDictionaryEntry {
                    Label("修正已通过 AI 加入词典", systemImage: "checkmark.circle.fill")
                        .font(LerroTheme.font(12, weight: .medium))
                        .foregroundStyle(LerroTheme.green)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("等待自动词典学习")
                }
            }
        }
        .onAppear {
            learnedEntryIDsAtStart = Set(
                session.dictionaryEntries.filter { $0.source == .learned }.map(\.id)
            )
            if isFixture {
                dictionaryPracticeText = "我正在使用 Lerro 完成语音写作。"
                dictionaryPracticeLearned = true
            }
            editorFocused = true
        }
    }

    private var toneContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("应用", selection: $toneApplication) {
                Text("选择一个应用").tag(nil as ApplicationDescriptor?)
                ForEach(session.availableApplications) { application in
                    Text(verbatim: application.name)
                        .tag(application as ApplicationDescriptor?)
                }
            }

            TextEditor(text: $toneInstruction)
                .font(LerroTheme.font(14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 90)
                .background(LerroTheme.topLayer)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                        .stroke(LerroTheme.thinBorder)
                }

            Button {
                runTonePreview()
            } label: {
                Text(LocalizedStringKey(
                    isTonePreviewing ? "正在运行 AI 预览" : "运行 AI 预览"
                ))
            }
            .buttonStyle(LerroPillButtonStyle(prominent: tonePreview.isEmpty))
            .disabled(toneApplication == nil || trimmedToneInstruction.isEmpty || isTonePreviewing)

            if !tonePreview.isEmpty {
                Text(verbatim: tonePreview)
                    .font(LerroTheme.font(13))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LerroTheme.fillContainerThin)
                    .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
            }
        }
    }

    private var visualPanel: some View {
        VStack(spacing: 18) {
            Image(systemName: step.icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(LerroTheme.accent)
                .frame(width: 76, height: 76)
                .background(LerroTheme.fillContainerThin)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(LocalizedStringKey(step.shortTitle))
                .font(LerroTheme.font(14, weight: .medium))
            Text(LocalizedStringKey(visualCaption))
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LerroTheme.sidebar)
    }

    @ViewBuilder
    private func permissionRow(_ permission: OnboardingPermission) -> some View {
        let granted = permission == .microphone
            ? session.microphonePermission
            : session.accessibilityPermission
        statusRow(
            title: permission.title,
            icon: permission.icon,
            ready: granted,
            status: granted ? "已就绪" : "等待授权"
        ) {
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LerroTheme.green)
            } else {
                Button("授权") {
                    Task { await session.refreshPermissions(prompt: true) }
                }
                .buttonStyle(LerroPillButtonStyle(prominent: true))
                Button("系统设置") { openSystemSettings(permission) }
                    .buttonStyle(LerroPillButtonStyle())
            }
        }
    }

    private func statusRow<Accessory: View>(
        title: String,
        icon: String,
        ready: Bool,
        status: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                .foregroundStyle(ready ? LerroTheme.green : LerroTheme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: localized(title))
                    .font(LerroTheme.font(14, weight: .medium))
                Text(verbatim: localized(status))
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.secondaryText)
            }
            Spacer()
            accessory()
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

    private func prepareCurrentStep() async {
        switch step {
        case .speech:
            await session.refreshPermissions(prompt: false)
            await session.refreshLanguageResources()
            await session.refreshAudioInputDevices()
        case .shortcut:
            prepareShortcutDraftIfNeeded()
            shortcutConfigurationPrepared = session.beginShortcutConfiguration()
            if !shortcutConfigurationPrepared {
                shortcutSaveError = session.currentError ?? "请完成当前听写后再设置快捷键。"
            }
        case .tone:
            session.refreshAvailableApplications()
        case .privacy, .ai, .dictation, .recovery, .dictionary:
            break
        }
    }

    private func next() {
        if step == .shortcut {
            saveShortcutAndAdvance()
            return
        }
        if step == .recovery, !aiIsReady {
            session.completeOnboarding()
            return
        }
        if step == .tone {
            guard let application = toneApplication else { return }
            session.saveAppToneProfile(AppToneProfile(
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.name,
                instruction: trimmedToneInstruction
            ))
            session.completeOnboarding()
            return
        }
        guard let following = OnboardingStep(rawValue: step.rawValue + 1) else {
            session.completeOnboarding()
            return
        }
        navigate(to: following)
    }

    private func previous() {
        guard let prior = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        navigate(to: prior)
    }

    private func navigate(to destination: OnboardingStep) {
        if reduceMotion {
            step = destination
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { step = destination }
        }
    }

    private func prepareShortcutDraftIfNeeded() {
        guard dictateShortcutDraft == nil,
              let definition = session.preferences.hotkeys.first(where: { $0.action == .dictate }) else {
            return
        }
        dictateShortcutDraft = ShortcutBindingDraft(definition: definition)
        dictateShortcutActivation = .toggle
    }

    private func saveShortcutAndAdvance() {
        guard !isShortcutSaving, let draft = dictateShortcutDraft else { return }
        isShortcutSaving = true
        let existing = session.preferences.hotkeys.first(where: { $0.action == .dictate })
        Task { @MainActor in
            let saved = await session.commitHotkey(
                for: .dictate,
                replacing: existing,
                keyCode: draft.keyCode,
                modifiers: draft.modifiers,
                usesFunctionKey: draft.usesFunctionKey,
                activation: .toggle,
                displayName: draft.displayName
            )
            isShortcutSaving = false
            guard saved else {
                shortcutSaveError = "这个快捷键与已有按键冲突，请重新选择。"
                return
            }
            shortcutSaveError = ""
            navigate(to: .dictation)
        }
    }

    private func togglePracticeCapture() {
        editorFocused = true
        Task { @MainActor in
            await Task.yield()
            session.toggleCapture(.dictation)
        }
    }

    private func runTonePreview() {
        guard let application = toneApplication else { return }
        isTonePreviewing = true
        Task { @MainActor in
            tonePreview = await session.previewAppTone(
                application: application,
                instruction: trimmedToneInstruction
            ) ?? ""
            isTonePreviewing = false
        }
    }

    private func learnDictionaryCorrection() {
        isLearningDictionaryCorrection = true
        Task { @MainActor in
            dictionaryPracticeLearned = await session.learnOnboardingCorrection(
                originalText: dictionaryPracticeOriginal,
                correctedText: dictionaryPracticeText
            )
            isLearningDictionaryCorrection = false
        }
    }

    private func openSystemSettings(_ permission: OnboardingPermission) {
        guard let url = URL(string: permission.settingsURL), NSWorkspace.shared.open(url) else {
            session.currentError = "无法打开系统设置，请在隐私与安全性中开启 Lerro。"
            return
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .privacy: privacyConfirmed
        case .speech:
            session.requiredPermissionsGranted
                && session.speechResourceStatus.state == .ready
                && session.onboardingMicrophoneTestPassed
        case .ai: true
        case .shortcut: dictateShortcutDraft != nil && shortcutConfigurationPrepared
        case .dictation: hasCompletedDictation
        case .recovery: hasCopiedRecoveryText
        case .dictionary: hasLearnedDictionaryEntry
        case .tone: toneApplication != nil && !trimmedToneInstruction.isEmpty && !tonePreview.isEmpty
        }
    }

    private var blockingMessage: String? {
        guard !canAdvance else { return nil }
        return switch step {
        case .privacy: "请确认数据保存设置"
        case .speech: "请完成权限、语音资源和麦克风测试"
        case .shortcut: "请录制一个听写快捷键"
        case .dictation: "请完成一次真实听写"
        case .recovery: "请点击再次复制"
        case .dictionary: "请完成一次 AI 自动词典学习"
        case .tone: "请选择应用并运行 AI 预览"
        case .ai: nil
        }
    }

    private var primaryActionTitle: String {
        if step == .recovery, !aiIsReady { return "完成设置" }
        if step == .tone { return "保存并开始使用" }
        if step == .shortcut, isShortcutSaving { return "正在保存…" }
        return "继续"
    }

    private var progressText: String {
        LerroInterfaceLocalization.format(
            "第 %lld 步，共 %lld 步",
            locale: locale,
            arguments: Int64(step.rawValue + 1), Int64(OnboardingStep.allCases.count)
        )
    }

    private var visualCaption: String {
        switch step {
        case .privacy: "历史与录音由你决定。"
        case .speech: "权限、资源和麦克风逐项验证。"
        case .ai: "Apple 听写、远端 AI、本地 AI。"
        case .shortcut: "\(dictationShortcutName) · 按一下开始，再按一下结束。"
        case .dictation: "实时预览，完成后直接写入。"
        case .recovery: "焦点变化时，文字安全留在剪贴板。"
        case .dictionary: "修正专名，Lerro 自动学习。"
        case .tone: "每个应用都有合适的表达方式。"
        }
    }

    private var historyRetentionBinding: Binding<HistoryRetention> {
        Binding {
            session.preferences.historyRetention
        } set: { value in
            session.preferences.historyRetention = value
            if value == .never { session.preferences.saveAudio = false }
        }
    }

    private var saveAudioBinding: Binding<Bool> {
        Binding {
            session.preferences.saveAudio
        } set: { session.preferences.saveAudio = $0 }
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

    private var dictationShortcutName: String {
        dictateShortcutDraft?.displayName
            ?? session.preferences.hotkeys.first(where: { $0.action == .dictate })?.displayName
            ?? "Fn"
    }

    private var dictationButtonTitle: String {
        switch session.phase {
        case .listening: "结束听写"
        case .transcribing, .enhancing, .inserting: "正在处理"
        case .idle, .success, .failed, .cancelled: "开始听写"
        }
    }

    private var dictationPhaseText: String {
        if hasCompletedDictation { return "文字已写入练习编辑器" }
        return switch session.phase {
        case .idle: "准备开始"
        case .listening: "正在实时预览"
        case .transcribing: "正在完成转写"
        case .enhancing: "正在 AI 润色"
        case .inserting: "正在写入"
        case .success: "已完成"
        case .failed: "请重试"
        case .cancelled: "已取消"
        }
    }

    private var isCaptureProcessing: Bool {
        session.phase == .transcribing || session.phase == .enhancing || session.phase == .inserting
    }

    private var microphoneStatus: String {
        if session.onboardingMicrophoneTestPassed { return "检测到清晰的麦克风输入" }
        if session.isOnboardingMicrophoneTestRunning { return "请对着麦克风说一句话" }
        return "运行一次麦克风测试"
    }

    private var hasLearnedDictionaryEntry: Bool {
        dictionaryPracticeLearned || session.dictionaryEntries.contains {
            $0.source == .learned && !learnedEntryIDsAtStart.contains($0.id)
        }
    }

    private var aiIsReady: Bool {
        switch session.preferences.intelligenceMode {
        case .raw: false
        case .remote: session.preferences.remoteProvider.isReadyForUse
        case .local: session.localAIIsReady
        }
    }

    private var trimmedToneInstruction: String {
        toneInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recoverySample: String {
        "这是一段写入失败后保留在剪贴板的练习文字。"
    }

    private var dictionaryPracticeOriginal: String {
        "我正在使用乐若完成语音写作。"
    }

    private var isFixture: Bool {
        ProcessInfo.processInfo.environment["LERRO_FIXTURE_MODE"] == "1"
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct WaveLevelMeter: View {
    let level: Float
    let reduceMotion: Bool
    let isRunning: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(LerroTheme.fillContainerTough)
                Capsule()
                    .fill(level >= 0.12 ? LerroTheme.green : LerroTheme.accent)
                    .frame(width: max(4, geometry.size.width * CGFloat(min(1, max(0, level)))))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 8)
        .opacity(isRunning ? 1 : 0.55)
        .accessibilityHidden(true)
    }
}
