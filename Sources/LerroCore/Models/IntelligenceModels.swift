import Foundation

public enum IntelligenceTask: String, Codable, Sendable {
    case polish
    case translate
    case answer
    case rewriteSelection
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

    public init(
        task: IntelligenceTask,
        mode: IntelligenceMode = .local,
        remoteProvider: RemoteProviderConfiguration? = nil,
        transcript: String,
        selectedText: String? = nil,
        targetLanguage: String? = nil,
        context: CapturedContext,
        dictionary: [DictionaryEntry] = [],
        toneInstruction: String? = nil
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
    }
}

public enum IntelligenceDisposition: String, Codable, Sendable {
    case insert
    case replaceSelection
    case showAnswer
    case openURL
}

public struct IntelligenceResult: Sendable, Equatable {
    public var text: String
    public var disposition: IntelligenceDisposition
    public var url: URL?
    public var modelIdentifier: String
    public var source: IntelligenceResultSource

    public init(
        text: String,
        disposition: IntelligenceDisposition,
        url: URL? = nil,
        modelIdentifier: String,
        source: IntelligenceResultSource = .local
    ) {
        self.text = text
        self.disposition = disposition
        self.url = url
        self.modelIdentifier = modelIdentifier
        self.source = source
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
    case translationUnavailable(String)
    case selectionTooLong(Int)
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
            "本地模型暂不可用：\(message)"
        case .remoteUnavailable(let message):
            "远程模型暂不可用：\(message)"
        case .translationUnavailable(let message):
            "设备端翻译暂不可用：\(message)"
        case .selectionTooLong(let maximumCharacters):
            "选中文字最多支持 \(maximumCharacters) 字符，请缩小选区后重试"
        case .cancelled:
            "已取消"
        }
    }
}
