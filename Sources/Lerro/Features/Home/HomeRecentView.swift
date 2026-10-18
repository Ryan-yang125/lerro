import SwiftUI
import LerroCore

/// Latest history rows. Clicking a row opens the history page.
struct HomeRecentView: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LerroSectionHeader(title: "最近", actionTitle: "全部历史") {
                session.destination = .history
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
            ForEach(session.recentHistoryEntries) { entry in
                HomeRecentRow(
                    entry: entry,
                    open: { session.destination = .history },
                    copy: { session.copyText(entry.finalText) }
                )
            }
        }
    }
}

private struct HomeRecentRow: View {
    let entry: HistoryEntry
    let open: () -> Void
    let copy: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            LerroAppIcon(bundleIdentifier: entry.bundleIdentifier, name: entry.applicationName, size: 22)
            Text(verbatim: summary)
                .font(LerroFont.body)
                .foregroundStyle(LerroTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? LerroTheme.fillHover : Color.clear)
        )
        .padding(.horizontal, -10)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(summary)，\(timeText)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("复制"), copy)
    }

    private var trailing: some View {
        HStack(spacing: 6) {
            if isHovering {
                LerroIconButton(systemImage: "doc.on.doc", help: "复制", action: copy)
            } else {
                if entry.status == .failed {
                    LerroStatusDot(color: LerroTheme.orange)
                }
                Text(verbatim: timeText)
                    .font(LerroFont.footnote)
                    .foregroundStyle(LerroTheme.metadataText)
                    .monospacedDigit()
            }
        }
        .frame(minWidth: 44, alignment: .trailing)
    }

    private var summary: String {
        let text = entry.finalText.isEmpty ? entry.rawText : entry.finalText
        return text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private var timeText: String {
        if calendar.isDateInToday(entry.createdAt) {
            return entry.createdAt.formatted(
                .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale)
            )
        }
        if calendar.isDateInYesterday(entry.createdAt) {
            return LerroInterfaceLocalization.string("昨天", locale: locale)
        }
        return entry.createdAt.formatted(.dateTime.month().day().locale(locale))
    }
}

/// Up to three most recently learned dictionary corrections.
struct HomeLearnedView: View {
    @Bindable var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LerroSectionHeader(title: "最近学到", actionTitle: "打开词典") {
                session.destination = .dictionary
            }
            .padding(.top, 18)
            .padding(.bottom, 6)
            HStack(spacing: 8) {
                ForEach(session.recentlyLearnedEntries.prefix(3)) { entry in
                    Button {
                        session.destination = .dictionary
                    } label: {
                        LerroChip {
                            Text(verbatim: "\(entry.phrase) → ")
                                .foregroundStyle(LerroTheme.secondaryText)
                            + Text(verbatim: entry.replacement)
                                .fontWeight(.semibold)
                                .foregroundStyle(LerroTheme.text)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: "\(entry.phrase) → \(entry.replacement)"))
                }
                Spacer(minLength: 0)
            }
        }
    }
}
