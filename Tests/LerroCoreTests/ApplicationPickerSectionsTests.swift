import Foundation
import Testing
@testable import LerroCore

@Suite("Application picker sections")
struct ApplicationPickerSectionsTests {
    private func app(_ id: String, _ name: String, running: Bool = false) -> ApplicationDescriptor {
        ApplicationDescriptor(bundleIdentifier: id, name: name, isRunning: running)
    }

    private func sections(
        _ applications: [ApplicationDescriptor],
        counts: [String: Int] = [:],
        excluded: Set<String> = [],
        query: String = ""
    ) -> [ApplicationPickerSection] {
        ApplicationPickerGrouping.sections(
            applications: applications,
            dictationCounts: counts,
            excludedBundleIdentifiers: excluded,
            query: query
        )
    }

    @Test("Sections are ordered frequent, running, installed")
    func sectionOrder() {
        let result = sections(
            [
                app("com.example.zeta", "Zeta"),
                app("com.example.beta", "Beta", running: true),
                app("com.example.alpha", "Alpha"),
            ],
            counts: ["com.example.zeta": 3]
        )

        #expect(result.map(\.kind) == [.frequent, .running, .installed])
        #expect(result[0].applications.map(\.name) == ["Zeta"])
        #expect(result[1].applications.map(\.name) == ["Beta"])
        #expect(result[2].applications.map(\.name) == ["Alpha"])
    }

    @Test("Frequent sorts by count then name and is capped")
    func frequentSortAndCap() {
        let applications = (0..<12).map { app("com.example.app\($0)", "App \($0)") }
        var counts = Dictionary(uniqueKeysWithValues: applications.map { ($0.bundleIdentifier, 5) })
        counts["com.example.app11"] = 50

        let result = sections(applications, counts: counts)
        let frequent = result.first { $0.kind == .frequent }?.applications ?? []

        #expect(frequent.count == ApplicationPickerGrouping.maximumFrequent)
        #expect(frequent.first?.bundleIdentifier == "com.example.app11")
        #expect(frequent.dropFirst().map(\.name) == [
            "App 0", "App 1", "App 2", "App 3", "App 4", "App 5", "App 6",
        ])
        let installed = result.first { $0.kind == .installed }?.applications ?? []
        #expect(installed.count == 4)
    }

    @Test("Frequent apps leave the running section")
    func frequentRunningAppIsNotDuplicated() {
        let result = sections(
            [app("com.example.chat", "Chat", running: true), app("com.example.mail", "Mail", running: true)],
            counts: ["com.example.chat": 2]
        )

        #expect(result.map(\.kind) == [.frequent, .running])
        #expect(result[1].applications.map(\.name) == ["Mail"])
    }

    @Test("Lerro and excluded apps are removed")
    func removesLerroAndExcluded() {
        let result = sections(
            [
                app(ApplicationIdentity.bundleIdentifier, "Lerro", running: true),
                app("com.example.excluded", "Excluded", running: true),
                app("com.example.kept", "Kept"),
            ],
            counts: [ApplicationIdentity.bundleIdentifier: 9, "com.example.excluded": 9],
            excluded: ["com.example.excluded"]
        )

        #expect(result.flatMap(\.applications).map(\.name) == ["Kept"])
    }

    @Test("Query filters across sections by name and bundle ID")
    func queryFilters() {
        let applications = [
            app("com.example.notes", "Notes"),
            app("com.example.editor", "Editor", running: true),
            app("com.example.chat", "Chat"),
        ]
        let counts = ["com.example.chat": 4]

        let byName = sections(applications, counts: counts, query: "  NOTE ")
        #expect(byName.flatMap(\.applications).map(\.name) == ["Notes"])

        let byBundle = sections(applications, counts: counts, query: "example.ch")
        #expect(byBundle.map(\.kind) == [.frequent])
        #expect(byBundle.first?.applications.map(\.name) == ["Chat"])

        #expect(sections(applications, counts: counts, query: "missing").isEmpty)
    }

    @Test("Empty sections are omitted")
    func emptySectionsOmitted() {
        let result = sections([app("com.example.alpha", "Alpha")])

        #expect(result.map(\.kind) == [.installed])
    }

    @Test("Counts for bundle IDs outside the catalog are ignored")
    func frequentIgnoresUnknownBundles() {
        let result = sections(
            [app("com.example.alpha", "Alpha")],
            counts: ["com.example.unknown": 20]
        )

        #expect(result.map(\.kind) == [.installed])
        #expect(result.flatMap(\.applications).map(\.bundleIdentifier) == ["com.example.alpha"])
    }
}
