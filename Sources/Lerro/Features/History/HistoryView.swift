import SwiftUI
import LerroCore

private enum HistoryTab: String, CaseIterable, Identifiable {
    case all = "全部"
    case dictation = "听写"
    case translation = "翻译"
    case ask = "指令"
    var id: Self { self }

    init(mode: CaptureMode?) {
        self = switch mode {
        case .dictation: .dictation
        case .translation: .translation
        case .ask: .ask
        case nil: .all
        }
    }

    var mode: CaptureMode? {
        switch self {
        case .all: nil
        case .dictation: .dictation
        case .translation: .translation
        case .ask: .ask
        }
    }
}

private struct HistoryDayGroup: Identifiable {
    let id: Date
    let title: String
    var entries: [HistoryEntry]
}

private struct HistoryPageTrigger: Equatable {
    let tailID: UUID?
    let hasMore: Bool
    let searchText: String
    let mode: CaptureMode?
    let listRevision: UInt64
}

private struct HistoryAutoRequest: Equatable {
    let tailID: UUID
    let listRevision: UInt64
}

struct HistoryView: View {
    @Bindable var session: AppSession
    @State private var tab: HistoryTab
    @State private var searchText: String
    @State private var isSearchExpanded: Bool
    @State private var pendingRetention: HistoryRetention?
    @State private var showRetentionConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @State private var lastAutoRequest: HistoryAutoRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    init(session: AppSession) {
        self.session = session
        let initialSearch = session.historySearch
        _tab = State(initialValue: HistoryTab(mode: session.historyModeFilter))
        _searchText = State(initialValue: initialSearch)
        _isSearchExpanded = State(initialValue: !initialSearch.isEmpty)
    }

    var body: some View {
        let dayGroups = groups

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LerroPageTitle(title: localized("历史"))
                    .frame(height: 40)
                Spacer()
                if !session.historyEntries.isEmpty {
                    LerroIconButton(systemName: "trash", help: "删除所有历史") {
                        showDeleteAllConfirmation = true
                    }
                }
            }

            retentionCard
                .frame(height: 140.5)
                .padding(.top, 12)

            HStack(spacing: 12) {
                Picker("历史类型", selection: $tab) {
                    ForEach(HistoryTab.allCases) { item in
                        Text(LocalizedStringKey(item.rawValue)).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 320)
                .onChange(of: tab) { _, item in
                    lastAutoRequest = nil
                    Task {
                        await session.updateHistoryQuery(
                            searchText: searchText,
                            mode: item.mode
                        )
                    }
                }

                Spacer()

                if isSearchExpanded {
                    LerroSearchField(placeholder: "搜索历史", text: $searchText)
                        .frame(width: 220)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
                LerroIconButton(systemName: "magnifyingglass", help: "搜索") {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        if isSearchExpanded && !searchText.isEmpty {
                            searchText = ""
                        } else {
                            isSearchExpanded.toggle()
                        }
                    }
                }
            }
            .padding(.top, 16)

            if dayGroups.isEmpty, session.isLoadingHistoryPage {
                historyLoadingState
            } else if dayGroups.isEmpty {
                EmptyStateView(
                    systemImage: retentionIsDisabled ? "eye.slash" : "clock.arrow.circlepath",
                    title: emptyTitle,
                    detail: emptyDetail
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(dayGroups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(LocalizedStringKey(group.title))
                                    .font(LerroTheme.font(12, weight: .medium))
                                    .foregroundStyle(LerroTheme.tertiaryText)
                                    .padding(.horizontal, 12)

                                LazyVStack(spacing: 0) {
                                    ForEach(group.entries) { entry in
                                        HistoryListRow(entry: entry, session: session)
                                        if entry.id != group.entries.last?.id {
                                            Divider().overlay(LerroTheme.thinBorder)
                                        }
                                    }
                                }
                                .background(LerroTheme.fillContainerThin)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: LerroTheme.cardRadius,
                                    style: .continuous
                                ))
                            }
                        }

