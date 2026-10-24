import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LerroCore

private enum DictionaryScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case learned = "自动记住"
    case manual = "手动添加"
    var id: Self { self }

    func includes(_ entry: DictionaryEntry) -> Bool {
        switch self {
        case .all: true
        case .learned: entry.source == .learned
        case .manual: entry.source == .manual
        }
    }
}

private enum DictionaryGroup: CaseIterable, Identifiable {
    case recent
    case learned
    case manual
    var id: Self { self }

    var title: String {
        switch self {
        case .recent: "本周新增"
        case .learned: "自动记住"
        case .manual: "手动添加"
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
    var isRecentlyLearned: Bool {
        source == .learned && createdAt > Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
    }

    var group: DictionaryGroup {
        if source == .learned { return isRecentlyLearned ? .recent : .learned }
        return .manual
    }
}

struct DictionaryView: View {
    @Bindable var session: AppSession
    @State private var scope: DictionaryScope = .all
    @State private var selection = Set<DictionaryEntry.ID>()
    @State private var editorTarget: DictionaryEditorTarget?
    @State private var pendingDeletion: [DictionaryEntry] = []
    @Environment(\.locale) private var locale

    var body: some View {
        let entries = displayedEntries
        Group {
            if entries.isEmpty {
                LerroEmptyState(
                    title: session.dictionarySearch.isEmpty ? "建立你的个人词典" : "没有匹配词语",
                    hint: session.dictionarySearch.isEmpty
                        ? "添加姓名、品牌、缩写与专业术语，让每次听写更准确。"
                        : "尝试新的关键词，或清空当前搜索。"
                )
            } else {
                list(entries)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LerroTheme.main)
        .navigationTitle(Text(verbatim: localized("词典")))
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

    private func list(_ entries: [DictionaryEntry]) -> some View {
        let sections = DictionaryGroup.allCases.compactMap { group -> (DictionaryGroup, [DictionaryEntry])? in
            let members = entries.filter { $0.group == group }
            return members.isEmpty ? nil : (group, members)
        }
        return List(selection: $selection) {
            ForEach(Array(sections.enumerated()), id: \.element.0) { index, section in
                Section {
                    ForEach(section.1) { entry in
                        row(entry)
                            .listRowBackground(section.0 == .recent ? LerroTheme.success.opacity(0.08) : nil)
                    }
                } header: {
                    sectionHeader(section.0, showsLimitNote: index == 0 && scope == .all)
                }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
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

    private func sectionHeader(_ group: DictionaryGroup, showsLimitNote: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(group.title))
                .font(LerroFont.cardTitle)
                .foregroundStyle(LerroTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if showsLimitNote {
                Text("只有最常用的 40 个词条会发给 AI")
                    .font(LerroFont.footnote)
                    .foregroundStyle(LerroTheme.metadataText)
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ entry: DictionaryEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                title(entry)
                sourceLine(entry)
            }
            Spacer(minLength: 8)
            if let bundleIdentifier = entry.applicationBundleIdentifier {
                let name = applicationName(for: bundleIdentifier)
                LerroAppIcon(bundleIdentifier: bundleIdentifier, name: name, size: 16)
                    .help(name)
                    .accessibilityLabel(Text(verbatim: name))
            }
            Text(verbatim: trailingText(entry))
                .font(LerroFont.caption.monospacedDigit())
                .foregroundStyle(LerroTheme.metadataText)
                .lineLimit(1)
            Button {
                pendingDeletion = [entry]
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LerroTheme.tertiaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("删除")
            .accessibilityLabel(Text("删除"))
        }
        .padding(.vertical, 3)
    }

    private func title(_ entry: DictionaryEntry) -> some View {
        Text(verbatim: entry.replacement)
            .font(LerroFont.body.weight(.semibold))
            .lineLimit(1)
    }

    @ViewBuilder
    private func sourceLine(_ entry: DictionaryEntry) -> some View {
        if entry.source == .learned {
            if let historyID = entry.learnedFromEntryIDs.last {
                HStack(spacing: 4) {
                    Text(verbatim: learnedSummary(entry))
                    Text(verbatim: "·")
                    Button {
                        session.showHistoryEntry(historyID)
                    } label: {
                        Text("查看")
                            .foregroundStyle(LerroTheme.accentText)
                    }
                    .buttonStyle(.plain)
                }
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
                .lineLimit(1)
            } else if entry.phrase != entry.replacement {
                Text(verbatim: LerroInterfaceLocalization.format(
                    "由「%@」改正而来",
                    locale: locale,
                    arguments: entry.phrase
                ))
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
                .lineLimit(1)
            }
        } else {
            Text("手动添加")
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
        }
    }

    private func learnedSummary(_ entry: DictionaryEntry) -> String {
        let count = entry.learnedFromEntryIDs.count
        guard let heard = entry.heardAs.last else {
            return LerroInterfaceLocalization.format("出现在 %lld 条听写里", locale: locale, arguments: count)
        }
        return LerroInterfaceLocalization.format(
            "出现在 %lld 条听写里 · 曾被听成 %@",
            locale: locale,
            arguments: count,
            heard
        )
    }

    private func trailingText(_ entry: DictionaryEntry) -> String {
        guard entry.group == .recent else {
            return LerroInterfaceLocalization.format("用了 %lld 次", locale: locale, arguments: entry.useCount)
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(entry.createdAt) { return localized("今天") }
        if calendar.isDateInYesterday(entry.createdAt) { return localized("昨天") }
        return entry.createdAt.formatted(.dateTime.month().day().locale(locale))
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
        return filtered.sorted { lhs, rhs in
            if lhs.group == .recent, rhs.group == .recent { return lhs.createdAt > rhs.createdAt }
            if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
            return lhs.phrase.localizedStandardCompare(rhs.phrase) == .orderedAscending
        }
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
            : localized("删除这个词条？")
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
                arguments: localized(error.localizedDescription)
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
                arguments: localized(error.localizedDescription)
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
    let session: AppSession
    let existing: DictionaryEntry?
    let close: () -> Void
    @State private var phrase: String
    @State private var replacement: String
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
        _applicationBundleIdentifier = State(initialValue: entry?.applicationBundleIdentifier ?? "")
    }

    private var isLearned: Bool { existing?.source == .learned }
    private var trimmedPhrase: String { phrase.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedReplacement: String { replacement.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedPhrase.isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("听到", text: $phrase)
                    .focused($phraseFocused)
                    .onSubmit(save)

                if isLearned {
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
        switch entry.source {
        case .manual:
            entry.replacement = trimmedPhrase
        case .learned:
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
