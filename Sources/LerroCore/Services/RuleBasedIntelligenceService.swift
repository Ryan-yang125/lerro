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
        case .translate:
            throw LerroError.modelUnavailable("翻译需要完成本地语言模型下载")
        }
    }

    public func modelStatus() -> LocalModelStatus { statusValue }

}
