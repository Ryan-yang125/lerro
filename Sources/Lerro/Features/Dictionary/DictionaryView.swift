import AppKit
import SwiftUI
import LerroCore

private enum DictionaryTab: String, CaseIterable, Identifiable {
    case all = "全部"
    case learned = "自动添加"
    case manual = "手动添加"
    var id: Self { self }

    init(source: DictionaryEntrySource?) {
        self = switch source {
        case .learned: .learned
        case .manual: .manual
        case nil: .all
        }
    }

    var source: DictionaryEntrySource? {
        switch self {
        case .all: nil
        case .learned: .learned
        case .manual: .manual
        }
    }
}

struct DictionaryView: View {
    @Bindable var session: AppSession
    @State private var tab: DictionaryTab
    @State private var searchText: String
    @State private var displayedEntries: [DictionaryEntry]
    @State private var isSearchExpanded: Bool
    @State private var editingEntry: DictionaryEntry?
    @State private var isEditorPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    init(session: AppSession) {
        self.session = session
        let initialTab = DictionaryTab(source: session.dictionarySourceFilter)
        let initialSearch = session.dictionarySearch
        _tab = State(initialValue: initialTab)
        _searchText = State(initialValue: initialSearch)
        _displayedEntries = State(initialValue: Self.filtered(
            session.dictionaryEntries,
            searchText: initialSearch,
            source: initialTab.source
        ))
        _isSearchExpanded = State(initialValue: !initialSearch.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LerroPageTitle(title: localized("词典"))
                    .frame(height: 40)
                Spacer()
                Button("新建词条", systemImage: "plus") {
                    editingEntry = nil
                    isEditorPresented = true
                }
                .buttonStyle(LerroPillButtonStyle(prominent: true))
            }

            HStack(spacing: 12) {
                Picker("词条来源", selection: $tab) {
                    ForEach(DictionaryTab.allCases) { item in
                        Text(LocalizedStringKey(item.rawValue)).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
                .onChange(of: tab) { _, item in
                    session.dictionarySourceFilter = item.source
                    updateDisplayedEntries()
                }

                Spacer()

                if isSearchExpanded {
                    LerroSearchField(placeholder: "搜索词典", text: $searchText)
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

            if displayedEntries.isEmpty {
                EmptyStateView(
                    systemImage: "character.book.closed",
                    title: searchText.isEmpty ? "建立您的个人词典" : "没有匹配词语",
                    detail: searchText.isEmpty
                        ? "添加姓名、品牌、缩写与专业术语，让每次听写更准确。"
                        : "尝试新的关键词，或清空当前搜索。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedEntries) { entry in
                            DictionaryListRow(entry: entry) {
                                editingEntry = entry
                                isEditorPresented = true
                            } delete: {
                                session.deleteDictionaryEntry(entry)
                            }
                            if entry.id != displayedEntries.last?.id {
                                Divider().overlay(LerroTheme.thinBorder)
                            }
                        }
                    }
                    .background(LerroTheme.topLayer)
                    .clipShape(RoundedRectangle(
                        cornerRadius: LerroTheme.cardRadius,
                        style: .continuous
                    ))
                    .overlay {
                        RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                            .stroke(LerroTheme.thinBorder, lineWidth: 1)
                    }
                    .shadow(color: LerroTheme.cardShadow, radius: 2, x: 0, y: 1)
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
        .onChange(of: session.dictionaryEntries) {
            updateDisplayedEntries()
        }
        .sheet(isPresented: $isEditorPresented, onDismiss: { editingEntry = nil }) {
            DictionaryEditorView(entry: editingEntry) { phrase, replacement in
                var entry = editingEntry ?? DictionaryEntry(phrase: phrase, replacement: replacement)
                entry.phrase = phrase
                entry.replacement = replacement
                entry.source = .manual
                return await session.saveDictionaryEntry(entry)
            } importCSV: {
                await importCSV()
            } cancel: {
                closeEditor()
            }
        }
    }

    private func updateSearchAfterDelay(_ value: String) async {
        do {
            try await Task.sleep(for: .milliseconds(120))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        session.dictionarySearch = value
        updateDisplayedEntries()
    }

    private func updateDisplayedEntries() {
        displayedEntries = Self.filtered(
            session.dictionaryEntries,
            searchText: searchText,
            source: tab.source
        )
    }

    private static func filtered(
        _ entries: [DictionaryEntry],
        searchText: String,
        source: DictionaryEntrySource?
    ) -> [DictionaryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let sourceMatches = source.map { entry.source == $0 } ?? true
            let searchMatches = query.isEmpty
                || entry.phrase.localizedCaseInsensitiveContains(query)
                || entry.replacement.localizedCaseInsensitiveContains(query)
            return sourceMatches && searchMatches
        }
    }

    private func closeEditor() {
        isEditorPresented = false
        editingEntry = nil
    }

    private func importCSV() async -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 2_000_000 else {
                session.currentError = localized("词典导入失败：CSV 文件不能超过 2 MB")
                return false
            }
            let contents = try String(contentsOf: url, encoding: .utf8)
            return await session.importDictionaryCSV(contents)
        } catch {
            session.currentError = String(
                format: localized("词典导入失败：%@"),
                locale: locale,
                error.localizedDescription
            )
            return false
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct DictionaryListRow: View {
    let entry: DictionaryEntry
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovering = false
    @State private var showDeleteConfirmation = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.phrase)
                    .font(LerroTheme.font(14, weight: .medium))
                    .foregroundStyle(LerroTheme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(entry.source == .learned ? "自动添加" : entry.isSnippet ? "快捷语" : "手动添加"))
                    if entry.replacement != entry.phrase {
                        Text("·")
                        Text(verbatim: entry.replacement)
                    }
                }
                .lerroTypography(.caption)
                .foregroundStyle(LerroTheme.metadataText)
            }
            Spacer()
            HStack(spacing: 2) {
                Button(action: edit) {
                    Image(systemName: "pencil")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LerroPressButtonStyle())
                .help("编辑")
                .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                    "编辑 %@",
                    locale: locale,
                    arguments: entry.phrase
                )))
                Button { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LerroPressButtonStyle())
                .help("删除")
                .accessibilityLabel(Text(verbatim: LerroInterfaceLocalization.format(
                    "删除 %@",
                    locale: locale,
                    arguments: entry.phrase
                )))
            }
            .foregroundStyle(LerroTheme.secondaryText)
            .opacity(hovering || colorSchemeContrast == .increased ? 1 : 0.62)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(hovering ? LerroTheme.fillHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeOut(duration: LerroTheme.hoverDuration)) {
                hovering = isHovering
            }
        }
        .contextMenu {
            Button("编辑", action: edit)
            Button("删除", role: .destructive) { showDeleteConfirmation = true }
        }
        .alert("删除这个词语？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: delete)
        }
    }

}

