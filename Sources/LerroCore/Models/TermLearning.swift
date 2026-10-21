import Foundation

/// A proper noun the model corrected in dictations, waiting for enough distinct dictations to be learned.
public struct TermCandidate: Codable, Hashable, Sendable {
    /// Display form: the spelling of the latest sighting.
    public var term: String
    /// How the term was misrecognized. At most 5, unique, latest last.
    public var heardAs: [String]
    /// Distinct history entries the term appeared in. At most 5.
    public var entryIDs: [UUID]
    public var firstSeenAt: Date
    public var lastSeenAt: Date

    public init(
        term: String,
        heardAs: [String] = [],
        entryIDs: [UUID] = [],
        firstSeenAt: Date,
        lastSeenAt: Date
    ) {
        self.term = term
        self.heardAs = heardAs
        self.entryIDs = entryIDs
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct TermLearningState: Codable, Hashable, Sendable {
    /// Key is `TermLearner.normalized(term)`.
    public var candidates: [String: TermCandidate]
    /// `TermLearner.normalized(term)` of terms the user removed; they are never learned again.
    public var dismissed: Set<String>

    public init(candidates: [String: TermCandidate] = [:], dismissed: Set<String> = []) {
        self.candidates = candidates
        self.dismissed = dismissed
    }

    public static let empty = TermLearningState()
}

public enum TermLearningStatus: Equatable, Sendable {
    case inDictionary
    case pending(remaining: Int)
    case notLearning
}

public enum TermLearner {
    public static let requiredEntries = 2
    public static let minimumLength = 2
    public static let maximumLength = 40
    public static let maximumStoredItems = 5

    /// Trimmed, whitespace-collapsed and lowercased.
    public static func normalized(_ term: String) -> String {
        term.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Accumulates the proper nouns of one successful dictate call. Only words that are both
    /// the corrected side of a fix and listed in `terms` count, and one entry counts once per term.
    /// Candidates that reach `requiredEntries` are returned as dictionary entries and removed.
    public static func observe(
        state: TermLearningState,
        fixes: [AIWordFix],
        terms: [String],
        finalText: String,
        entryID: UUID,
        dictionary: [DictionaryEntry],
        now: Date
    ) -> (state: TermLearningState, learned: [DictionaryEntry]) {
        let listed = Set(terms.map(normalized))
        let known = dictionaryKeys(dictionary)

        var order: [String] = []
        var sightings: [String: (term: String, heardAs: [String])] = [:]
        for fix in fixes {
            let term = fix.corrected.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let key = normalized(term)
            guard listed.contains(key),
                  isLearnable(term),
                  finalText.range(of: term, options: .caseInsensitive) != nil,
                  !known.contains(key),
                  !state.dismissed.contains(key)
            else { continue }
            let heard = fix.recognized.trimmingCharacters(in: .whitespacesAndNewlines)
            var sighting = sightings[key] ?? (term: term, heardAs: [])
            sighting.term = term
            if !heard.isEmpty, normalized(heard) != key, !sighting.heardAs.contains(heard) {
                sighting.heardAs.append(heard)
            }
            if sightings[key] == nil { order.append(key) }
            sightings[key] = sighting
        }

        var updated = state
        var learned: [DictionaryEntry] = []
        for key in order {
            guard let sighting = sightings[key] else { continue }
            var candidate = updated.candidates[key] ?? TermCandidate(
                term: sighting.term,
                firstSeenAt: now,
                lastSeenAt: now
            )
            guard !candidate.entryIDs.contains(entryID) else { continue }

            candidate.term = sighting.term
            candidate.lastSeenAt = now
            candidate.entryIDs = Array((candidate.entryIDs + [entryID]).suffix(maximumStoredItems))
            for heard in sighting.heardAs {
                candidate.heardAs.removeAll { $0 == heard }
                candidate.heardAs.append(heard)
            }
            candidate.heardAs = Array(candidate.heardAs.suffix(maximumStoredItems))

            if candidate.entryIDs.count >= requiredEntries {
                updated.candidates.removeValue(forKey: key)
                learned.append(DictionaryEntry(
                    phrase: candidate.term,
                    replacement: candidate.term,
                    source: .learned,
                    createdAt: now,
                    updatedAt: now,
                    heardAs: candidate.heardAs,
                    learnedFromEntryIDs: candidate.entryIDs
                ))
            } else {
                updated.candidates[key] = candidate
            }
        }
        return (updated, learned)
    }

    public static func status(
        of term: String,
        state: TermLearningState,
        dictionary: [DictionaryEntry]
    ) -> TermLearningStatus {
        let key = normalized(term)
        if dictionaryKeys(dictionary).contains(key) { return .inDictionary }
        guard !state.dismissed.contains(key),
              let candidate = state.candidates[key]
        else { return .notLearning }
        return .pending(remaining: max(1, requiredEntries - candidate.entryIDs.count))
    }

    public static func dismiss(_ term: String, in state: TermLearningState) -> TermLearningState {
        let key = normalized(term)
        var updated = state
        updated.candidates.removeValue(forKey: key)
        updated.dismissed.insert(key)
        return updated
    }

    private static func dictionaryKeys(_ dictionary: [DictionaryEntry]) -> Set<String> {
        var keys = Set<String>()
        for entry in dictionary {
            keys.insert(normalized(entry.phrase))
            keys.insert(normalized(entry.replacement))
        }
        return keys
    }

    private static func isLearnable(_ term: String) -> Bool {
        guard (minimumLength...maximumLength).contains(term.count),
              term.contains(where: \.isLetter),
              term.range(of: #"^\d{1,2}[:：]\d{2}([:：]\d{2})?$"#, options: .regularExpression) == nil
        else { return false }
        return true
    }
}

public enum DictionaryUsageCounter {
    /// Entries whose replacement (or phrase) appears in `text`, case-insensitively,
    /// with `useCount` + 1 and `lastUsedAt` set to `now`. Only changed entries are returned.
    public static func entriesUsed(
        in text: String,
        dictionary: [DictionaryEntry],
        now: Date
    ) -> [DictionaryEntry] {
        dictionary.compactMap { entry in
            let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = replacement.isEmpty
                ? entry.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                : replacement
            guard !target.isEmpty, text.range(of: target, options: .caseInsensitive) != nil else { return nil }
            var used = entry
            used.useCount += 1
            used.lastUsedAt = now
            return used
        }
    }
}

public struct DictionaryWeekSummary: Equatable, Sendable {
    /// Replacements of terms learned in the last 7 days, newest first.
    public var learnedTerms: [String]
    /// AI word fixes in the last 7 days of history.
    public var corrections: Int
    /// Fixes whose corrected side equals a dictionary replacement or phrase.
    public var correctionsUsingDictionary: Int

    public init(learnedTerms: [String], corrections: Int, correctionsUsingDictionary: Int) {
        self.learnedTerms = learnedTerms
        self.corrections = corrections
        self.correctionsUsingDictionary = correctionsUsingDictionary
    }

    public static let empty = DictionaryWeekSummary(
        learnedTerms: [],
        corrections: 0,
        correctionsUsingDictionary: 0
    )
}

public enum DictionaryWeek {
    public static let windowSeconds: TimeInterval = 7 * 24 * 60 * 60

    public static func summary(
        history: [HistoryEntry],
        dictionary: [DictionaryEntry],
        now: Date
    ) -> DictionaryWeekSummary {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        let learnedTerms = dictionary
            .filter { $0.source == .learned && $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.replacement)

        var known = Set<String>()
        for entry in dictionary {
            known.insert(TermLearner.normalized(entry.phrase))
            known.insert(TermLearner.normalized(entry.replacement))
        }

        var corrections = 0
        var usingDictionary = 0
        for entry in history where entry.createdAt >= cutoff {
            guard let fixes = entry.aiCall?.fixes else { continue }
            corrections += fixes.count
            usingDictionary += fixes.filter { known.contains(TermLearner.normalized($0.corrected)) }.count
        }
        return DictionaryWeekSummary(
            learnedTerms: learnedTerms,
            corrections: corrections,
            correctionsUsingDictionary: usingDictionary
        )
    }
}
