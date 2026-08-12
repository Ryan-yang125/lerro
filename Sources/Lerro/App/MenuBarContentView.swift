import AppKit
import SwiftUI
import LerroCore

struct MenuBarContentView: View {
    let session: AppSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: {}) {
            Label {
                Text(verbatim: statusMenuTitle)
            } icon: {
                Image(systemName: statusSystemImage)
            }
        }
        .disabled(true)

        Divider()

        captureItem(.dictation, title: "听写", fallbackShortcut: "Fn", icon: "waveform")
        captureItem(
            .translation,
            title: "翻译",
            fallbackShortcut: "Fn ⇧",
            icon: "character.bubble"
        )
        if session.isCaptureCancellationAvailable {
            Button {
                session.cancelCapture()
            } label: {
                Label("取消当前会话", systemImage: "xmark.circle")
            }
        }

        Divider()

        Button {
            showSettings(.settings)
        } label: {
            Label {
                Text(verbatim: microphoneStatusTitle)
            } icon: {
                Image(systemName: "mic")
            }
        }

        Button {
            showSettings(.intelligence)
        } label: {
            Label {
                Text(verbatim: intelligenceMenuTitle)
            } icon: {
                Image(systemName: intelligenceIcon)
            }
        }

        Divider()

        Button {
            openMainWindow()
        } label: {
            Label("打开 Lerro", systemImage: "arrow.up.forward.app")
        }

        Button {
            showSettings(.settings)
        } label: {
            Label("设置…", systemImage: "gearshape")
        }

        Button {
            session.dismissSettings()
            session.isOnboardingPresented = true
            openMainWindow()
        } label: {
            Label("重新查看引导", systemImage: "questionmark.circle")
        }

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出 Lerro", systemImage: "power")
        }
    }

    private func captureItem(
        _ mode: LerroCore.CaptureMode,
        title: String,
        fallbackShortcut: String,
        icon: String
    ) -> some View {
        let localizedTitle = localized(title)
        let activeTitle = switch mode {
        case .dictation: localized("完成听写")
        case .translation: localized("完成翻译")
        case .ask: localized("完成指令")
        }
        return Button {
            session.toggleCapture(mode)
        } label: {
            Label {
                Text(verbatim: LerroNativeMenuPresentation.captureTitle(
                    title: localizedTitle,
                    activeTitle: activeTitle,
                    shortcut: shortcut(for: mode, fallback: localized(fallbackShortcut)),
                    phase: session.phase,
                    activeMode: session.activeMode,
                    mode: mode
                ))
            } icon: {
                Image(systemName: icon)
            }
        }
        .disabled(!LerroNativeMenuPresentation.captureActionEnabled(
            mode: mode,
            phase: session.phase,
            activeMode: session.activeMode
        ))
    }

    private func shortcut(for mode: CaptureMode, fallback: String) -> String {
        let action: HotkeyAction = switch mode {
        case .dictation: .dictate
        case .translation: .translate
        case .ask: .ask
        }
        return session.preferences.hotkeys.first(where: { $0.action == action })?.displayName
            ?? fallback
    }

    private func showSettings(_ destination: SettingsDestination) {
        openWindow(id: "main")
        session.presentSettings(destination)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var microphoneStatusTitle: String {
        let device = session.audioInputDevices.first(where: \.isDefault)?.name ?? localized("系统麦克风")
        let permission = localized(session.microphonePermission ? "已授权" : "待授权")
        return LerroNativeMenuPresentation.shortTitle("\(device) · \(permission)")
    }

    private var statusMenuTitle: String {
        "Lerro · \(localized(statusTitleKey))"
    }

    private var intelligenceMenuTitle: String {
        "\(localized("智能处理")) · \(intelligenceStatus)"
    }

    private var statusTitleKey: String {
        switch session.phase {
        case .idle, .success, .cancelled: "就绪"
        case .listening: "正在听"
        case .transcribing, .enhancing, .inserting: "处理中"
        case .failed: "需要处理"
        }
    }

    private var statusSystemImage: String {
        switch session.phase {
        case .idle, .success, .cancelled: "checkmark.circle"
        case .listening: "waveform.circle.fill"
        case .transcribing, .enhancing, .inserting: "ellipsis.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var intelligenceIcon: String {
        switch session.preferences.intelligenceMode {
        case .raw: "waveform"
        case .local: "cpu"
        case .remote: "network"
        }
    }

    private var intelligenceStatus: String {
        switch session.preferences.intelligenceMode {
        case .raw:
            localized("原始听写")
        case .remote:
            session.preferences.remoteProvider.provider.lerroDisplayName
        case .local:
            switch session.modelStatus.state {
            case .loaded: localized("本地 AI 已就绪")
            case .loading, .downloading: localized("本地 AI 准备中")
            case .paused: localized("本地 AI 下载已暂停")
            case .failed: localized("本地 AI 需重试")
            case .ready: localized("本地 AI 可加载")
            case .unavailable: localized("本地 AI 未下载")
            }
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

enum LerroNativeMenuPresentation {
    static let maximumTitleCharacters = 30

    static func captureActionEnabled(
        mode: CaptureMode,
        phase: CapturePhase,
        activeMode: CaptureMode
    ) -> Bool {
        switch phase {
        case .listening:
            mode == activeMode
        case .transcribing, .enhancing, .inserting:
            false
        case .idle, .success, .failed, .cancelled:
            true
        }
    }

    static func captureTitle(
        title: String,
        activeTitle: String,
        shortcut: String,
        phase: CapturePhase,
        activeMode: CaptureMode,
        mode: CaptureMode
    ) -> String {
        let actionTitle = phase == .listening && activeMode == mode ? activeTitle : title
        return shortTitle("\(actionTitle) · \(shortcut)")
    }

    static func shortTitle(_ title: String) -> String {
        guard title.count > maximumTitleCharacters else { return title }
        return String(title.prefix(maximumTitleCharacters - 1)) + "…"
    }
}