private struct DictionaryEditorView: View {
    private enum EntryKind: String, CaseIterable, Identifiable {
        case term = "词条"
        case snippet = "快捷语"
        var id: Self { self }
    }

    let existingEntry: DictionaryEntry?
    let save: (String, String) async -> Bool
    let importCSV: () async -> Bool
    let cancel: () -> Void
    @State private var phrase: String
    @State private var replacement: String
    @State private var kind: EntryKind
    @State private var isWorking = false
    @FocusState private var focused: Bool

    init(
        entry: DictionaryEntry?,
        save: @escaping (String, String) async -> Bool,
        importCSV: @escaping () async -> Bool,
        cancel: @escaping () -> Void
    ) {
        existingEntry = entry
        self.save = save
        self.importCSV = importCSV
        self.cancel = cancel
        _phrase = State(initialValue: entry?.phrase ?? "")
        _replacement = State(initialValue: entry?.replacement ?? "")
        _kind = State(initialValue: entry?.isSnippet == true
            ? .snippet
            : .term)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringKey(existingEntry == nil ? "新建" : "编辑"))
                .lerroTypography(.title)
                .frame(height: 30)

            Picker("类型", selection: $kind) {
                ForEach(EntryKind.allCases) { kind in
                    Text(LocalizedStringKey(kind.rawValue)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 16)

            TextField(kind == .snippet ? "说出触发词" : "输入词语", text: $phrase)
                .textFieldStyle(.plain)
                .lerroTypography(.body)
                .padding(.horizontal, 10)
                .frame(height: 41)
                .background(LerroTheme.main)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                        .stroke(LerroTheme.focusBorder, lineWidth: 1)
                }
                .focused($focused)
                .padding(.top, 12)
                .onSubmit(savePhrase)

            if kind == .snippet {
                TextEditor(text: $replacement)
                    .font(LerroTheme.font(14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 100)
                    .background(LerroTheme.main)
                    .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                            .stroke(LerroTheme.focusBorder, lineWidth: 1)
                    }
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                Button("导入 CSV") { perform(importCSV) }
                    .buttonStyle(LerroPillButtonStyle())
                    .disabled(isWorking)
                Spacer()
                Button("取消", action: cancel)
                    .buttonStyle(LerroPillButtonStyle())
                    .disabled(isWorking)
                Button(action: savePhrase) {
                    Text(LocalizedStringKey(existingEntry == nil ? "添加" : "保存"))
                }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                    .disabled(trimmedPhrase.isEmpty || (kind == .snippet && trimmedReplacement.isEmpty) || isWorking)
            }
            .padding(.top, 24)
        }
        .padding(24)
        .frame(width: 448, height: kind == .snippet ? 360 : 242, alignment: .topLeading)
        .background(LerroTheme.main)
        .onAppear { focused = true }
        .onChange(of: phrase) {
            if phrase.count > 100 { phrase = String(phrase.prefix(100)) }
        }
        .onChange(of: replacement) {
            if replacement.count > 4_000 { replacement = String(replacement.prefix(4_000)) }
        }
    }

    private var trimmedPhrase: String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedReplacement: String {
        replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func savePhrase() {
        guard !trimmedPhrase.isEmpty else { return }
        perform { await save(trimmedPhrase, kind == .snippet ? trimmedReplacement : trimmedPhrase) }
    }

    private func perform(_ operation: @escaping () async -> Bool) {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            let succeeded = await operation()
            isWorking = false
            if succeeded { cancel() }
        }
    }
}
