import SwiftUI
import LerroCore

struct SidebarView: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @Environment(\.openSettings) private var openSettingsWindow

    var body: some View {
        List(selection: $session.destination) {
            row(.home, title: "首页", systemImage: "house")
            row(.history, title: "历史", systemImage: "clock.arrow.circlepath", count: session.historyAllCount)
            row(
                .dictionary,
                title: "词典",
                systemImage: "character.book.closed",
                count: session.dictionaryEntries.count
            )
            row(
                .appTones,
                title: "应用语气",
                systemImage: "text.bubble",
                count: session.preferences.appToneProfiles.count
            )
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            LerroWordmark(height: 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
                .padding(.top, 4)
                .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    @ViewBuilder
    private func row(
        _ destination: SidebarDestination,
        title: String,
        systemImage: String,
        count: Int? = nil
    ) -> some View {
        let label = Label(localized(title), systemImage: systemImage)
        Group {
            if let count {
                label.badge(count)
            } else {
                label
            }
        }
        .tag(destination)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if AppUpdateController.shared.updateAvailable {
                updateCard
            }
            aiStatusButton

            HStack(spacing: 4) {
                LerroIconButton(systemImage: "gearshape", help: "设置") {
                    showSettings(.general)
                }
                Spacer(minLength: 0)
                Text(verbatim: AppMetadata.version)
                    .font(LerroFont.footnote)
                    .foregroundStyle(LerroTheme.tertiaryText)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var aiStatusButton: some View {
        switch session.aiStatus {
        case .off:
            statusButton(
                dot: LerroTheme.tertiaryText,
                title: localized("AI 整理"),
                detail: " · " + localized("未开启"),
                fill: Color.primary.opacity(0.06),
                showsChevron: true
            ) {
                session.presentAIGuide()
            }
        case .ready:
            statusButton(
                dot: LerroTheme.success,
                title: readyTitle,
                detail: readyDetail,
                fill: Color.primary.opacity(0.06),
                showsChevron: false
            ) {
                showSettings(.ai)
            }
        case .outOfBalance:
            statusButton(
                dot: LerroTheme.warning,
                title: localized("余额"),
                detail: " " + balanceAmount(loadedBalance),
                fill: LerroTheme.warning.opacity(0.14),
                trailingLink: localized("充值")
            ) {
                session.openURL(DeepSeekLinks.topUp)
            }
        }
    }

    private func statusButton(
        dot: Color,
        title: String,
        detail: String,
        fill: Color,
        showsChevron: Bool = false,
        trailingLink: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LerroStatusDot(color: dot)
                (Text(verbatim: title)
                    .fontWeight(.semibold)
                    .foregroundStyle(LerroTheme.text)
                    + Text(verbatim: detail)
                    .foregroundStyle(LerroTheme.secondaryText))
                    .font(LerroFont.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let trailingLink {
                    Text(verbatim: trailingLink)
                        .font(LerroFont.caption)
                        .foregroundStyle(LerroTheme.accentText)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LerroTheme.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title + detail + (trailingLink.map { "，\($0)" } ?? "")))
    }

    private var loadedBalance: DeepSeekBalance? {
        if case .loaded(let balance) = session.deepSeekBalance { return balance }
        return nil
    }

    private var readyTitle: String {
        localized(loadedBalance == nil ? "AI 整理已开启" : "AI 整理")
    }

    /// " · 余额 ¥8.42" once the balance is loaded.
    private var readyDetail: String {
        guard let balance = loadedBalance else { return "" }
        return " · " + localized("余额") + " " + balanceAmount(balance)
    }

    /// "¥8.42". Without a loaded balance, "¥0.00".
    private func balanceAmount(_ balance: DeepSeekBalance?) -> String {
        let code = balance?.currencyCode ?? "CNY"
        let symbol: String
        switch code {
        case "CNY": symbol = "¥"
        case "USD": symbol = "$"
        default: symbol = code + " "
        }
        let value = balance?.total ?? 0
        return symbol + value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    private var updateCard: some View {
        let title = updateTitle
        return Button {
            AppUpdateController.shared.checkForUpdates()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(LerroFont.caption)
                Text(verbatim: title)
                    .font(LerroFont.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(verbatim: localized("更新"))
                    .font(LerroFont.caption)
            }
            .foregroundStyle(LerroTheme.accentText)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LerroTheme.accentSoft)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(title)，\(localized("更新"))"))
    }

    private var updateTitle: String {
        if let version = AppUpdateController.shared.availableVersion {
            return LerroInterfaceLocalization.format("新版本 %@", locale: locale, arguments: version)
        }
        return localized("有新版本")
    }

    private func showSettings(_ tab: SettingsTab) {
        session.settingsTab = tab
        openSettingsWindow()
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}
