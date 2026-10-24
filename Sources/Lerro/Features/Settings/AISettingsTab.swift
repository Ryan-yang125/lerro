import SwiftUI
import LerroCore

struct AISettingsTab: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow
    @State private var showsAdvanced = false
    @State private var monthTotals = AIUsageTotals()

    var body: some View {
        Group {
            if session.aiSettingsShowsUsage {
                AIUsageView(session: session)
            } else {
                mainPage
            }
        }
        .frame(width: SettingsLayout.width, height: SettingsLayout.tallHeight)
        .onDisappear { session.aiSettingsShowsUsage = false }
    }

    // MARK: Main page

    private var mainPage: some View {
        let isEnabled = session.preferences.intelligenceMode == .remote

        return Form {
            SettingsPermissionBanner(session: session)

            Section {
                Toggle("AI 整理", isOn: aiEnabledBinding)
            }

            if !session.hasDeepSeekKey {
                Section {
                    DeepSeekKeyGuide(session: session)
                }
            } else if isEnabled {
                deepSeekSection

                advancedDisclosure

                if showsAdvanced {
                    advancedSections
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await session.refreshDeepSeekBalance()
            await loadMonthTotals()
        }
    }

    private var aiEnabledBinding: Binding<Bool> {
        Binding {
            session.preferences.intelligenceMode == .remote
        } set: { enabled in
            session.setAIEnabled(enabled)
        }
    }

    // MARK: DeepSeek

    private var deepSeekSection: some View {
        Section("DeepSeek") {
            LabeledContent("状态") {
                statusValue
            }

            settingsRow("API Key") {
                HStack(spacing: 8) {
                    Text(verbatim: maskedAPIKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(LerroTheme.secondaryText)
                    Button("更换") {
                        Task { _ = await session.clearDeepSeekKey() }
                    }
                    .buttonStyle(LerroButtonStyle(.secondary))
                }
            }

            settingsRow("余额") {
                balanceValue
            }

            settingsRow("这个月") {
                HStack(spacing: 8) {
                    Text(verbatim: monthSummary)
                        .foregroundStyle(LerroTheme.secondaryText)
                    Button("明细") {
                        session.aiSettingsShowsUsage = true
                    }
                    .buttonStyle(LerroButtonStyle(.secondary))
                }
            }
        }
    }

    /// Label and trailing controls centred on one line; `LabeledContent`
    /// top-aligns its label when the trailing side holds a button.
    private func settingsRow<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center) {
            Text(title)
            Spacer(minLength: 12)
            content()
        }
    }

    @ViewBuilder
    private var statusValue: some View {
        if case .loading = session.deepSeekBalance {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在读取")
            }
        } else if session.aiStatus == .outOfBalance {
            HStack(spacing: 6) {
                LerroStatusDot(color: LerroTheme.warning)
                Text("余额用完")
            }
        } else {
            HStack(spacing: 6) {
                LerroStatusDot(color: LerroTheme.success)
                Text("已连接")
            }
        }
    }

    @ViewBuilder
    private var balanceValue: some View {
        switch session.deepSeekBalance {
        case .loaded(let balance):
            HStack(spacing: 8) {
                Text(verbatim: Self.amountText(balance.total, currencyCode: balance.currencyCode))
                    .font(LerroFont.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(balance.isEmpty ? LerroTheme.warning : LerroTheme.text)
                Button("充值") {
                    session.openURL(DeepSeekLinks.topUp)
                }
                .buttonStyle(LerroButtonStyle(.secondary))
            }
        case .failed:
            HStack(spacing: 8) {
                Text("读取失败")
                    .foregroundStyle(LerroTheme.secondaryText)
                Button("重试") {
                    Task { await session.refreshDeepSeekBalance(force: true) }
                }
                .buttonStyle(LerroButtonStyle(.secondary))
            }
        case .unknown, .loading:
            ProgressView().controlSize(.small)
        }
    }

    /// First 7 characters, an ellipsis, then the last 4.
    private var maskedAPIKey: String {
        let key = session.preferences.remoteProvider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count > 11 else { return String(repeating: "•", count: max(key.count, 4)) }
        return "\(key.prefix(7))…\(key.suffix(4))"
    }

    private var monthSummary: String {
        let format = UsageFormat(locale: locale)
        let cost = format.cost([.cny: monthTotals.costs[.cny] ?? 0])
        let count = LerroInterfaceLocalization.format(
            "%lld 次", locale: locale, arguments: monthTotals.requests
        )
        return "\(cost) · \(count)"
    }

    private func loadMonthTotals() async {
        let now = Date.now
        let calendar = Calendar.current
        let dayOfMonth = calendar.component(.day, from: now)
        let start = AIUsageStatistics.rangeStart(days: dayOfMonth, now: now, calendar: calendar)
        let records = await session.aiUsageRecords(since: start)
        monthTotals = AIUsageStatistics.report(
            records: records,
            days: dayOfMonth,
            now: now
        ).totals
    }

    static func amountText(_ amount: Decimal, currencyCode: String) -> String {
        let symbol = currencyCode == "USD" ? "$" : "¥"
        let value = NSDecimalNumber(decimal: amount).doubleValue
        return symbol + String(format: "%.2f", value)
    }

    // MARK: Advanced

    private var advancedDisclosure: some View {
        Section {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsAdvanced.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LerroTheme.tertiaryText)
                        .rotationEffect(.degrees(showsAdvanced ? 90 : 0))
                        .accessibilityHidden(true)
                    Text("高级")
                        .foregroundStyle(LerroTheme.text)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(Text(verbatim: localized(showsAdvanced ? "已展开" : "已折叠")))
        }
    }

    @ViewBuilder
    private var advancedSections: some View {
        Section("发给 AI 的内容") {
            Toggle("App 名称", isOn: $session.preferences.remoteProvider.contextSharing.application)
            Toggle("窗口标题", isOn: $session.preferences.remoteProvider.contextSharing.windowTitle)
            Toggle("光标附近的文字", isOn: $session.preferences.remoteProvider.contextSharing.nearbyText)
            Toggle("选中的文字", isOn: $session.preferences.remoteProvider.contextSharing.selectedText)
            Toggle("个人词典", isOn: $session.preferences.remoteProvider.contextSharing.dictionary)
            Toggle("应用语气", isOn: $session.preferences.remoteProvider.contextSharing.tone)
        }

        Section {
            Toggle("修正后自动学词", isOn: $session.preferences.automaticDictionaryLearningEnabled)
        }

        Section {
            ForEach(AIPromptKind.allCases) { kind in
                promptRow(kind)
            }
        } header: {
            Text("提示词")
        } footer: {
            Text("API Key 以明文保存在这台 Mac 的设置文件中。")
                .font(LerroFont.footnote)
        }
    }

    private func promptRow(_ kind: AIPromptKind) -> some View {
        Button {
            openWindow(id: "prompt", value: kind)
        } label: {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(kind.lerroTitle))
                    .foregroundStyle(LerroTheme.text)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LerroTheme.tertiaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: localized(kind.lerroTitle)))
        .accessibilityAddTraits(.isButton)
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}
