import Foundation

public enum TranscriptSpacing {
    /// Removes whitespace SpeechTranscriber places around CJK punctuation and collapses runs of spaces.
    public static func normalize(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard isSpace(scalars[index]) else {
                output.append(scalars[index])
                index += 1
                continue
            }
            var end = index
            while end < scalars.count, isSpace(scalars[end]) { end += 1 }
            let previous = output.last
            let next = end < scalars.count ? scalars[end] : nil
            // Full-width punctuation carries its own spacing, so whitespace on
            // either side of it is dropped.
            let removable = previous.map(isCJKPunctuation) ?? true
                || next.map(isCJKPunctuation) ?? true
            if !removable { output.append(" ") }
            index = end
        }
        return String(output).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let cjkPunctuation: Set<Unicode.Scalar> = Set("，。！？；：、）】》」』…（【《「『".unicodeScalars)

    private static func isCJKPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        cjkPunctuation.contains(scalar)
    }

    /// Only spaces and tabs collapse; line breaks inside the text stay untouched.
    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t"
    }
}
