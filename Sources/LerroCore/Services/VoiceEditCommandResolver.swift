import Foundation

public enum DeterministicVoiceEditOutcome: Equatable, Sendable {
    case restorePreviousVersion
    case replaceText(String)
    case beginRedictation
}

public enum DeterministicVoiceEditError: Error, Equatable, Sendable {
    case sentenceNumberOutOfRange
    case sourceTextMissing
    case emptyResult
}

public enum VoiceEditCommandResolver {
    public static func resolve(_ transcript: String) -> VoiceEditRequest? {
        let instruction = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return nil }
        let command = instruction.trimmingCharacters(in: trailingPunctuation)
        let folded = command.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        if undoCommands.contains(folded) {
            return .deterministic(.undo)
        }
        if redictationCommands.contains(folded) {
            return .deterministic(.redictate)
        }
        if let sentenceNumber = deletedSentenceNumber(in: folded) {
            return .deterministic(.deleteSentence(sentenceNumber))
        }
        if let replacement = exactReplacement(in: command) {
            return .deterministic(replacement)
        }
        guard hasExplicitSemanticIntent(folded) else { return nil }

        return .semantic(SemanticVoiceEditRequest(
            operation: semanticOperation(for: folded),
            instruction: instruction
        ))
    }

    private static func deletedSentenceNumber(in instruction: String) -> Int? {
        let patterns = [
            #"^(?:删除|删掉|去掉)第?([0-9一二三四五六七八九十两]+)(?:个)?句(?:话)?$"#,
            #"^第?([0-9一二三四五六七八九十两]+)(?:个)?句(?:话)?(?:删除|删掉|去掉)$"#,
            #"^(?:delete|remove)(?:\s+the)?\s+(?:(?:sentence)\s+)?([0-9]+|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)(?:\s+sentence)?$"#,
        ]
        for pattern in patterns {
            guard let match = firstMatch(pattern: pattern, in: instruction),
                  let tokenRange = Range(match.range(at: 1), in: instruction) else { continue }
            return parseOrdinal(String(instruction[tokenRange]))
        }
        return nil
    }

    private static func exactReplacement(
        in instruction: String
    ) -> DeterministicVoiceEditCommand? {
        let patterns = [
            #"^(?:把|将)?\s*(.+?)\s*(?:改成|替换成|替换为)\s*(.+)$"#,
            #"^(?:replace|change)\s+(.+?)\s+(?:with|to)\s+(.+)$"#,
        ]
        for pattern in patterns {
            guard let match = firstMatch(pattern: pattern, in: instruction),
                  let sourceRange = Range(match.range(at: 1), in: instruction),
                  let replacementRange = Range(match.range(at: 2), in: instruction) else { continue }
            let source = stripQuotes(String(instruction[sourceRange]))
            let replacement = stripQuotes(String(instruction[replacementRange]))
            guard !source.isEmpty, !replacement.isEmpty else { continue }
            return .replaceExact(source: source, replacement: replacement)
        }
        return nil
    }

    private static func semanticOperation(for instruction: String) -> SemanticVoiceEditOperation {
        if containsAny(instruction, ["翻译", "译成", "translate"]) {
            return .translate
        }
        if containsAny(instruction, ["改短", "简短", "精简", "缩短", "shorten", "shorter", "condense"]) {
            return .shorten
        }
        if containsAny(instruction, ["扩写", "展开", "详细", "变长", "expand", "longer", "elaborate"]) {
            return .expand
        }
        if containsAny(instruction, [
            "语气", "正式", "随意", "友好", "专业",
            "tone", "formal", "casual", "friendly", "professional",
        ]) {
            return .changeTone
        }
        return .general
    }

    private static func hasExplicitSemanticIntent(_ instruction: String) -> Bool {
        if containsAny(instruction, [
            "刚才", "改", "调整", "重写", "保留", "精简", "扩写", "缩短", "简短",
            "展开", "详细", "变长", "语气", "翻译", "译成", "删除", "删掉", "去掉",
        ]) {
            return true
        }
        let englishPrefixes = [
            "edit ", "change ", "rewrite ", "adjust ", "keep ", "shorten ", "expand ",
            "translate ", "delete ", "remove ", "make it ",
        ]
        return englishPrefixes.contains { instruction.hasPrefix($0) }
            || instruction == "edit"
            || instruction == "rewrite"
            || instruction == "adjust"
    }

    private static func parseOrdinal(_ token: String) -> Int? {
        if let value = Int(token), value > 0 { return value }
        let english: [String: Int] = [
            "first": 1,
            "second": 2,
            "third": 3,
            "fourth": 4,
            "fifth": 5,
            "sixth": 6,
            "seventh": 7,
            "eighth": 8,
            "ninth": 9,
            "tenth": 10,
        ]
        if let value = english[token] { return value }

        let chineseDigits: [Character: Int] = [
            "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9,
        ]
        if token == "十" { return 10 }
        if token.contains("十") {
            let components = token.split(separator: "十", omittingEmptySubsequences: false)
            guard components.count == 2 else { return nil }
            let tens = components[0].first.flatMap { chineseDigits[$0] } ?? 1
            let ones = components[1].first.flatMap { chineseDigits[$0] } ?? 0
            let value = tens * 10 + ones
            return value > 0 ? value : nil
        }
        guard token.count == 1, let character = token.first else { return nil }
        return chineseDigits[character]
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range)
    }

    private static func stripQuotes(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [
            ("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"), ("「", "」"), ("『", "』"),
        ]
        if let first = result.first,
           let last = result.last,
           pairs.contains(where: { $0.0 == first && $0.1 == last }),
           result.count >= 2 {
            result.removeFirst()
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains { value.contains($0) }
    }

    private static let undoCommands: Set<String> = [
        "撤销", "撤回", "撤销修改", "撤销刚才的修改", "恢复上一版", "回到上一版",
        "undo", "undo that", "undo edit", "undo last edit", "go back", "restore previous version",
    ]

    private static let redictationCommands: Set<String> = [
        "重新听写", "重新说", "重说一遍", "从头再说", "重新录入",
        "redictate", "say it again", "start over", "dictate again",
    ]

    private static let trailingPunctuation = CharacterSet(charactersIn: ",.!?;:，。！？；：")
}

