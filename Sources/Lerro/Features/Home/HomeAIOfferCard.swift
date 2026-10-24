import SwiftUI

/// Offer to turn on AI cleanup, shown until a DeepSeek Key exists or the user
/// dismisses it. The right side shows a before and after example.
struct HomeAIOfferCard: View {
    let startGuide: () -> Void
    let dismiss: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("开启 AI 整理")
                    .font(LerroFont.pageTitle)
                    .foregroundStyle(LerroTheme.text)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Button(action: startGuide) {
                        Text("三步开启")
                    }
                    .buttonStyle(LerroButtonStyle(.primary, compact: true))
                    Button(action: dismiss) {
                        Text("暂不开启")
                    }
                    .buttonStyle(LerroButtonStyle(.secondary, compact: true))
                }
            }
            .frame(width: 200, alignment: .leading)
            example
        }
        .homeCard(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
    }

    private var example: some View {
        HStack(spacing: 12) {
            Text(said)
                .foregroundStyle(LerroTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LerroTheme.tertiaryText)
                .accessibilityHidden(true)
            Text(verbatim: LerroInterfaceLocalization.string("周三下午四点开会，叫上 Laura。", locale: locale))
                .fontWeight(.medium)
                .foregroundStyle(LerroTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(LerroFont.body)
        .lineSpacing(2)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            LerroTheme.fillContainerThin,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// The localized example with each `[...]` span struck through.
    private var said: AttributedString {
        let source = LerroInterfaceLocalization.string("[嗯那个]周三下午[呃]四点开会，叫上[罗拉]", locale: locale)
        var result = AttributedString()
        var isStruck = false
        for piece in source.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "[" || $0 == "]" }) {
            var run = AttributedString(String(piece))
            if isStruck {
                run.strikethroughStyle = Text.LineStyle(pattern: .solid, color: LerroTheme.danger)
                run.foregroundColor = LerroTheme.tertiaryText
            }
            result.append(run)
            isStruck.toggle()
        }
        return result
    }
}
