import Charts
import SwiftUI
import LerroCore

/// AI usage statistics: tokens, estimated cost, per-feature and per-model
/// breakdowns, and editable model prices.
struct UsageSettingsTab: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @State private var range: UsageRange = .week
    @State private var records: [AIUsageRecord] = []
    @State private var hasLoaded = false
    @State private var priceTarget: PriceTarget?
    @State private var showClearConfirmation = false

    private static let loadedDays = 30

    var body: some View {
        let report = AIUsageStatistics.report(
            records: records,
            prices: AIModelPriceTable(overrides: session.preferences.modelPrices),
            days: range.days,
            now: .now
        )
        let format = UsageFormat(locale: locale)

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
        .task(id: range) { await reload() }
        .sheet(item: $priceTarget) { target in
            ModelPriceEditor(session: session, modelIdentifier: target.modelIdentifier)
        }
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

    private func reload() async {
        let since = AIUsageStatistics.rangeStart(days: Self.loadedDays, now: .now)
        records = await session.aiUsageRecords(since: since)
        hasLoaded = true
    }

    // MARK: Sections

    private func summarySection(_ totals: AIUsageTotals, format: UsageFormat) -> some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                UsageStat(title: "费用（估算）", value: format.cost(totals.costs))
                UsageStat(title: "Token", value: format.tokens(totals.totalTokens))
                UsageStat(
                    title: "请求",
                    value: format.integer(totals.requests),
                    detail: totals.failedRequests > 0
                        ? "· " + LerroInterfaceLocalization.format(
                            "失败 %lld", locale: locale, arguments: totals.failedRequests
                        )
                        : nil
                )
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
                    HStack(spacing: 10) {
                        Text(verbatim: format.summary(
                            entry.totals,
                            unpricedLabel: LerroInterfaceLocalization.string("未设价格", locale: locale)
                        ))
                        .foregroundStyle(LerroTheme.secondaryText)
                        Button("价格…") {
                            priceTarget = PriceTarget(modelIdentifier: entry.modelIdentifier)
                        }
                        .buttonStyle(LerroButtonStyle(.secondary))
                    }
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

private struct PriceTarget: Identifiable {
    let modelIdentifier: String
    var id: String { modelIdentifier.lowercased() }
}

private extension AIUsageFeature {
    var usageTitle: String {
        switch self {
        case .dictate: "润色"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value)
                    .font(LerroFont.stat)
                    .foregroundStyle(LerroTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let detail {
                    Text(verbatim: detail)
                        .font(LerroFont.caption)
                        .foregroundStyle(LerroTheme.secondaryText)
                        .lineLimit(1)
                }
            }
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

// MARK: - Price editor

private struct ModelPriceEditor: View {
    @Bindable var session: AppSession
    let modelIdentifier: String
    @Environment(\.dismiss) private var dismiss

    @State private var currency: AIUsageCurrency = .cny
    @State private var input = 0.0
    @State private var cachedInput = 0.0
    @State private var output = 0.0
    @State private var offPeakFactor: Double?

    private var table: AIModelPriceTable {
        AIModelPriceTable(overrides: session.preferences.modelPrices)
    }

    private var hasOverride: Bool {
        let key = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return session.preferences.modelPrices.contains { $0.id == key }
    }

    private var canReset: Bool {
        hasOverride && table.builtInPrice(for: modelIdentifier) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("币种", selection: $currency) {
                        Text("¥ 人民币").tag(AIUsageCurrency.cny)
                        Text("$ 美元").tag(AIUsageCurrency.usd)
                    }
                }
                Section("每百万 Token") {
                    priceField("输入", value: $input)
                    priceField("缓存命中输入", value: $cachedInput)
                    priceField("输出", value: $output)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 8) {
                if canReset {
                    Button("恢复默认") {
                        session.resetModelPrice(modelIdentifier: modelIdentifier)
                        dismiss()
                    }
                    .buttonStyle(LerroButtonStyle(.secondary))
                }
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(LerroButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    session.setModelPrice(AIModelPrice(
                        modelIdentifier: modelIdentifier,
                        currency: currency,
                        inputPerMillion: input,
                        cachedInputPerMillion: cachedInput,
                        outputPerMillion: output,
                        offPeakFactor: offPeakFactor
                    ))
                    dismiss()
                }
                .buttonStyle(LerroButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 420)
        .onAppear(perform: load)
    }

    private func priceField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent {
            TextField(
                "",
                value: value,
                format: .number.precision(.fractionLength(0...4))
            )
            .multilineTextAlignment(.trailing)
            .labelsHidden()
            .frame(width: 100)
        } label: {
            Text(LocalizedStringKey(title))
        }
    }

    private func load() {
        let initial = table.price(for: modelIdentifier)
        currency = initial?.currency ?? .cny
        input = initial?.inputPerMillion ?? 0
        cachedInput = initial?.cachedInputPerMillion ?? 0
        output = initial?.outputPerMillion ?? 0
        offPeakFactor = initial?.offPeakFactor
    }
}
