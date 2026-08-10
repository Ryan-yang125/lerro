import SwiftUI
import LerroCore

struct RootView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            if session.isPanelOnlyVisualFixture {
                visualFixture
            } else {
                NavigationSplitView {
                    SidebarView(session: session)
                        .navigationSplitViewColumnWidth(
                            min: 200,
                            ideal: LerroTheme.sidebarWidth,
                            max: 260
                        )
                } detail: {
                    detail
                }
                .navigationSplitViewStyle(.balanced)
                .tracking(LerroTheme.uiTracking)
                .allowsHitTesting(!session.isOnboardingPresented && !session.isSettingsPresented)
                .accessibilityHidden(session.isOnboardingPresented || session.isSettingsPresented)

                if session.isOnboardingPresented {
                    OnboardingView(session: session)
                        .tracking(LerroTheme.uiTracking)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.985).combined(with: .opacity))
                        .allowsHitTesting(!session.isSettingsPresented)
                        .accessibilityHidden(session.isSettingsPresented)
                        .zIndex(10)
                }

                if session.isSettingsPresented {
                    settingsModal
                        .transition(reduceMotion
                            ? .opacity
                            : .scale(scale: 0.98).combined(with: .opacity))
                        .zIndex(20)
                }
            }
        }
        .frame(
            minWidth: LerroTheme.hubMinimumSize.width,
            minHeight: LerroTheme.hubMinimumSize.height
        )
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbarVisibility(
            session.isSettingsPresented ? .hidden : .automatic,
            for: .windowToolbar
        )
        .tint(LerroTheme.accent)
        .accentColor(LerroTheme.accent)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.isOnboardingPresented)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: session.isSettingsPresented)
        .alert("下载本地 AI 模型？", isPresented: $session.isModelDownloadConsentPresented) {
            Button("下载并启用") { session.approveLocalModelDownload() }
            if session.canContinueWithBaseDictation {
                Button("使用基础听写") { session.continueWithBaseDictation() }
            }
            Button("稍后", role: .cancel) { session.cancelModelDownloadConsent() }
        } message: {
            Text("Lerro 将从 Hugging Face 下载约 3.03 GB 的 Qwen3.5 4B 模型并保存在这台 Mac。听写内容、选中文字与生成结果留在本机。")
        }
        .alert("Lerro", isPresented: Binding(
            get: { session.currentError != nil },
            set: { if !$0 { session.currentError = nil } }
        )) {
            Button("好") { session.currentError = nil }
        } message: {
            Text(verbatim: LerroInterfaceLocalization.string(session.currentError ?? "", locale: locale))
        }
    }

    private var settingsModal: some View {
        GeometryReader { geometry in
            let width = min(
                LerroTheme.settingsMaximumSize.width,
                max(
                    LerroTheme.settingsMinimumSize.width,
                    geometry.size.width - LerroTheme.settingsModalHorizontalInset * 2
                )
            )
            let height = min(
                LerroTheme.settingsMaximumSize.height,
                max(
                    LerroTheme.settingsMinimumSize.height,
                    geometry.size.height - LerroTheme.settingsModalVerticalInset * 2
                )
            )

            ZStack {
                Color.black
                    .opacity(colorScheme == .dark ? 0.46 : 0.24)
                    .contentShape(Rectangle())
                    .onTapGesture { session.dismissSettings() }
                    .accessibilityHidden(true)

                SettingsOverlayView(session: session)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(
                        cornerRadius: LerroTheme.settingsModalCornerRadius,
                        style: .continuous
                    ))
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: LerroTheme.settingsModalCornerRadius,
                            style: .continuous
                        )
                        .stroke(LerroTheme.border, lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.20), radius: 28, x: 0, y: 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch session.destination {
        case .home:
            HomeView(session: session)
        case .history:
            HistoryView(session: session)
        case .dictionary:
            DictionaryView(session: session)
        }
    }

    @ViewBuilder
    private var visualFixture: some View {
        ZStack {
            LerroTheme.canvas
            switch session.visualFixturePresentation {
            case "ask":
                AskAnswerCardView(session: session)
                    .frame(width: 800, height: 500)
            case "hud-waiting", "hud-recording", "hud-profile", "hud-dictating", "hud-hands-free", "hud-processing", "hud-error", "hud-receipt", "hud-send-confirmation":
                CaptureHUDView(session: session)
                    .frame(width: 750, height: 500)
            default:
                EmptyView()
            }
        }
    }
}
