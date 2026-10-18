import Foundation

public enum ApplicationPickerSectionKind: String, Sendable, Hashable {
    case frequent
    case running
    case installed
}

public struct ApplicationPickerSection: Identifiable, Sendable, Hashable {
    public var kind: ApplicationPickerSectionKind
    public var applications: [ApplicationDescriptor]
    public var id: ApplicationPickerSectionKind { kind }

    public init(kind: ApplicationPickerSectionKind, applications: [ApplicationDescriptor]) {
        self.kind = kind
        self.applications = applications
    }
}

public enum ApplicationPickerGrouping {
    public static let maximumFrequent = 8

    public static func sections(
        applications: [ApplicationDescriptor],
        dictationCounts: [String: Int],
        excludedBundleIdentifiers: Set<String>,
        query: String
    ) -> [ApplicationPickerSection] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = applications.filter { application in
            application.bundleIdentifier != ApplicationIdentity.bundleIdentifier
                && !excludedBundleIdentifiers.contains(application.bundleIdentifier)
                && (query.isEmpty
                    || application.name.localizedCaseInsensitiveContains(query)
                    || application.bundleIdentifier.localizedCaseInsensitiveContains(query))
        }

        let frequent = candidates
            .filter { (dictationCounts[$0.bundleIdentifier] ?? 0) > 0 }
            .sorted { lhs, rhs in
                let lhsCount = dictationCounts[lhs.bundleIdentifier] ?? 0
                let rhsCount = dictationCounts[rhs.bundleIdentifier] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return byName(lhs, rhs)
            }
            .prefix(maximumFrequent)
        let frequentIdentifiers = Set(frequent.map(\.bundleIdentifier))
        let remaining = candidates.filter { !frequentIdentifiers.contains($0.bundleIdentifier) }

        let sections = [
            ApplicationPickerSection(kind: .frequent, applications: Array(frequent)),
            ApplicationPickerSection(
                kind: .running,
                applications: remaining.filter(\.isRunning).sorted(by: byName)
            ),
            ApplicationPickerSection(
                kind: .installed,
                applications: remaining.filter { !$0.isRunning }.sorted(by: byName)
            ),
        ]
        return sections.filter { !$0.applications.isEmpty }
    }

    private static func byName(_ lhs: ApplicationDescriptor, _ rhs: ApplicationDescriptor) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.bundleIdentifier < rhs.bundleIdentifier
    }
}
