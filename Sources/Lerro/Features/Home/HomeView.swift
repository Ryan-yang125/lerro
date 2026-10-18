import SwiftUI
import LerroCore

struct HomeView: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @State private var range: UsageRange = .today

    var body: some View {
        // One ScrollView for both states: the window toolbar picks its
        // background from the first scroll view it sees, so swapping an
        // empty state for a ScrollView after history loads left a stale
        // toolbar background in dark mode.
        ScrollView {
            if session.historyAllCount == 0 {
                LerroEmptyState(title: emptyTitle, hint: nil)
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical)
            } else {
                content
            }
        }
        .background(LerroTheme.main)
        .navigationTitle("首页")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("统计范围", selection: $range) {
                    ForEach(UsageRange.allCases, id: \.self) { range in
                        Text(LocalizedStringKey(Self.title(for: range))).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 0) {
                HomeHeroView(
                    summary: session.usageStatistics.summary(for: range),
                    rangeTitle: localized(Self.title(for: range)),
                    dailyWords: session.usageStatistics.dailyWords
                )
                HomeStripView(session: session)
                HomeRecentView(session: session)
                if !session.recentlyLearnedEntries.isEmpty {
                    HomeLearnedView(session: session)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 24)
            .padding(.horizontal, LerroTheme.contentHorizontalPadding)
            .frame(maxWidth: 880, alignment: .topLeading)
            .frame(maxWidth: .infinity)
    }

    private var emptyTitle: String {
        let shortcut = session.preferences.hotkeys
            .first { $0.action == .dictate }?.displayName ?? ""
        return LerroInterfaceLocalization.format(
            "按 %@ 说一句话试试",
            locale: locale,
            arguments: shortcut
        )
    }

    static func title(for range: UsageRange) -> String {
        switch range {
        case .today: "今天"
        case .lastSevenDays: "7 天"
        case .allTime: "全部"
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}
