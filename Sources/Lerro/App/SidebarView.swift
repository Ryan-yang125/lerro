import SwiftUI
import LerroCore

struct SidebarView: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @FocusState private var focusedDestination: SidebarDestination?

    var body: some View {
        @Bindable var updater = AppUpdateController.shared
        VStack(spacing: 0) {
            LerroBrandBadge()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)

            VStack(spacing: 4) {
                navigationButton(.home, title: "首页", systemName: "house")
                navigationButton(.history, title: "历史", systemName: "clock.arrow.circlepath")
                navigationButton(.dictionary, title: "词典", systemName: "character.book.closed")
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 20)

            HStack(spacing: 4) {
                LerroIconButton(systemName: "person.crop.circle", help: "个性化") {
                    showSettings(.personalization)
                }
                .frame(maxWidth: .infinity)
                LerroIconButton(systemName: "gearshape", help: "设置") {
                    showSettings(.settings)
                }
                .frame(maxWidth: .infinity)
                LerroIconButton(systemName: "questionmark.circle", help: "帮助与引导") {
                    session.isOnboardingPresented = true
                }
                .frame(maxWidth: .infinity)
                if updater.updateAvailable {
                    LerroIconButton(
                        systemName: AppUpdatePresentation.availableIcon,
                        help: "发现新版本，立即下载",
                        foreground: Color(nsColor: .systemBlue)
                    ) {
                        updater.checkForUpdates()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("发现新版本，立即下载")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(LerroTheme.sidebar)
    }

    private func navigationButton(
        _ destination: SidebarDestination,
        title: String,
        systemName: String
    ) -> some View {
        let selected = session.destination == destination
        return Button {
            session.destination = destination
            focusedDestination = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: LerroTheme.navigationIconSize, weight: .medium))
                    .frame(width: 18)
                Text(verbatim: localized(title))
                    .lerroTypography(selected ? .label : .secondary)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(LerroNavigationButtonStyle(selected: selected))
        .focused($focusedDestination, equals: destination)
        .onMoveCommand { direction in
            moveNavigationFocus(from: destination, direction: direction)
        }
        .accessibilityLabel(Text(verbatim: localized(title)))
        .accessibilityValue(Text(verbatim: selected ? localized("已选择") : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func showSettings(_ entryPoint: SettingsEntryPoint) {
        session.presentSettings(entryPoint)
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }

    private func moveNavigationFocus(
        from destination: SidebarDestination,
        direction: MoveCommandDirection
    ) {
        let destinations: [SidebarDestination] = [.home, .history, .dictionary]
        guard let index = destinations.firstIndex(of: destination) else { return }

        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(destinations.startIndex, index - 1)
        case .down:
            nextIndex = min(destinations.index(before: destinations.endIndex), index + 1)
        case .left, .right:
            return
        @unknown default:
            return
        }

        let nextDestination = destinations[nextIndex]
        session.destination = nextDestination
        focusedDestination = nextDestination
    }
}
