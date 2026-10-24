import SwiftUI
import LerroCore

/// History page: day-grouped list on the left, detail of the selected entry on the right.
struct HistoryView: View {
    let session: AppSession

    @State private var tab: HistoryTab
    @State private var searchText: String
    @State private var selectedID: UUID?
    @State private var entryPendingDeletion: HistoryEntry?
    @Environment(\.locale) private var locale

    private static let listWidth: CGFloat = 360

    init(session: AppSession) {
        self.session = session
        _tab = State(initialValue: HistoryTab(mode: session.historyModeFilter))
        _searchText = State(initialValue: session.historySearch)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LerroTheme.main)
            .navigationTitle(Text(verbatim: LerroInterfaceLocalization.string("历史", locale: locale)))
            .searchable(text: $searchText, prompt: Text("搜索历史"))
            .toolbar {
                ToolbarItem {
                    Picker("历史类型", selection: $tab) {
                        ForEach(HistoryTab.allCases) { item in
                            Text(LocalizedStringKey(item.title)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .task(id: searchText) {
                await applyQuery(debounced: true)
            }
            .task(id: session.historyFocusID) {
                await focusRequestedEntry()
            }
            .onChange(of: tab) { _, _ in
                Task { await applyQuery(debounced: false) }
            }
            .confirmationDialog(
                Text("删除这条记录？"),
                isPresented: Binding(
                    get: { entryPendingDeletion != nil },
                    set: { if !$0 { entryPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: entryPendingDeletion
            ) { entry in
                Button("删除", role: .destructive) { delete(entry) }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("这条记录及其录音将被永久删除。")
            }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let entries = visibleEntries
        if entries.isEmpty {
            if isLoadingFirstResults {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text("正在加载历史记录"))
            } else {
                emptyState
            }
        } else {
            let selected = entries.first { $0.id == selectedID } ?? entries[0]
            HStack(spacing: 0) {
                HistoryListView(
                    session: session,
                    groups: HistoryPresentation.groups(from: entries, locale: locale),
                    selectedID: selected.id,
                    select: { selectedID = $0 },
                    requestDelete: { entryPendingDeletion = $0 }
                )
                .frame(width: Self.listWidth)
                Divider()
                HistoryDetailView(
                    entry: selected,
                    session: session,
                    requestDelete: { entryPendingDeletion = $0 }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if session.preferences.historyRetention == .never {
            LerroEmptyState(
                title: "历史记录已关闭",
                hint: "在设置中选择保存时长，即可在本机保留新的记录。"
            )
        } else if !searchText.isEmpty || tab != .all {
            LerroEmptyState(title: "没有匹配结果", hint: "尝试新的关键词或历史类型。")
        } else {
            LerroEmptyState(
                title: "还没有历史记录",
                hint: "完成一次听写或翻译后，记录会出现在这里。"
            )
        }
    }

    // MARK: State

    private var visibleEntries: [HistoryEntry] {
        session.historyEntries.filter { tab.includes($0) }
    }

    /// An empty list can still fill up while pages load, which matters for the client-side 未写入 filter.
    private var isLoadingFirstResults: Bool {
        session.isLoadingHistoryPage || (tab == .failed && session.historyHasMore)
    }

    private func applyQuery(debounced: Bool) async {
        if debounced {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
        }
        await session.updateHistoryQuery(searchText: searchText, mode: tab.mode)
    }

    /// Shows the entry requested through `AppSession.showHistoryEntry`, loading further pages until it is present.
    private func focusRequestedEntry() async {
        guard let id = session.historyFocusID else { return }
        tab = .all
        searchText = ""
        await session.updateHistoryQuery(searchText: "", mode: nil)
        while !Task.isCancelled,
              !session.historyEntries.contains(where: { $0.id == id }),
              session.historyHasMore {
            if session.isLoadingHistoryPage {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            let loadedCount = session.historyEntries.count
            await session.loadNextHistoryPage()
            if session.historyEntries.count == loadedCount { break }
        }
        guard !Task.isCancelled else { return }
        selectedID = id
        session.historyFocusID = nil
    }

    private func delete(_ entry: HistoryEntry) {
        let entries = visibleEntries
        if entry.id == (entries.first { $0.id == selectedID } ?? entries.first)?.id,
           let index = entries.firstIndex(where: { $0.id == entry.id }) {
            let neighbor = index + 1 < entries.count ? entries[index + 1] : (index > 0 ? entries[index - 1] : nil)
            selectedID = neighbor?.id
        }
        entryPendingDeletion = nil
        session.deleteHistoryEntry(entry)
    }
}
