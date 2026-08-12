import SwiftUI
import LerroCore

struct HomeView: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("说出来，就写好了")
                    .lerroTypography(.title)
                    .foregroundStyle(LerroTheme.text)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .top, spacing: 20) {
                    dashboard
                        .frame(maxWidth: .infinity)
                    rightRail
                        .frame(width: 218)
                }
            }
            .padding(.top, LerroTheme.contentTopPadding)
            .padding(.horizontal, LerroTheme.contentHorizontalPadding)
            .padding(.bottom, LerroTheme.contentBottomPadding)
            .frame(maxWidth: 1180, alignment: .topLeading)
        }
        .background(LerroTheme.main)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("您的数据保存在这台 Mac", systemImage: "lock.fill")
                .lerroTypography(.caption)
                .foregroundStyle(LerroTheme.secondaryText)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                metric(value: durationString(session.usage.totalDuration), label: "总口述时间")
                metric(value: compactNumber(session.usage.totalWords), label: "口述字数")
                metric(value: durationString(session.usage.savedSeconds), label: "节省时间")
                metric(value: "\(session.usage.averageWordsPerMinute)", label: "每分钟字数")
            }

            personalization
        }
        .padding(16)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder, lineWidth: 1)
        }
    }

    private func metric(value: String, label: String) -> some View {
        LerroCard(padding: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: localized(label))
                    .lerroTypography(.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
                Text(verbatim: value)
                    .lerroTypography(.title)
                    .foregroundStyle(LerroTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var personalization: some View {
        LerroCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("个性化")
                        .lerroTypography(.heading)
                        .foregroundStyle(LerroTheme.text)
                    Spacer()
                }

                HStack(spacing: 20) {
                    personalizationMetric(value: session.dictionaryEntries.count, label: "词典")
                    personalizationMetric(
                        value: session.dictionaryEntries.filter { $0.source == .learned }.count,
                        label: "学习修正"
                    )
                    personalizationMetric(
                        value: session.preferences.appToneProfiles.filter(\.enabled).count,
                        label: "应用语气"
                    )
                }

                Label("词典、历史与设置保存在这台 Mac。", systemImage: "lock.shield")
                    .lerroTypography(.caption)
                    .foregroundStyle(LerroTheme.secondaryText)

                HStack {
                    Button("管理个性化") {
                        showSettings(.personalization)
                    }
                    .buttonStyle(LerroPillButtonStyle())
                    Spacer()
                }
            }
        }
    }

    private func personalizationMetric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: "\(value)")
                .lerroTypography(.heading)
                .monospacedDigit()
            Text(verbatim: localized(label))
                .lerroTypography(.caption)
                .foregroundStyle(LerroTheme.secondaryText)
        }
    }

    private var rightRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            LerroCard(padding: 8) {
                VStack(spacing: 2) {
                    shortcutRow(.dictation, title: "听写", detail: "Fn")
                    shortcutRow(.translation, title: "翻译", detail: "Fn Left Shift")
                }
            }

            Button {
                session.isOnboardingPresented = true
            } label: {
                HStack {
                    Text("使用指南")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .lerroTypography(.heading)
                .foregroundStyle(LerroTheme.text)
                .padding(.horizontal, 14)
                .frame(height: 42)
            }
            .buttonStyle(LerroCardButtonStyle())

            infoCard(
                title: "项目说明",
                detail: "了解 Lerro 的本地优先设计",
                icon: "arrow.up.right.square",
                entryPoint: .recommendation
            )
            HomeIntelligenceCard(session: session)

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Lerro for Mac · \(AppMetadata.version)")
                Button("检查更新") {
                    AppUpdateController.shared.checkForUpdates()
                }
                .buttonStyle(LerroPressButtonStyle())
            }
            .lerroTypography(.caption)
            .foregroundStyle(LerroTheme.tertiaryText)
        }
    }

    private func shortcutRow(_ mode: CaptureMode, title: String, detail: String) -> some View {
        Button { session.toggleCapture(mode) } label: {
            HStack(spacing: 10) {
                Image(systemName: modeIcon(mode))
                    .font(.system(size: LerroTheme.navigationIconSize, weight: .medium))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: localized(title))
                        .lerroTypography(.label)
                        .foregroundStyle(LerroTheme.text)
                    Text(verbatim: shortcut(for: mode, fallback: localized(detail)))
                        .lerroTypography(.caption)
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(LerroNavigationButtonStyle(selected: false))
        .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
            "快捷键 %@：%@",
            locale: locale,
            arguments: localized(title), shortcut(for: mode, fallback: localized(detail))
        )))
    }

    private func infoCard(
        title: String,
        detail: String,
        icon: String,
        entryPoint: SettingsEntryPoint
    ) -> some View {
        Button { showSettings(entryPoint) } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                    .foregroundStyle(LerroTheme.text)
                Text(verbatim: localized(title))
                    .lerroTypography(.heading)
                    .foregroundStyle(LerroTheme.text)
                Text(verbatim: localized(detail))
                    .lerroTypography(.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        }
        .buttonStyle(LerroCardButtonStyle())
    }

    private func modeIcon(_ mode: CaptureMode) -> String {
        switch mode {
        case .dictation: "waveform"
        case .translation: "character.bubble"
        case .ask: "sparkles"
        }
    }

    private func shortcut(for mode: CaptureMode, fallback: String) -> String {
        let action: HotkeyAction = switch mode {
        case .dictation: .dictate
        case .translation: .translate
        case .ask: .ask
        }
        return session.preferences.hotkeys.first(where: { $0.action == action })?.displayName ?? fallback
    }

    private func durationString(_ duration: TimeInterval) -> String {
        if duration >= 3_600 {
            return LerroInterfaceLocalization.format("%.1f 小时", locale: locale, arguments: duration / 3_600)
        }
        if duration >= 60 {
            return LerroInterfaceLocalization.format("%lld 分钟", locale: locale, arguments: Int64(duration / 60))
        }
        return LerroInterfaceLocalization.format("%lld 秒", locale: locale, arguments: Int64(duration))
    }

    private func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private func showSettings(_ entryPoint: SettingsEntryPoint) {
        session.presentSettings(entryPoint)
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct HomeIntelligenceCard: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            session.presentSettings(SettingsEntryPoint.intelligence)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                    .foregroundStyle(LerroTheme.text)
                Text("智能处理")
                    .lerroTypography(.heading)
                    .foregroundStyle(LerroTheme.text)
                Text(verbatim: summary)
                    .lerroTypography(.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        }
        .buttonStyle(LerroCardButtonStyle())
    }

    private var summary: String {
        switch session.preferences.intelligenceMode {
        case .raw:
            localized("原始听写")
        case .local:
            localizedStatus(session.modelStatus.message.isEmpty ? "Qwen3.5 4B 本地 AI" : session.modelStatus.message)
        case .remote:
            "\(session.preferences.remoteProvider.provider.lerroDisplayName) · \(session.preferences.remoteProvider.modelIdentifier)"
        }
    }

    private var icon: String {
        switch session.preferences.intelligenceMode {
        case .raw: "waveform"
        case .local: "cpu"
        case .remote: "network"
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }

    private func localizedStatus(_ message: String) -> String {
        LerroInterfaceLocalization.statusString(message, locale: locale)
    }
}
