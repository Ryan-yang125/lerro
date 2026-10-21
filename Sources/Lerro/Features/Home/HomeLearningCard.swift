import SwiftUI
import LerroCore

/// Terms Lerro learned this week and how many recognition errors the AI fixed.
struct HomeLearningCard: View {
    let summary: DictionaryWeekSummary
    let openDictionary: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: title)
                    .font(LerroFont.cardTitle)
                    .foregroundStyle(LerroTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: openDictionary) {
                    Text("去词典")
                        .font(LerroFont.caption)
                        .foregroundStyle(LerroTheme.accentText)
                }
                .buttonStyle(.plain)
            }
            if !summary.learnedTerms.isEmpty {
                AIChipFlow {
                    ForEach(summary.learnedTerms, id: \.self) { term in
                        LerroChip { Text(verbatim: term) }
                    }
                }
            }
            if summary.corrections > 0 {
                Text(verbatim: LerroInterfaceLocalization.format(
                    "AI 这周帮你纠正了 %lld 处识别错误，其中 %lld 处用到了词典里的词。",
                    locale: locale,
                    arguments: summary.corrections,
                    summary.correctionsUsingDictionary
                ))
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.metadataText)
            }
        }
        .homeCard(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
    }

    private var title: String {
        summary.learnedTerms.isEmpty
            ? LerroInterfaceLocalization.string("这周的识别纠正", locale: locale)
            : LerroInterfaceLocalization.format(
                "这周 Lerro 学会了 %lld 个词",
                locale: locale,
                arguments: summary.learnedTerms.count
            )
    }
}
