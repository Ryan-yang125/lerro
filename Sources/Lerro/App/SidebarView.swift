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
        let status = session.intelligenceStatus
        return VStack(spacing: 6) {
            Button {
                showSettings(.intelligence)
            } label: {
                HStack(spacing: 8) {
                    LerroStatusDot(color: status.isReady ? LerroTheme.success : LerroTheme.warning)
                    (Text(verbatim: status.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(LerroTheme.text)
                        + Text(verbatim: " · \(status.detail)")
                        .foregroundStyle(LerroTheme.secondaryText))
                        .font(LerroFont.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(status.title) · \(status.detail)"))

            HStack(spacing: 4) {
                LerroIconButton(systemImage: "gearshape", help: "设置") {
                    showSettings(.general)
                }
                if AppUpdateController.shared.updateAvailable {
                    LerroIconButton(
                        systemImage: "arrow.down.circle",
                        help: "发现新版本，立即下载"
                    ) {
                        AppUpdateController.shared.checkForUpdates()
                    }
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

    private func showSettings(_ tab: SettingsTab) {
        session.settingsTab = tab
        openSettingsWindow()
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}