public enum DeterministicVoiceEditor {
    public static func outcome(
        for command: DeterministicVoiceEditCommand,
        currentText: String
    ) throws -> DeterministicVoiceEditOutcome {
        switch command {
        case .undo:
            return .restorePreviousVersion
        case .redictate:
            return .beginRedictation
        case .replaceExact(let source, let replacement):
            guard !source.isEmpty, currentText.contains(source) else {
                throw DeterministicVoiceEditError.sourceTextMissing
            }
            let updated = currentText.replacingOccurrences(of: source, with: replacement)
            guard !updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DeterministicVoiceEditError.emptyResult
            }
            return .replaceText(updated)
        case .deleteSentence(let sentenceNumber):
            let ranges = sentenceRanges(in: currentText)
            guard sentenceNumber > 0, sentenceNumber <= ranges.count else {
                throw DeterministicVoiceEditError.sentenceNumberOutOfRange
            }
            var updated = currentText
            updated.removeSubrange(ranges[sentenceNumber - 1])
            updated = updated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !updated.isEmpty else { throw DeterministicVoiceEditError.emptyResult }
            return .replaceText(updated)
        }
    }

    private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        let terminators: Set<Character> = ["。", "！", "？", ".", "!", "?"]
        var ranges: [Range<String.Index>] = []
        var sentenceStart = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            guard terminators.contains(text[index]) else {
                index = text.index(after: index)
                continue
            }
            var sentenceEnd = text.index(after: index)
            while sentenceEnd < text.endIndex, terminators.contains(text[sentenceEnd]) {
                sentenceEnd = text.index(after: sentenceEnd)
            }
            while sentenceEnd < text.endIndex, text[sentenceEnd].isWhitespace {
                sentenceEnd = text.index(after: sentenceEnd)
            }
            ranges.append(sentenceStart..<sentenceEnd)
            sentenceStart = sentenceEnd
            index = sentenceEnd
        }

        if sentenceStart < text.endIndex,
           text[sentenceStart...].contains(where: { !$0.isWhitespace }) {
            ranges.append(sentenceStart..<text.endIndex)
        }
        return ranges
    }
}
