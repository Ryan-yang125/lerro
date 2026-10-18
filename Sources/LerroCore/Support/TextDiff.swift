import Foundation

/// Character-level difference between two strings, computed over grapheme
/// clusters with a longest-common-subsequence alignment.
public enum TextDiff {
    public struct Segment: Equatable, Sendable {
        public enum Kind: Sendable {
            case same
            case removed
            case inserted
        }

        public var kind: Kind
        public var text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Both inputs longer than this many characters skip the alignment.
    static let inputLengthCap = 2000
    /// Maximum number of alignment table cells after trimming the common prefix and suffix.
    static let tableCellCap = 4_000_000

    public static func segments(from old: String, to new: String) -> [Segment] {
        let oldChars = Array(old)
        let newChars = Array(new)
        if oldChars.count > inputLengthCap, newChars.count > inputLengthCap {
            return [Segment(kind: .removed, text: old), Segment(kind: .inserted, text: new)]
        }

        var prefix = 0
        while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldChars.count - prefix,
              suffix < newChars.count - prefix,
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }

        let oldMiddle = Array(oldChars[prefix..<(oldChars.count - suffix)])
        let newMiddle = Array(newChars[prefix..<(newChars.count - suffix)])

        var builder = Builder()
        builder.append(.same, oldChars[..<prefix])
        if oldMiddle.count * newMiddle.count > tableCellCap {
            builder.append(.removed, oldMiddle[...])
            builder.append(.inserted, newMiddle[...])
        } else {
            align(oldMiddle, newMiddle, into: &builder)
        }
        builder.append(.same, oldChars[(oldChars.count - suffix)...])
        return builder.segments
    }

    private static func align(_ old: [Character], _ new: [Character], into builder: inout Builder) {
        let rows = old.count
        let columns = new.count
        if rows == 0 || columns == 0 {
            builder.append(.removed, old[...])
            builder.append(.inserted, new[...])
            return
        }

        // lcs[i * width + j] is the LCS length of old[i...] and new[j...].
        let width = columns + 1
        var lcs = [Int32](repeating: 0, count: (rows + 1) * width)
        for i in stride(from: rows - 1, through: 0, by: -1) {
            for j in stride(from: columns - 1, through: 0, by: -1) {
                if old[i] == new[j] {
                    lcs[i * width + j] = lcs[(i + 1) * width + j + 1] + 1
                } else {
                    lcs[i * width + j] = max(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
                }
            }
        }

        var i = 0
        var j = 0
        while i < rows, j < columns {
            if old[i] == new[j] {
                builder.append(.same, old[i...i])
                i += 1
                j += 1
            } else if lcs[(i + 1) * width + j] >= lcs[i * width + j + 1] {
                builder.append(.removed, old[i...i])
                i += 1
            } else {
                builder.append(.inserted, new[j...j])
                j += 1
            }
        }
        builder.append(.removed, old[i...])
        builder.append(.inserted, new[j...])
    }

    /// Accumulates segments and merges neighbours of the same kind.
    private struct Builder {
        var segments: [Segment] = []

        mutating func append(_ kind: Segment.Kind, _ characters: ArraySlice<Character>) {
            guard !characters.isEmpty else { return }
            let text = String(characters)
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].text += text
            } else {
                segments.append(Segment(kind: kind, text: text))
            }
        }
    }
}
