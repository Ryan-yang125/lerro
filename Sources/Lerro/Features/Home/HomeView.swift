import SwiftUI
import LerroCore

struct HomeView: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale

    var body: some View {
        LerroSplitLayout(axis: .vertical, firstLength: LerroTheme.pageHeaderHeight) {
            LerroPageHeader(LerroInterfaceLocalization.string("首页", locale: locale)) {
                HomeShortcutsView(hotkeys: session.preferences.hotkeys)
            }
            ScrollView {
                if session.homeStatistics.totalDictations == 0 {
                    LerroEmptyState(title: emptyTitle, hint: nil)
                        .frame(maxWidth: .infinity)
                        .containerRelativeFrame(.vertical)
                } else {
                    content
                }
            }
        }
        .background(LerroTheme.main.ignoresSafeArea())
    }

    private var content: some View {
        let statistics = session.homeStatistics
        return VStack(alignment: .leading, spacing: LerroTheme.cardSpacing) {
            HomeHeaderView(totalWords: statistics.total.totalWords)
                .padding(.bottom, 8)
            HomeStatCards(statistics: statistics)
            if session.showsAIOffer {
                HomeAIOfferCard(
                    startGuide: { session.presentAIGuide() },
                    dismiss: { session.dismissAIOffer() }
                )
            }
            if !session.dictionaryWeekSummary.learnedTerms.isEmpty || session.dictionaryWeekSummary.corrections > 0 {
                HomeLearningCard(summary: session.dictionaryWeekSummary) {
                    session.destination = .dictionary
                }
            }
            HomeActivityCard(statistics: statistics)
            LerroEqualColumns(spacing: LerroTheme.cardSpacing) {
                HomeTopAppsCard(apps: statistics.topApps)
                HomeHoursCard(hourCounts: statistics.hourCounts, peakHour: statistics.peakHour)
            }
        }
        .padding(.top, LerroTheme.contentTopPadding)
        .padding(.bottom, 28)
        .padding(.horizontal, LerroTheme.contentHorizontalPadding)
        .frame(maxWidth: 812 + 2 * LerroTheme.contentHorizontalPadding, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
}

// MARK: Shared card style and formatting

extension View {
    /// Surface, hairline border, card radius and padding shared by the Home cards.
    func homeCard() -> some View {
        self
            .padding(LerroTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                LerroTheme.card,
                in: RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                    .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
            }
    }
}

/// A number with an optional unit, for example "108" "小时".
struct HomeQuantityPart: Identifiable {
    let id: Int
    let value: String
    let unit: String
}

enum HomeFormat {
    /// "108 小时 51 分钟", "12 分钟" or "40 秒".
    static func duration(_ seconds: TimeInterval, locale: Locale) -> [HomeQuantityPart] {
        let total = max(0, Int(seconds.rounded()))
        let hour = LerroInterfaceLocalization.string("小时", locale: locale)
        let minute = LerroInterfaceLocalization.string("分钟", locale: locale)
        let second = LerroInterfaceLocalization.string("秒", locale: locale)
        if total >= 3_600 {
            var hours = total / 3_600
            var minutes = (total % 3_600 + 30) / 60
            if minutes == 60 {
                hours += 1
                minutes = 0
            }
            return [
                HomeQuantityPart(id: 0, value: hours.formatted(.number.locale(locale)), unit: hour),
                HomeQuantityPart(id: 1, value: "\(minutes)", unit: minute)
            ]
        }
        if total >= 60 {
            return [HomeQuantityPart(id: 0, value: "\(total / 60)", unit: minute)]
        }
        return [HomeQuantityPart(id: 0, value: "\(total)", unit: second)]
    }

    /// "12 分钟", at least one minute.
    static func minutes(_ seconds: TimeInterval, locale: Locale) -> String {
        let value = max(1, Int((seconds / 60).rounded()))
        return "\(value) " + LerroInterfaceLocalization.string("分钟", locale: locale)
    }
}
