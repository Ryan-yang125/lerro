import SwiftUI
import LerroCore

struct HomeView: View {
    @Bindable var session: AppSession
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    var body: some View {
        // One ScrollView for both states: the window toolbar picks its
        // background from the first scroll view it sees, so swapping an
        // empty state for a ScrollView after history loads left a stale
        // toolbar background in dark mode.
        ScrollView {
            if session.homeStatistics.totalDictations == 0 {
                LerroEmptyState(title: emptyTitle, hint: nil)
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical)
            } else {
                content
            }
        }
        .background {
            HomeBackdrop(showsGlow: !(systemReduceTransparency || session.visualFixtureReduceTransparency))
        }
        .navigationTitle("首页")
        .toolbar {
            // A toolbar item keeps the full-height toolbar, so the sidebar
            // holds the traffic lights like on the other pages.
            ToolbarItem(placement: .primaryAction) {
                HomeShortcutsView(hotkeys: session.preferences.hotkeys)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var content: some View {
        let statistics = session.homeStatistics
        return VStack(alignment: .leading, spacing: 12) {
            HomeHeaderView(totalWords: statistics.total.totalWords)
            .padding(.top, 6)
            .padding(.bottom, 8)
            HomeStatCards(statistics: statistics)
            HomeActivityCard(statistics: statistics)
            HStack(alignment: .top, spacing: 12) {
                HomeTopAppsCard(apps: statistics.topApps)
                HomeHoursCard(hourCounts: statistics.hourCounts, peakHour: statistics.peakHour)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .padding(.bottom, 28)
        .padding(.horizontal, LerroTheme.contentHorizontalPadding)
        .frame(maxWidth: 812 + 2 * LerroTheme.contentHorizontalPadding, alignment: .topLeading)
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
}

// MARK: Backdrop

/// Page fill, a dot grid fading out over the top 430 pt, and a faint accent
/// glow at the top right. Not interactive; the glow is hidden under Reduce
/// Transparency.
private struct HomeBackdrop: View {
    let showsGlow: Bool

    private let dotSpacing: CGFloat = 14
    private let dotDiameter: CGFloat = 1.2
    private let dotFadeHeight: CGFloat = 430

    var body: some View {
        ZStack(alignment: .top) {
            LerroTheme.main
            Canvas { context, size in
                var dots = Path()
                var y = dotSpacing / 2
                while y < size.height {
                    var x = dotSpacing / 2
                    while x < size.width {
                        dots.addEllipse(in: CGRect(
                            x: x - dotDiameter / 2,
                            y: y - dotDiameter / 2,
                            width: dotDiameter,
                            height: dotDiameter
                        ))
                        x += dotSpacing
                    }
                    y += dotSpacing
                }
                context.fill(dots, with: .color(LerroTheme.homeDot))
            }
            .frame(height: dotFadeHeight)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.6), location: 0.45),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            if showsGlow {
                Canvas { context, size in
                    let radiusX: CGFloat = 260
                    let radiusY: CGFloat = 210
                    let center = CGPoint(x: size.width - 140, y: 50)
                    var scaled = context
                    scaled.translateBy(x: center.x, y: center.y)
                    scaled.scaleBy(x: 1, y: radiusY / radiusX)
                    scaled.fill(
                        Path(ellipseIn: CGRect(x: -radiusX, y: -radiusX, width: radiusX * 2, height: radiusX * 2)),
                        with: .radialGradient(
                            Gradient(colors: [LerroTheme.accentSoft, LerroTheme.accentSoft.opacity(0)]),
                            center: .zero,
                            startRadius: 0,
                            endRadius: radiusX
                        )
                    )
                }
                .frame(height: 280)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Shared card style and formatting

extension View {
    /// Surface, hairline border and card radius shared by the Home cards.
    func homeCard(_ padding: EdgeInsets) -> some View {
        self
            .padding(padding)
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
