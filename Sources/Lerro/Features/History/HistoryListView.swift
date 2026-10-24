import SwiftUI
import LerroCore

private struct HistoryPageTrigger: Equatable {
    let tailID: UUID?
    let hasMore: Bool
    let listRevision: UInt64
}

private struct HistoryAutoRequest: Equatable {
    let tailID: UUID
    let listRevision: UInt64
}

/// Grouped, paged list of history entries with sticky day headers.
struct HistoryListView: View {
    let session: AppSession
    let groups: [HistoryDayGroup]
    let selectedID: UUID?
    let select: (UUID) -> Void
    let requestDelete: (HistoryEntry) -> Void

    @State private var lastAutoRequest: HistoryAutoRequest?
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                HistoryRow(
                                    entry: entry,
                                    isSelected: entry.id == selectedID,
                                    session: session,
                                    select: {
                                        isFocused = true
                                        select(entry.id)
                                    },
                                    requestDelete: requestDelete
                                )
                                .id(entry.id)
                            }
                        } header: {
                            HistoryGroupHeader(title: group.title)
                        }
                    }
                    paginationFooter
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .lerroPageFocusable(.history, in: session)
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { moveSelection(by: -1) }
            .onKeyPress(.downArrow) { moveSelection(by: 1) }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private var paginationFooter: some View {
        Group {
            if session.isLoadingHistoryPage {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .accessibilityLabel(Text("正在加载更多"))
            } else if session.historyHasMore {
                Color.clear.frame(height: 34)
            }
        }
        .task(id: pageTrigger) {
            await loadNextPageIfNeeded()
        }
    }

    private var pageTrigger: HistoryPageTrigger {
        HistoryPageTrigger(
            tailID: session.historyEntries.last?.id,
            hasMore: session.historyHasMore,
            listRevision: session.historyListRevision
        )
    }

    private func loadNextPageIfNeeded() async {
        guard session.historyHasMore, !session.isLoadingHistoryPage else { return }
        guard let tailID = session.historyEntries.last?.id else { return }
        let request = HistoryAutoRequest(tailID: tailID, listRevision: session.historyListRevision)
        guard lastAutoRequest != request else { return }
        lastAutoRequest = request
        await session.loadNextHistoryPage()
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let ids = groups.flatMap { $0.entries.map(\.id) }
        guard !ids.isEmpty else { return .ignored }
        let current = selectedID.flatMap { ids.firstIndex(of: $0) } ?? (offset > 0 ? -1 : ids.count)
        let next = min(max(current + offset, 0), ids.count - 1)
        select(ids[next])
        return .handled
    }
}

private struct HistoryGroupHeader: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(LerroFont.sectionLabel)
            .foregroundStyle(LerroTheme.metadataText)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LerroTheme.main)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let session: AppSession
    let select: () -> Void
    let requestDelete: (HistoryEntry) -> Void

    @State private var isHovering = false
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                LerroAppIcon(
                    bundleIdentifier: entry.bundleIdentifier,
                    name: entry.applicationName,
                    size: 22
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: HistoryPresentation.listText(for: entry, locale: locale))
                        .font(LerroFont.body)
                        .foregroundStyle(hasPrimaryText ? LerroTheme.text : LerroTheme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    footnote
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: LerroTheme.hoverDuration), value: isHovering)
        .contextMenu {
            HistoryEntryMenuItems(entry: entry, session: session, requestDelete: requestDelete)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footnote: some View {
        HStack(spacing: 6) {
            if entry.status == .failed {
                HStack(spacing: 4) {
                    LerroStatusDot(color: LerroTheme.warning)
                    Text(LocalizedStringKey(HistoryPresentation.hasText(entry) ? "未写入，已复制" : "未写入"))
                        .fontWeight(.semibold)
                        .foregroundStyle(LerroTheme.warning)
                }
            }
            Text(verbatim: HistoryPresentation.footnote(for: entry, locale: locale))
                .foregroundStyle(LerroTheme.metadataText)
        }
        .font(LerroFont.footnote)
        .lineLimit(1)
    }

    private var hasPrimaryText: Bool {
        switch entry.status {
        case .failed, .undone: true
        case .completed: HistoryPresentation.hasText(entry)
        case .cancelled: false
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var background: Color {
        if isSelected { return LerroTheme.accentSoft }
        return isHovering ? LerroTheme.fillHover : Color.clear
    }
}
