import Foundation

public struct TextPipeline: Sendable {
    public init() {}

    public func clean(
        _ source: String,
        dictionary: [DictionaryEntry],
        applicationBundleIdentifier: String?
    ) -> String {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        text = collapseWhitespace(text)
        text = removeFillers(text)
        text = collapseWhitespace(text)
        text = collapseImmediateRepetitions(text)
        text = applyDictionary(text, entries: dictionary, applicationBundleIdentifier: applicationBundleIdentifier)
        text = normalizePunctuation(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collapseWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    }

    private func removeFillers(_ text: String) -> String {
        let patterns = [
            "(?i)(^|[\\s，。！？、])(?:嗯+|呃+|额+|那个|就是|然后呢)(?=$|[\\s，。！？、])",
            "(?i)\\b(?:um+|uh+|erm+|you know)\\b"
        ]
        return patterns.reduce(text) { value, pattern in
            value.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        }
    }

    private func collapseImmediateRepetitions(_ text: String) -> String {
        text.replacingOccurrences(
            of: "(?i)\\b([\\p{L}\\p{N}]{2,})(?:[ ,，、]+\\1)+\\b",
            with: "$1",
            options: .regularExpression
        )
    }

    private func applyDictionary(
        _ text: String,
        entries: [DictionaryEntry],
        applicationBundleIdentifier: String?
    ) -> String {
        let candidates = entries
            .filter { entry in
                entry.applicationBundleIdentifier == nil
                    || entry.applicationBundleIdentifier == applicationBundleIdentifier
            }
            .sorted { $0.phrase.count > $1.phrase.count }

        return candidates.reduce(text) { value, entry in
            let escapedPhrase = NSRegularExpression.escapedPattern(for: entry.phrase)
            let startsWithASCIIWord = entry.phrase.unicodeScalars.first.map(isASCIIWordScalar) == true
            let endsWithASCIIWord = entry.phrase.unicodeScalars.last.map(isASCIIWordScalar) == true
            let pattern = (startsWithASCIIWord ? "(?<![A-Za-z0-9_])" : "")
                + escapedPhrase
                + (endsWithASCIIWord ? "(?![A-Za-z0-9_])" : "")
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return value
            }
            return expression.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..., in: value),
                withTemplate: NSRegularExpression.escapedTemplate(for: entry.replacement)
            )
        }
    }

    private func isASCIIWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 128
            && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
    }

    private func normalizePunctuation(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+([，。！？、；：,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([，。！？、；：])\\s+", with: "$1", options: .regularExpression)
    }
}
