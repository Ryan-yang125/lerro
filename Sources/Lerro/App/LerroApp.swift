import AppKit
import SwiftUI
import LerroCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppUpdateController.shared.startIfEligible()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct LerroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession()

    var body: some Scene {
        Window("Lerro", id: "main") {
            RootView(session: session)
                .background(TranslationResourcePreparationHost(session: session))
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

        MenuBarExtra {
            MenuBarContentView(session: session)
        } label: {
            LerroMenuBarIcon(
                assetName: LerroMenuBarPresentation.assetName(for: session.phase),
                fallbackSystemName: LerroMenuBarPresentation.systemImage(for: session.phase),
                accessibilityLabel: LerroMenuBarPresentation.accessibilityLabel(for: session.phase)
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
private struct LerroCommands: Commands {
    let session: AppSession
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                presentSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

        }

        CommandMenu("Lerro") {
            Button("开始听写") { session.toggleCapture(.dictation) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("开始翻译") { session.toggleCapture(.translation) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("开始问答") { session.toggleCapture(.ask) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Divider()
            Button("粘贴上次结果") { session.pasteLastResult() }
                .keyboardShortcut("v", modifiers: [.command, .control])
            Divider()
            Button("检查更新…") { AppUpdateController.shared.checkForUpdates() }
        }
    }

    private func presentSettings() {
        openWindow(id: "main")
        session.presentSettings(SettingsEntryPoint.settings)
        NSApp.activate(ignoringOtherApps: true)
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

    static func assetName(for phase: CapturePhase) -> String {
        switch phase {
        case .idle, .success, .cancelled: "LerroMenuIdleTemplate"
        case .listening: "LerroMenuListeningTemplate"
        case .transcribing, .enhancing, .inserting: "LerroMenuProcessingTemplate"
        case .failed: "LerroMenuErrorTemplate"
        }
    }

    static func accessibilityLabel(for phase: CapturePhase) -> String {
        switch phase {
        case .idle, .success, .cancelled: "Lerro，空闲"
        case .listening: "Lerro，正在听写"
        case .transcribing, .enhancing, .inserting: "Lerro，正在处理"
        case .failed: "Lerro，需要处理"
        }
    }
}
