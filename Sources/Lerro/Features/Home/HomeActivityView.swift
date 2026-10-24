import SwiftUI
import LerroCore

/// Streak numbers, today's words and the 53-week activity heatmap.
struct HomeActivityCard: View {
    let statistics: HomeStatistics
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 40) {
                metric(statistics.activeDays, title: "活跃天数")
                metric(statistics.currentStreak, title: "当前连续")
                metric(statistics.longestStreak, title: "最长连续")
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    value(statistics.today.totalWords, unit: "字")
                    Text("今天")
                        .font(LerroFont.caption)
                        .foregroundStyle(LerroTheme.metadataText)
                }
                .accessibilityElement(children: .combine)
            }
            HomeHeatmap(weeks: statistics.weeks, monthLabels: statistics.monthLabels)
            HStack {
                Text(verbatim: LerroInterfaceLocalization.format(
                    "过去一年 · %@ 天有听写",
                    locale: locale,
                    arguments: statistics.activeDays.formatted(.number.locale(locale))
                ))
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("少")
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(LerroTheme.heatmap[level])
                            .frame(width: 10, height: 10)
                    }
                    Text("多")
                }
                .accessibilityHidden(true)
            }
            .font(LerroFont.footnote)
            .foregroundStyle(LerroTheme.metadataText)
        }
        .homeCard()
    }

    private func metric(_ number: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value(number, unit: "天")
            Text(LocalizedStringKey(title))
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.metadataText)
        }
        .accessibilityElement(children: .combine)
    }

    private func value(_ number: Int, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: number.formatted(.number.locale(locale)))
                .font(LerroFont.streakValue)
                .foregroundStyle(LerroTheme.text)
            Text(verbatim: LerroInterfaceLocalization.string(unit, locale: locale))
                .font(LerroFont.streakUnit)
                .foregroundStyle(LerroTheme.secondaryText)
        }
        .lineLimit(1)
    }
}

/// 53 week columns by 7 weekday rows. Cell size shrinks to fit the card width.
private struct HomeHeatmap: View {
    let weeks: [[HomeStatistics.Day]]
    let monthLabels: [HomeStatistics.MonthLabel]
    @Environment(\.locale) private var locale
    /// Changes only when the fitted cell size changes, so resizing the window
    /// while the cells are at full size does not update or redraw the heatmap.
    @State private var cell: CGFloat = 11
    @State private var hovered: Position?
    @State private var tooltipSize: CGSize = .zero

    private struct Position: Equatable {
        var column: Int
        var row: Int
    }

    private let gap: CGFloat = 3
    private let maximumCell: CGFloat = 11
    private let monthRowHeight: CGFloat = 14
    /// Room around the cells for today's outline and the enlarged hovered cell.
    private let margin: CGFloat = 4

    private var columns: Int { max(weeks.count, 1) }

    /// Cell size for the available width, rounded down to a quarter point.
    private func fittedCell(for width: CGFloat) -> CGFloat {
        let fitted = (width - 2 * margin - gap * CGFloat(columns - 1)) / CGFloat(columns)
        return max(6, min(maximumCell, (fitted * 4).rounded(.down) / 4))
    }

    private var gridWidth: CGFloat { 2 * margin + CGFloat(columns) * cell + gap * CGFloat(columns - 1) }
    private var pitch: CGFloat { cell + gap }
    private var gridHeight: CGFloat { 7 * cell + 6 * gap }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            weekdayLabels
            VStack(alignment: .leading, spacing: 2) {
                monthRow
                grid
            }
            .onGeometryChange(for: CGFloat.self) { fittedCell(for: $0.size.width) } action: { cell = $0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
    }

    // MARK: Labels

