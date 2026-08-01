import AppKit
import SwiftUI
import LerroCore

struct MenuBarContentView: View {
    let session: AppSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(action: {}) {
            Label("Lerro · \(statusTitle)", systemImage: statusSystemImage)
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
        captureItem(.ask, title: "问答", fallbackShortcut: "Fn Space", icon: "sparkles")

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
            Label(microphoneStatusTitle, systemImage: "mic")
        }

        Button {
            showSettings(.intelligence)
        } label: {
            Label("智能处理 · \(intelligenceStatus)", systemImage: intelligenceIcon)
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
        Button {
            session.toggleCapture(mode)
        } label: {
            Label(
                LerroNativeMenuPresentation.captureTitle(
                    title: title,
                    shortcut: shortcut(for: mode, fallback: fallbackShortcut),
                    phase: session.phase,
                    activeMode: session.activeMode,
                    mode: mode
                ),
                systemImage: icon
            )
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
        let device = session.audioInputDevices.first(where: \.isDefault)?.name ?? "系统麦克风"
        let permission = session.microphonePermission ? "已授权" : "待授权"
        return LerroNativeMenuPresentation.shortTitle("\(device) · \(permission)")
    }

    private var statusTitle: String {
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
            "原始听写"
        case .remote:
            session.preferences.remoteProvider.provider.lerroDisplayName
        case .local:
            switch session.modelStatus.state {
            case .loaded: "本地 AI 已就绪"
            case .loading, .downloading: "本地 AI 准备中"
            case .failed: "本地 AI 需重试"
            case .ready: "本地 AI 可加载"
            case .unavailable: "本地 AI 未下载"
            }
        }
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
        shortcut: String,
        phase: CapturePhase,
        activeMode: CaptureMode,
        mode: CaptureMode
    ) -> String {
        let actionTitle = phase == .listening && activeMode == mode
            ? "完成\(title)"
            : title
        return shortTitle("\(actionTitle) · \(shortcut)")
    }

    static func shortTitle(_ title: String) -> String {
        guard title.count > maximumTitleCharacters else { return title }
        return String(title.prefix(maximumTitleCharacters - 1)) + "…"
    }
}
