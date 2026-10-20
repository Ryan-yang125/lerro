import Foundation

public struct CloudPromptComposer: Sendable {
    public static let dictatePromptVersion = "J_input_method_fixes_json_v1"
    public static let translatePromptVersion = "translate_v1"
    public static let maximumKnownTerms = 40
    public static let maximumKnownTermCharacters = 40
    public static let maximumSelectedTextCharacters = CapturedContext.maximumSelectedTextCharacters

    public init() {}

    public func prompts(
        for request: IntelligenceRequest
    ) throws -> (system: String, user: String) {
        let sharing = request.remoteProvider?.contextSharing ?? .balanced
        let payload = payload(for: request)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let userPrompt = String(decoding: try encoder.encode(payload), as: UTF8.self)
        return (systemPrompt(for: request.task), userPrompt)
    }

    private func payload(for request: IntelligenceRequest) -> CloudPromptPayload {
        let sharing = request.remoteProvider?.contextSharing ?? .balanced
        let cursorBefore = resolvedCursorBefore(from: request.context)
        let cursorAfter = request.context.cursorAfter.map { String($0.prefix(40)) }
        let selectedText = request.selectedText.map {
            String($0.prefix(Self.maximumSelectedTextCharacters))
        }

        return CloudPromptPayload(
            schemaVersion: "lerro.\(request.task.schemaName).v2",
            rawData: .init(transcript: request.transcript),
            normalizationRules: .init(
                version: request.task == .polish ? "natural_dictation_v2" : "structured_task_v1",
                task: request.task.schemaName,
                targetLanguage: request.targetLanguage,
                enabled: normalizationRules(for: request.task)
            ),
            workspace: .init(
                applicationType: sharing.application ? applicationType(for: request.context) : "unknown",
                applicationName: sharing.application ? request.context.applicationName.nonempty : nil,
                windowTitle: sharing.windowTitle ? request.context.windowTitle?.nonempty : nil,
                cursorBefore: sharing.nearbyText ? cursorBefore?.nonempty : nil,
                cursorAfter: sharing.nearbyText ? cursorAfter?.nonempty : nil,
                selectedText: sharing.selectedText ? selectedText?.nonempty : nil
            ),
            personalization: .init(
                glossary: sharing.dictionary
                    ? matchingGlossary(
                        for: request,
                        cursorBefore: sharing.nearbyText ? cursorBefore : nil,
                        cursorAfter: sharing.nearbyText ? cursorAfter : nil,
                        selectedText: sharing.selectedText ? selectedText : nil,
                        includeApplicationScope: sharing.application
                    )
                    : [],
                knownTerms: sharing.dictionary
                    ? knownTerms(for: request, includeApplicationScope: sharing.application)
                    : [],
                tone: sharing.tone ? request.toneInstruction?.nonempty ?? "natural" : "natural"
            )
        )
    }

    private func systemPrompt(for task: IntelligenceTask) -> String {
        switch task {
        case .polish:
            Self.dictateSystemPrompt
        case .translate:
            Self.translateSystemPrompt
        }
    }

    private func normalizationRules(for task: IntelligenceTask) -> [String] {
        switch task {
        case .polish:
            [
                "resolve_explicit_self_corrections",
                "remove_nonsemantic_fillers",
                "collapse_accidental_repetition",
                "preserve_meaningful_repetition",
                "restore_punctuation",
                "interpret_spoken_layout_controls",
                "preserve_protected_spans"
            ]
        case .translate:
            ["resolve_explicit_self_corrections", "preserve_protected_spans", "preserve_formatting"]
        }
    }

    private func resolvedCursorBefore(from context: CapturedContext) -> String? {
        if let cursorBefore = context.cursorBefore {
            return String(cursorBefore.suffix(80))
        }
        return context.focusedText.map { String($0.suffix(80)) }
    }

    private func matchingGlossary(
        for request: IntelligenceRequest,
        cursorBefore: String?,
        cursorAfter: String?,
        selectedText: String?,
        includeApplicationScope: Bool
    ) -> [CloudPromptPayload.Personalization.GlossaryEntry] {
        let searchableText = [
            request.transcript,
            selectedText,
            cursorBefore,
            cursorAfter
        ]
            .compactMap { $0 }
            .joined(separator: "\n")

        return request.dictionary
            .filter { entry in
                (entry.applicationBundleIdentifier == nil
                    || (includeApplicationScope
                        && entry.applicationBundleIdentifier == request.context.bundleIdentifier))
                    && searchableText.localizedCaseInsensitiveContains(entry.phrase)
            }
            .sorted { lhs, rhs in
                let lhsScoped = lhs.applicationBundleIdentifier != nil
                let rhsScoped = rhs.applicationBundleIdentifier != nil
                if lhsScoped != rhsScoped { return lhsScoped }
                if lhs.phrase.count != rhs.phrase.count { return lhs.phrase.count > rhs.phrase.count }
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(12)
            .map { .init(phrase: $0.phrase, replacement: $0.replacement) }
    }

    private func knownTerms(
        for request: IntelligenceRequest,
        includeApplicationScope: Bool
    ) -> [String] {
        let candidates = request.dictionary
            .filter { entry in
                !entry.isSnippet
                    && (entry.applicationBundleIdentifier == nil
                        || (includeApplicationScope
                            && entry.applicationBundleIdentifier == request.context.bundleIdentifier))
            }
            .sorted { lhs, rhs in
                let lhsScoped = lhs.applicationBundleIdentifier != nil
                let rhsScoped = rhs.applicationBundleIdentifier != nil
                if lhsScoped != rhsScoped { return lhsScoped }
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.phrase < rhs.phrase
            }

        var seen = Set<String>()
        var terms: [String] = []
        for entry in candidates {
            let source = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines).nonempty
                ?? entry.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty,
                  source.count <= Self.maximumKnownTermCharacters,
                  seen.insert(source.lowercased()).inserted
            else { continue }
            terms.append(source)
            if terms.count == Self.maximumKnownTerms { break }
        }
        return terms
    }

