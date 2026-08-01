import Testing
@testable import LerroCore

@Suite("Settings routing and persistence state")
struct SettingsAndPersistenceLogicTests {
    @Test("Every settings entry point resolves to its intended page")
    func resolvesSettingsEntryPoints() {
        #expect(SettingsEntryPoint.account.destination == .account)
        #expect(SettingsEntryPoint.settings.destination == .settings)
        #expect(SettingsEntryPoint.personalization.destination == .personal)
        #expect(SettingsEntryPoint.upgrade.destination == .account)
        #expect(SettingsEntryPoint.invitation.destination == .account)
        #expect(SettingsEntryPoint.recommendation.destination == .account)
    }

    @Test("Preference saves coalesce changes and roll back to the last success")
    func coalescesPreferenceSaves() throws {
        let initial = UserPreferences()
        var first = initial
        first.appearance = .dark
        var latest = first
        latest.muteOtherAudio = false
        var queue = PreferenceSaveQueue(confirmed: initial)

        #expect(queue.enqueue(initial) == nil)
        #expect(queue.enqueue(first) == first)
        #expect(queue.enqueue(latest) == nil)
        #expect(queue.inFlight == first)
        #expect(queue.queued == latest)

        let nextValue = queue.didSave(first)
        let next = try #require(nextValue)
        #expect(next == latest)
        #expect(queue.confirmed == first)
        #expect(queue.inFlight == latest)

        let rollbackValue = queue.didFail(latest)
        let rollback = try #require(rollbackValue)
        #expect(rollback == first)
        #expect(queue.confirmed == first)
        #expect(queue.inFlight == nil)
        #expect(queue.queued == nil)
    }

    @Test("Returning to the confirmed preferences is persisted after an in-flight save")
    func persistsARevertedPreference() throws {
        let initial = UserPreferences()
        var changed = initial
        changed.showInDock = false
        var queue = PreferenceSaveQueue(confirmed: initial)

        #expect(queue.enqueue(changed) == changed)
        #expect(queue.enqueue(initial) == nil)
        #expect(queue.queued == initial)

        let restoreValue = queue.didSave(changed)
        let restore = try #require(restoreValue)
        #expect(restore == initial)
        let finalSave = queue.didSave(initial)
        #expect(finalSave == nil)
        #expect(queue.confirmed == initial)
    }

    @Test("Dictionary CSV parsing supports headers, BOM, and phrase-only rows")
    func parsesDictionaryCSV() throws {
        let entries = try DictionaryCSVParser.parse(
            "\u{feff}phrase,replacement\nType less,Lerro\nCodex\nSwift UI,"
        )

        #expect(entries.map(\.phrase) == ["Type less", "Codex", "Swift UI"])
        #expect(entries.map(\.replacement) == ["Lerro", "Codex", "Swift UI"])
    }

    @Test("Dictionary CSV parsing rejects files without entries")
    func rejectsEmptyDictionaryCSV() {
        #expect(throws: DictionaryCSVError.emptyFile) {
            try DictionaryCSVParser.parse("")
        }
        #expect(throws: DictionaryCSVError.noEntries) {
            try DictionaryCSVParser.parse("phrase,replacement\n,\n")
        }
    }
}
