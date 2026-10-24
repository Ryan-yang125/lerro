import Foundation

public enum IntelligenceTask: String, Codable, Sendable {
    case polish
    case translate
}

public struct IntelligenceRequest: Sendable, Equatable {
    public var task: IntelligenceTask
    public var mode: IntelligenceMode
    public var remoteProvider: RemoteProviderConfiguration?
    public var transcript: String
    public var selectedText: String?
    public var targetLanguage: String?
    public var context: CapturedContext
    public var dictionary: [DictionaryEntry]
    public var toneInstruction: String?
    public var usageFeature: AIUsageFeature
    /// The history entry this request will produce; recorded on the usage record.
    public var historyEntryID: UUID?

    /// `usageFeature` defaults to `.dictate` for polish and `.translate` for translate.
    public init(
        task: IntelligenceTask,
        mode: IntelligenceMode = .remote,
        remoteProvider: RemoteProviderConfiguration? = nil,
        transcript: String,
        selectedText: String? = nil,
        targetLanguage: String? = nil,
        context: CapturedContext,
        dictionary: [DictionaryEntry] = [],
        toneInstruction: String? = nil,
        usageFeature: AIUsageFeature? = nil,
        historyEntryID: UUID? = nil
    ) {
        self.task = task
        self.mode = mode
        self.remoteProvider = remoteProvider
        self.transcript = transcript
        self.selectedText = selectedText
        self.targetLanguage = targetLanguage
        self.context = context
        self.dictionary = dictionary
        self.toneInstruction = toneInstruction
        self.usageFeature = usageFeature ?? (task == .translate ? .translate : .dictate)
        self.historyEntryID = historyEntryID
    }
}

public struct DictionaryLearningRequest: Sendable, Equatable {
    public static let maximumSpanCharacters = 256
    public static let maximumContextCharacters = 160

    public var mode: IntelligenceMode
    public var remoteProvider: RemoteProviderConfiguration?
    public var originalSpan: String
    public var correctedSpan: String
    public var contextBefore: String?
    public var contextAfter: String?
    public var applicationName: String
    public var bundleIdentifier: String?
    public var historyEntryID: UUID?

    public init(
        mode: IntelligenceMode,
        remoteProvider: RemoteProviderConfiguration? = nil,
        originalSpan: String,
        correctedSpan: String,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        applicationName: String,
        bundleIdentifier: String? = nil,
        historyEntryID: UUID? = nil
    ) {
        self.mode = mode
        self.remoteProvider = remoteProvider
        self.originalSpan = String(originalSpan.prefix(Self.maximumSpanCharacters))
        self.correctedSpan = String(correctedSpan.prefix(Self.maximumSpanCharacters))
        self.contextBefore = contextBefore.map {
            String($0.suffix(Self.maximumContextCharacters))
        }
        self.contextAfter = contextAfter.map {
            String($0.prefix(Self.maximumContextCharacters))
        }
        self.applicationName = String(applicationName.prefix(128))
        self.bundleIdentifier = bundleIdentifier.map { String($0.prefix(255)) }
        self.historyEntryID = historyEntryID
    }
}

public enum DictionaryLearningValidationError: Error, Equatable, Sendable {
    case invalidCandidate
    case tooManyCandidates
    case invalidJSON
}

public struct DictionaryLearningCandidate: Codable, Equatable, Hashable, Sendable {
    public var phrase: String
    public var replacement: String
    public var confidence: Double

    public init(phrase: String, replacement: String, confidence: Double) {
        self.phrase = phrase
        self.replacement = replacement
        self.confidence = confidence
    }

    public var isValid: Bool {
        let source = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return !source.isEmpty
            && !target.isEmpty
            && source == phrase
            && target == replacement
            && source != target
            && confidence.isFinite
            && (0...1).contains(confidence)
    }
}

public struct DictionaryLearningDecision: Codable, Equatable, Sendable {
    public static let maximumCandidates = 3
    public var candidates: [DictionaryLearningCandidate]

    public init(validating candidates: [DictionaryLearningCandidate]) throws {
        guard candidates.count <= Self.maximumCandidates else {
            throw DictionaryLearningValidationError.tooManyCandidates
        }
        let mappings = candidates.map {
            "\($0.phrase.trimmingCharacters(in: .whitespacesAndNewlines))\u{0}\($0.replacement.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        guard candidates.allSatisfy(\.isValid), Set(mappings).count == mappings.count else {
            throw DictionaryLearningValidationError.invalidCandidate
        }
        self.candidates = candidates
    }

    public static let noLearning = try! DictionaryLearningDecision(validating: [])

    private enum CodingKeys: String, CodingKey {
        case candidates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(validating: container.decode(
            [DictionaryLearningCandidate].self,
            forKey: .candidates
        ))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(candidates, forKey: .candidates)
    }

    public static func decodeStrictJSON(_ generated: String) throws -> Self {
        let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}",
              let data = trimmed.data(using: .utf8) else {
            throw DictionaryLearningValidationError.invalidJSON
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["candidates"],
                  let candidates = object["candidates"] as? [[String: Any]],
                  candidates.allSatisfy({ candidate in
                      Set(candidate.keys) == ["phrase", "replacement", "confidence"]
                          && candidate["phrase"] is String
                          && candidate["replacement"] is String
                          && candidate["confidence"] is NSNumber
                  }) else {
                throw DictionaryLearningValidationError.invalidJSON
            }
            let decoded = try JSONDecoder().decode(Self.self, from: data)
            return try Self(validating: decoded.candidates)
        } catch let error as DictionaryLearningValidationError {
            throw error
        } catch {
            throw DictionaryLearningValidationError.invalidJSON
        }
    }
}

public struct IntelligenceResult: Sendable, Equatable {
    public var text: String
    public var modelIdentifier: String
    public var source: IntelligenceResultSource
    /// The remote call behind this result; nil for raw results.
    public var call: AICallTrace?

    public init(
        text: String,
        modelIdentifier: String,
        source: IntelligenceResultSource = .remote,
        call: AICallTrace? = nil
    ) {
        self.text = text
        self.modelIdentifier = modelIdentifier
        self.source = source
        self.call = call
    }
}

public enum LerroError: LocalizedError, Sendable {
    case permissionRequired(String)
    case speechUnavailable(String)
    case emptyTranscription
    case secureField
    case insertionFailed(String)
    case localData(String)
    case modelUnavailable(String)
    case remoteUnavailable(String)
    case insufficientBalance
    case invalidAPIKey
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .permissionRequired(let permission):
            "需要开启\(permission)权限"
        case .speechUnavailable(let message):
            "语音识别暂不可用：\(message)"
        case .emptyTranscription:
            "没有识别到语音"
        case .secureField:
            "为保护敏感信息，密码输入框中已停用语音输入"
        case .insertionFailed(let message):
            "文本写入失败：\(message)"
        case .localData(let message):
            "本地数据处理失败：\(message)"
        case .modelUnavailable(let message):
            "AI 模型暂不可用：\(message)"
        case .remoteUnavailable(let message):
            "远程模型暂不可用：\(message)"
        case .insufficientBalance:
            "DeepSeek 余额用完了"
        case .invalidAPIKey:
            "API Key 无效或没有访问权限"
        case .cancelled:
            "已取消"
        }
    }
}
