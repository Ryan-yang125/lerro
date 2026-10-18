import AppKit
import SwiftUI
import LerroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppUpdateController.shared.startIfEligible()
        MenuBarPanelFocus.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct LerroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession()
    @State private var menuBarAnimator = LerroMenuBarAnimator()

    var body: some Scene {
        Window("Lerro", id: "main") {
            RootView(session: session)
                .environment(\.locale, LerroInterfaceLocalization.locale(for: session.preferences.appLanguage))
                .task { await session.start() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    Task { await session.applicationDidBecomeActive() }
                }
        }
        .defaultSize(width: 1080, height: 750)
        .windowResizability(.contentMinSize)
        .commands { LerroCommands(session: session) }

        Settings {
            LerroSettingsView(session: session)
                .environment(\.locale, LerroInterfaceLocalization.locale(for: session.preferences.appLanguage))
                .tint(LerroTheme.accent)
        }

        MenuBarExtra {
            MenuBarPanelView(session: session)
                .environment(\.locale, LerroInterfaceLocalization.locale(for: session.preferences.appLanguage))
        } label: {
            LerroMenuBarIcon(
                assetName: menuBarAnimator.assetName,
                fallbackSystemName: LerroMenuBarPresentation.systemImage(for: session.phase),
                accessibilityLabel: LerroMenuBarPresentation.accessibilityLabel(
                    for: session.phase,
                    locale: LerroInterfaceLocalization.locale(for: session.preferences.appLanguage)
                )
            )
            .onChange(of: session.phase, initial: true) { _, phase in
                menuBarAnimator.update(phase: phase)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private struct LerroCommands: Commands {
    let session: AppSession

    var body: some Commands {
        CommandMenu("Lerro") {
            Button { session.toggleCapture(.dictation) } label: { Text(verbatim: copy("开始听写")) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button { session.toggleCapture(.translation) } label: { Text(verbatim: copy("开始翻译")) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button { session.pasteLastResult() } label: { Text(verbatim: copy("粘贴上次结果")) }
                .keyboardShortcut("v", modifiers: [.command, .control])
            Divider()
            Button { AppUpdateController.shared.checkForUpdates() } label: { Text(verbatim: copy("检查更新…")) }
        }
    }

    private func copy(_ key: String) -> String {
        LerroInterfaceLocalization.string(
            key,
            locale: LerroInterfaceLocalization.locale(for: session.preferences.appLanguage)
        )
    }
}

enum LerroMenuBarPresentation {
    static func systemImage(for phase: CapturePhase) -> String {
        switch phase {
        case .idle, .success, .cancelled: "waveform"
        case .listening: "waveform.circle.fill"
        case .transcribing, .enhancing, .inserting: "ellipsis.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    static func accessibilityLabel(for phase: CapturePhase, locale: Locale) -> String {
        let key: String
        switch phase {
        case .idle, .success, .cancelled: key = "Lerro，空闲"
        case .listening: key = "Lerro，正在听写"
        case .transcribing, .enhancing, .inserting: key = "Lerro，正在处理"
        case .failed: key = "Lerro，需要处理"
        }
        return LerroInterfaceLocalization.string(key, locale: locale)
    }
}
