import AppKit
import SwiftUI

struct AboutSettingsTab: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow

    private static let releaseNotesURL = URL(string: "https://lerroapp.com/changelog")
    private static let websiteURL = URL(string: "https://lerroapp.com")
    private static let sourceURL = URL(string: "https://github.com/Ryan-yang125/lerro")

    var body: some View {
        Form {
            SettingsPermissionBanner(session: session)

            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text("Lerro")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.top, 8)
                    Text(verbatim: LerroInterfaceLocalization.format(
                        "版本 %@（%@）",
                        locale: locale,
                        arguments: AppMetadata.version, AppMetadata.build
                    ))
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
                    HStack(spacing: 8) {
                        Button("检查更新") {
                            AppUpdateController.shared.checkForUpdates()
                        }
                        .buttonStyle(LerroButtonStyle(.secondary))
                        Button("版本说明") {
                            if let url = Self.releaseNotesURL { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(LerroButtonStyle(.secondary))
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)

            Section {
                LabeledContent("官网") {
                    if let url = Self.websiteURL {
                        Link("lerroapp.com", destination: url)
                            .foregroundStyle(LerroTheme.accentText)
                    }
                }
                LabeledContent("源代码") {
                    if let url = Self.sourceURL {
                        Link("GitHub", destination: url)
                            .foregroundStyle(LerroTheme.accentText)
                    }
                }
            }

            Section {
                SettingsLinkRow(title: "重新查看引导") {
                    session.restartOnboarding()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                SettingsLinkRow(title: "隐私政策") { openBundledDocument("PrivacyPolicy") }
                SettingsLinkRow(title: "服务条款") { openBundledDocument("TermsOfUse") }
                SettingsLinkRow(title: "开源许可", trailing: "Apache-2.0") { openLicenses() }
            }
        }
        .settingsForm(height: 560)
    }

    private func openBundledDocument(_ resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "html") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openLicenses() {
        guard let url = Bundle.main.resourceURL?.appending(path: "ThirdPartyLicenses", directoryHint: .isDirectory),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }
}
