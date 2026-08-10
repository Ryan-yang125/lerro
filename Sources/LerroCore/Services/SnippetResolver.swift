import Foundation

public enum SnippetResolver {
    public static func resolve(
        transcript: String,
        entries: [DictionaryEntry],
        applicationBundleIdentifier: String?
    ) -> DictionaryEntry? {
        let spoken = normalized(transcript)
        guard !spoken.isEmpty else { return nil }

        let candidates = entries.filter { entry in
            guard entry.isSnippet,
                  normalized(entry.phrase) == spoken else {
                return false
            }
            guard let scopedBundle = entry.applicationBundleIdentifier else { return true }
            return scopedBundle == applicationBundleIdentifier
        }
        return candidates.first { $0.applicationBundleIdentifier == applicationBundleIdentifier }
            ?? candidates.first { $0.applicationBundleIdentifier == nil }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .localizedLowercase
    }
}
