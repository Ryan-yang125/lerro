import SwiftUI
import LerroCore
import LerroMac

private enum HistoryDetailMode: Hashable {
    case result
    case diff
    case raw

    var title: String {
        switch self {
        case .result: "结果"
        case .diff: "对比原文"
        case .raw: "原文"
        }
    }
}

/// Detail pane for the selected history entry.
struct HistoryDetailView: View {
    let entry: HistoryEntry
    let session: AppSession
    let requestDelete: (HistoryEntry) -> Void

    @State private var mode: HistoryDetailMode = .result
    @State private var player = RecordingPlayer()
    @State private var highlightsAICall = false
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let aiCallScrollID = "aiCall"

    private struct HighlightKey: Hashable {
        let entryID: UUID
        let highlightID: UUID?
    }

    var body: some View {
        ScrollViewReader { proxy in
            scrollContent
                .task(id: HighlightKey(entryID: entry.id, highlightID: session.aiCallHighlightID)) {
                    await highlightAICall(scrollingWith: proxy)
                }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 16)
                modePicker
                    .padding(.bottom, 10)
                bodyText
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                Divider()
                    .padding(.bottom, 16)
                metadata
                aiCall
                audio
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: entry.id) { _, _ in player.stop() }
        .onDisappear { player.stop() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            LerroAppIcon(bundleIdentifier: entry.bundleIdentifier, name: entry.applicationName, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.applicationName)
                    .font(LerroFont.bodyEmphasis)
                    .foregroundStyle(LerroTheme.text)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(LerroFont.footnote)
                    .foregroundStyle(LerroTheme.metadataText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                session.copyText(entry.finalText)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(LerroButtonStyle(.secondary))
            Menu {
                HistoryEntryMenuItems(entry: entry, session: session, requestDelete: requestDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LerroTheme.text)
                    .frame(width: 28, height: 28)
                    .background(LerroTheme.actionFill, in: Circle())
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("更多操作"))
        }
    }

