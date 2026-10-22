import SwiftUI

/// Main window sheet that walks through getting a DeepSeek Key.
struct AIGuideSheet: View {
    @Bindable var session: AppSession
    @State private var isConnected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("开启 AI 整理")
                .font(LerroFont.pageTitle)
                .foregroundStyle(LerroTheme.text)
                .accessibilityAddTraits(.isHeader)
            DeepSeekKeyGuide(session: session) {
                isConnected = true
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    session.isAIGuidePresented = false
                } label: {
                    Text("取消")
                }
                .buttonStyle(LerroButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
                Button {
                    session.isAIGuidePresented = false
                } label: {
                    Text("完成")
                }
                .buttonStyle(LerroButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!isConnected)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: 560)
        .tracking(LerroTheme.uiTracking)
        .tint(LerroTheme.accent)
    }
}
