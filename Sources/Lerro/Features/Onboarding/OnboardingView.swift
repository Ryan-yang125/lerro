import AppKit
import SwiftUI
import LerroCore

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case practice
    case ai
    case start

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "欢迎和权限"
        case .practice: "试一次"
        case .ai: "AI 整理"
        case .start: "开始使用"
        }
    }
}

private enum OnboardingPermission: String, CaseIterable, Identifiable {
    case microphone
    case accessibility

    var id: String { rawValue }
    var title: String { self == .microphone ? "麦克风" : "辅助功能" }
    var detail: String { self == .microphone ? "听你说话" : "把字写到光标处" }
    var icon: String { self == .microphone ? "mic" : "accessibility" }
    var settingsURL: String {
        self == .microphone
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }
}

private enum OnboardingAIChoice {
    case raw
    case ai
}

private enum OnboardingAccessibilityFocus: Hashable {
    case heading
}

struct OnboardingView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var accessibilityFocus: OnboardingAccessibilityFocus?
    @FocusState private var editorFocused: Bool

    @State private var step: OnboardingStep = .welcome
    @State private var highestStep: OnboardingStep = .welcome
    @State private var hasRequestedMicrophone = false
    @State private var practiceText = ""
    @State private var hasCompletedDictation = false
    @State private var aiChoice: OnboardingAIChoice = .ai

    var body: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: 232)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LerroTheme.main)
        .task(id: step) {
            await prepareCurrentStep()
        }
        .onChange(of: step) { previous, current in
            if previous == .practice, session.isCaptureCancellationAvailable {
                session.cancelCapture()
            }
            highestStep = OnboardingStep(rawValue: max(highestStep.rawValue, current.rawValue)) ?? current
            session.preferences.onboardingStepIndex = current.rawValue
            session.savePreferences()
            Task { @MainActor in accessibilityFocus = .heading }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, step == .welcome else { return }
            Task { await session.refreshPermissions(prompt: false) }
        }
        .onChange(of: session.phase) { previous, current in
            guard step == .practice, previous == .inserting, current == .idle || current == .success else {
                return
            }
            hasCompletedDictation = true
        }
        .onAppear {
            if let rawStep = session.preferences.onboardingStepIndex,
               let restored = OnboardingStep(rawValue: rawStep) {
                step = restored
                highestStep = restored
            }
            if session.aiStatus == .off, session.hasDeepSeekKey {
                aiChoice = .raw
            }
            accessibilityFocus = .heading
        }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            LerroWordmark(height: 26)
                .padding(.horizontal, 10)
                .padding(.top, 34)
                .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(OnboardingStep.allCases) { item in
                    railRow(item)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(LerroTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(LerroTheme.thinBorder).frame(width: 0.5)
        }
    }

    private func railRow(_ item: OnboardingStep) -> some View {
        let isCurrent = item == step
        let isDone = !isCurrent && item.rawValue < highestStep.rawValue
        let isReachable = item.rawValue <= highestStep.rawValue
        return Button {
            navigate(to: item)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    if isDone {
                        Circle().fill(LerroTheme.success)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white)
                    } else {
                        Circle().strokeBorder(
                            isCurrent ? LerroTheme.accent : LerroTheme.border,
                            lineWidth: 1.5
                        )
                        Text(verbatim: "\(item.rawValue + 1)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(isCurrent ? LerroTheme.accentText : LerroTheme.tertiaryText)
                    }
                }
                .frame(width: 22, height: 22)
                Text(LocalizedStringKey(item.title))
                    .font(.system(size: 13.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? LerroTheme.text : LerroTheme.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isCurrent ? LerroTheme.fillSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isReachable)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        pageContent
                            .id(step)
                            .transition(reduceMotion ? .identity : .opacity)
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 64)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("返回", action: previous)
                .buttonStyle(LerroButtonStyle(.secondary))
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            Button(action: next) {
                Text(LocalizedStringKey(primaryActionTitle))
            }
            .buttonStyle(LerroButtonStyle(.primary))
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch step {
        case .welcome: welcomeContent
        case .practice: practiceContent
        case .ai: aiContent
        case .start: startContent
        }
    }

    private func heading(_ title: String, lead: Text) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(LerroTheme.font(26, weight: .bold))
                .foregroundStyle(LerroTheme.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($accessibilityFocus, equals: .heading)
            lead
                .font(.system(size: 14.5))
                .foregroundStyle(LerroTheme.secondaryText)
        }
        .padding(.bottom, 26)
    }

    // MARK: Step 1

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("欢迎使用 Lerro", lead: Text(verbatim: welcomeLead))

            VStack(spacing: 0) {
                ForEach(Array(OnboardingPermission.allCases.enumerated()), id: \.element.id) { index, permission in
                    if index > 0 { Divider() }
                    permissionRow(permission)
                }
            }
            .background(LerroTheme.topLayer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
            }

            speechResourceRow
                .padding(.top, 14)
        }
    }

    private func permissionRow(_ permission: OnboardingPermission) -> some View {
        let granted = permission == .microphone
            ? session.microphonePermission
            : session.accessibilityPermission
        return HStack(spacing: 14) {
            Image(systemName: permission.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LerroTheme.accentText)
                .frame(width: 36, height: 36)
                .background(LerroTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(permission.title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LerroTheme.text)
                Text(LocalizedStringKey(permission.detail))
                    .font(.system(size: 12.5))
                    .foregroundStyle(LerroTheme.metadataText)
            }
            Spacer()
            if granted {
                Label("已允许", systemImage: "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(LerroTheme.success)
            } else {
                Button(LocalizedStringKey(permission == .microphone ? "允许" : "打开")) {
                    request(permission)
                }
                .buttonStyle(LerroButtonStyle(.primary, compact: true))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var speechResourceRow: some View {
        let status = session.speechResourceStatus
        HStack(spacing: 10) {
            switch status.state {
            case .ready:
                Label("语音识别已就绪", systemImage: "checkmark.circle")
                    .foregroundStyle(LerroTheme.success)
            case .available, .downloading:
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text("正在准备语音识别")
            case .failed, .unsupported:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(LerroTheme.warning)
                    .accessibilityHidden(true)
                Text(verbatim: status.message.isEmpty
                    ? localized("语音识别暂不可用，请稍后重试")
                    : localized(status.message))
                if status.state == .failed {
                    Button("重试") { session.prepareSpeechResources() }
                        .buttonStyle(.plain)
                        .foregroundStyle(LerroTheme.accentText)
                }
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(LerroTheme.metadataText)
    }

    // MARK: Step 2

    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("试一次", lead: Text("光标已经在下面的框里。"))

            VStack(spacing: 16) {
                Button(action: togglePracticeCapture) {
                    practiceKeycap
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: dictationShortcutName))
                Text(practiceHint)
                    .font(.system(size: 14))
                    .foregroundStyle(LerroTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)

            practiceEditor

            if hasCompletedDictation {
                Label("写好了。在微信、邮件、飞书里都是这样用。", systemImage: "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(LerroTheme.success)
                    .padding(.top, 12)
            }

            HStack(spacing: 10) {
                LevelBars(level: session.audioLevel, reduceMotion: reduceMotion)
                Picker("麦克风", selection: microphoneSelection) {
                    Text("系统默认麦克风").tag("")
                    ForEach(session.audioInputDevices) { device in
                        Text(verbatim: device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(isCaptureBusy)
                Spacer()
                Button("更改快捷键") {
                    session.settingsTab = .dictation
                    openSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(LerroTheme.accentText)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(LerroTheme.metadataText)
            .padding(.top, 12)
        }
    }

    private var isListening: Bool {
        session.phase == .listening && session.activeMode == .dictation
    }

    private var practiceKeycap: some View {
        Text(verbatim: dictationShortcutName)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(isListening ? Color.white : LerroTheme.text)
            .frame(minWidth: 92, minHeight: 78)
            .padding(.horizontal, 12)
            .background {
                // The key's lower edge is a shadow on the shape only, so the
                // label is not drawn twice.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isListening ? LerroTheme.accent : LerroTheme.keycapFill(colorScheme))
                    .shadow(color: isListening ? LerroTheme.accent.opacity(0.4) : LerroTheme.keycapBorder(colorScheme), radius: 0, x: 0, y: isListening ? 1 : 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isListening ? LerroTheme.accent : LerroTheme.keycapBorder(colorScheme), lineWidth: 1)
            }
            .background {
                if isListening {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LerroTheme.accentSoft)
                        .padding(-8)
                }
            }
            .offset(y: isListening ? 3 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isListening)
    }

    private var practiceHint: AttributedString {
        let key = session.preferredDictationActivation == .hold ? "按住 **%@** 说话，说完松开" : "按一下 **%@** 开始说话，说完再按一下"
        let text = LerroInterfaceLocalization.format(key, locale: locale, arguments: dictationShortcutName)
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private var practiceEditor: some View {
        TextEditor(text: $practiceText)
            .font(.system(size: 16))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(height: 150)
            .background(LerroTheme.topLayer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                if practiceText.isEmpty {
                    Text("比如说：下午三点开会，记得带上周的报表")
                        .font(.system(size: 16))
                        .foregroundStyle(LerroTheme.tertiaryText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        editorFocused ? LerroTheme.focusBorder : LerroTheme.thinBorder,
                        lineWidth: editorFocused ? 2 : 0.5
                    )
            }
            .focused($editorFocused)
            .accessibilityLabel(Text("练习输入框"))
    }

    // MARK: Step 3

    private var aiContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("要开启 AI 整理吗？", lead: Text("AI 会去掉口头禅、改正听错的词、补好标点。"))

            beforeAfter

            HStack(spacing: 10) {
                routeCard(.raw, title: "只转文字", detail: "免费，现在就能用")
                routeCard(.ai, title: "AI 整理", detail: "用你的 DeepSeek 账号，约 2 元/月")
            }
            .padding(.top, 18)

            if aiChoice == .ai {
                DeepSeekKeyGuide(session: session, showsCostHint: false)
                    .padding(.top, 14)
            } else {
                Text("之后也可以在首页或设置中开启。")
                    .font(.system(size: 13))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LerroTheme.topLayer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
                    }
                    .padding(.top, 14)
            }
        }
    }

    private var beforeAfter: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("你说的")
                    .font(.system(size: 11))
                    .foregroundStyle(LerroTheme.metadataText)
                Text(sampleSaid)
                    .foregroundStyle(LerroTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LerroTheme.tertiaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 整理后")
                    .font(.system(size: 11))
                    .foregroundStyle(LerroTheme.metadataText)
                Text("下午三点开会，记得带上周的报表。")
                    .fontWeight(.medium)
                    .foregroundStyle(LerroTheme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .lineSpacing(3)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(LerroTheme.topLayer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var sampleSaid: AttributedString {
        // Struck segments are the words AI removes or corrects.
        let segments: [(String, Bool)] = locale.language.languageCode == .chinese
            ? [("嗯", true), ("下午三点开会，", false), ("呃", true),
               ("记得带上周的", false), ("保表", true), ("报表", false)]
            : [("Um, ", true), ("meeting at three, ", false), ("uh, ", true),
               ("bring last week's ", false), ("repot ", true), ("report", false)]
        var attributed = AttributedString()
        for (text, struck) in segments {
            var part = AttributedString(text)
            if struck {
                part.strikethroughStyle = Text.LineStyle(pattern: .solid, color: LerroTheme.danger)
                part.foregroundColor = LerroTheme.tertiaryText
            }
            attributed += part
        }
        return attributed
    }

    private func routeCard(_ choice: OnboardingAIChoice, title: String, detail: String) -> some View {
        let selected = aiChoice == choice
        return Button {
            selectAIChoice(choice)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LerroTheme.text)
                Text(LocalizedStringKey(detail))
                    .font(.system(size: 12.5))
                    .foregroundStyle(LerroTheme.metadataText)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? LerroTheme.accentSoft : LerroTheme.topLayer,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? LerroTheme.accent : LerroTheme.thinBorder,
                        lineWidth: selected ? 1.5 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Step 4

    private var startContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("可以开始了", lead: Text("记住这三个快捷键就够了。"))

            VStack(spacing: 0) {
                shortcutRow(
                    title: "听写",
                    shortcut: hotkey(.dictate),
                    detail: activationDetail(hotkey(.dictate)?.activation, toggle: "按一下开始，再按一下结束", hold: "按住说话，松开结束")
                )
                Divider()
                shortcutRow(
                    title: "翻译",
                    shortcut: hotkey(.translate),
                    detail: activationDetail(hotkey(.translate)?.activation, toggle: "按一下开始，再按一下写出译文", hold: "按住说话，松开后写出译文")
                )
                Divider()
                shortcutRow(
                    title: "粘贴上次结果",
                    shortcut: hotkey(.pasteLastResult),
                    detail: "字没写进去时，用它再贴一次"
                )
            }
            .background(LerroTheme.topLayer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
            }

            menuBarIllustration
                .padding(.top, 22)
        }
    }

    private func shortcutRow(title: String, shortcut: HotkeyDefinition?, detail: String) -> some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LerroTheme.text)
                .frame(width: 110, alignment: .leading)
            Group {
                if let shortcut {
                    LerroShortcutKeys(displayName: shortcut.displayName)
                } else {
                    Text("未设置")
                        .font(.system(size: 13))
                        .foregroundStyle(LerroTheme.tertiaryText)
                }
            }
            .frame(width: 110, alignment: .leading)
            Text(LocalizedStringKey(detail))
                .font(.system(size: 13))
                .foregroundStyle(LerroTheme.metadataText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var menuBarIllustration: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()
                Image(systemName: "wifi")
                LerroMark(height: 14)
                    .frame(width: 24, height: 22)
                    .background(LerroTheme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(LerroTheme.accent, lineWidth: 2)
                            .padding(-5)
                    }
                Image(systemName: "battery.100percent")
                Text(Date.now, format: .dateTime.month().day().weekday().hour().minute())
            }
            .font(.system(size: 12.5))
            .foregroundStyle(colorScheme == .dark ? Color(white: 0.93) : Color(white: 0.13))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(colorScheme == .dark ? Color(white: 0.12).opacity(0.6) : Color.white.opacity(0.55))

            HStack {
                Spacer()
                Text("Lerro 在菜单栏这里，点开能看到上一次的结果")
                    .font(.system(size: 12.5))
                    .foregroundStyle(colorScheme == .dark ? Color(white: 0.87) : Color(white: 0.2))
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .frame(height: 84, alignment: .top)
        }
        .background(menuBarWallpaper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var menuBarWallpaper: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [Color(red: 0.118, green: 0.165, blue: 0.267), Color(red: 0.173, green: 0.129, blue: 0.208), Color(red: 0.2, green: 0.157, blue: 0.122)]
            : [Color(red: 0.788, green: 0.839, blue: 0.949), Color(red: 0.914, green: 0.847, blue: 0.925), Color(red: 0.953, green: 0.89, blue: 0.827)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Actions

    private func prepareCurrentStep() async {
        switch step {
        case .welcome:
            await session.refreshPermissions(prompt: false)
            await session.refreshLanguageResources()
            await session.refreshAudioInputDevices()
            while !Task.isCancelled, !session.requiredPermissionsGranted {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                await session.refreshPermissions(prompt: false)
            }
        case .practice:
            await session.refreshAudioInputDevices()
            await Task.yield()
            editorFocused = true
        case .ai, .start:
            break
        }
    }

    private func request(_ permission: OnboardingPermission) {
        Task { @MainActor in
            switch permission {
            case .microphone:
                if hasRequestedMicrophone, !session.microphonePermission {
                    openSystemSettings(permission)
                    return
                }
                hasRequestedMicrophone = true
                await session.refreshPermissions(prompt: true)
            case .accessibility:
                await session.refreshPermissions(prompt: true)
                if !session.accessibilityPermission { openSystemSettings(permission) }
            }
        }
    }

    private func openSystemSettings(_ permission: OnboardingPermission) {
        guard let url = URL(string: permission.settingsURL), NSWorkspace.shared.open(url) else {
            session.currentError = "无法打开系统设置，请在隐私与安全性中开启 Lerro。"
            return
        }
    }

    private func togglePracticeCapture() {
        editorFocused = true
        Task { @MainActor in
            await Task.yield()
            session.toggleCapture(.dictation)
        }
    }

    private func selectAIChoice(_ choice: OnboardingAIChoice) {
        aiChoice = choice
        switch choice {
        case .raw:
            session.setAIEnabled(false)
        case .ai:
            if session.hasDeepSeekKey { session.setAIEnabled(true) }
        }
    }

    private func next() {
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
        guard destination != step else { return }
        if reduceMotion {
            step = destination
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { step = destination }
        }
    }

    // MARK: State

    private var canAdvance: Bool {
        switch step {
        case .welcome: session.requiredPermissionsGranted
        case .practice: hasCompletedDictation
        case .ai, .start: true
        }
    }

    private var primaryActionTitle: String {
        switch step {
        case .welcome, .practice: "继续"
        case .ai: aiChoice == .raw || session.aiStatus == .ready ? "继续" : "稍后设置"
        case .start: "打开 Lerro"
        }
    }

    private var isCaptureBusy: Bool {
        switch session.phase {
        case .listening, .transcribing, .enhancing, .inserting: true
        case .idle, .success, .failed, .cancelled: false
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding {
            session.preferences.microphoneDeviceUID ?? ""
        } set: { value in
            session.selectMicrophone(uid: value.isEmpty ? nil : value)
        }
    }

    private func hotkey(_ action: HotkeyAction) -> HotkeyDefinition? {
        session.preferences.hotkeys.first(where: { $0.action == action })
    }

    private func activationDetail(_ activation: ShortcutActivation?, toggle: String, hold: String) -> String {
        activation == .hold ? hold : toggle
    }

    private var dictationShortcutName: String {
        hotkey(.dictate)?.displayName ?? "Fn"
    }

    private var welcomeLead: String {
        let key = session.preferredDictationActivation == .hold
            ? "按住 %@ 说话，松开后文字写到光标处。请先允许两项权限。"
            : "按一下 %@ 开始说话，再按一下，文字写到光标处。请先允许两项权限。"
        return LerroInterfaceLocalization.format(key, locale: locale, arguments: dictationShortcutName)
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct LevelBars: View {
    let level: Float
    let reduceMotion: Bool

    private static let weights: [CGFloat] = [0.5, 0.8, 1, 0.7, 0.9, 0.6, 0.8, 0.5]

    var body: some View {
        let clamped = CGFloat(min(1, max(0, level)))
        HStack(spacing: 2) {
            ForEach(Array(Self.weights.enumerated()), id: \.offset) { _, weight in
                Capsule()
                    .fill(LerroTheme.tertiaryText)
                    .frame(width: 3, height: max(4, 14 * clamped * weight))
            }
        }
        .frame(height: 14)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}
