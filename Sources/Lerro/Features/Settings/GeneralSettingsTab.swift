import SwiftUI
import LerroCore

struct GeneralSettingsTab: View {
    @Bindable var session: AppSession

    var body: some View {
        Form {
            SettingsPermissionBanner(session: session)

            Section {
                Picker("外观", selection: $session.preferences.appearance) {
                    Text("跟随系统").tag(AppAppearance.system)
                    Text("浅色").tag(AppAppearance.light)
                    Text("深色").tag(AppAppearance.dark)
                }

                Picker("界面语言", selection: $session.preferences.appLanguage) {
                    Text("跟随系统").tag(AppLanguage.system)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese)
                    Text("English").tag(AppLanguage.english)
                }
            }

            Section {
                Toggle("提示音", isOn: $session.preferences.playsCaptureSounds)
                Toggle("在程序坞中显示", isOn: $session.preferences.showInDock)
                Toggle("登录时启动", isOn: $session.preferences.launchAtLogin)
            }
        }
        .settingsForm(height: 360)
    }
}