    private var weekdayLabels: some View {
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(verbatim: [1, 3, 5].contains(row) && row < symbols.count ? symbols[row] : "")
                    .font(LerroFont.axisLabel)
                    .foregroundStyle(LerroTheme.metadataText)
                    .frame(height: cell, alignment: .center)
            }
        }
        .frame(width: 22, alignment: .leading)
        .padding(.top, monthRowHeight + 2 + margin)
    }

    private var monthRow: some View {
        let symbols = formatter.shortStandaloneMonthSymbols ?? []
        return ZStack(alignment: .topLeading) {
            ForEach(monthLabels, id: \.column) { label in
                if label.month >= 1, label.month <= symbols.count {
                    Text(verbatim: symbols[label.month - 1])
                        .font(LerroFont.axisLabel)
                        .foregroundStyle(LerroTheme.metadataText)
                        .fixedSize()
                        .offset(x: margin + CGFloat(label.column) * pitch)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: monthRowHeight, alignment: .topLeading)
    }

    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        return formatter
    }

    // MARK: Grid

    private var grid: some View {
        Canvas { context, _ in
            let radius = cell * 3 / 11
            for (column, week) in weeks.enumerated() {
                for (row, day) in week.enumerated() {
                    let rect = CGRect(
                        x: margin + CGFloat(column) * pitch,
                        y: margin + CGFloat(row) * pitch,
                        width: cell,
                        height: cell
                    )
                    if day.isFuture {
                        context.stroke(
                            Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius, style: .continuous),
                            with: .color(LerroTheme.fillContainerTough),
                            lineWidth: 1
                        )
                    } else {
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                            with: .color(LerroTheme.heatmap[min(max(day.level, 0), 4)])
                        )
                    }
                    if day.isToday {
                        context.stroke(
                            Path(
                                roundedRect: rect.insetBy(dx: -2, dy: -2),
                                cornerRadius: radius + 2,
                                style: .continuous
                            ),
                            with: .color(LerroTheme.accent),
                            lineWidth: 1
                        )
                    }
                }
            }
            if let hovered, weeks.indices.contains(hovered.column), weeks[hovered.column].indices.contains(hovered.row) {
                let day = weeks[hovered.column][hovered.row]
                let grow = cell * 0.175
                let rect = CGRect(
                    x: margin + CGFloat(hovered.column) * pitch - grow,
                    y: margin + CGFloat(hovered.row) * pitch - grow,
                    width: cell + 2 * grow,
                    height: cell + 2 * grow
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: radius * 1.35, style: .continuous),
                    with: .color(LerroTheme.heatmap[min(max(day.level, 0), 4)])
                )
            }
        }
        .frame(height: gridHeight + 2 * margin)
        // Never wider than the cells, and free to shrink so the card width
        // decides the cell size (onGeometryChange above).
        .frame(maxWidth: gridWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                let next = position(at: point)
                if next != hovered { hovered = next }
            case .ended:
                hovered = nil
            }
        }
        .overlay(alignment: .topLeading) {
            if let hovered, weeks.indices.contains(hovered.column), weeks[hovered.column].indices.contains(hovered.row) {
                tooltip(for: weeks[hovered.column][hovered.row], at: hovered)
            }
        }
    }

    private func position(at point: CGPoint) -> Position? {
        let x = point.x - margin
        let y = point.y - margin
        guard x >= 0, y >= 0 else { return nil }
        let column = Int(x / pitch)
        let row = Int(y / pitch)
        guard weeks.indices.contains(column), weeks[column].indices.contains(row), !weeks[column][row].isFuture else {
            return nil
        }
        return Position(column: column, row: row)
    }

    private func tooltip(for day: HomeStatistics.Day, at position: Position) -> some View {
        let centerX = margin + CGFloat(position.column) * pitch + cell / 2
        let top = margin + CGFloat(position.row) * pitch
        let x = min(max(0, centerX - tooltipSize.width / 2), max(0, gridWidth - tooltipSize.width))
        return HomeHeatmapTooltip(text: tooltipText(for: day))
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tooltipSize = $0 }
            .offset(x: x, y: top - tooltipSize.height - 6)
            .allowsHitTesting(false)
    }

    private func tooltipText(for day: HomeStatistics.Day) -> String {
        let date = day.date.formatted(.dateTime.month().day().locale(locale))
        if day.dictations > 0 || day.words > 0 {
            return LerroInterfaceLocalization.format(
                "%@ · %@ 字 · %lld 次",
                locale: locale,
                arguments: date,
                day.words.formatted(.number.locale(locale)),
                day.dictations
            )
        }
        return LerroInterfaceLocalization.format("%@ · 没有听写", locale: locale, arguments: date)
    }

    private var accessibilitySummary: String {
        let active = weeks.reduce(0) { $0 + $1.filter { $0.dictations > 0 }.count }
        return LerroInterfaceLocalization.format(
            "过去一年 · %@ 天有听写",
            locale: locale,
            arguments: active.formatted(.number.locale(locale))
        )
    }
}

private struct HomeHeatmapTooltip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(LerroFont.caption)
            .foregroundStyle(LerroTheme.hudPaper)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LerroTheme.hudInk, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            }
    }
}
