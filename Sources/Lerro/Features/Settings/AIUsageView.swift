import AppKit
import Charts
import SwiftUI
import LerroCore

/// AI usage statistics from local records: tokens, estimated cost, per-feature
/// and per-model breakdowns. Second level of Settings > AI 整理.
struct AIUsageView: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow
    @State private var range: UsageRange = .week
    @State private var records: [AIUsageRecord] = []
    @State private var linkedEntries: [UUID: HistoryEntry] = [:]
    @State private var hasLoaded = false
    @State private var showClearConfirmation = false

    private static let loadedDays = 30
    private static let visibleCallLimit = 50

    var body: some View {
        let report = AIUsageStatistics.report(
            records: records,
            days: range.days,
            now: .now
        )
        let format = UsageFormat(locale: locale)
        let calls = visibleCalls()

        VStack(spacing: 0) {
            backBar

            Form {
                Section {
                    Picker("范围", selection: $range) {
                        ForEach(UsageRange.allCases) { option in
                            Text(LocalizedStringKey(option.title)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if hasLoaded && report.totals.requests == 0 {
                    Section {
                        LerroEmptyState(title: "还没有 AI 用量")
                            .frame(height: 220)
                    }
                } else if hasLoaded {
                    summarySection(report.totals, format: format)
                    if range != .day {
                        chartSection(report.daily, format: format)
                    }
                    callSection(calls, format: format)
                    featureSection(report.byFeature, format: format)
                    modelSection(report.byModel, format: format)
                    Section {
                        Button("清除用量记录…", role: .destructive) {
                            showClearConfirmation = true
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(LerroTheme.danger)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task(id: range) { await reload() }
        .task(id: calls.map(\.id)) { await loadLinkedEntries(for: calls) }
        .confirmationDialog(
            "清除用量记录？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task {
                    await session.deleteAllAIUsage()
                    await reload()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这台 Mac 上的 AI 用量记录会被删除，无法恢复。")
        }
    }

    private var backBar: some View {
        HStack {
            Button {
                session.aiSettingsShowsUsage = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("AI 整理")
                }
                .foregroundStyle(LerroTheme.accentText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private func reload() async {
        let since = AIUsageStatistics.rangeStart(days: Self.loadedDays, now: .now)
        records = await session.aiUsageRecords(since: since)
        hasLoaded = true
    }

    /// Newest first, limited to the selected range.
    private func visibleCalls() -> [AIUsageRecord] {
        let now = Date.now
        let start = AIUsageStatistics.rangeStart(days: range.days, now: now)
        return Array(
            records
                .filter { $0.date >= start && $0.date <= now }
                .sorted { $0.date > $1.date }
                .prefix(Self.visibleCallLimit)
        )
    }

    private func loadLinkedEntries(for calls: [AIUsageRecord]) async {
        let ids = Set(calls.compactMap(\.historyEntryID))
        guard !ids.isEmpty else {
            linkedEntries = [:]
            return
        }
        let loaded = await session.historyEntries(ids: ids)
        guard !Task.isCancelled else { return }
        linkedEntries = loaded
    }

    // MARK: Sections

    private func summarySection(_ totals: AIUsageTotals, format: UsageFormat) -> some View {
        let succeeded = totals.requests - totals.failedRequests - totals.unpricedRequests
        let averageCost: String? = succeeded > 0 && !totals.costs.isEmpty
            ? LerroInterfaceLocalization.format(
                "平均每次 %@",
                locale: locale,
                arguments: format.cost(totals.costs.mapValues { $0 / Double(succeeded) })
            )
            : nil
        let failed: String? = totals.failedRequests > 0
            ? LerroInterfaceLocalization.format(
                "失败 %lld 次", locale: locale, arguments: totals.failedRequests
            )
            : nil
        let cacheHit: String? = totals.inputTokens > 0
            ? LerroInterfaceLocalization.format(
                "%lld%% 命中缓存",
                locale: locale,
                arguments: Int((Double(totals.cachedInputTokens) / Double(totals.inputTokens) * 100).rounded())
            )
            : nil

        return Section {
            HStack(alignment: .top, spacing: 16) {
                UsageStat(title: "费用（估算）", value: format.cost(totals.costs), detail: averageCost)
                UsageStat(
                    title: "调用",
                    value: LerroInterfaceLocalization.format(
                        "%lld 次", locale: locale, arguments: totals.requests
                    ),
                    detail: failed,
                    detailColor: LerroTheme.danger
                )
                UsageStat(title: "Token", value: format.tokens(totals.totalTokens), detail: cacheHit)
            }
            .padding(.vertical, 4)
        }
    }

    private func chartSection(_ daily: [AIUsageDay], format: UsageFormat) -> some View {
        Section {
            Chart(daily) { day in
                BarMark(
                    x: .value("日期", day.day, unit: .day),
                    y: .value("Token", day.totals.totalTokens)
                )
                .foregroundStyle(LerroTheme.accent)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text(verbatim: format.tokens(count))
                        }
                    }
                }
            }
            .frame(height: 140)
            .padding(.vertical, 6)
        }
    }

    private func callSection(_ calls: [AIUsageRecord], format: UsageFormat) -> some View {
        Section("调用记录") {
            ForEach(calls) { record in
                callRow(record, format: format)
            }
        }
    }

    @ViewBuilder
    private func callRow(
        _ record: AIUsageRecord,
        format: UsageFormat
    ) -> some View {
        let entry = record.historyEntryID.flatMap { linkedEntries[$0] }
        if let entry {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                session.showHistoryEntry(entry.id)
            } label: {
                callRowContent(record, entry: entry, format: format)
            }
            .buttonStyle(.plain)
        } else {
            callRowContent(record, entry: nil, format: format)
        }
    }

    private func callRowContent(
        _ record: AIUsageRecord,
        entry: HistoryEntry?,
        format: UsageFormat
    ) -> some View {
        let text = entry.map { firstLine(of: $0.finalText) } ?? ""
        let latency = LerroInterfaceLocalization.format(
            "%.1f 秒", locale: locale, arguments: Double(record.latencyMilliseconds) / 1000
        )
        let secondary = [entry?.applicationName, latency]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let costText = callCost(record, format: format)

        return HStack(alignment: .top, spacing: 10) {
            Text(verbatim: format.time(record.date, includesDate: range != .day))
                .font(LerroFont.caption.monospacedDigit())
                .foregroundStyle(LerroTheme.secondaryText)
                .frame(width: range == .day ? 40 : 84, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(record.feature.usageTitle))
                        .font(LerroFont.body)
                        .foregroundStyle(LerroTheme.secondaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if !text.isEmpty {
                        Text(verbatim: text)
                            .font(LerroFont.body)
                            .foregroundStyle(LerroTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Text(verbatim: secondary)
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if record.succeeded {
                if let costText {
                    Text(verbatim: costText)
                        .font(LerroFont.body.monospacedDigit())
                        .foregroundStyle(LerroTheme.text)
                }
            } else {
                Text("失败")
                    .font(LerroFont.body)
                    .foregroundStyle(LerroTheme.danger)
            }

            if entry != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LerroTheme.tertiaryText)
                    .frame(height: 18)
            }
        }
        .contentShape(Rectangle())
    }

    private func callCost(
        _ record: AIUsageRecord,
        format: UsageFormat
    ) -> String? {
        guard let tokens = record.tokens else { return nil }
        guard let price = AIModelPrice.price(for: record.modelIdentifier) else { return "—" }
        return format.cost([price.currency: price.cost(of: tokens, at: record.date)])
    }

    private func firstLine(of text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    private func featureSection(
        _ features: [AIUsageFeatureBreakdown],
        format: UsageFormat
    ) -> some View {
        Section("按功能") {
            ForEach(features) { entry in
                LabeledContent {
                    Text(verbatim: format.summary(entry.totals, unpricedLabel: nil))
                        .foregroundStyle(LerroTheme.secondaryText)
                } label: {
                    Text(LocalizedStringKey(entry.feature.usageTitle))
                }
            }
        }
    }

    private func modelSection(
        _ models: [AIUsageModelBreakdown],
        format: UsageFormat
    ) -> some View {
        Section("按模型") {
            ForEach(models) { entry in
                LabeledContent {
                    Text(verbatim: format.summary(
                        entry.totals,
                        unpricedLabel: LerroInterfaceLocalization.string("未设价格", locale: locale)
                    ))
                    .foregroundStyle(LerroTheme.secondaryText)
                } label: {
                    Text(verbatim: entry.modelIdentifier)
                }
            }
        }
    }
}

// MARK: - Supporting types

private enum UsageRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        }
    }

    var title: String {
        switch self {
        case .day: "今天"
        case .week: "7 天"
        case .month: "30 天"
        }
    }
}

private extension AIUsageFeature {
    var usageTitle: String {
        switch self {
        case .dictate: "听写整理"
        case .translate: "翻译"
        case .dictionaryLearning: "自动学词"
        case .tonePreview: "语气预览"
        case .connectionTest: "连接测试"
        }
    }
}

private struct UsageStat: View {
    let title: String
    let value: String
    var detail: String?
    var detailColor: Color = LerroTheme.secondaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
            Text(verbatim: value)
                .font(LerroFont.stat)
                .foregroundStyle(LerroTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: detail ?? " ")
                .font(LerroFont.caption)
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct UsageFormat {
    let locale: Locale

    private var isChinese: Bool { locale.language.languageCode?.identifier == "zh" }

    func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Grouped below 10,000; compact "1.2 万" (zh) or "12.3K" / "1.2M" above.
    func tokens(_ value: Int) -> String {
        guard value >= 10_000 else { return integer(value) }
        if isChinese {
            return String(format: "%.1f 万", Double(value) / 10_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        return String(format: "%.1fK", Double(value) / 1_000)
    }

    /// "HH:mm", or "M/d HH:mm" when `includesDate`.
    func time(_ date: Date, includesDate: Bool) -> String {
        let style = includesDate
            ? Date.FormatStyle().month(.defaultDigits).day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            : Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return date.formatted(style.locale(locale))
    }

    func cost(_ costs: [AIUsageCurrency: Double]) -> String {
        let parts = AIUsageCurrency.allCases.compactMap { currency -> String? in
            guard let amount = costs[currency] else { return nil }
            let digits = amount > 0 && amount < 0.01 ? 4 : 2
            return currency.symbol + String(format: "%.\(digits)f", amount)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " + ")
    }

    /// "tokens · cost", or "tokens · unpricedLabel" when nothing could be priced.
    func summary(_ totals: AIUsageTotals, unpricedLabel: String?) -> String {
        let costText: String
        if let unpricedLabel, totals.unpricedRequests > 0, totals.costs.isEmpty {
            costText = unpricedLabel
        } else {
            costText = cost(totals.costs)
        }
        return tokens(totals.totalTokens) + " · " + costText
    }
}
