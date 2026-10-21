import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LerroCore

private enum DictionaryScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case learned = "自动学习"
    case manual = "手动"
    case snippets = "快捷语"
    var id: Self { self }

    func includes(_ entry: DictionaryEntry) -> Bool {
        switch self {
        case .all: true
        case .learned: entry.source == .learned
        case .manual: entry.source == .manual && !entry.isSnippet
        case .snippets: entry.isSnippet
        }
    }
}

private enum DictionaryEditorTarget: Identifiable {
    case new
    case edit(DictionaryEntry)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let entry): entry.id.uuidString
        }
    }

    var entry: DictionaryEntry? {
        switch self {
        case .new: nil
        case .edit(let entry): entry
        }
    }
}

fileprivate extension DictionaryEntry {
    var scopeSortKey: String { applicationBundleIdentifier ?? "" }

    var sourceSortKey: Int {
        if isSnippet { return 2 }
        return source == .learned ? 0 : 1
    }

    var isRecentlyLearned: Bool {
        source == .learned && createdAt > Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
    }
}

struct DictionaryView: View {
    @Bindable var session: AppSession
    @State private var scope: DictionaryScope = .all
    @State private var sortOrder: [KeyPathComparator<DictionaryEntry>] = []
    @State private var selection = Set<DictionaryEntry.ID>()
    @State private var editorTarget: DictionaryEditorTarget?
    @State private var pendingDeletion: [DictionaryEntry] = []
    @Environment(\.locale) private var locale

