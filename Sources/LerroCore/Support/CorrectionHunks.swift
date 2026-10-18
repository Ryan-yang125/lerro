import Foundation

/// One localized replacement between the speech transcript and the polished text.
public struct CorrectionHunk: Equatable, Sendable {
    public var original: String
    public var corrected: String
    public var contextBefore: String
    public var contextAfter: String

    public init(original: String, corrected: String, contextBefore: String, contextAfter: String) {
        self.original = original
        self.corrected = corrected
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

/// Finds substitutions (text replaced by different text) between a raw
/// transcript and its polished version. Deletions, insertions, punctuation,
/// case-only changes and function-word swaps are not dictionary material.
public enum CorrectionHunkExtractor {
    public static let maximumSideCharacters = 20
    public static let contextCharacters = 40

    private static let trimmedCharacters = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)

    private static let functionWords: Set<String> = Set(
        "的得地他她它在再做作那哪吗嘛呢了着和跟与及把给被让就也都是有这个".map { String($0) }
    )

    public static func hunks(raw: String, final: String) -> [CorrectionHunk] {
        let segments = TextDiff.segments(from: raw, to: final)
        let finalCharacters = Array(final)
        var hunks: [CorrectionHunk] = []
        var finalPosition = 0
        var index = 0
        while index < segments.count {
            let segment = segments[index]
            if segment.kind == .same {
                finalPosition += segment.text.count
                index += 1
                continue
            }
            let start = finalPosition
            var removed = ""
            var inserted = ""
            while index < segments.count, segments[index].kind != .same {
                let current = segments[index]
                switch current.kind {
                case .removed:
                    removed += current.text
                case .inserted:
                    inserted += current.text
                    finalPosition += current.text.count
                case .same:
                    break
                }
                index += 1
            }
            let end = finalPosition

            let original = removed.trimmingCharacters(in: trimmedCharacters)
            let corrected = inserted.trimmingCharacters(in: trimmedCharacters)
            guard isCandidate(original: original, corrected: corrected) else { continue }

            let beforeStart = max(0, start - contextCharacters)
            let beforeEnd = min(start, finalCharacters.count)
            let afterStart = min(end, finalCharacters.count)
            let afterEnd = min(finalCharacters.count, end + contextCharacters)
            hunks.append(CorrectionHunk(
                original: original,
                corrected: corrected,
                contextBefore: beforeStart < beforeEnd ? String(finalCharacters[beforeStart..<beforeEnd]) : "",
                contextAfter: afterStart < afterEnd ? String(finalCharacters[afterStart..<afterEnd]) : ""
            ))
        }
        return hunks
    }

    private static func isCandidate(original: String, corrected: String) -> Bool {
        guard !original.isEmpty, !corrected.isEmpty,
              original.count <= maximumSideCharacters,
              corrected.count <= maximumSideCharacters else { return false }
        guard comparisonForm(original) != comparisonForm(corrected) else { return false }
        if original.count == 1, corrected.count == 1,
           functionWords.contains(original), functionWords.contains(corrected) {
            return false
        }
        return true
    }

    private static func comparisonForm(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines).joined().lowercased()
    }
}