                        historyPaginationFooter
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 15)
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.top, LerroTheme.contentTopPadding)
        .padding(.horizontal, LerroTheme.contentHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LerroTheme.main)
        .task(id: searchText) {
            await updateSearchAfterDelay(searchText)
        }
        .alert("更改保存时长", isPresented: $showRetentionConfirmation) {
            Button("取消", role: .cancel) { pendingRetention = nil }
            Button {
                if let pendingRetention {
                    session.setHistoryRetention(pendingRetention)
                }
                pendingRetention = nil
            } label: {
                Text(LocalizedStringKey(retentionActionTitle))
            }
        } message: {
            Text(LocalizedStringKey(retentionConfirmationMessage))
        }
        .alert("删除所有历史？", isPresented: $showDeleteAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { session.deleteAllHistory() }
        } message: {
            Text("此操作会删除这台 Mac 上保存的全部听写与指令记录。")
        }
    }

    private var historyLoadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在加载历史记录")
                .font(LerroTheme.font(14))
                .foregroundStyle(LerroTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
                .accessibilityLabel(localized("正在加载历史记录"))
    }

    private var historyPaginationFooter: some View {
        VStack(spacing: 8) {
            if session.isLoadingHistoryPage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载更多")
                }
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.secondaryText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(localized("正在加载更多历史记录"))
            } else if session.historyHasMore {
                Button("加载更多") {
                    Task { await loadNextHistoryPageManually() }
                }
                .buttonStyle(LerroPillButtonStyle())
                    .accessibilityHint(localized("加载下一页历史记录"))
            }

            if session.historyTotalCount > 0 {
                Text(verbatim: LerroInterfaceLocalization.format(
                    "已加载 %lld / %lld",
                    locale: locale,
                    arguments: Int64(session.historyEntries.count), Int64(session.historyTotalCount)
                ))
                    .lerroTypography(.caption)
                    .foregroundStyle(LerroTheme.tertiaryText)
                    .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                        "已加载 %lld 条，共 %lld 条历史记录",
                        locale: locale,
                        arguments: Int64(session.historyEntries.count), Int64(session.historyTotalCount)
                    )))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .task(id: pageTrigger) {
            await loadNextHistoryPageIfNeeded()
        }
    }

    private var pageTrigger: HistoryPageTrigger {
        HistoryPageTrigger(
            tailID: session.historyEntries.last?.id,
            hasMore: session.historyHasMore,
            searchText: session.historySearch,
            mode: session.historyModeFilter,
            listRevision: session.historyListRevision
        )
    }

    private var retentionCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text("保存历史")
                        .font(LerroTheme.font(14, weight: .medium))
                    Text("选择 Lerro 在这台 Mac 上保留历史记录的时间。")
                        .font(LerroTheme.font(14))
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Spacer()
                Picker("历史保存时长", selection: Binding(
                    get: { session.preferences.historyRetention },
                    set: {
                        pendingRetention = $0
                        showRetentionConfirmation = true
                    }
                )) {
                    Text("永不").tag(HistoryRetention.never)
                    Text("24 小时").tag(HistoryRetention.oneDay)
                    Text("1 周").tag(HistoryRetention.oneWeek)
                    Text("1 个月").tag(HistoryRetention.oneMonth)
                    Text("永久").tag(HistoryRetention.forever)
                }
                .labelsHidden()
                .frame(width: 160, height: 40)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: LerroTheme.cardIconSize, weight: .medium))
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text("数据隐私")
                        .font(LerroTheme.font(14, weight: .medium))
                    Text("历史记录只保存在本地，可随时删除。")
                        .font(LerroTheme.font(14))
                        .foregroundStyle(LerroTheme.secondaryText)
                }
                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .background(LerroTheme.topLayer)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder, lineWidth: 1)
        }
        .shadow(color: LerroTheme.cardShadow, radius: 2, x: 0, y: 1)
    }

    private var groups: [HistoryDayGroup] {
        let calendar = Calendar.current
        var result: [HistoryDayGroup] = []

        for entry in session.historyEntries {
            let date = calendar.startOfDay(for: entry.createdAt)
            if result.last?.id == date {
                result[result.count - 1].entries.append(entry)
                continue
            }

            let title: String
            if calendar.isDateInToday(date) {
                title = "今天"
            } else if calendar.isDateInYesterday(date) {
                title = "昨天"
            } else {
                title = date.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
                )
            }
            result.append(HistoryDayGroup(id: date, title: title, entries: [entry]))
        }

        return result
    }

    private var retentionIsDisabled: Bool { session.preferences.historyRetention == .never }
    private var emptyTitle: String {
        if retentionIsDisabled { return "历史记录已关闭" }
        if !searchText.isEmpty || tab != .all { return "没有匹配结果" }
        return "还没有历史记录"
    }
    private var emptyDetail: String {
        if retentionIsDisabled { return "在设置中选择保存时长，即可在本机保留新的记录。" }
        if !searchText.isEmpty || tab != .all { return "尝试新的关键词或历史类型。" }
        return "完成一次听写、翻译或指令后，记录会出现在这里。"
    }
    private var retentionActionTitle: String { pendingRetention == .never ? "关闭保存" : "确认更改" }
    private var retentionConfirmationMessage: String {
        switch pendingRetention {
        case .never: "新的记录将不再保存；已有记录可从本页单独删除。"
        case .oneDay, .oneWeek, .oneMonth: "超过所选时长的记录会根据本地保留策略清理。"
        default: "新的保存时长会立即用于后续记录。"
        }
    }

    private func updateSearchAfterDelay(_ value: String) async {
        do {
            try await Task.sleep(for: .milliseconds(120))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        guard value != session.historySearch || tab.mode != session.historyModeFilter else { return }
        lastAutoRequest = nil
        await session.updateHistoryQuery(searchText: value, mode: tab.mode)
    }

    private func loadNextHistoryPageIfNeeded() async {
        guard session.historyHasMore, !session.isLoadingHistoryPage else { return }
        guard let tailID = session.historyEntries.last?.id else { return }
        let request = HistoryAutoRequest(
            tailID: tailID,
            listRevision: session.historyListRevision
        )
        guard lastAutoRequest != request else { return }
        lastAutoRequest = request
        await session.loadNextHistoryPage()
    }

    private func loadNextHistoryPageManually() async {
        guard session.historyHasMore, !session.isLoadingHistoryPage else { return }
        if let tailID = session.historyEntries.last?.id {
            lastAutoRequest = HistoryAutoRequest(
                tailID: tailID,
                listRevision: session.historyListRevision
            )
        }
        await session.loadNextHistoryPage()
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct HistoryListRow: View {
    let entry: HistoryEntry
    let session: AppSession
    @State private var hovering = false
    @State private var showDeleteConfirmation = false
    @State private var showCorrection = false
    @State private var showContextReceipt = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: LerroTheme.navigationIconSize, weight: .medium))
                .foregroundStyle(LerroTheme.secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: primaryText)
                    .font(LerroTheme.font(14))
                    .foregroundStyle(entry.status == .failed ? LerroTheme.red : LerroTheme.text)
                    .lineLimit(entry.mode == .ask ? 2 : 1)
                HStack(spacing: 5) {
                    Text(LocalizedStringKey(modeTitle))
                    Text("·")
                    Text(verbatim: entry.applicationName)
                    Text("·")
                    Text(verbatim: entry.createdAt.formatted(
                        Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
                    ))
                }
                .lerroTypography(.caption)
                .foregroundStyle(LerroTheme.metadataText)
            }

            Spacer(minLength: 8)

            if entry.mode == .ask, entry.answerText?.isEmpty == false {
                Button("查看回答") { session.showHistoryAnswer(entry) }
                    .buttonStyle(LerroPillButtonStyle())
            }

            HStack(spacing: 4) {
                if entry.contextReceipt != nil
                    || entry.phaseTimings != nil
                    || (entry.editLineage?.versions.count ?? 0) > 1 {
                    Button { showContextReceipt.toggle() } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(LerroPressButtonStyle())
                    .help("上下文回执")
                    .accessibilityLabel(localized("上下文回执"))
                }
                Button { session.copyText(entry.finalText) } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LerroPressButtonStyle())
                .help("复制")
                .accessibilityLabel(localized("复制结果"))
                Menu {
                    Button("复制原始转写") { session.copyText(entry.rawText) }
                    if !entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("重新处理文本") { session.retryHistoryEntry(entry) }
                    }
                    if entry.mode == .dictation, entry.status == .completed {
                        Button("修正并学习") { showCorrection = true }
                    }
                    if entry.audioRelativePath != nil {
                        Button("下载音频") { session.exportAudio(entry) }
                    }
                    Divider()
                    Button("删除", role: .destructive) { showDeleteConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .accessibilityLabel(localized("更多操作"))
            }
            .foregroundStyle(LerroTheme.secondaryText)
            .opacity(hovering || colorSchemeContrast == .increased ? 1 : 0.62)
            }
            if showContextReceipt {
                contextReceiptDetails
                    .padding(.leading, 36)
                    .padding(.trailing, 8)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: entry.mode == .ask ? 65 : 49)
        .background(hovering ? LerroTheme.fillHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeOut(duration: LerroTheme.hoverDuration)) {
                hovering = isHovering
            }
        }
        .contextMenu {
            Button("复制结果") { session.copyText(entry.finalText) }
            Button("复制原始转写") { session.copyText(entry.rawText) }
            if !entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("重新处理文本") { session.retryHistoryEntry(entry) }
            }
            if entry.mode == .dictation, entry.status == .completed {
                Button("修正并学习") { showCorrection = true }
            }
            if entry.audioRelativePath != nil {
                Button("导出音频") { session.exportAudio(entry) }
            }
            Divider()
            Button("删除", role: .destructive) { showDeleteConfirmation = true }
        }
        .alert("删除这条记录？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { session.deleteHistoryEntry(entry) }
        }
        .sheet(isPresented: $showCorrection) {
            HistoryCorrectionSheet(entry: entry, session: session) {
                showCorrection = false
            }
        }
    }

    private var primaryText: String {
        if entry.status == .failed { return "转写失败，可从更多菜单重试" }
        if entry.status == .cancelled { return "已取消的录音" }
        if entry.status == .undone {
            return LerroInterfaceLocalization.format(
                "已撤回 · %@",
                locale: locale,
                arguments: entry.finalText
            )
        }
        if entry.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "没有检测到语音" }
        return entry.finalText
    }
    private var modeTitle: String {
        switch entry.mode {
        case .dictation: "听写"
        case .translation: "翻译"
        case .ask: "指令"
        }
    }
    private var icon: String {
        switch entry.mode {
        case .dictation: "waveform"
        case .translation: "character.bubble"
        case .ask: "sparkles"
        }
    }

    private var contextReceiptDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let route = entry.processingRoute {
                    receiptChip(routeTitle(route), icon: "cpu")
                }
                if entry.finishAction == .submitted {
                    receiptChip("已发送", icon: "paperplane.fill")
                }
                if let lineage = entry.editLineage, lineage.versions.count > 1 {
                    receiptChip(
                        LerroInterfaceLocalization.format(
                            "%lld 个版本",
                            locale: locale,
                            arguments: Int64(lineage.versions.count)
                        ),
                        icon: "clock.arrow.circlepath"
                    )
                }
                if let receipt = entry.contextReceipt {
                    ForEach(
                        receipt.capturedCategories.sorted { $0.rawValue < $1.rawValue },
                        id: \.self
                    ) { category in
                        receiptChip(contextCategoryTitle(category), icon: contextCategoryIcon(category))
                    }
                }
            }
            if let receipt = entry.contextReceipt, !receipt.remoteSharedCategories.isEmpty {
                Text(verbatim: LerroInterfaceLocalization.format(
                    "API 已共享：%@",
                    locale: locale,
                    arguments: receipt.remoteSharedCategories
                        .sorted { $0.rawValue < $1.rawValue }
                        .map(contextCategoryTitle)
                        .joined(separator: "、")
                ))
                .font(LerroTheme.font(12))
                .foregroundStyle(LerroTheme.metadataText)
            }
            if let timings = entry.phaseTimings {
                Text(verbatim: LerroInterfaceLocalization.format(
                    "录音 %.1fs · 转写 %.2fs · 处理 %.2fs · 写入 %.2fs",
                    locale: locale,
                    arguments: timings.recording,
                        timings.transcription,
                        timings.processing,
                        timings.delivery
                ))
                .font(LerroTheme.font(12))
                .monospacedDigit()
                .foregroundStyle(LerroTheme.metadataText)
            }
        }
        .transition(.opacity)
    }

    private func receiptChip(_ title: String, icon: String) -> some View {
        Label(LocalizedStringKey(title), systemImage: icon)
            .font(LerroTheme.font(12, weight: .medium))
            .foregroundStyle(LerroTheme.secondaryText)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(LerroTheme.fillSelected)
            .clipShape(Capsule())
    }

    private func routeTitle(_ route: HistoryProcessingRoute) -> String {
        switch route {
        case .raw: "原始转写"
        case .local: "本地 AI"
        case .remote: "API 模型"
        case .appleTranslation: "Apple 翻译"
        case .localSnippet: "本地快捷语"
        }
    }

    private func contextCategoryTitle(_ category: HistoryContextCategory) -> String {
        switch category {
        case .application: "应用"
        case .windowTitle: "窗口标题"
        case .nearbyText: "光标上下文"
        case .selectedText: "选中文字"
        case .dictionary: "个人词典"
        case .tone: "应用语气"
        }
    }

    private func contextCategoryIcon(_ category: HistoryContextCategory) -> String {
        switch category {
        case .application: "app"
        case .windowTitle: "macwindow"
        case .nearbyText: "text.cursor"
        case .selectedText: "selection.pin.in.out"
        case .dictionary: "character.book.closed"
        case .tone: "slider.horizontal.3"
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct HistoryCorrectionSheet: View {
    let entry: HistoryEntry
    let session: AppSession
    let close: () -> Void
    @State private var correctedText: String
    @State private var phrase = ""
    @State private var replacement = ""
    @State private var isSaving = false

    init(entry: HistoryEntry, session: AppSession, close: @escaping () -> Void) {
        self.entry = entry
        self.session = session
        self.close = close
        _correctedText = State(initialValue: entry.finalText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("修正并学习")
                .lerroTypography(.title)

            TextEditor(text: $correctedText)
                .font(LerroTheme.font(14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 150)
                .background(LerroTheme.main)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                        .stroke(LerroTheme.focusBorder, lineWidth: 1)
                }

            HStack(spacing: 10) {
                TextField("识别成了", text: $phrase)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundStyle(LerroTheme.secondaryText)
                TextField("以后写成", text: $replacement)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消", action: close)
                    .buttonStyle(LerroPillButtonStyle())
                    .disabled(isSaving)
                Button("保存") {
                    isSaving = true
                    Task { @MainActor in
                        let saved = await session.saveHistoryCorrection(
                            entry,
                            correctedText: correctedText,
                            phrase: phrase,
                            replacement: replacement
                        )
                        isSaving = false
                        if saved { close() }
                    }
                }
                .buttonStyle(LerroPillButtonStyle(prominent: true))
                .disabled(correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 560, height: 330)
        .background(LerroTheme.main)
    }
}
