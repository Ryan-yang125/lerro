import SwiftUI
import LerroCore

/// Total words dictated.
struct HomeHeaderView: View {
    let totalWords: Int
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: totalWords.formatted(.number.locale(locale)))
                        .font(LerroFont.heroNumber)
                        .tracking(-1.4)
                        .foregroundStyle(LerroTheme.text)
                    Text("字")
                        .font(LerroFont.heroUnit)
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text("累计听写字数")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LerroTheme.metadataText)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}

/// The dictate and translate shortcuts, shown in the Home toolbar.
struct HomeShortcutsView: View {
    let hotkeys: [HotkeyDefinition]

    private let actions: [(action: HotkeyAction, title: String)] = [
        (.dictate, "听写"),
        (.translate, "翻译")
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(actions, id: \.action) { item in
                if let hotkey = hotkeys.first(where: { $0.action == item.action }) {
                    HStack(spacing: 6) {
                        LerroShortcutKeys(displayName: hotkey.displayName)
                        Text(LocalizedStringKey(item.title))
                            .font(LerroFont.caption)
                            .foregroundStyle(LerroTheme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }
}

/// Saved time, speaking speed, dictation time and count, each with today's change.
struct HomeStatCards: View {
    let statistics: HomeStatistics
    @Environment(\.locale) private var locale

    var body: some View {
        let total = statistics.total
        let today = statistics.today
        LerroEqualColumns(spacing: 12) {
            HomeStatCard(
                parts: HomeFormat.duration(total.savedSeconds, locale: locale),
                title: "比打字省下",
                today: today.savedSeconds >= 30
                    ? todayLine("+" + HomeFormat.minutes(today.savedSeconds, locale: locale))
                    : nil
            )
            HomeStatCard(
                parts: [HomeQuantityPart(
                    id: 0,
                    value: total.averageWordsPerMinute.formatted(.number.locale(locale)),
                    unit: localized("字 / 分钟")
                )],
                title: "平均语速",
                today: today.totalDuration > 0
                    ? todayLine("\(today.averageWordsPerMinute.formatted(.number.locale(locale))) \(localized("字 / 分钟"))")
                    : nil
            )
            HomeStatCard(
                parts: HomeFormat.duration(total.totalDuration, locale: locale),
                title: "听写时长",
                today: today.totalDuration > 0
                    ? todayLine("+" + HomeFormat.minutes(today.totalDuration, locale: locale))
                    : nil
            )
            HomeStatCard(
                parts: [HomeQuantityPart(
                    id: 0,
                    value: statistics.totalDictations.formatted(.number.locale(locale)),
                    unit: localized("次")
                )],
                title: "听写次数",
                today: statistics.todayDictations > 0
                    ? todayLine("+\(statistics.todayDictations.formatted(.number.locale(locale)))")
                    : nil
            )
        }
    }

    private func todayLine(_ value: String) -> String {
        LerroInterfaceLocalization.format("今天 %@", locale: locale, arguments: value)
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct HomeStatCard: View {
    let parts: [HomeQuantityPart]
    let title: String
    /// Today's line, nil when there was no use today.
    let today: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ForEach(parts) { part in
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: part.value)
                            .font(LerroFont.cardValue)
                            .foregroundStyle(LerroTheme.text)
                        if !part.unit.isEmpty {
                            Text(verbatim: part.unit)
                                .font(LerroFont.cardUnit)
                                .foregroundStyle(LerroTheme.secondaryText)
                        }
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(LocalizedStringKey(title))
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.metadataText)
            Group {
                if let today {
                    Text(verbatim: today)
                        .font(LerroFont.cardDelta)
                        .foregroundStyle(LerroTheme.accentText)
                } else {
                    Text(verbatim: "—")
                        .font(LerroFont.caption)
                        .foregroundStyle(LerroTheme.tertiaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 7)
        }
        .homeCard(EdgeInsets(top: 16, leading: 18, bottom: 15, trailing: 18))
        .accessibilityElement(children: .combine)
    }
}