    private var subtitle: String {
        var parts = [
            "\(HistoryPresentation.dayTitle(for: entry.createdAt, locale: locale)) \(HistoryPresentation.time(entry.createdAt, locale: locale))",
            HistoryPresentation.localized(HistoryPresentation.modeTitle(entry.mode), locale: locale),
            HistoryPresentation.seconds(entry.duration, locale: locale)
        ]
        switch entry.status {
        case .failed: parts.append(HistoryPresentation.localized("未写入", locale: locale))
        case .cancelled: parts.append(HistoryPresentation.localized("已取消", locale: locale))
        case .undone: parts.append(HistoryPresentation.localized("已撤回", locale: locale))
        case .completed: break
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Text

    private var availableModes: [HistoryDetailMode] {
        entry.mode == .translation ? [.result, .raw] : [.result, .diff, .raw]
    }

    private var effectiveMode: HistoryDetailMode {
        availableModes.contains(mode) ? mode : .result
    }

    private var modePicker: some View {
        Picker("显示内容", selection: $mode) {
            ForEach(availableModes, id: \.self) { item in
                Text(LocalizedStringKey(item.title)).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private var bodyText: some View {
        switch effectiveMode {
        case .result:
            if HistoryPresentation.hasText(entry) {
                detailText(Text(verbatim: entry.finalText), color: LerroTheme.text)
            } else {
                detailText(
                    Text(verbatim: HistoryPresentation.listText(for: entry, locale: locale)),
                    color: LerroTheme.secondaryText
                )
            }
        case .diff:
            let segments = TextDiff.segments(from: entry.rawText, to: entry.finalText)
            detailText(Text(diffString(segments)), color: LerroTheme.text)
                .accessibilityLabel(Text(verbatim: spokenDiff(segments)))
        case .raw:
            detailText(Text(verbatim: entry.rawText), color: LerroTheme.secondaryText)
        }
    }

    private func detailText(_ text: Text, color: Color) -> some View {
        text
            .font(LerroFont.detail)
            .foregroundStyle(color)
            .lineSpacing(6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diffString(_ segments: [TextDiff.Segment]) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .same:
                break
            case .removed:
                part.swiftUI.foregroundColor = LerroTheme.tertiaryText
                part.swiftUI.strikethroughStyle = Text.LineStyle(
                    pattern: .solid,
                    color: LerroTheme.tertiaryText
                )
            case .inserted:
                part.swiftUI.foregroundColor = LerroTheme.accentText
                part.swiftUI.backgroundColor = LerroTheme.accentSoft
            }
            result.append(part)
        }
        return result
    }

    private func spokenDiff(_ segments: [TextDiff.Segment]) -> String {
        let removed = HistoryPresentation.localized("已删除", locale: locale)
        let inserted = HistoryPresentation.localized("新增", locale: locale)
        return segments.map { segment in
            switch segment.kind {
            case .same: segment.text
            case .removed: "\(removed) \(segment.text)"
            case .inserted: "\(inserted) \(segment.text)"
            }
        }.joined(separator: " ")
    }

    // MARK: AI call

    @ViewBuilder
    private var aiCall: some View {
        if let call = entry.aiCall {
            HistoryAICallView(
                entry: entry,
                call: call,
                session: session,
                isHighlighted: highlightsAICall
            )
            .id(Self.aiCallScrollID)
            .padding(.top, 20)
        }
    }

    /// Scrolls to the AI card and outlines it briefly when the session asks for it.
    private func highlightAICall(scrollingWith proxy: ScrollViewProxy) async {
        guard entry.aiCall != nil, session.aiCallHighlightID == entry.id else { return }
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        if reduceMotion {
            proxy.scrollTo(Self.aiCallScrollID, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(Self.aiCallScrollID, anchor: .center)
            }
        }
        highlightsAICall = true
        try? await Task.sleep(for: .milliseconds(1200))
        highlightsAICall = false
        if session.aiCallHighlightID == entry.id {
            session.aiCallHighlightID = nil
        }
    }

    // MARK: Metadata

    private var metadata: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
            if entry.aiCall == nil {
                metadataRow("处理") {
                    Text(verbatim: processingText)
                }
            }
            if let timings = entry.phaseTimings, timingsTotal(timings) > 0 {
                metadataRow("耗时") {
                    HistoryTimingView(timings: timings, locale: locale)
                }
            }
            if let timings = entry.phaseTimings, let readyToSpeak = timings.duration(of: .readyToSpeak) {
                metadataRow("按键到可以说话") {
                    HistoryStartupTimingView(timings: timings, readyToSpeak: readyToSpeak, locale: locale)
                }
            }
            if let windowTitle = entry.windowTitle, !windowTitle.isEmpty {
                metadataRow("窗口") {
                    Text(verbatim: windowTitle)
                        .lineLimit(2)
                }
            }
            if entry.aiCall == nil, let receipt = entry.contextReceipt {
                metadataRow("发送给 AI") {
                    Text(verbatim: sharedContextText(receipt))
                }
            }
        }
        .font(LerroFont.caption)
    }

    private func metadataRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(title))
                .foregroundStyle(LerroTheme.metadataText)
            content()
                .foregroundStyle(LerroTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func timingsTotal(_ timings: HistoryPhaseTimings) -> TimeInterval {
        timings.transcription + timings.processing + timings.delivery
    }

    private var processingText: String {
        let key: String
        switch entry.processingRoute {
        case .raw: key = "原始听写"
        case .local: key = "本地 AI"
        case .remote:
            if let model = entry.modelIdentifier, !model.isEmpty { return model }
            key = "API 模型"
        case .appleTranslation: key = "Apple 翻译"
        case .localSnippet: key = "快捷语"
        case nil: key = entry.wasEnhanced ? "AI 润色" : "原始听写"
        }
        return HistoryPresentation.localized(key, locale: locale)
    }

    private func sharedContextText(_ receipt: HistoryContextReceipt) -> String {
        let shared = HistoryContextCategory.allCases.filter { receipt.remoteSharedCategories.contains($0) }
        guard !shared.isEmpty else { return HistoryPresentation.localized("未发送", locale: locale) }
        return shared
            .map { HistoryPresentation.localized(categoryTitle($0), locale: locale) }
            .joined(separator: "、")
    }

    private func categoryTitle(_ category: HistoryContextCategory) -> String {
        switch category {
        case .application: "应用名"
        case .windowTitle: "窗口标题"
        case .nearbyText: "光标附近文字"
        case .selectedText: "选中文字"
        case .dictionary: "词典"
        case .tone: "应用语气"
        }
    }

    // MARK: Audio

    @ViewBuilder
    private var audio: some View {
        if entry.audioRelativePath != nil, let url = session.recordingURL(for: entry) {
            HistoryAudioRow(url: url, fallbackDuration: entry.duration, player: player)
                .padding(.top, 16)
        }
    }
}

// MARK: Timing

private struct HistoryTimingView: View {
    let timings: HistoryPhaseTimings
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: LerroInterfaceLocalization.format(
                "共 %.1f 秒",
                locale: locale,
                arguments: total
            ))
            bar
                .padding(.top, 2)
            Text(verbatim: breakdown)
                .font(LerroFont.footnote)
                .foregroundStyle(LerroTheme.metadataText)
        }
    }

    private var total: TimeInterval {
        timings.transcription + timings.processing + timings.delivery
    }

    private var bar: some View {
        let segments: [(value: TimeInterval, color: Color)] = [
            (timings.transcription, LerroTheme.tertiaryText),
            (timings.processing, LerroTheme.accent),
            (timings.delivery, LerroTheme.success)
        ]
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(segments.indices, id: \.self) { index in
                    Rectangle()
                        .fill(segments[index].color)
                        .frame(width: proxy.size.width * max(segments[index].value, 0) / total)
                }
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 240)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private var breakdown: String {
        if timings.processing > 0 {
            return LerroInterfaceLocalization.format(
                "转写 %.1f · AI %.1f · 写入 %.1f",
                locale: locale,
                arguments: timings.transcription, timings.processing, timings.delivery
            )
        }
        return LerroInterfaceLocalization.format(
            "转写 %.1f · 写入 %.1f",
            locale: locale,
            arguments: timings.transcription, timings.delivery
        )
    }
}