    private func applicationType(for context: CapturedContext) -> String {
        let identity = [context.applicationName, context.bundleIdentifier ?? ""]
            .joined(separator: " ")
            .lowercased()
        if ["mail", "outlook", "spark"].contains(where: identity.contains) {
            return "email"
        }
        if ["messages", "wechat", "weixin", "slack", "discord", "teams", "telegram", "chat"]
            .contains(where: identity.contains) {
            return "chat"
        }
        if ["xcode", "visual studio code", "vscode", "cursor", "terminal", "iterm", "codex"]
            .contains(where: identity.contains) {
            return "code"
        }
        if ["notes", "obsidian", "notion"].contains(where: identity.contains) {
            return "notes"
        }
        return "document"
    }

    /// Extracts `text` from the Dictate JSON response. Plain text is returned
    /// unchanged; broken JSON or an empty `text` returns an empty string so the
    /// pipeline falls back to the raw transcript instead of pasting JSON.
    public static func dictateText(from generated: String) -> String {
        let json = unfencedJSON(generated)
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(DictateResponse.self, from: data)
        else {
            // Broken JSON must not be pasted; an empty result makes the
            // pipeline fall back to the raw transcript.
            return json.hasPrefix("{") ? "" : generated
        }
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    /// Word fixes listed in the Dictate JSON response. Malformed pairs are ignored.
    public static func dictateFixes(from generated: String) -> [AIWordFix] {
        guard let data = unfencedJSON(generated).data(using: .utf8),
              let response = try? JSONDecoder().decode(DictateFixesResponse.self, from: data)
        else { return [] }
        return (response.fixes ?? []).compactMap { pair in
            pair.count == 2 ? AIWordFix(recognized: pair[0], corrected: pair[1]) : nil
        }
    }

    private static func unfencedJSON(_ generated: String) -> String {
        var json = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            var lines = json.split(separator: "\n", omittingEmptySubsequences: false)
            lines.removeFirst()
            if let last = lines.last, last.trimmingCharacters(in: .whitespaces) == "```" {
                lines.removeLast()
            }
            json = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return json
    }

    public static let dictateSystemPrompt = AIPromptDocument.document(for: .dictate).fullText
    public static let translateSystemPrompt = AIPromptDocument.document(for: .translate).fullText
}

private struct DictateResponse: Decodable {
    let text: String
}

private struct DictateFixesResponse: Decodable {
    let fixes: [[String]]?
}

private struct CloudPromptPayload: Encodable {
    struct RawData: Encodable {
        let transcript: String
    }

    struct NormalizationRules: Encodable {
        let version: String
        let task: String
        let targetLanguage: String?
        let enabled: [String]

        enum CodingKeys: String, CodingKey {
            case version
            case task
            case targetLanguage = "target_language"
            case enabled
        }
    }

    struct Workspace: Encodable {
        let applicationType: String
        let applicationName: String?
        let windowTitle: String?
        let cursorBefore: String?
        let cursorAfter: String?
        let selectedText: String?

        enum CodingKeys: String, CodingKey {
            case applicationType = "application_type"
            case applicationName = "application_name"
            case windowTitle = "window_title"
            case cursorBefore = "cursor_before"
            case cursorAfter = "cursor_after"
            case selectedText = "selected_text"
        }
    }

    struct Personalization: Encodable {
        struct GlossaryEntry: Encodable {
            let phrase: String
            let replacement: String
        }

        let glossary: [GlossaryEntry]
        let knownTerms: [String]?
        let tone: String

        init(glossary: [GlossaryEntry], knownTerms: [String], tone: String) {
            self.glossary = glossary
            self.knownTerms = knownTerms.isEmpty ? nil : knownTerms
            self.tone = tone
        }

        enum CodingKeys: String, CodingKey {
            case glossary
            case knownTerms = "known_terms"
            case tone
        }
    }

    let schemaVersion: String
    let rawData: RawData
    let normalizationRules: NormalizationRules
    let workspace: Workspace
    let personalization: Personalization

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case rawData = "raw_data"
        case normalizationRules = "normalization_rules"
        case workspace
        case personalization
    }

}

private extension IntelligenceTask {
    var schemaName: String {
        switch self {
        case .polish: "dictate"
        case .translate: "translate"
        }
    }
}

private extension String {
    var nonempty: String? {
        isEmpty ? nil : self
    }
}
