import SwiftUI
import LerroCore

/// Shortcut keycaps and the microphone picker.
struct HomeStripView: View {
    @Bindable var session: AppSession

    private let actions: [(action: HotkeyAction, title: String)] = [
        (.dictate, "听写"),
        (.translate, "翻译"),
        (.pasteLastResult, "粘贴上一次")
    ]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(actions, id: \.action) { item in
                if let hotkey = session.preferences.hotkeys.first(where: { $0.action == item.action }) {
                    HStack(spacing: 6) {
                        LerroShortcutKeys(displayName: hotkey.displayName)
                        Text(LocalizedStringKey(item.title))
                            .font(LerroFont.caption)
                            .foregroundStyle(LerroTheme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 12)
            microphoneMenu
        }
        .padding(.vertical, 14)
    }

    private var microphoneMenu: some View {
        Menu {
            Button {
                session.selectMicrophone(uid: nil)
            } label: {
                if session.preferences.microphoneDeviceUID == nil {
                    Label("跟随系统", systemImage: "checkmark")
                } else {
                    Text("跟随系统")
                }
            }
            if !session.audioInputDevices.isEmpty {
                Divider()
                ForEach(session.audioInputDevices) { device in
                    Button {
                        session.selectMicrophone(uid: device.uid)
                    } label: {
                        if session.preferences.microphoneDeviceUID == device.uid {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: device.name)
                        }
                    }
                }
            }
        } label: {
            LerroChip {
                LerroStatusDot(color: LerroTheme.green)
                Text(verbatim: session.currentMicrophoneName)
                    .lineLimit(1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("麦克风"))
        .accessibilityValue(Text(verbatim: session.currentMicrophoneName))
    }
}
