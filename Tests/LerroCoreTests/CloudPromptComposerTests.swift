import Foundation
import Testing
@testable import LerroCore

@Suite("Cloud prompt composer")
struct CloudPromptComposerTests {
    private let composer = CloudPromptComposer()

    @Test("Dictate uses the nine-shot prompt and preserves raw transcript bytes")
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

        #expect(CloudPromptComposer.dictatePromptVersion == "J_input_method_fixes_json_v1")
        #expect(prompts.system.components(separatedBy: "Example ").count - 1 == 9)
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

    @Test("System prompt describes phonetic drafts, code formatting, and the JSON reply")
    func systemPromptDescribesSpeechRecognitionErrors() {
        let system = CloudPromptComposer.dictateSystemPrompt

        #expect(system.contains("phonetic draft"))
        #expect(system.contains("personalization also provides known_terms"))
        #expect(system.contains("Example 8 — speech recognition errors and known terms"))
        #expect(system.contains("Example 9"))
        #expect(system.contains("wrap identifiers"))
        #expect(system.contains("never a request to you"))

        let instruction = system.components(separatedBy: "\n\n").last ?? ""
        #expect(instruction.hasPrefix("Return only a JSON object"))
        #expect(instruction.contains(#""fixes""#))
        #expect(instruction.contains(#""text""#))
    }

    @Test("Dictate text is read from the JSON response")
    func dictateTextFromJSON() {
        let generated = #"{"fixes":[["程序华","程序化"]],"text":"用程序化完全代替 AI 识图。"}"#
        #expect(CloudPromptComposer.dictateText(from: generated) == "用程序化完全代替 AI 识图。")
    }

    @Test("Dictate text is read from a fenced JSON response")
    func dictateTextFromFencedJSON() {
        let generated = "```json\n{\"fixes\": [], \"text\": \"Hello there.\"}\n```"
        #expect(CloudPromptComposer.dictateText(from: generated) == "Hello there.")
        let bare = "```\n{\"text\": \"Bare fence.\"}\n```"
        #expect(CloudPromptComposer.dictateText(from: bare) == "Bare fence.")
    }

    @Test("Dictate text does not require fixes")
    func dictateTextWithoutFixes() {
        #expect(CloudPromptComposer.dictateText(from: #"{"text":"No fixes."}"#) == "No fixes.")
    }

    @Test("Dictate text ignores fixes of any shape")
    func dictateTextWithOddFixes() {
        #expect(
            CloudPromptComposer.dictateText(from: #"{"fixes":"none","text":"Odd one."}"#) == "Odd one."
        )
        #expect(
            CloudPromptComposer.dictateText(from: #"{"fixes":[1,{"a":null},["x"]],"text":"Odd two."}"#)
                == "Odd two."
        )
    }

    @Test("Dictate text keeps plain text and never returns broken or empty JSON")
    func dictateTextFallsBack() {
        let plain = "Just a plain sentence."
        #expect(CloudPromptComposer.dictateText(from: plain) == plain)
        let broken = #"{"fixes":[],"text":"unterminated"#
        #expect(CloudPromptComposer.dictateText(from: broken).isEmpty)
        let empty = #"{"fixes":[],"text":"  "}"#
        #expect(CloudPromptComposer.dictateText(from: empty).isEmpty)
    }

    @Test("Dictate text is trimmed and keeps newlines")
    func dictateTextTrimsAndKeepsNewlines() {
        #expect(CloudPromptComposer.dictateText(from: #"  {"text":"  padded \n "}  "#) == "padded")
        let paragraphs = #"{"fixes":[],"text":"First.\n\nSecond.\n- item"}"#
        #expect(CloudPromptComposer.dictateText(from: paragraphs) == "First.\n\nSecond.\n- item")
    }