private struct HistoryStartupTimingView: View {
    let timings: HistoryPhaseTimings
    let readyToSpeak: TimeInterval
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: LerroInterfaceLocalization.format(
                "%.2f 秒",
                locale: locale,
                arguments: readyToSpeak
            ))
            if !breakdown.isEmpty {
                Text(verbatim: breakdown)
                    .font(LerroFont.footnote)
                    .foregroundStyle(LerroTheme.metadataText)
            }
        }
    }

    private var breakdown: String {
        let parts: [(key: String, segment: CaptureTraceSegment)] = [
            ("准备 %.2f", .appPreparation),
            ("语音启动 %.2f", .speechStartup),
            ("首字 %.2f", .firstPartial)
        ]
        return parts
            .compactMap { part in
                timings.duration(of: part.segment).map {
                    LerroInterfaceLocalization.format(part.key, locale: locale, arguments: $0)
                }
            }
            .joined(separator: " · ")
    }
}

// MARK: Audio

private struct HistoryAudioRow: View {
    let url: URL
    let fallbackDuration: TimeInterval
    let player: RecordingPlayer

    private var isPlaying: Bool { player.playingURL == url }
    private var total: TimeInterval { player.duration > 0 ? player.duration : fallbackDuration }

    var body: some View {
        HStack(spacing: 10) {
            LerroIconButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                help: isPlaying ? "暂停" : "播放"
            ) {
                player.toggle(url: url)
            }
            progressBar
            Text(verbatim: timeText)
                .font(LerroFont.caption)
                .monospacedDigit()
                .foregroundStyle(LerroTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(LerroTheme.fillContainerThin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(LerroTheme.tertiaryText.opacity(0.25))
                Capsule()
                    .fill(LerroTheme.accent)
                    .frame(width: proxy.size.width * player.progress)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("播放进度"))
        .accessibilityValue(Text(verbatim: "\(Int(player.progress * 100))%"))
    }

    private var timeText: String {
        let totalText = HistoryPresentation.clock(total)
        guard player.progress > 0 else { return totalText }
        return "\(HistoryPresentation.clock(total * player.progress)) / \(totalText)"
    }
}
