import Foundation

public enum TextMetrics {
    public static func countWords(in text: String) -> Int {
        let latinWords = text.split { character in
            character.isWhitespace || character.isPunctuation
        }.filter { token in
            token.contains { $0.isLetter || $0.isNumber }
        }

        let cjkCount = text.unicodeScalars.reduce(into: 0) { result, scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                result += 1
            default:
                break
            }
        }

        let latinOnlyCount = latinWords.filter { token in
            token.unicodeScalars.contains { scalar in
                !(0x3400...0x4DBF).contains(scalar.value)
                    && !(0x4E00...0x9FFF).contains(scalar.value)
                    && !(0xF900...0xFAFF).contains(scalar.value)
            }
        }.count

        return cjkCount + latinOnlyCount
    }

    public static func usageSummary(entries: [HistoryEntry]) -> UsageSummary {
        let completed = entries.filter { $0.status == .completed }
        let duration = completed.reduce(0) { $0 + $1.duration }
        let words = completed.reduce(0) { $0 + countWords(in: $1.finalText) }
        let typingSeconds = Double(words) / 40.0 * 60.0
        let saved = max(0, typingSeconds - duration)
        let wpm = duration > 0 ? Int((Double(words) / duration) * 60.0) : 0
        return UsageSummary(
            totalDuration: duration,
            totalWords: words,
            savedSeconds: saved,
            averageWordsPerMinute: wpm
        )
    }
}
