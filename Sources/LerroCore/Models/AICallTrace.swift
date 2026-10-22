import Foundation

public enum AIPromptKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case dictate
    case translate
    case dictionaryLearning

    public var id: String { rawValue }
}

/// One remote model call as sent and received. Stored inside a history entry.
public struct AICallTrace: Codable, Hashable, Sendable {
    public var prompt: AIPromptKind
    public var promptVersion: String
    /// The configured model ID that was sent.
    public var modelIdentifier: String
    /// Exact user message.
    public var userPrompt: String
    /// Exact assistant message content.
    public var response: String
    public var tokens: AITokenUsage?
    public var latencyMilliseconds: Int
    public var startedAt: Date

    public init(
        prompt: AIPromptKind,
        promptVersion: String,
        modelIdentifier: String,
        userPrompt: String,
        response: String,
        tokens: AITokenUsage? = nil,
        latencyMilliseconds: Int,
        startedAt: Date
    ) {
        self.prompt = prompt
        self.promptVersion = promptVersion
        self.modelIdentifier = modelIdentifier
        self.userPrompt = userPrompt
        self.response = response
        self.tokens = tokens
        self.latencyMilliseconds = max(0, latencyMilliseconds)
        self.startedAt = startedAt
    }

    /// Parsed user payload; nil when `userPrompt` is not the dictate or translate JSON.
    public var sentContext: AISentContext? {
        guard prompt != .dictionaryLearning else { return nil }
        return AISentContext(userPrompt: userPrompt)
    }

    /// Word fixes from a dictate response; empty for other prompts or unparsable output.
    public var fixes: [AIWordFix] {
        prompt == .dictate ? CloudPromptComposer.dictateFixes(from: response) : []
    }

    /// Proper-noun corrections from a dictate response; empty for other prompts or unparsable output.
    public var terms: [String] {
        prompt == .dictate ? CloudPromptComposer.dictateTerms(from: response) : []
    }
}

public struct AIWordFix: Hashable, Sendable {
    public var recognized: String
    public var corrected: String

    public init(recognized: String, corrected: String) {
        self.recognized = recognized
        self.corrected = corrected
    }
}

public struct AIGlossaryMapping: Hashable, Sendable {
    public var phrase: String
    public var replacement: String

    public init(phrase: String, replacement: String) {
        self.phrase = phrase
        self.replacement = replacement
    }
}

/// What the model saw, decoded from the dictate or translate user payload.
public struct AISentContext: Hashable, Sendable {
    public var transcript: String
    public var targetLanguage: String?
    public var applicationName: String?
    public var windowTitle: String?
    public var cursorBefore: String?
    public var cursorAfter: String?
    public var selectedText: String?
    public var knownTerms: [String]
    public var glossary: [AIGlossaryMapping]
    public var tone: String?

    public init?(userPrompt: String) {
        guard let data = userPrompt.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let transcript = (root["raw_data"] as? [String: Any])?["transcript"] as? String
        else { return nil }

        let rules = root["normalization_rules"] as? [String: Any]
        let workspace = root["workspace"] as? [String: Any]
        let personalization = root["personalization"] as? [String: Any]

        self.transcript = transcript
        targetLanguage = rules?["target_language"] as? String
        applicationName = workspace?["application_name"] as? String
        windowTitle = workspace?["window_title"] as? String
        cursorBefore = workspace?["cursor_before"] as? String
        cursorAfter = workspace?["cursor_after"] as? String
        selectedText = workspace?["selected_text"] as? String
        knownTerms = personalization?["known_terms"] as? [String] ?? []
        glossary = (personalization?["glossary"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let phrase = entry["phrase"] as? String,
                  let replacement = entry["replacement"] as? String
            else { return nil }
            return AIGlossaryMapping(phrase: phrase, replacement: replacement)
        }
        tone = personalization?["tone"] as? String
    }
}
