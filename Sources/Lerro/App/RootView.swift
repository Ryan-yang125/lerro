import AppKit
import SwiftUI
import LerroCore

struct RootView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

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
                .allowsHitTesting(!session.isOnboardingPresented)
                .accessibilityHidden(session.isOnboardingPresented)

                if session.isOnboardingPresented {
                    OnboardingView(session: session)
                        .tracking(LerroTheme.uiTracking)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.985).combined(with: .opacity))
                        .zIndex(10)
                }
            }
        }
        .frame(
            minWidth: LerroTheme.hubMinimumSize.width,
            minHeight: LerroTheme.hubMinimumSize.height
        )
        .toolbarVisibility(session.isOnboardingPresented ? .hidden : .automatic, for: .windowToolbar)
        .tint(LerroTheme.accent)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: session.isOnboardingPresented)
        .onChange(of: session.visualFixturePresentation, initial: true) { _, presentation in
            if presentation?.hasPrefix("settings-") == true {
                openSettings()
            }
            if let presentation, presentation.hasPrefix("prompt-"),
               let kind = AIPromptKind(rawValue: String(presentation.dropFirst("prompt-".count))) {
                openWindow(id: "prompt", value: kind)
            }
        }
        .onChange(of: session.isOnboardingPresented) { _, isPresented in
            if isPresented {
                openWindow(id: "main")
                NSApp.activate()
            }
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

    @ViewBuilder
    private var detail: some View {
        switch session.destination {
        case .home:
            HomeView(session: session)
        case .history:
            HistoryView(session: session)
        case .dictionary:
            DictionaryView(session: session)
        case .appTones:
            AppTonesView(session: session)
        }
    }

    @ViewBuilder
    private var visualFixture: some View {
        ZStack {
            LerroTheme.canvas
            if session.visualFixturePresentation?.hasPrefix("hud-") == true {
                CaptureHUDView(session: session)
                    .frame(width: 750, height: 500)
            }
            if session.visualFixturePresentation?.hasPrefix("menubar-panel") == true {
                MenuBarPanelView(session: session, drawsChrome: true)
            }
        }
    }
}
