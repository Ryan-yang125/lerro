import SwiftUI
import LerroCore

/// Top applications by words, with real app icons.
struct HomeTopAppsCard: View {
    let apps: [HomeStatistics.AppShare]
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("常用应用")
                .font(LerroFont.cardTitle)
                .foregroundStyle(LerroTheme.text)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 9) {
                ForEach(apps) { app in
                    row(app)
                }
            }
        }
        .homeCard(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
    }

    private func row(_ app: HomeStatistics.AppShare) -> some View {
        let top = Double(apps.first?.words ?? 0)
        let ratio = top > 0 ? Double(app.words) / top : 0
        return HStack(spacing: 8) {
            LerroAppIcon(bundleIdentifier: app.bundleIdentifier, name: app.name, size: 20)
            Text(verbatim: app.name)
                .font(LerroFont.body)
                .foregroundStyle(LerroTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 84, alignment: .leading)
            Capsule()
                .fill(LerroTheme.fillContainerTough)
                .frame(height: 7)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(LerroTheme.accent)
                            .frame(width: max(7, proxy.size.width * ratio))
                    }
                }
            Text(verbatim: percentage(app.share))
                .font(LerroFont.caption)
                .monospacedDigit()
                .foregroundStyle(LerroTheme.metadataText)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(app.name) \(percentage(app.share))"))
    }

    private func percentage(_ share: Double) -> String {
        share < 0.01 ? "<1%" : "\(Int((share * 100).rounded()))%"
    }
}

/// 24 hourly bars by dictation count; the busiest quarter uses the accent color.
struct HomeHoursCard: View {
    let hourCounts: [Int]
    let peakHour: Int?
    @Environment(\.locale) private var locale

    private let chartHeight: CGFloat = 84

    var body: some View {
        let maximum = max(hourCounts.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 12) {
            Text("说话时段")
                .font(LerroFont.cardTitle)
                .foregroundStyle(LerroTheme.text)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<24, id: \.self) { hour in
                        let count = hour < hourCounts.count ? hourCounts[hour] : 0
                        UnevenRoundedRectangle(
                            topLeadingRadius: 3,
                            bottomLeadingRadius: 1,
                            bottomTrailingRadius: 1,
                            topTrailingRadius: 3,
                            style: .continuous
                        )
                        .fill(count > 0 && Double(count) >= Double(maximum) * 0.75
                              ? LerroTheme.accent
                              : LerroTheme.fillContainerTough)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, chartHeight * CGFloat(count) / CGFloat(maximum)))
                    }
                }
                .frame(height: chartHeight, alignment: .bottom)
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text(verbatim: "\(hour)")
                        if hour != 24 { Spacer(minLength: 0) }
                    }
                }
                .font(LerroFont.axisLabel)
                .foregroundStyle(LerroTheme.metadataText)
            }
            .accessibilityHidden(true)
            if let peakHour {
                peakLine(peakHour)
            }
        }
        .homeCard(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .accessibilityElement(children: .combine)
    }

    private func peakLine(_ hour: Int) -> some View {
        let formatted = LerroInterfaceLocalization.format(
            "最常在 **%@** 点左右说话",
            locale: locale,
            arguments: "\(hour)"
        )
        let text = (try? AttributedString(markdown: formatted)) ?? AttributedString(formatted)
        return Text(text)
            .font(LerroFont.caption)
            .foregroundStyle(LerroTheme.secondaryText)
            .padding(.top, 4)
    }
}
