import Foundation

public actor RuleBasedIntelligenceService: IntelligenceProcessing {
    private let pipeline = TextPipeline()
    private var statusValue = LocalModelStatus(
        state: .ready,
        modelIdentifier: "local-deterministic",
        progress: 1,
        message: "本地基础处理已就绪"
    )

    public init() {}

    public func prepare(modelIdentifier: String) {
        statusValue.modelIdentifier = modelIdentifier
    }

    public func process(_ request: IntelligenceRequest) throws -> IntelligenceResult {
        let cleaned = pipeline.clean(
            request.transcript,
            dictionary: request.dictionary,
            applicationBundleIdentifier: request.context.bundleIdentifier
        )
        guard !cleaned.isEmpty else { throw LerroError.emptyTranscription }

        switch request.task {
        case .polish:
            return IntelligenceResult(text: cleaned, disposition: .insert, modelIdentifier: statusValue.modelIdentifier)
        case .rewriteSelection:
            let selected = request.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let replacement = selected.isEmpty ? cleaned : basicRewrite(selected: selected, instruction: cleaned)
            return IntelligenceResult(text: replacement, disposition: .replaceSelection, modelIdentifier: statusValue.modelIdentifier)
        case .translate:
            throw LerroError.modelUnavailable("翻译需要完成本地语言模型下载")
        case .answer:
            throw LerroError.modelUnavailable("Ask 需要完成本地语言模型下载")
        }
    }

    public func modelStatus() -> LocalModelStatus { statusValue }

    private func basicRewrite(selected: String, instruction: String) -> String {
        let lowercased = instruction.lowercased()
        if lowercased.contains("大写") || lowercased.contains("uppercase") {
            return selected.uppercased()
        }
        if lowercased.contains("小写") || lowercased.contains("lowercase") {
            return selected.lowercased()
        }
        if lowercased.contains("精简") || lowercased.contains("shorter") {
            return String(selected.prefix(max(1, selected.count * 2 / 3)))
        }
        return selected
    }
}
