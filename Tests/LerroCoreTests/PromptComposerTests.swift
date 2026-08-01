import Foundation
import Testing
@testable import LerroCore

@Suite("Prompt composer")
struct PromptComposerTests {
    private let composer = PromptComposer()

    @Test("Polish prompt carries bounded context, style, and glossary")
    func composesPolishPrompt() {
        let nearbyText = String(repeating: "x", count: 2_005)
        let dictionary = (0...100).map {
            DictionaryEntry(phrase: "term\($0)", replacement: "replacement\($0)")
        }
        let request = IntelligenceRequest(
            task: .polish,
            transcript: "raw transcript",
            context: CapturedContext(
                applicationName: "Notes",
                windowTitle: "Planning",
                focusedText: nearbyText
            ),
            dictionary: dictionary,
            toneInstruction: "Use short sentences."
        )

        let prompts = composer.prompts(for: request, cleanedTranscript: "clean transcript")

        #expect(prompts.system.contains("Return only the final user-facing text"))
        #expect(prompts.user.contains("Application: Notes"))
        #expect(prompts.user.contains("Window: Planning"))
        #expect(prompts.user.contains("Application style: Use short sentences."))
        #expect(prompts.user.contains(String(repeating: "x", count: 2_000)))
        #expect(!prompts.user.contains(String(repeating: "x", count: 2_001)))
        #expect(prompts.user.contains("term99 → replacement99"))
        #expect(!prompts.user.contains("term100 → replacement100"))
        #expect(prompts.user.contains("Dictation:\nclean transcript"))
    }

    @Test("Translate prompt includes the requested language")
    func composesTranslatePrompt() {
        let request = makeRequest(task: .translate, targetLanguage: "ja_JP")

        let prompts = composer.prompts(for: request, cleanedTranscript: "Good morning")

        #expect(prompts.system.contains("Translate naturally"))
        #expect(prompts.user.contains("Target language: ja_JP"))
        #expect(prompts.user.contains("Dictation:\nGood morning"))
    }

    @Test("Glossary includes global and current-application entries only")
    func filtersGlossaryByApplication() {
        let request = IntelligenceRequest(
            task: .polish,
            transcript: "Transcript",
            context: CapturedContext(
                applicationName: "Codex",
                bundleIdentifier: "com.openai.codex"
            ),
            dictionary: [
                DictionaryEntry(phrase: "global phrase", replacement: "GLOBAL_VALUE"),
                DictionaryEntry(
                    phrase: "codex phrase",
                    replacement: "CODEX_VALUE",
                    applicationBundleIdentifier: "com.openai.codex"
                ),
                DictionaryEntry(
                    phrase: "notes phrase",
                    replacement: "NOTES_VALUE",
                    applicationBundleIdentifier: "com.apple.Notes"
                )
            ]
        )

        let prompts = composer.prompts(for: request, cleanedTranscript: "Transcript")

        #expect(prompts.user.contains("global phrase → GLOBAL_VALUE"))
        #expect(prompts.user.contains("codex phrase → CODEX_VALUE"))
        #expect(!prompts.user.contains("notes phrase"))
        #expect(!prompts.user.contains("NOTES_VALUE"))
    }

    @Test("Glossary excludes application entries when bundle identifier is unavailable")
    func excludesScopedGlossaryWithoutApplicationIdentifier() {
        let request = IntelligenceRequest(
            task: .polish,
            transcript: "Transcript",
            context: CapturedContext(applicationName: "Unknown"),
            dictionary: [
                DictionaryEntry(phrase: "global phrase", replacement: "GLOBAL_VALUE"),
                DictionaryEntry(
                    phrase: "scoped phrase",
                    replacement: "SCOPED_VALUE",
                    applicationBundleIdentifier: "com.example.app"
                )
            ]
        )

        let prompts = composer.prompts(for: request, cleanedTranscript: "Transcript")

        #expect(prompts.user.contains("global phrase → GLOBAL_VALUE"))
        #expect(!prompts.user.contains("scoped phrase"))
        #expect(!prompts.user.contains("SCOPED_VALUE"))
    }

    @Test("Translate prompt defaults to English")
    func defaultsTranslationTargetToEnglish() {
        let request = makeRequest(task: .translate)

        let prompts = composer.prompts(for: request, cleanedTranscript: "早上好")

        #expect(prompts.user.contains("Target language: English"))
    }

    @Test("Answer prompt includes selected text and spoken request")
    func composesAnswerPrompt() {
        let request = IntelligenceRequest(
            task: .answer,
            transcript: "Explain this",
            selectedText: "Selected passage",
            context: CapturedContext(applicationName: "Safari")
        )

        let prompts = composer.prompts(for: request, cleanedTranscript: "Explain this")

        #expect(prompts.system.contains("desktop assistant"))
        #expect(prompts.user.contains("Selected text:\nSelected passage"))
        #expect(prompts.user.contains("Request:\nExplain this"))
    }

    @Test("Rewrite prompt requests a complete replacement")
    func composesRewriteSelectionPrompt() {
        let request = IntelligenceRequest(
            task: .rewriteSelection,
            transcript: "Make it concise",
            selectedText: "A long selected paragraph",
            context: CapturedContext(applicationName: "Mail")
        )

        let prompts = composer.prompts(for: request, cleanedTranscript: "Make it concise")

        #expect(prompts.system.contains("complete replacement text"))
        #expect(prompts.user.contains("Selected text:\nA long selected paragraph"))
        #expect(prompts.user.contains("Editing instruction:\nMake it concise"))
    }

    private func makeRequest(
        task: IntelligenceTask,
        targetLanguage: String? = nil
    ) -> IntelligenceRequest {
        IntelligenceRequest(
            task: task,
            transcript: "Transcript",
            targetLanguage: targetLanguage,
            context: CapturedContext(applicationName: "Test App")
        )
    }
}
