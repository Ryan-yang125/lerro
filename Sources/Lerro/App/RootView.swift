import AppKit
import SwiftUI
import LerroCore

struct RootView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var focusResetter = WindowFocusResetter()
    @State private var toolbarBandHeight: CGFloat = 0

    var body: some View {
        ZStack {
            if session.isPanelOnlyVisualFixture {
                visualFixture
            } else {
                // A fixed sidebar beside the page. The window has an empty
                // toolbar and no visible title: the sidebar runs up under the
                // traffic lights and each page draws its own header
                // (LerroPageHeader) in the toolbar's 52 pt band.
                LerroSplitLayout(axis: .horizontal, firstLength: LerroTheme.sidebarWidth) {
                    SidebarView(session: session)
                        .background(LerroTheme.sidebar)
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(LerroTheme.thinBorder)
                                .frame(width: 0.5)
                        }
                    detail
                        .background(LerroTheme.main)
                }
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
        .ignoresSafeArea(.container, edges: .top)
        // SwiftUI adds the toolbar band to the minimum content size, so it is
        // taken off here to keep the whole window at least 988 × 658.
        .frame(
            minWidth: LerroTheme.hubMinimumSize.width,
            minHeight: LerroTheme.hubMinimumSize.height - toolbarBandHeight
        )
        .tint(LerroTheme.accent)
        .background(MainWindowToolbarInstaller(bandHeight: $toolbarBandHeight))
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
        .sheet(isPresented: $session.isAIGuidePresented) {
            AIGuideSheet(session: session)
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

    /// All four pages stay alive; switching only changes which one is visible.
    /// The window title is set here once, because every page would otherwise
    /// set its own.
    private var detail: some View {
        ZStack {
            ForEach(SidebarDestination.allCases, id: \.self) { destination in
                page(destination)
                    .lerroPageVisibility(destination == session.destination)
            }
        }
        .navigationTitle(Text(verbatim: windowTitle))
        .background(WindowFocusResetterView(resetter: focusResetter))
        .onChange(of: session.destination) { _, _ in focusResetter.resetFocus() }
    }

    @ViewBuilder
    private func page(_ destination: SidebarDestination) -> some View {
        switch destination {
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

    private var windowTitle: String {
        switch session.destination {
        case .home: LerroInterfaceLocalization.string("首页", locale: locale)
        case .history: LerroInterfaceLocalization.string("历史", locale: locale)
        case .dictionary: LerroInterfaceLocalization.string("词典", locale: locale)
        case .appTones: LerroInterfaceLocalization.string("应用语气", locale: locale)
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

private extension View {
    /// A hidden page keeps its state but is invisible, ignores the pointer,
    /// and is skipped by VoiceOver. Keyboard focus is gated per control; see
    /// "Page lifecycle" in MainWindowComponents.
    func lerroPageVisibility(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

/// Holds the window of the page area so a page switch can drop keyboard focus
/// held by a control on the page being hidden.
@MainActor
private final class WindowFocusResetter {
    weak var window: NSWindow?

    func resetFocus() {
        window?.makeFirstResponder(nil)
    }
}

private struct WindowFocusResetterView: NSViewRepresentable {
    let resetter: WindowFocusResetter

    func makeNSView(context: Context) -> NSView {
        WindowTrackingView(resetter: resetter)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Records its window when it joins one; the view has no window when created.
private final class WindowTrackingView: NSView {
    private let resetter: WindowFocusResetter

    init(resetter: WindowFocusResetter) {
        self.resetter = resetter
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resetter.window = window
    }
}

/// Gives the main window an empty unified toolbar. macOS then draws the
/// window with its toolbar corner radius (26 pt) and centres the traffic
/// lights on y = 26, the middle line of every page header.
private struct MainWindowToolbarInstaller: NSViewRepresentable {
    @Binding var bandHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = ToolbarInstallingView()
        view.onInstall = { height in bandHeight = height }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ToolbarInstallingView: NSView {
    var onInstall: (CGFloat) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window.toolbar == nil else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "LerroMainWindow")
        window.toolbarStyle = .unified
        let bandHeight = window.frame.height - window.contentLayoutRect.height
        DispatchQueue.main.async { [onInstall] in onInstall(bandHeight) }
    }
}