    var body: some View {
        let entries = displayedEntries
        Group {
            if entries.isEmpty {
                LerroEmptyState(
                    title: session.dictionarySearch.isEmpty ? "建立您的个人词典" : "没有匹配词语",
                    hint: session.dictionarySearch.isEmpty
                        ? "添加姓名、品牌、缩写与专业术语，让每次听写更准确。"
                        : "尝试新的关键词，或清空当前搜索。"
                )
            } else {
                table(entries)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LerroTheme.main)
        .navigationTitle(Text("词典"))
        .searchable(text: $session.dictionarySearch, prompt: Text("搜索词典"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("词条来源", selection: $scope) {
                    ForEach(DictionaryScope.allCases) { item in
                        Text(verbatim: "\(localized(item.rawValue)) \(count(of: item))").tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem {
                Menu {
                    Button("导入 CSV…") { Task { await importCSV() } }
                    Button("导出 CSV…") { exportCSV() }
                        .disabled(session.dictionaryEntries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel(Text("更多"))
                }
                .menuIndicator(.hidden)
                .help("更多")
            }
            ToolbarItem {
                Button {
                    editorTarget = .new
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(LerroButtonStyle(.primary))
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .task {
            session.refreshAvailableApplications()
        }
        .onChange(of: session.dictionaryEntries) { _, entries in
            selection.formIntersection(Set(entries.map(\.id)))
        }
        .sheet(item: $editorTarget) { target in
            DictionaryEditorSheet(session: session, entry: target.entry) {
                editorTarget = nil
            }
        }
        .confirmationDialog(
            Text(verbatim: deletionTitle),
            isPresented: Binding(
                get: { !pendingDeletion.isEmpty },
                set: { if !$0 { pendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                pendingDeletion.forEach(session.deleteDictionaryEntry)
                selection.subtract(pendingDeletion.map(\.id))
                pendingDeletion = []
            }
            Button("取消", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func table(_ entries: [DictionaryEntry]) -> some View {
        Table(entries, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("听到", value: \.phrase) { entry in
                Text(verbatim: entry.phrase)
                    .font(LerroFont.body)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 180)

            TableColumn("写成", value: \.replacement) { entry in
                replacementCell(entry)
            }
            .width(min: 140, ideal: 260)

            TableColumn("范围", value: \.scopeSortKey) { entry in
                scopeCell(entry)
            }
            .width(min: 90, ideal: 140)

            TableColumn("来源", value: \.sourceSortKey) { entry in
                Text(LocalizedStringKey(sourceTitle(entry)))
                    .font(LerroFont.body)
                    .foregroundStyle(LerroTheme.secondaryText)
            }
            .width(min: 64, ideal: 84)

            TableColumn("使用", value: \.useCount) { entry in
                Text(verbatim: "\(entry.useCount)")
                    .font(LerroFont.body.monospacedDigit())
                    .foregroundStyle(LerroTheme.secondaryText)
            }
            .width(min: 48, ideal: 60)
            .alignment(.numeric)
        }
        .tableStyle(.inset)
        .contextMenu(forSelectionType: DictionaryEntry.ID.self) { ids in
            let targets = selectedEntries(for: ids)
            if targets.count == 1, let entry = targets.first {
                Button("编辑") { editorTarget = .edit(entry) }
            }
            if targets.contains(where: { $0.applicationBundleIdentifier != nil }) {
                Button("提升为全局") { promoteToGlobal(targets) }
            }
            if !targets.isEmpty {
                Button("删除", role: .destructive) { pendingDeletion = targets }
            }
        } primaryAction: { ids in
            if let entry = selectedEntries(for: ids).first, ids.count == 1 {
                editorTarget = .edit(entry)
            }
        }
        .onDeleteCommand {
            let targets = selectedEntries(for: selection)
            if !targets.isEmpty { pendingDeletion = targets }
        }
    }

    private func replacementCell(_ entry: DictionaryEntry) -> some View {
        HStack(spacing: 6) {
            if entry.isSnippet {
                Text(verbatim: entry.replacement.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineLimit(1)
            } else {
                Text(verbatim: entry.replacement)
                    .font(LerroFont.bodyEmphasis)
                    .lineLimit(1)
            }
            if entry.isRecentlyLearned {
                Text("新")
                    .font(LerroFont.footnote.weight(.semibold))
                    .foregroundStyle(LerroTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(LerroTheme.accentSoft, in: Capsule())
                    .accessibilityLabel(Text("最近学到"))
            }
        }
    }

    @ViewBuilder
    private func scopeCell(_ entry: DictionaryEntry) -> some View {
        if let bundleIdentifier = entry.applicationBundleIdentifier {
            let name = applicationName(for: bundleIdentifier)
            HStack(spacing: 6) {
                LerroAppIcon(bundleIdentifier: bundleIdentifier, name: name, size: 16)
                Text(verbatim: name)
                    .font(LerroFont.body)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("全局")
                .font(LerroFont.body)
                .foregroundStyle(LerroTheme.secondaryText)
        }
    }

    // MARK: Data

    private var displayedEntries: [DictionaryEntry] {
        let query = session.dictionarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = session.dictionaryEntries.filter { entry in
            scope.includes(entry)
                && (query.isEmpty
                    || entry.phrase.localizedCaseInsensitiveContains(query)
                    || entry.replacement.localizedCaseInsensitiveContains(query))
        }
        return filtered.sorted(using: sortOrder)
    }

    private func count(of scope: DictionaryScope) -> Int {
        return session.dictionaryEntries.reduce(0) { $0 + (scope.includes($1) ? 1 : 0) }
    }

    private func selectedEntries(for ids: Set<DictionaryEntry.ID>) -> [DictionaryEntry] {
        session.dictionaryEntries.filter { ids.contains($0.id) }
    }

    private func applicationName(for bundleIdentifier: String) -> String {
        session.availableApplications.first { $0.bundleIdentifier == bundleIdentifier }?.name
            ?? session.preferences.appToneProfiles.first { $0.bundleIdentifier == bundleIdentifier }?.applicationName
            ?? bundleIdentifier.split(separator: ".").last.map(String.init)
            ?? bundleIdentifier
    }

    private func sourceTitle(_ entry: DictionaryEntry) -> String {
        if entry.isSnippet { return "快捷语" }
        return entry.source == .learned ? "自动学习" : "手动"
    }

    private func promoteToGlobal(_ targets: [DictionaryEntry]) {
        let scoped = targets.filter { $0.applicationBundleIdentifier != nil }
        Task {
            for var entry in scoped {
                entry.applicationBundleIdentifier = nil
                _ = await session.saveDictionaryEntry(entry)
            }
        }
    }

    private var deletionTitle: String {
        pendingDeletion.count > 1
            ? LerroInterfaceLocalization.format("删除 %lld 个词条？", locale: locale, arguments: pendingDeletion.count)
            : localized("删除这个词语？")
    }

    // MARK: CSV

    private func importCSV() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 2_000_000 else {
                session.currentError = localized("词典导入失败：CSV 文件不能超过 2 MB")
                return
            }
            let contents = try String(contentsOf: url, encoding: .utf8)
            _ = await session.importDictionaryCSV(contents)
        } catch {
            session.currentError = LerroInterfaceLocalization.format(
                "词典导入失败：%@",
                locale: locale,
                arguments: error.localizedDescription
            )
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = localized("词典") + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Matches DictionaryCSVParser: the phrase ends at the first comma and
        // the rest of the line is the replacement.
        var rows = ["phrase,replacement"]
        for entry in session.dictionaryEntries {
            rows.append(Self.csvLine(entry.phrase) + "," + Self.csvLine(entry.replacement))
        }
        do {
            try (rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            session.currentError = LerroInterfaceLocalization.format(
                "词典导出失败：%@",
                locale: locale,
                arguments: error.localizedDescription
            )
        }
    }

    private static func csvLine(_ value: String) -> String {
        value.components(separatedBy: .newlines).joined(separator: " ")
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

// MARK: - Editor

private struct DictionaryEditorSheet: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case term = "词条"
        case snippet = "快捷语"
        var id: Self { self }
    }

    let session: AppSession
    let existing: DictionaryEntry?
    let close: () -> Void
    @State private var phrase: String
    @State private var replacement: String
    @State private var kind: Kind
    @State private var applicationBundleIdentifier: String
    @State private var isSaving = false
    @FocusState private var phraseFocused: Bool
    @Environment(\.locale) private var locale

    init(session: AppSession, entry: DictionaryEntry?, close: @escaping () -> Void) {
        self.session = session
        self.existing = entry
        self.close = close
        _phrase = State(initialValue: entry?.phrase ?? "")
        _replacement = State(initialValue: entry?.replacement ?? "")
        _kind = State(initialValue: entry?.isSnippet == true ? .snippet : .term)
        _applicationBundleIdentifier = State(initialValue: entry?.applicationBundleIdentifier ?? "")
    }

    private var isLearned: Bool { existing?.source == .learned }
    private var trimmedPhrase: String { phrase.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedReplacement: String { replacement.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedPhrase.isEmpty && !(kind == .snippet && trimmedReplacement.isEmpty) && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if !isLearned {
                    Picker("类型", selection: $kind) {
                        ForEach(Kind.allCases) { item in
                            Text(LocalizedStringKey(item.rawValue)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                TextField("听到", text: $phrase)
                    .focused($phraseFocused)
                    .onSubmit(save)

                if kind == .snippet {
                    LabeledContent("写成") {
                        TextEditor(text: $replacement)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(height: 96)
                            .background(LerroTheme.fillContainerThin, in: RoundedRectangle(
                                cornerRadius: LerroTheme.controlRadius,
                                style: .continuous
                            ))
                    }
                } else if isLearned {
                    TextField("写成", text: $replacement)
                }

                Picker("范围", selection: $applicationBundleIdentifier) {
                    Text("全局").tag("")
                    ForEach(scopeOptions, id: \.bundleIdentifier) { option in
                        Text(verbatim: option.name).tag(option.bundleIdentifier)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack(spacing: 8) {
                Spacer()
                Button("取消", action: close)
                    .buttonStyle(LerroButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("保存", action: save)
                    .buttonStyle(LerroButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { phraseFocused = true }
        .onChange(of: phrase) {
            if phrase.count > 100 { phrase = String(phrase.prefix(100)) }
        }
        .onChange(of: replacement) {
            if replacement.count > 4_000 { replacement = String(replacement.prefix(4_000)) }
        }
    }

    private var scopeOptions: [(bundleIdentifier: String, name: String)] {
        var options = session.availableApplications
            .map { (bundleIdentifier: $0.bundleIdentifier, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !applicationBundleIdentifier.isEmpty,
           !options.contains(where: { $0.bundleIdentifier == applicationBundleIdentifier }) {
            options.insert((applicationBundleIdentifier, applicationBundleIdentifier), at: 0)
        }
        return options
    }

    private func save() {
        guard canSave else { return }
        var entry = existing ?? DictionaryEntry(phrase: trimmedPhrase, source: .manual)
        entry.phrase = trimmedPhrase
        switch (kind, entry.source) {
        case (.snippet, _):
            entry.replacement = trimmedReplacement
        case (.term, .manual):
            entry.replacement = trimmedPhrase
        case (.term, .learned):
            entry.replacement = trimmedReplacement.isEmpty ? trimmedPhrase : trimmedReplacement
        }
        entry.applicationBundleIdentifier = applicationBundleIdentifier.isEmpty
            ? nil
            : applicationBundleIdentifier
        isSaving = true
        Task { @MainActor in
            let succeeded = await session.saveDictionaryEntry(entry)
            isSaving = false
            if succeeded { close() }
        }
    }
}
