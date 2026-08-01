import Foundation

public struct PromptComposer: Sendable {
    public init() {}

    public func prompts(for request: IntelligenceRequest, cleanedTranscript: String) -> (system: String, user: String) {
        let glossary = request.dictionary
            .filter { entry in
                entry.applicationBundleIdentifier == nil
                    || entry.applicationBundleIdentifier == request.context.bundleIdentifier
            }
            .prefix(100)
            .map { "\($0.phrase) → \($0.replacement)" }
            .joined(separator: "\n")
        let context = [
            "Application: \(request.context.applicationName)",
            request.context.windowTitle.map { "Window: \($0)" },
            request.context.focusedText.map { "Nearby text: \(String($0.prefix(2_000)))" },
            request.toneInstruction.map { "Application style: \($0)" },
            glossary.isEmpty ? nil : "Glossary:\n\(glossary)"
        ].compactMap { $0 }.joined(separator: "\n")

        let sharedRules = """
        You are the local writing engine inside a macOS dictation app. Return only the final user-facing text. Preserve meaning, names, numbers, URLs, code, and the speaker's chosen order. Remove filler words, false starts, and accidental repetition. Apply natural punctuation and paragraph breaks. Follow the glossary exactly. Never add explanations or markdown fences.
        """

        switch request.task {
        case .polish:
            return (
                sharedRules,
                """
                Context:
                \(context)

                Dictation:
                \(cleanedTranscript)
                """
            )
        case .translate:
            return (
                sharedRules + " Translate naturally while preserving tone and formatting.",
                """
                Target language: \(request.targetLanguage ?? "English")
                Context:
                \(context)

                Dictation:
                \(cleanedTranscript)
                """
            )
        case .answer:
            return (
                """
                You are a concise local desktop assistant. Answer the user's spoken request using the supplied on-screen context. Give the useful result directly. Use plain text unless a short list materially improves clarity.
                """,
                """
                Context:
                \(context)
                Selected text:
                \(request.selectedText ?? "")

                Request:
                \(cleanedTranscript)
                """
            )
        case .rewriteSelection:
            return (
                sharedRules + " Apply the spoken editing instruction to the selected text and return the complete replacement text.",
                """
                Context:
                \(context)
                Selected text:
                \(request.selectedText ?? "")

                Editing instruction:
                \(cleanedTranscript)
                """
            )
        }
    }
}
