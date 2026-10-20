import Foundation

public struct DictionaryLearningPromptComposer: Sendable {
    public static let promptVersion = "dictionary_learning_v1"
    public static let maximumOutputTokens = 384

    public init() {}

    public func prompts(
        for request: DictionaryLearningRequest
    ) throws -> (system: String, user: String) {
        let payload = DictionaryLearningPromptPayload(
            originalSpan: request.originalSpan,
            correctedSpan: request.correctedSpan,
            contextBefore: request.contextBefore,
            contextAfter: request.contextAfter,
            applicationName: request.applicationName,
            bundleIdentifier: request.bundleIdentifier
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let user = String(decoding: try encoder.encode(payload), as: UTF8.self)
        return (Self.systemPrompt, user)
    }

    public static let systemPrompt = AIPromptDocument.document(for: .dictionaryLearning).fullText
}

private struct DictionaryLearningPromptPayload: Encodable {
    let originalSpan: String
    let correctedSpan: String
    let contextBefore: String?
    let contextAfter: String?
    let applicationName: String
    let bundleIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case originalSpan = "original_span"
        case correctedSpan = "corrected_span"
        case contextBefore = "context_before"
        case contextAfter = "context_after"
        case applicationName = "application_name"
        case bundleIdentifier = "bundle_identifier"
    }
}
