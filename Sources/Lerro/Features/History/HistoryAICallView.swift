import SwiftUI
import LerroCore

/// "AI 处理" card in the history detail: what the model changed, what it saw,
/// what the call cost, and the raw request and response.
struct HistoryAICallView: View {
    let entry: HistoryEntry
    let call: AICallTrace
    let session: AppSession
    let isHighlighted: Bool

    @State private var showsCostDetail = false
    @State private var showsRawData = false
    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let context: AISentContext?
    private let fixes: [AIWordFix]
    private let removedFragments: [String]

    init(entry: HistoryEntry, call: AICallTrace, session: AppSession, isHighlighted: Bool) {
        self.entry = entry
        self.call = call
        self.session = session
        self.isHighlighted = isHighlighted
        let fixes = call.prompt == .dictate ? call.fixes : []
        self.context = call.sentContext
        self.fixes = fixes
        self.removedFragments = call.prompt == .dictate
            ? Self.removedFragments(rawText: entry.rawText, finalText: entry.finalText, fixes: fixes)
            : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !fixes.isEmpty || !removedFragments.isEmpty {
                Divider()
                changesBlock
            }
            Divider()
            seenBlock
            Divider()
            costBlock
            Divider()
            footer
        }
        .background(LerroTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LerroTheme.accent, lineWidth: 2)
                .opacity(isHighlighted ? 1 : 0)
                .animation(reduceMotion ? Animation?.none : Animation.easeOut(duration: 0.3), value: isHighlighted)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showsRawData) {
            HistoryAIRawDataSheet(call: call, session: session)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("AI 处理")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LerroTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(verbatim: headerSummary)
                .font(LerroFont.caption)
                .monospacedDigit()
                .foregroundStyle(LerroTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var headerSummary: String {
        var parts = [call.modelIdentifier]
        if let cost {
            parts.append(Self.amount(cost.total, currency: cost.currency))
        }
        parts.append(LerroInterfaceLocalization.format(
            "%.1f 秒",
            locale: locale,
            arguments: Double(call.latencyMilliseconds) / 1000
        ))
        return parts.joined(separator: " · ")
    }

    // MARK: What changed

    private var changesBlock: some View {
        block("AI 改了什么") {
            VStack(alignment: .leading, spacing: 8) {
                if !fixes.isEmpty {
                    AIChipFlow {
                        ForEach(Array(fixes.enumerated()), id: \.offset) { _, fix in
                            HStack(spacing: 6) {
                                fixChip(fix)
                                learningBadge(for: fix)
                            }
                        }
                    }
                }
                if !removedFragments.isEmpty {
                    AIChipFlow {
                        Text("去掉的内容")
                            .font(LerroFont.footnote)
                            .foregroundStyle(LerroTheme.metadataText)
                            .padding(.trailing, 2)
                        ForEach(removedFragments, id: \.self) { fragment in
                            removedChip(fragment)
                        }
                    }
                }
            }
        }
    }

    private func fixChip(_ fix: AIWordFix) -> some View {
        LerroChip {
            Text(verbatim: fix.recognized)
                .strikethrough(true, color: LerroTheme.tertiaryText)
                .foregroundStyle(LerroTheme.tertiaryText)
            Text(verbatim: "→")
                .foregroundStyle(LerroTheme.metadataText)
            Text(verbatim: fix.corrected)
                .fontWeight(.medium)
                .foregroundStyle(LerroTheme.accentText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(fix.recognized) → \(fix.corrected)"))
    }

    @ViewBuilder
    private func learningBadge(for fix: AIWordFix) -> some View {
        let corrected = TermLearner.normalized(fix.corrected)
        if call.terms.contains(where: { TermLearner.normalized($0) == corrected }) {
            switch session.termLearningStatus(for: fix.corrected) {
            case .inDictionary:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .accessibilityHidden(true)
                    Text("已记住")
                }
                .font(LerroFont.footnote.weight(.medium))
                .foregroundStyle(LerroTheme.success)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(LerroTheme.success.opacity(0.14), in: Capsule())
            case .pending(let remaining):
                Text(verbatim: LerroInterfaceLocalization.format(
                    "再出现 %lld 次就记住",
                    locale: locale,
                    arguments: remaining
                ))
                .font(LerroFont.footnote)
                .foregroundStyle(LerroTheme.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(LerroTheme.fillContainerTough, in: Capsule())
            case .notLearning:
                EmptyView()
            }
        }
    }

    private func removedChip(_ fragment: String) -> some View {
        LerroChip {
            Text(verbatim: fragment)
                .strikethrough(true, color: LerroTheme.tertiaryText)
                .foregroundStyle(LerroTheme.tertiaryText)
        }
    }

    private static func removedFragments(
        rawText: String,
        finalText: String,
        fixes: [AIWordFix]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for segment in TextDiff.segments(from: rawText, to: finalText) where segment.kind == .removed {
            let fragment = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard fragment.contains(where: { $0.isLetter || $0.isNumber }),
                  !fixes.contains(where: { $0.recognized.contains(fragment) }),
                  seen.insert(fragment).inserted
            else { continue }
            result.append(fragment)
        }
        return result
    }

    // MARK: What the model saw

    private var seenBlock: some View {
        block("AI 看到了什么") {
            Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 7) {
                if let context {
                    seenRow(symbol: "mic", label: "你说的话") { valueText(context.transcript) }
                    if let target = context.targetLanguage, !target.isEmpty {
                        seenRow(symbol: "globe", label: "目标语言") { valueText(target) }
                    }
                    if let name = context.applicationName, !name.isEmpty {
                        seenRow(symbol: "app", label: "应用") { valueText(name) }
                    }
                    if let title = context.windowTitle, !title.isEmpty {
                        seenRow(symbol: "macwindow", label: "窗口标题") { valueText(title, lineLimit: 2) }
                    }
                    if let nearby = nearbyText(context) {
                        seenRow(symbol: "text.cursor", label: "光标附近文字") { valueText(nearby, lineLimit: 4) }
                    }
                    if let selected = context.selectedText, !selected.isEmpty {
                        seenRow(symbol: "highlighter", label: "选中文字") { valueText(selected, lineLimit: 4) }
                    }
                    if !context.knownTerms.isEmpty || !context.glossary.isEmpty {
                        seenRow(
                            symbol: "character.book.closed",
                            label: "词典",
                            link: "去词典",
                            action: { session.destination = .dictionary }
                        ) {
                            AIChipFlow {
                                ForEach(context.knownTerms, id: \.self) { term in
                                    LerroChip { Text(verbatim: term) }
                                }
                                ForEach(Array(context.glossary.enumerated()), id: \.offset) { _, mapping in
                                    LerroChip {
                                        Text(verbatim: "\(mapping.phrase) → \(mapping.replacement)")
                                    }
                                }
                            }
                        }
                    }
                    if let tone = context.tone, !tone.isEmpty {
                        seenRow(
                            symbol: "quote.bubble",
                            label: "语气",
                            link: "改语气",
                            action: { session.destination = .appTones }
                        ) { valueText(tone) }
                    }
                }
                if let unsent = unsentCategories {
                    seenRow(
                        symbol: "eye.slash",
                        label: "没有发送",
                        link: "设置",
                        action: {
                            session.settingsTab = .intelligence
                            openSettings()
                        }
                    ) {
                        Text(verbatim: unsent)
                            .foregroundStyle(LerroTheme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                seenRow(
                    symbol: "doc.text",
                    label: "提示词",
                    link: "查看",
                    action: { openWindow(id: "prompt", value: call.prompt) }
                ) { valueText(promptName) }
            }
            .font(LerroFont.caption)
        }
    }

    private func seenRow<Value: View>(
        symbol: String,
        label: String,
        link: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder value: () -> Value
    ) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(LerroTheme.tertiaryText)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(label))
                .foregroundStyle(LerroTheme.metadataText)
                .lineLimit(1)
                .gridColumnAlignment(.leading)
            value()
            if let link, let action {
                Button(action: action) {
                    Text(LocalizedStringKey(link))
                        .foregroundStyle(LerroTheme.accentText)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    private func valueText(_ text: String, lineLimit: Int? = nil) -> some View {
        Text(verbatim: text)
            .foregroundStyle(LerroTheme.text)
            .lineLimit(lineLimit)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nearbyText(_ context: AISentContext) -> String? {
        let before = context.cursorBefore ?? ""
        let after = context.cursorAfter ?? ""
        guard !before.isEmpty || !after.isEmpty else { return nil }
        return "\(before)▏\(after)"
    }

    private var unsentCategories: String? {
        guard let receipt = entry.contextReceipt else { return nil }
        let unsent = HistoryContextCategory.allCases.filter {
            !receipt.remoteSharedCategories.contains($0)
        }
        guard !unsent.isEmpty else { return nil }
        return unsent
            .map { HistoryPresentation.localized(Self.categoryTitle($0), locale: locale) }
            .joined(separator: "、")
    }

    private static func categoryTitle(_ category: HistoryContextCategory) -> String {
        switch category {
        case .application: "应用名"
        case .windowTitle: "窗口标题"
        case .nearbyText: "光标附近文字"
        case .selectedText: "选中文字"
        case .dictionary: "词典"
        case .tone: "应用语气"
        }
    }

    private var promptName: String {
        let key: String
        switch call.prompt {
        case .dictate: key = "听写润色"
        case .translate: key = "翻译"
        case .dictionaryLearning: key = "自动学词"
        }
        return HistoryPresentation.localized(key, locale: locale)
    }

    // MARK: Cost

    private var cost: AICallCost? {
        guard let tokens = call.tokens,
              let price = AIModelPriceTable(overrides: session.preferences.modelPrices)
                .price(for: call.modelIdentifier)
        else { return nil }
        return price.breakdown(of: tokens, at: call.startedAt)
    }

    private var costBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("花了多少")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if cost != nil {
                    Button {
                        showsCostDetail.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text("怎么算的")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(showsCostDetail ? 90 : 0))
                        }
                        .font(LerroFont.caption)
                        .foregroundStyle(LerroTheme.accentText)
                    }
                    .buttonStyle(.plain)
                    .animation(reduceMotion ? Animation?.none : Animation.easeOut(duration: 0.15), value: showsCostDetail)
                }
            }
            .padding(.bottom, 8)
            Text(verbatim: costSentence)
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
                .textSelection(.enabled)
            if showsCostDetail, let cost {
                costTable(cost)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var costSentence: String {
        guard call.tokens != nil else {
            return HistoryPresentation.localized("服务商没有返回用量", locale: locale)
        }
        guard let cost else {
            return HistoryPresentation.localized("这个模型没有设置价格，无法估算费用", locale: locale)
        }
        let amount = Self.amount(cost.total, currency: cost.currency)
        guard cost.total > 0 else {
            return LerroInterfaceLocalization.format("约 %@。", locale: locale, arguments: amount)
        }
        let uses = (1 / cost.total).formatted(
            .number.locale(locale).precision(.significantDigits(1...2))
        )
        let key = cost.currency == .cny ? "约 %@，1 块钱大约能用 %@ 次。" : "约 %@，1 美元大约能用 %@ 次。"
        return LerroInterfaceLocalization.format(key, locale: locale, arguments: amount, uses)
    }

    private func costTable(_ cost: AICallCost) -> some View {
        let symbol = cost.currency.symbol
        return Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(Array(cost.lines.enumerated()), id: \.offset) { _, line in
                if line.tokens > 0 {
                    GridRow {
                        Text(LocalizedStringKey(Self.lineTitle(line.kind)))
                            .foregroundStyle(LerroTheme.secondaryText)
                            .gridColumnAlignment(.leading)
                        Text(verbatim: tokenText(line.tokens))
                            .foregroundStyle(LerroTheme.text)
                        Text(verbatim: LerroInterfaceLocalization.format(
                            "× %@ / 百万",
                            locale: locale,
                            arguments: symbol + String(format: "%g", line.pricePerMillion)
                        ))
                        .foregroundStyle(LerroTheme.secondaryText)
                        Text(verbatim: Self.amount(line.amount, currency: cost.currency))
                            .foregroundStyle(LerroTheme.text)
                    }
                }
            }
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text("合计")
                    .fontWeight(.semibold)
                    .foregroundStyle(LerroTheme.text)
                Text(verbatim: tokenText(call.tokens?.totalTokens ?? 0))
                    .foregroundStyle(LerroTheme.text)
                if let factor = cost.appliedOffPeakFactor {
                    Text(verbatim: LerroInterfaceLocalization.format(
                        "非高峰时段 × %@",
                        locale: locale,
                        arguments: String(format: "%g", factor)
                    ))
                    .foregroundStyle(LerroTheme.secondaryText)
                } else {
                    Color.clear.frame(width: 0, height: 0)
                }
                Text(verbatim: Self.amount(cost.total, currency: cost.currency))
                    .fontWeight(.semibold)
                    .foregroundStyle(LerroTheme.text)
            }
        }
        .font(LerroFont.caption)
        .monospacedDigit()
        .textSelection(.enabled)
    }

    private func tokenText(_ count: Int) -> String {
        LerroInterfaceLocalization.format(
            "%@ Token",
            locale: locale,
            arguments: count.formatted(.number.locale(locale))
        )
    }

    private static func lineTitle(_ kind: AICallCostLine.Kind) -> String {
        switch kind {
        case .cachedInput: "提示词（命中缓存）"
        case .input: "这次的内容"
        case .output: "AI 写出的结果"
        }
    }

    /// Currency amount with two significant digits for values below 1, so
    /// 0.0014 stays readable.
    private static func amount(_ value: Double, currency: AIUsageCurrency) -> String {
        let symbol = currency.symbol
        guard value > 0 else { return symbol + "0" }
        guard value < 1 else { return symbol + String(format: "%.2f", value) }
        let decimals = min(8, max(2, 1 - Int(floor(log10(value)))))
        var text = String(format: "%.\(decimals)f", value)
        while text.hasSuffix("0"), let dot = text.firstIndex(of: "."),
              text.distance(from: dot, to: text.endIndex) > 3 {
            text.removeLast()
        }
        return symbol + text
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                showsRawData = true
            } label: {
                Text("查看原始数据")
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.accentText)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: Layout helpers

    private func block<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LerroTheme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

// MARK: Chip flow

/// Left-to-right layout that wraps to the next line when a row is full.
struct AIChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: Raw data

private struct HistoryAIRawDataSheet: View {
    private enum Tab: Hashable {
        case request
        case response
    }

    let call: AICallTrace
    let session: AppSession

    @State private var tab: Tab = .request
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("原始数据")
                    .font(LerroFont.pageTitle)
                    .foregroundStyle(LerroTheme.text)
                Spacer(minLength: 12)
                Picker("原始数据", selection: $tab) {
                    Text("发送").tag(Tab.request)
                    Text("返回").tag(Tab.response)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 12)
                Button {
                    session.copyText(content)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(LerroButtonStyle(.secondary))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(verbatim: content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LerroTheme.text)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(LerroTheme.fillContainerThin)
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(LerroButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 440, idealHeight: 560)
        .background(LerroTheme.main)
    }

    private var content: String {
        switch tab {
        case .request: requestJSON
        case .response: responseJSON
        }
    }

    private var requestJSON: String {
        let systemContent = LerroInterfaceLocalization.format(
            "%@（全文见提示词）",
            locale: locale,
            arguments: call.promptVersion
        )
        let system = AIRawJSON.Object(pairs: [("role", "system"), ("content", systemContent)])
        let user = AIRawJSON.Object(pairs: [
            ("role", "user"),
            ("content", AIRawJSON.value(from: call.userPrompt))
        ])
        let root = AIRawJSON.Object(pairs: [
            ("model", call.modelIdentifier),
            ("messages", [system, user] as [Any])
        ])
        return AIRawJSON.render(root)
    }

    private var responseJSON: String {
        var pairs: [(String, Any)] = [
            ("model", call.modelIdentifier),
            ("content", AIRawJSON.value(from: call.response))
        ]
        if let tokens = call.tokens {
            pairs.append(("usage", AIRawJSON.Object(pairs: [
                ("input_tokens", tokens.inputTokens),
                ("cached_input_tokens", tokens.cachedInputTokens),
                ("output_tokens", tokens.outputTokens)
            ])))
        }
        return AIRawJSON.render(AIRawJSON.Object(pairs: pairs))
    }
}

/// Pretty-printer that keeps the key order of the objects it builds and sorts
/// the keys of parsed objects.
private enum AIRawJSON {
    struct Object {
        var pairs: [(String, Any)]
    }

    /// Parsed JSON when the text is a JSON object or array (optionally inside a
    /// Markdown code fence), otherwise the text itself.
    static func value(from text: String) -> Any {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines = lines.dropLast() }
            trimmed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard trimmed.first == "{" || trimmed.first == "[",
              let data = trimmed.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data)
        else { return text }
        return parsed
    }

    static func render(_ value: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        switch value {
        case let object as Object:
            guard !object.pairs.isEmpty else { return "{}" }
            let body = object.pairs
                .map { "\(inner)\(string($0.0)): \(render($0.1, indent: indent + 1))" }
                .joined(separator: ",\n")
            return "{\n\(body)\n\(pad)}"
        case let dictionary as [String: Any]:
            return render(Object(pairs: dictionary.keys.sorted().map { ($0, dictionary[$0]!) }), indent: indent)
        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            let body = array
                .map { "\(inner)\(render($0, indent: indent + 1))" }
                .joined(separator: ",\n")
            return "[\n\(body)\n\(pad)]"
        case let text as String:
            return string(text)
        case is NSNull:
            return "null"
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID()
                ? (number.boolValue ? "true" : "false")
                : number.stringValue
        default:
            return string("\(value)")
        }
    }

    private static func string(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(text) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }
}
