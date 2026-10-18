import SwiftUI
import LerroCore

/// Four usage numbers for the selected range and the 7-day word chart.
struct HomeHeroView: View {
    let summary: UsageSummary
    let rangeTitle: String
    let dailyWords: [DailyWordCount]
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 28) {
                    stats.fixedSize()
                    Spacer(minLength: 0)
                    HomeWeekChart(dailyWords: dailyWords)
                        .frame(minWidth: 180, maxWidth: 280)
                }
                VStack(alignment: .leading, spacing: 20) {
                    stats.fixedSize()
                    HomeWeekChart(dailyWords: dailyWords)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 22)
            Divider()
        }
    }

    private var stats: some View {
        let duration = Self.duration(summary.totalDuration)
        let saved = Self.duration(summary.savedSeconds)
        return HStack(alignment: .bottom, spacing: 36) {
            HomeStat(
                rangeTitle: rangeTitle,
                value: summary.totalWords.formatted(.number.locale(locale)),
                unit: nil,
                label: localized("字")
            )
            HomeStat(
                rangeTitle: rangeTitle,
                value: duration.value,
                unit: localized(duration.unit),
                label: localized("口述")
            )
            HomeStat(
                rangeTitle: rangeTitle,
                value: saved.value,
                unit: localized(saved.unit),
                label: localized("比打字省下")
            )
            HomeStat(
                rangeTitle: rangeTitle,
                value: summary.averageWordsPerMinute.formatted(.number.locale(locale)),
                unit: nil,
                label: localized("字 / 分钟")
            )
        }
    }

    private static func duration(_ seconds: TimeInterval) -> (value: String, unit: String) {
        if seconds >= 3_600 { return (String(format: "%.1f", seconds / 3_600), "小时") }
        if seconds >= 60 { return ("\(Int(seconds / 60))", "分钟") }
        return ("\(Int(seconds))", "秒")
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct HomeStat: View {
    let rangeTitle: String
    let value: String
    let unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(LerroFont.stat)
                    .foregroundStyle(LerroTheme.text)
                if let unit {
                    Text(verbatim: unit)
                        .font(LerroFont.statUnit)
                        .foregroundStyle(LerroTheme.secondaryText)
                }
            }
            Text(verbatim: label)
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(rangeTitle) \(value)\(unit.map { " \($0)" } ?? "") \(label)"))
    }
}

/// Seven rounded bars, heights relative to the busiest day; today uses the accent color.
private struct HomeWeekChart: View {
    let dailyWords: [DailyWordCount]
    @Environment(\.locale) private var locale

    private let chartHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(dailyWords.enumerated()), id: \.offset) { index, item in
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 2,
                        bottomTrailingRadius: 2,
                        topTrailingRadius: 4,
                        style: .continuous
                    )
                    .fill(index == dailyWords.count - 1 ? LerroTheme.accent : LerroTheme.fillSelected)
                    .frame(height: barHeight(item.words))
                }
            }
            .frame(height: chartHeight, alignment: .bottom)
            HStack(spacing: 10) {
                ForEach(Array(dailyWords.enumerated()), id: \.offset) { index, item in
                    Text(verbatim: dayLabel(item.day, isToday: index == dailyWords.count - 1))
                        .font(LerroFont.footnote)
                        .foregroundStyle(LerroTheme.metadataText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
    }

    private func barHeight(_ words: Int) -> CGFloat {
        let maximum = dailyWords.map(\.words).max() ?? 0
        guard maximum > 0 else { return 4 }
        return max(4, chartHeight * CGFloat(words) / CGFloat(maximum))
    }

    private func dayLabel(_ day: Date, isToday: Bool) -> String {
        if isToday { return LerroInterfaceLocalization.string("今天", locale: locale) }
        return day.formatted(.dateTime.weekday(.narrow).locale(locale))
    }

    private var accessibilityDescription: String {
        let unit = LerroInterfaceLocalization.string("字", locale: locale)
        let days = dailyWords.enumerated().map { index, item in
            let name = index == dailyWords.count - 1
                ? LerroInterfaceLocalization.string("今天", locale: locale)
                : item.day.formatted(.dateTime.weekday(.wide).locale(locale))
            return "\(name) \(item.words) \(unit)"
        }
        let title = LerroInterfaceLocalization.string("近 7 天字数", locale: locale)
        return ([title] + days).joined(separator: "，")
    }
}
