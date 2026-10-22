import SwiftUI
import LerroCore

/// Filter choices in the toolbar. `failed` is applied client-side over the loaded pages.
enum HistoryTab: String, CaseIterable, Identifiable {
    case all
    case dictation
    case translation
    case failed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部"
        case .dictation: "听写"
        case .translation: "翻译"
        case .failed: "未写入"
        }
    }

    /// Mode passed to the session query. `failed` loads every mode.
    var mode: CaptureMode? {
        switch self {
        case .all, .failed: nil
        case .dictation: .dictation
        case .translation: .translation
        }
    }

    init(mode: CaptureMode?) {
        self = switch mode {
        case .dictation: .dictation
        case .translation: .translation
        case .ask, nil: .all
        }
    }

    func includes(_ entry: HistoryEntry) -> Bool {
        self == .failed ? entry.status == .failed : true
    }
}

struct HistoryDayGroup: Identifiable {
    let id: Date
    let title: String
    var entries: [HistoryEntry]
}

/// Text and formatting shared by the list and the detail pane.
enum HistoryPresentation {
    static func localized(_ key: String, locale: Locale) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }

    static func groups(from entries: [HistoryEntry], locale: Locale) -> [HistoryDayGroup] {
        let calendar = Calendar.current
        var result: [HistoryDayGroup] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if result.last?.id == day {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append(HistoryDayGroup(
                    id: day,
                    title: dayTitle(for: day, locale: locale),
                    entries: [entry]
                ))
            }
        }
        return result
    }

    static func dayTitle(for date: Date, locale: Locale) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return localized("今天", locale: locale) }
        if calendar.isDateInYesterday(date) { return localized("昨天", locale: locale) }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
    }

    static func time(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle().hour().minute().locale(locale))
    }

    static func modeTitle(_ mode: CaptureMode) -> String {
        switch mode {
        case .dictation: "听写"
        case .translation: "翻译"
        case .ask: "指令"
        }
    }

    static func hasText(_ entry: HistoryEntry) -> Bool {
        !entry.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// First line of a list row.
    static func listText(for entry: HistoryEntry, locale: Locale) -> String {
        switch entry.status {
        case .failed:
            if hasText(entry) { return entry.finalText }
            let raw = entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? localized("转写失败", locale: locale) : entry.rawText
        case .cancelled:
            return localized("已取消的录音", locale: locale)
        case .undone:
            return LerroInterfaceLocalization.format(
                "已撤回 · %@",
                locale: locale,
                arguments: entry.finalText
            )
        case .completed:
            return hasText(entry) ? entry.finalText : localized("没有检测到语音", locale: locale)
        }
    }

    /// "App · HH:mm" plus " · AI 整理" or " · 翻译" when they apply.
    static func footnote(for entry: HistoryEntry, locale: Locale) -> String {
        var parts = [entry.applicationName, time(entry.createdAt, locale: locale)]
        switch entry.mode {
        case .translation: parts.append(localized("翻译", locale: locale))
        case .ask: parts.append(localized("指令", locale: locale))
        case .dictation:
            if entry.wasEnhanced { parts.append(localized("AI 整理", locale: locale)) }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func seconds(_ value: TimeInterval, locale: Locale) -> String {
        let total = max(1, Int(value.rounded()))
        if total < 60 {
            return LerroInterfaceLocalization.format("%lld 秒", locale: locale, arguments: Int64(total))
        }
        return LerroInterfaceLocalization.format(
            "%lld 分 %lld 秒",
            locale: locale,
            arguments: Int64(total / 60), Int64(total % 60)
        )
    }

    static func clock(_ value: TimeInterval) -> String {
        let total = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Items shared by the row context menu and the detail "more" menu.
struct HistoryEntryMenuItems: View {
    let entry: HistoryEntry
    let session: AppSession
    let requestDelete: (HistoryEntry) -> Void

    var body: some View {
        Button {
            session.copyText(entry.finalText)
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }
        if !entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
                session.copyText(entry.rawText)
            } label: {
                Label("复制原始转写", systemImage: "text.quote")
            }
            if entry.mode != .ask {
                Button {
                    session.retryHistoryEntry(entry)
                } label: {
                    Label("用 AI 重新处理", systemImage: "sparkles")
                }
            }
        }
        if entry.audioRelativePath != nil {
            Button {
                session.exportAudio(entry)
            } label: {
                Label("导出录音", systemImage: "square.and.arrow.up")
            }
        }
        Divider()
        Button(role: .destructive) {
            requestDelete(entry)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
}