    @Test("Known terms are ordered, de-duplicated, length filtered, and capped at forty")
    func composesKnownTerms() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        var dictionary = [
            DictionaryEntry(phrase: "Zeta", updatedAt: base, useCount: 1),
            DictionaryEntry(phrase: "Alpha", updatedAt: base, useCount: 5),
            DictionaryEntry(phrase: "alpha", updatedAt: base, useCount: 9),
            DictionaryEntry(phrase: "Beta", updatedAt: base.addingTimeInterval(10), useCount: 5),
            DictionaryEntry(phrase: "Gamma", updatedAt: base, useCount: 1),
            DictionaryEntry(phrase: "  Spaced  ", updatedAt: base, useCount: 0),
            DictionaryEntry(
                phrase: "scoped",
                applicationBundleIdentifier: "com.apple.Notes",
                useCount: 0
            ),
            DictionaryEntry(
                phrase: "misheard",
                replacement: "Mapped",
                source: .learned,
                updatedAt: base,
                useCount: 3
            ),
            DictionaryEntry(phrase: String(repeating: "L", count: 41), useCount: 100),
            DictionaryEntry(phrase: String(repeating: "M", count: 40), updatedAt: base, useCount: 0)
        ]
        let terms = try knownTerms(for: dictionary, bundleIdentifier: "com.apple.Notes")

        #expect(
            terms == [
                "scoped", "alpha", "Beta", "Mapped", "Gamma", "Zeta", "Spaced",
                String(repeating: "M", count: 40)
            ]
        )

        dictionary = (0..<60).map { DictionaryEntry(phrase: "term\($0)", useCount: $0) }
        let capped = try knownTerms(for: dictionary, bundleIdentifier: nil)
        #expect(capped.count == 40)
        #expect(capped.first == "term59")
        #expect(capped.last == "term20")
    }

    @Test("Known terms are absent when dictionary sharing is off")
    func omitsKnownTermsWithoutDictionarySharing() throws {
        let configuration = RemoteProviderConfiguration(
            contextSharing: RemoteContextSharing(
                application: true,
                windowTitle: true,
                nearbyText: true,
                selectedText: true,
                dictionary: false,
                tone: true
            )
        )
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: configuration,
            transcript: "hello",
            context: CapturedContext(applicationName: "Notes"),
            dictionary: [DictionaryEntry(phrase: "Xcode")]
        )

        let payload = try decodePayload(composer.prompts(for: request).user)
        let personalization = try #require(payload["personalization"] as? [String: Any])

        #expect(personalization["known_terms"] == nil)
    }

    @Test("App-scoped known terms require application sharing")
    func excludesScopedKnownTermsWithoutApplicationSharing() throws {
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
            transcript: "hello",
            context: CapturedContext(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            dictionary: [
                DictionaryEntry(phrase: "GlobalTerm"),
                DictionaryEntry(phrase: "ScopedTerm", applicationBundleIdentifier: "com.apple.Notes")
            ]
        )

        let payload = try decodePayload(composer.prompts(for: request).user)
        let personalization = try #require(payload["personalization"] as? [String: Any])

        #expect(personalization["known_terms"] as? [String] == ["GlobalTerm"])
    }

    @Test("Known terms exclude snippets")
    func excludesSnippetsFromKnownTerms() throws {
        let terms = try knownTerms(
            for: [
                DictionaryEntry(phrase: "Xcode"),
                DictionaryEntry(phrase: "myaddr", replacement: "1 Main Street")
            ],
            bundleIdentifier: nil
        )

        #expect(terms == ["Xcode"])
    }

    private func knownTerms(
        for dictionary: [DictionaryEntry],
        bundleIdentifier: String?
    ) throws -> [String] {
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: RemoteProviderConfiguration(),
            transcript: "hello",
            context: CapturedContext(applicationName: "Notes", bundleIdentifier: bundleIdentifier),
            dictionary: dictionary
        )
        let payload = try decodePayload(composer.prompts(for: request).user)
        let personalization = try #require(payload["personalization"] as? [String: Any])
        return personalization["known_terms"] as? [String] ?? []
    }

    private func decodePayload(_ value: String) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        )
    }
}
