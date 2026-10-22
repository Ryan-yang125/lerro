import AppKit
import SwiftUI
import LerroCore

/// Root of the `Settings` scene. Five tabs, each a grouped `Form`.
struct LerroSettingsView: View {
    @Bindable var session: AppSession

    var body: some View {
        TabView(selection: $session.settingsTab) {
            GeneralSettingsTab(session: session)
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            DictationSettingsTab(session: session)
                .tabItem { Label("听写", systemImage: "mic") }
                .tag(SettingsTab.dictation)

            AISettingsTab(session: session)
                .tabItem { Label("AI 整理", systemImage: "sparkles") }
                .tag(SettingsTab.ai)

            PrivacySettingsTab(session: session)
                .tabItem { Label("隐私", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)

            AboutSettingsTab(session: session)
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .tint(LerroTheme.accent)
        .environment(\.locale, LerroInterfaceLocalization.locale(for: session.preferences.appLanguage))
        .onChange(of: session.preferences) { previous, updated in
            session.savePreferences(from: previous, to: updated)
        }
        .task {
            await session.refreshPermissions(prompt: false)
            await session.refreshLanguageResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await session.refreshPermissions(prompt: false) }
        }
    }
}

enum SettingsLayout {
    static let width: CGFloat = 620
    static let tallHeight: CGFloat = 580
}

extension View {
    /// Native grouped form at the fixed settings width.
    func settingsForm(height: CGFloat) -> some View {
        formStyle(.grouped)
            .frame(width: SettingsLayout.width, height: height)
    }
}

/// Row that behaves as a button and ends with a disclosure chevron.
struct SettingsLinkRow: View {
    let title: String
    var trailing: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(title))
                    .foregroundStyle(LerroTheme.text)
                Spacer(minLength: 12)
                if let trailing {
                    Text(verbatim: trailing)
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LerroTheme.tertiaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
