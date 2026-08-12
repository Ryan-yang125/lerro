import Foundation
import Testing
@testable import LerroCore

@Suite("Cloud prompt composer")
struct CloudPromptComposerTests {
    private let composer = CloudPromptComposer()

    @Test("Dictate uses the seven-shot prompt and preserves raw transcript bytes")
    func composesDictatePrompt() throws {
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: RemoteProviderConfiguration(),
            transcript: "  嗯 hello hello  \n",
            context: CapturedContext(applicationName: "Notes")
        )

        let prompts = try composer.prompts(for: request)
        let payload = try decodePayload(prompts.user)
        let rawData = try #require(payload["raw_data"] as? [String: Any])

        #expect(CloudPromptComposer.dictatePromptVersion == "M_balanced_seven_shot")
        #expect(prompts.system.components(separatedBy: "Example ").count - 1 == 7)
        #expect(!prompts.system.contains("resolution exception"))
        #expect(!prompts.system.contains("Mina"))
        #expect(!prompts.system.contains("Nora"))
        #expect(rawData["transcript"] as? String == "  嗯 hello hello  \n")
    }

    @Test("Context uses bounded cursor text and obeys every sharing flag")
    func boundsAndFiltersContext() throws {
        let before = String(repeating: "B", count: 100)
        let after = String(repeating: "A", count: 60)
        let configuration = RemoteProviderConfiguration(
            contextSharing: RemoteContextSharing(
                application: false,
                windowTitle: false,
                nearbyText: true,
                selectedText: false,
                dictionary: false,
                tone: false
            )
        )
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: configuration,
            transcript: "dictation",
            selectedText: "private selection",
            context: CapturedContext(
                applicationName: "Notes",
                windowTitle: "Private title",
                focusedText: "fallback",
                cursorBefore: before,
                cursorAfter: after
            ),
            dictionary: [DictionaryEntry(phrase: "dictation", replacement: "mapped")],
            toneInstruction: "Formal"
        )

        let payload = try decodePayload(composer.prompts(for: request).user)
        let workspace = try #require(payload["workspace"] as? [String: Any])
        let personalization = try #require(payload["personalization"] as? [String: Any])

        #expect(workspace["application_type"] as? String == "unknown")
        #expect(workspace["application_name"] == nil)
        #expect(workspace["window_title"] == nil)
        #expect(workspace["selected_text"] == nil)
        #expect(workspace["cursor_before"] as? String == String(before.suffix(80)))
        #expect(workspace["cursor_after"] as? String == String(after.prefix(40)))
        #expect((personalization["glossary"] as? [Any])?.isEmpty == true)
        #expect(personalization["tone"] as? String == "natural")
    }

    @Test("Glossary includes only matching current-app entries and caps payload at twelve")
    func filtersAndCapsGlossary() throws {
        var dictionary = (0..<15).map { index in
            DictionaryEntry(
                phrase: "term\(index)",
                replacement: "value\(index)",
                useCount: index
            )
        }
        dictionary.append(DictionaryEntry(phrase: "unrelated", replacement: "excluded"))
        dictionary.append(DictionaryEntry(
            phrase: "term0",
            replacement: "wrong-app",
            applicationBundleIdentifier: "com.example.other"
        ))
        let transcript = (0..<15).map { "term\($0)" }.joined(separator: " ")
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: RemoteProviderConfiguration(),
            transcript: transcript,
            context: CapturedContext(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes"
            ),
            dictionary: dictionary
        )

        let payload = try decodePayload(composer.prompts(for: request).user)
        let personalization = try #require(payload["personalization"] as? [String: Any])
        let glossary = try #require(personalization["glossary"] as? [[String: Any]])

        #expect(glossary.count == 12)
        #expect(!glossary.contains { $0["replacement"] as? String == "excluded" })
        #expect(!glossary.contains { $0["replacement"] as? String == "wrong-app" })
    }

    @Test("Disabled context cannot influence the glossary payload")
    func disabledContextDoesNotSelectGlossaryEntries() throws {
        let configuration = RemoteProviderConfiguration(
            contextSharing: RemoteContextSharing(
                application: false,
                windowTitle: false,
                nearbyText: false,
                selectedText: false,
                dictionary: true,
                tone: false
            )
        )
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: configuration,
            transcript: "public transcript",
            selectedText: "private-selection-term",
            context: CapturedContext(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                cursorBefore: "private-cursor-term"
            ),
            dictionary: [
                DictionaryEntry(
                    phrase: "private-selection-term",
                    replacement: "selection-leak"
                ),
                DictionaryEntry(
                    phrase: "private-cursor-term",
                    replacement: "cursor-leak"
                ),
                DictionaryEntry(
                    phrase: "public transcript",
                    replacement: "scoped-leak",
                    applicationBundleIdentifier: "com.apple.Notes"
                ),
                DictionaryEntry(
                    phrase: "public transcript",
                    replacement: "global-match"
                )
            ]
        )

        let payload = try decodePayload(composer.prompts(for: request).user)
        let personalization = try #require(payload["personalization"] as? [String: Any])
        let glossary = try #require(personalization["glossary"] as? [[String: Any]])

        #expect(glossary.count == 1)
        #expect(glossary.first?["replacement"] as? String == "global-match")
    }

    @Test("Focused text remains the compatible cursor-before fallback")
    func fallsBackToFocusedText() throws {
        let focused = String(repeating: "F", count: 100)
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: RemoteProviderConfiguration(),
            transcript: "Explain",
            context: CapturedContext(applicationName: "Editor", focusedText: focused)
        )

        let payload = try decodePayload(composer.prompts(for: request).user)
        let workspace = try #require(payload["workspace"] as? [String: Any])

        #expect(workspace["cursor_before"] as? String == String(focused.suffix(80)))
        #expect(workspace["cursor_after"] == nil)
    }

    @Test("Remote selection context is bounded")
    func boundsRemoteSelection() throws {
        let longSelection = String(
            repeating: "S",
            count: CloudPromptComposer.maximumSelectedTextCharacters + 1
        )
        let dictate = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: RemoteProviderConfiguration(),
            transcript: "Add a sentence",
            selectedText: longSelection,
            context: CapturedContext(applicationName: "Editor")
        )
        let payload = try decodePayload(composer.prompts(for: dictate).user)
        let workspace = try #require(payload["workspace"] as? [String: Any])
        #expect(
            (workspace["selected_text"] as? String)?.count
                == CloudPromptComposer.maximumSelectedTextCharacters
        )
    }

    private func decodePayload(_ value: String) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        )
    }
}
