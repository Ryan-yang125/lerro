import AppKit
import SwiftUI
import LerroCore

/// One-line orange notice at the top of every settings page. Shown only when
/// the microphone or Accessibility permission is missing or the speech
/// resources are unavailable.
struct SettingsPermissionBanner: View {
    let session: AppSession

    private enum Issue {
        case microphone
        case accessibility
        case speechFailed
        case speechUnsupported

        var message: String {
            switch self {
            case .microphone: "麦克风权限被关掉了，听不到你说话"
            case .accessibility: "辅助功能权限被关掉了，字写不进其他 App"
            case .speechFailed: "语音资源没准备好"
            case .speechUnsupported: "这台 Mac 不支持当前的听写语言"
            }
        }

        var actionTitle: String? {
            switch self {
            case .microphone, .accessibility: "去打开"
            case .speechFailed: "重试"
            case .speechUnsupported: nil
            }
        }
    }

    private var issue: Issue? {
        if !session.microphonePermission { return .microphone }
        if !session.accessibilityPermission { return .accessibility }
        switch session.speechResourceStatus.state {
        case .failed: return .speechFailed
        case .unsupported: return .speechUnsupported
        case .ready, .available, .downloading: return nil
        }
    }

    var body: some View {
        if let issue {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(LerroTheme.warning)
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(issue.message))
                        .foregroundStyle(LerroTheme.text)
                    Spacer(minLength: 8)
                    if let actionTitle = issue.actionTitle {
                        Button(LocalizedStringKey(actionTitle)) { perform(issue) }
                            .buttonStyle(LerroButtonStyle(.primary, compact: true))
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(LerroTheme.warning.opacity(0.14))
        }
    }

    private func perform(_ issue: Issue) {
        switch issue {
        case .microphone:
            // Ask first; macOS only shows its prompt while access is undecided.
            Task {
                await session.refreshPermissions(prompt: true)
                if !session.microphonePermission {
                    openPrivacyPane("Privacy_Microphone")
                }
            }
        case .accessibility:
            openPrivacyPane("Privacy_Accessibility")
        case .speechFailed:
            session.prepareSpeechResources()
        case .speechUnsupported:
            break
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
