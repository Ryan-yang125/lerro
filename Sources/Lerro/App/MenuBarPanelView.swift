import AppKit
import SwiftUI
import LerroCore

/// Menu bar window: status, capture tiles, last result, today's usage, input
/// and intelligence pickers, and app shortcuts.
struct MenuBarPanelView: View {
    let session: AppSession
    /// Draws the panel material itself. The real menu bar window supplies its
    /// own; visual fixtures render the panel inside the main window.
    var drawsChrome = false

    @Environment(\.locale) private var locale
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var aiCostText: String?
    @State private var copiedEntryID: UUID?

    private let focus = MenuBarPanelFocus.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(missingPermissions, id: \.self) { permission in
                permissionRow(permission)
            }
            captureTiles
            if let entry = lastEntry {
                lastResultCard(entry)
            }
            todayLine
            pickerRows
            if AppUpdateController.shared.updateAvailable {
                updateRow
            }
            footer
        }
        .padding(12)
        .frame(width: 304)
        .tracking(LerroTheme.uiTracking)
        .tint(LerroTheme.accent)
        .background { chrome }
        .onAppear(perform: panelDidShow)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window === focus.panelWindow else { return }
            panelDidShow()
        }
    }

    // MARK: State

    private var status: MenuBarPanelPresentation.Status {
        MenuBarPanelPresentation.status(
            phase: session.phase,
            microphoneGranted: session.microphonePermission,
            accessibilityGranted: session.accessibilityPermission
        )
    }

    private var missingPermissions: [MenuBarPanelPresentation.MissingPermission] {
        MenuBarPanelPresentation.missingPermissions(
            microphoneGranted: session.microphonePermission,
            accessibilityGranted: session.accessibilityPermission
        )
    }

    private var lastEntry: HistoryEntry? {
        session.recentHistoryEntries.first { !$0.finalText.isEmpty }
    }

    private func hotkeyName(_ action: HotkeyAction) -> String? {
        session.preferences.hotkeys.first { $0.action == action }?.displayName
    }

    // MARK: Header

    private var header: some View {
        HStack {
            LerroWordmark(height: 15)
                .foregroundStyle(LerroTheme.text)
            Spacer(minLength: 8)
            statusPill
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
    }

    private var statusPill: some View {
        let title = localized(status.titleKey)
        let text = status == .listening
            ? "\(title) \(MenuBarPanelPresentation.elapsedText(session.captureElapsed))"
            : title
        return HStack(spacing: 6) {
            switch status {
            case .listening:
                MenuBarBlinkingCursor()
            case .permission, .failed:
                LerroStatusDot(color: LerroTheme.warning)
            case .processing:
                LerroStatusDot(color: LerroTheme.accent)
            case .ready:
                LerroStatusDot(color: LerroTheme.success)
            }
            Text(verbatim: text)
                .font(LerroFont.caption)
                .monospacedDigit()
                .foregroundStyle(status == .listening ? LerroTheme.accentText : LerroTheme.secondaryText)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(pillFill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var pillFill: Color {
        switch status {
        case .listening: LerroTheme.accentSoft
        case .permission, .failed: LerroTheme.warning.opacity(0.14)
        case .ready, .processing: LerroTheme.fillContainerThin
        }
    }

    // MARK: Permissions

    private func permissionRow(_ permission: MenuBarPanelPresentation.MissingPermission) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(LerroTheme.warning)
                .accessibilityHidden(true)
            Text(verbatim: localized(permission.titleKey))
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.text)
            Spacer(minLength: 4)
            Button {
                showSettings()
            } label: {
                Text(verbatim: localized("打开设置"))
            }
            .buttonStyle(LerroButtonStyle(.secondary, compact: true))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(LerroTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }

    // MARK: Capture tiles

    private var captureTiles: some View {
        HStack(spacing: 8) {
            captureTile(.dictation)
            captureTile(.translation)
        }
    }

    private func captureTile(_ mode: CaptureMode) -> some View {
        let tile = MenuBarPanelPresentation.tile(
            for: mode,
            phase: session.phase,
            activeMode: session.activeMode,
            permissionsGranted: missingPermissions.isEmpty
        )
        let isDictation = mode == .dictation
        let name = localized(isDictation ? "听写" : "翻译")
        let hotkey = hotkeyName(isDictation ? .dictate : .translate)
        let title: String
        switch tile {
        case .finish: title = localized(isDictation ? "完成听写" : "完成翻译")
        case .cancel: title = localized("取消")
        case .start, .disabled: title = name
        }
        return Button {
            switch tile {
            case .start:
                focus.performInTargetApplication { session.toggleCapture(mode) }
            case .finish:
                focus.closePanel()
                session.toggleCapture(mode)
            case .cancel:
                focus.closePanel()
                session.cancelCapture()
            case .disabled:
                break
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    switch tile {
                    case .finish:
                        MenuBarWaveform()
                    case .cancel:
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LerroTheme.accent)
                    case .start, .disabled:
                        LerroGlyphView(glyph: isDictation ? .dictate : .translate, size: 16)
                            .foregroundStyle(LerroTheme.accent)
                    }
                    Text(verbatim: title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                switch tile {
                case .cancel:
                    LerroKeycap("esc")
                case .start, .finish, .disabled:
                    if let hotkey {
                        LerroShortcutKeys(displayName: hotkey, onAccent: tile == .finish)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MenuBarTileStyle(isProminent: tile == .finish))
        .disabled(tile == .disabled)
        .accessibilityLabel(Text(verbatim: title))
    }

    // MARK: Last result

    private func lastResultCard(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 6) {
                    LerroAppIcon(
                        bundleIdentifier: entry.bundleIdentifier,
                        name: entry.applicationName,
                        size: 14
                    )
                    Text(verbatim: "\(entry.applicationName) · \(relativeText(entry.createdAt, now: context.date))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(LerroTheme.metadataText)
                        .lineLimit(1)
                }
            }
            Text(verbatim: entry.finalText)
                .font(LerroFont.body)
                .foregroundStyle(LerroTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.bottom, 8)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button {
                    copy(entry)
                } label: {
                    Text(verbatim: localized(copiedEntryID == entry.id ? "已复制" : "复制"))
                }
                .buttonStyle(LerroButtonStyle(.secondary, compact: true))
                Button {
                    focus.performInTargetApplication { session.paste(entry.finalText) }
                } label: {
                    Text(verbatim: pasteTitle)
                }
                .buttonStyle(LerroButtonStyle(.primary, compact: true))
                .disabled(status != .ready)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(LerroTheme.fillContainerThin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
    }

    private var pasteTitle: String {
        let title = localized("粘贴")
        guard let hotkey = hotkeyName(.pasteLastResult) else { return title }
        return "\(title) \(hotkey)"
    }

    private func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.finalText, forType: .string)
        copiedEntryID = entry.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedEntryID == entry.id { copiedEntryID = nil }
        }
    }

    private func relativeText(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    // MARK: Today

    private var todayLine: some View {
        let statistics = session.usageStatistics
        return HStack {
            markdownText("今天 **%@** 次", statistics.todayCount.formatted(.number.locale(locale)))
            Spacer(minLength: 8)
            markdownText("**%@** 字", statistics.today.totalWords.formatted(.number.locale(locale)))
            if let aiCostText {
                Spacer(minLength: 8)
                markdownText("AI **%@**", aiCostText)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(LerroTheme.metadataText)
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private func markdownText(_ key: String, _ argument: String) -> Text {
        let formatted = LerroInterfaceLocalization.format(key, locale: locale, arguments: argument)
        if let attributed = try? AttributedString(markdown: formatted) {
            return Text(attributed)
        }
        return Text(verbatim: formatted)
    }

    // MARK: Pickers

    private var pickerRows: some View {
        VStack(spacing: 0) {
            pickerRow(glyph: .mic, title: "麦克风") {
                Picker(selection: microphoneSelection) {
                    Text(verbatim: localized("跟随系统默认")).tag(String?.none)
                    ForEach(session.audioInputDevices) { device in
                        Text(verbatim: device.name).tag(String?.some(device.uid))
                    }
                } label: {
                    Text(verbatim: localized("麦克风"))
                }
            }
            pickerRow(glyph: .polish, title: "智能处理") {
                Picker(selection: intelligenceSelection) {
                    Text(verbatim: localized("纯苹果听写")).tag(IntelligenceMode.raw)
                    Text(verbatim: session.preferences.remoteProvider.provider.lerroDisplayName)
                        .disabled(!session.preferences.remoteProvider.isReadyForUse)
                        .tag(IntelligenceMode.remote)
                    Text(verbatim: localized("本地 AI"))
                        .disabled(!session.localAIIsReady)
                        .tag(IntelligenceMode.local)
                } label: {
                    Text(verbatim: localized("智能处理"))
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Divider() }
        .padding(.top, 8)
        .disabled(!session.canModifyIntelligenceConfiguration)
    }

    private func pickerRow<Control: View>(
        glyph: LerroGlyph,
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 9) {
            LerroGlyphView(glyph: glyph, size: 16)
                .foregroundStyle(LerroTheme.secondaryText)
            Text(verbatim: localized(title))
                .font(LerroFont.body)
                .foregroundStyle(LerroTheme.text)
            Spacer(minLength: 8)
            control()
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .tint(LerroTheme.secondaryText)
                .frame(maxWidth: 160, alignment: .trailing)
                .accessibilityLabel(Text(verbatim: localized(title)))
        }
        .frame(height: 32)
        .padding(.horizontal, 6)
    }

    private var microphoneSelection: Binding<String?> {
        Binding(
            get: {
                let uid = session.preferences.microphoneDeviceUID
                return session.audioInputDevices.contains { $0.uid == uid } ? uid : nil
            },
            set: { session.selectMicrophone(uid: $0) }
        )
    }

    private var intelligenceSelection: Binding<IntelligenceMode> {
        Binding(
            get: { session.preferences.intelligenceMode },
            set: { session.activateIntelligenceMode($0) }
        )
    }

    // MARK: Update

    private var updateRow: some View {
        Button {
            focus.closePanel()
            AppUpdateController.shared.checkForUpdates()
        } label: {
            HStack(spacing: 8) {
                LerroGlyphView(glyph: .update, size: 16)
                Text(verbatim: localized("下载新版本"))
                    .font(LerroFont.bodyEmphasis)
                Spacer(minLength: 0)
            }
            .foregroundStyle(LerroTheme.accentText)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(LerroTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.top, 6)
            HStack(spacing: 4) {
                Button {
                    openMainWindow()
                } label: {
                    Text(verbatim: localized("打开 Lerro"))
                        .font(LerroFont.bodyEmphasis)
                        .foregroundStyle(LerroTheme.text)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                LerroIconButton(glyph: .general, help: "设置") {
                    showSettings()
                }
                .keyboardShortcut(",")
                LerroIconButton(systemImage: "power", help: "退出 Lerro") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
    }

    // MARK: Window actions

    private func showSettings() {
        focus.closePanel()
        session.settingsTab = .general
        openSettings()
        NSApp.activate()
    }

    private func openMainWindow() {
        focus.closePanel()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func panelDidShow() {
        focus.panelDidAppear()
        Task {
            await session.refreshAudioInputDevices()
            await loadTodayAICost()
        }
    }

    private func loadTodayAICost() async {
        let now = Date.now
        let records = await session.aiUsageRecords(since: Calendar.current.startOfDay(for: now))
        let report = AIUsageStatistics.report(
            records: records,
            prices: AIModelPriceTable(overrides: session.preferences.modelPrices),
            days: 1,
            now: now
        )
        aiCostText = report.totals.costs.isEmpty
            ? nil
            : UsageFormat(locale: locale).cost(report.totals.costs)
    }

    // MARK: Chrome

    @ViewBuilder
    private var chrome: some View {
        if drawsChrome {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        } else {
            MenuBarPanelWindowReader()
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

// MARK: - Presentation

enum MenuBarPanelPresentation {
    enum Status: Equatable {
        case ready
        case listening
        case processing
        case failed
        case permission

        var titleKey: String {
            switch self {
            case .ready: "就绪"
            case .listening: "正在听"
            case .processing: "处理中"
            case .failed: "需要处理"
            case .permission: "需要权限"
            }
        }
    }

    enum MissingPermission: Hashable {
        case microphone
        case accessibility

        var titleKey: String {
            switch self {
            case .microphone: "麦克风未授权"
            case .accessibility: "辅助功能未授权"
            }
        }
    }

    enum Tile: Equatable {
        case start
        case finish
        case cancel
        case disabled
    }

    static func status(
        phase: CapturePhase,
        microphoneGranted: Bool,
        accessibilityGranted: Bool
    ) -> Status {
        guard microphoneGranted, accessibilityGranted else { return .permission }
        switch phase {
        case .idle, .success, .cancelled: return .ready
        case .listening: return .listening
        case .transcribing, .enhancing, .inserting: return .processing
        case .failed: return .failed
        }
    }

    static func missingPermissions(
        microphoneGranted: Bool,
        accessibilityGranted: Bool
    ) -> [MissingPermission] {
        var missing: [MissingPermission] = []
        if !microphoneGranted { missing.append(.microphone) }
        if !accessibilityGranted { missing.append(.accessibility) }
        return missing
    }

    /// State of the tile for `mode`. Instruction captures finish from the
    /// dictation tile.
    static func tile(
        for mode: CaptureMode,
        phase: CapturePhase,
        activeMode: CaptureMode,
        permissionsGranted: Bool
    ) -> Tile {
        switch phase {
        case .listening:
            let activeTile: CaptureMode = activeMode == .translation ? .translation : .dictation
            return mode == activeTile ? .finish : .cancel
        case .transcribing, .enhancing, .inserting:
            return .disabled
        case .idle, .success, .failed, .cancelled:
            return permissionsGranted ? .start : .disabled
        }
    }

    /// "m:ss"
    static func elapsedText(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Components

private struct MenuBarTileStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        Body(isProminent: isProminent, label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct Body<Label: View>: View {
        let isProminent: Bool
        let label: Label
        let isPressed: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .padding(.horizontal, 12)
                .frame(height: 60)
                .foregroundStyle(isProminent ? LerroTheme.primaryActionForeground : LerroTheme.text)
                .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(isPressed ? 0.8 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: LerroTheme.hoverDuration), value: hovering)
                .animation(.easeOut(duration: LerroTheme.pressDuration), value: isPressed)
        }

        private var fill: Color {
            if isProminent { return LerroTheme.accentButton }
            return hovering ? LerroTheme.actionFillHover : LerroTheme.actionFill
        }
    }
}

private struct MenuBarBlinkingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let isOn = reduceMotion
                || Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
            Capsule()
                .fill(LerroTheme.brandCursor)
                .frame(width: 2, height: 12)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 2, height: 12)
        .accessibilityHidden(true)
    }
}

private struct MenuBarWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isContracted = false

    private static let heights: [CGFloat] = [5, 10, 14, 8, 11]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.heights.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: Self.heights[index])
                    .scaleEffect(y: isContracted ? 0.4 : 1)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1),
                        value: isContracted
                    )
            }
        }
        .frame(height: 14)
        .onAppear { isContracted = !reduceMotion }
        .accessibilityHidden(true)
    }
}

/// Publishes the hosting window so actions can close the menu bar panel.
private struct MenuBarPanelWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Reader() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Reader: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            MenuBarPanelFocus.shared.panelWindow = window
        }
    }
}
