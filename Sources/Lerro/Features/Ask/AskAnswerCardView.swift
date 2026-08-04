import SwiftUI

struct AskAnswerCardView: View {
    @Bindable var session: AppSession
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var promptExpanded = false
    @State private var promptCopied = false
    @State private var answerCopied = false

    var body: some View {
        VStack(spacing: 16) {
            topBar
                .frame(height: 20)

            promptSection

            answerSection
                .frame(height: answerSectionHeight)
        }
        .padding(16)
        .frame(maxWidth: 744, minHeight: 400, maxHeight: 700)
        .background(reduceTransparency ? AnyShapeStyle(LerroTheme.elevated) : AnyShapeStyle(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LerroTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 24, y: 12)
        .padding(.horizontal, 8)
        .padding(.top, 24)
        .padding(.bottom, 64)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: AskCardHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(AskCardHeightPreferenceKey.self) { measuredHeight in
            guard measuredHeight > 0 else { return }
            session.resizeAnswerPanel(contentHeight: measuredHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var topBar: some View {
        ZStack {
            HStack(spacing: 6) {
                LerroMark(size: 18, foregroundStyle: LerroTheme.secondaryText)
                Text("Lerro")
                    .font(LerroTheme.font(14, weight: .semibold))
            }
            .foregroundStyle(LerroTheme.secondaryText)
            .frame(width: 91)

            HStack {
                Spacer()
                Button { session.closeAnswer() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LerroTheme.secondaryText)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LerroPressButtonStyle())
                .help("关闭 · Esc")
                .accessibilityLabel(localized("关闭问答面板"))
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .frame(width: 14, height: 22)
                Group {
                    if session.answerQuestion.isEmpty {
                        Text("请说出问题")
                    } else {
                        Text(verbatim: session.answerQuestion)
                    }
                }
                    .font(LerroTheme.font(14))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineSpacing(4)
                    .lineLimit(promptExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    session.copyText(session.answerQuestion)
                    markPromptCopied()
                } label: {
                    Image(systemName: promptCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(promptCopied ? LerroTheme.green : LerroTheme.tertiaryText)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(LerroPressButtonStyle())
                .help("复制问题")
                .accessibilityLabel(localized(promptCopied ? "问题已复制" : "复制问题"))
                .disabled(session.answerQuestion.isEmpty)
            }
            if session.answerQuestion.count > 110 {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        promptExpanded.toggle()
                    }
                } label: {
                    Text(LocalizedStringKey(promptExpanded ? "收起" : "更多"))
                }
                .buttonStyle(LerroPressButtonStyle())
                .font(LerroTheme.font(12, weight: .medium))
                .foregroundStyle(LerroTheme.secondaryText)
                .padding(.leading, 22)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var answerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                Text("回答")
                    .font(LerroTheme.font(16, weight: .semibold))
                Spacer()
                Button {
                    if let answer = session.answerText { session.copyText(answer) }
                    markAnswerCopied()
                } label: {
                    Image(systemName: answerCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(answerCopied ? LerroTheme.green : LerroTheme.tertiaryText)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(LerroPressButtonStyle())
                .help("复制回答")
                .accessibilityLabel(localized(answerCopied ? "回答已复制" : "复制回答"))
                .disabled(session.answerText?.isEmpty != false)
            }
            .foregroundStyle(LerroTheme.secondaryText)
            .padding(.horizontal, 16)
            .frame(height: 51)

            Divider().overlay(LerroTheme.thinBorder)

            ScrollView {
                if let answer = session.answerText, !answer.isEmpty {
                    Text(markdown(answer))
                        .font(LerroTheme.font(17))
                        .foregroundStyle(LerroTheme.text)
                        .lineSpacing(11)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在生成回答…")
                            .font(LerroTheme.font(15))
                            .foregroundStyle(LerroTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .background(LerroTheme.main)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LerroTheme.thinBorder, lineWidth: 1)
        }
    }

    private func markPromptCopied() {
        promptCopied = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            promptCopied = false
        }
    }

    private func markAnswerCopied() {
        answerCopied = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            answerCopied = false
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }

    private var answerSectionHeight: CGFloat {
        let answerCharacters = session.answerText?.count ?? 0
        let estimatedLines = max(3, ceil(Double(answerCharacters) / 58))
        return min(560, max(180, 74 + estimatedLines * 31))
    }

    private func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(source)
    }
}

private struct AskCardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 500

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
