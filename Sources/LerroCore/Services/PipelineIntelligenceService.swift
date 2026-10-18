import Foundation

public actor PipelineIntelligenceService: IntelligenceProcessing {
    private let runtime: any LocalLanguageModelRuntime
    private let remoteRuntime: (any RemoteLanguageModelRuntime)?
    private let composer: PromptComposer
    private let cloudComposer: CloudPromptComposer
    private let dictionaryLearningComposer: DictionaryLearningPromptComposer
    private let usageRecorder: (any AIUsageRepository)?
    private var modelIdentifier: String

    public init(
        runtime: any LocalLanguageModelRuntime,
        remoteRuntime: (any RemoteLanguageModelRuntime)? = nil,
        modelIdentifier: String,
        pipeline: TextPipeline = TextPipeline(),
        composer: PromptComposer = PromptComposer(),
        cloudComposer: CloudPromptComposer = CloudPromptComposer(),
        dictionaryLearningComposer: DictionaryLearningPromptComposer = DictionaryLearningPromptComposer(),
        usageRecorder: (any AIUsageRepository)? = nil
    ) {
        self.runtime = runtime
        self.remoteRuntime = remoteRuntime
        self.modelIdentifier = modelIdentifier
        self.composer = composer
        self.cloudComposer = cloudComposer
        self.dictionaryLearningComposer = dictionaryLearningComposer
        self.usageRecorder = usageRecorder
        _ = pipeline
    }

    public func prepare(modelIdentifier: String) async throws {
        self.modelIdentifier = modelIdentifier
        try await runtime.load(modelIdentifier: modelIdentifier)
    }

    public func pauseLocalModelPreparation() async {
        await runtime.pauseLoad()
    }

    public func discardLocalModelDownload() async throws {
        try await runtime.discardDownload()
    }

    public func process(_ request: IntelligenceRequest) async throws -> IntelligenceResult {
        let rawTranscript = request.transcript
        guard !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LerroError.emptyTranscription
        }
        let disposition = Self.disposition(for: request.task)

        if request.mode == .raw {
            guard request.task == .polish else {
                throw LerroError.modelUnavailable("翻译需要启用 AI")
            }
            return IntelligenceResult(
                text: rawTranscript,
                disposition: disposition,
                modelIdentifier: "raw-transcript",
                source: .raw
            )
        }

        let invocation = try invocation(for: request)
        let generated: String
        switch invocation.runtime {
        case .local:
            try await runtime.load(modelIdentifier: invocation.modelIdentifier)
            generated = try await runtime.generate(
                systemPrompt: invocation.systemPrompt,
                userPrompt: invocation.userPrompt,
                maxTokens: invocation.maxTokens
            )
        case .remote(let configuration):
            guard let remoteRuntime else {
                throw LerroError.remoteUnavailable("远程模型运行时尚未配置")
            }
            generated = try await recordingUsage(
                feature: request.usageFeature,
                configuration: configuration,
                tokens: \.tokens
            ) {
                try await remoteRuntime.generate(
                    configuration: configuration,
                    systemPrompt: invocation.systemPrompt,
                    userPrompt: invocation.userPrompt,
                    maxTokens: invocation.maxTokens
                )
            }.text
        }

        let generatedText = invocation.source == .remote && request.task == .polish
            ? CloudPromptComposer.dictateText(from: generated)
            : generated

        return IntelligenceResult(
            text: try Self.finalText(
                from: generatedText,
                fallbackTranscript: rawTranscript,
                task: request.task,
                source: invocation.source
            ),
            disposition: disposition,
            modelIdentifier: invocation.modelIdentifier,
            source: invocation.source
        )
    }

    public func classifyCorrection(
        _ request: DictionaryLearningRequest
    ) async throws -> DictionaryLearningDecision {
        guard request.mode != .raw else {
            throw LerroError.modelUnavailable("自动词典学习需要启用 AI")
        }
        let original = request.originalSpan.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = request.correctedSpan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !corrected.isEmpty, original != corrected else {
            return .noLearning
        }

        let prompts = try dictionaryLearningComposer.prompts(for: request)
        let generated: String
        switch request.mode {
        case .raw:
            preconditionFailure("Raw correction requests are rejected before runtime routing")
        case .local:
            try await runtime.load(modelIdentifier: modelIdentifier)
            generated = try await runtime.generate(
                systemPrompt: prompts.system,
                userPrompt: prompts.user,
                maxTokens: DictionaryLearningPromptComposer.maximumOutputTokens
            )
        case .remote:
            guard let configuration = request.remoteProvider else {
                throw LerroError.remoteUnavailable("远程模型配置缺失")
            }
            guard let remoteRuntime else {
                throw LerroError.remoteUnavailable("远程模型运行时尚未配置")
            }
            generated = try await recordingUsage(
                feature: .dictionaryLearning,
                configuration: configuration,
                tokens: \.tokens
            ) {
                try await remoteRuntime.generate(
                    configuration: configuration,
                    systemPrompt: prompts.system,
                    userPrompt: prompts.user,
                    maxTokens: DictionaryLearningPromptComposer.maximumOutputTokens
                )
            }.text
        }
        let decision = try DictionaryLearningDecision.decodeStrictJSON(generated)
        guard decision.candidates.allSatisfy({ candidate in
            original.localizedCaseInsensitiveContains(candidate.phrase)
                && corrected.localizedCaseInsensitiveContains(candidate.replacement)
        }) else {
            throw DictionaryLearningValidationError.invalidCandidate
        }
        return decision
    }

    public func modelStatus() async -> LocalModelStatus {
        await runtime.status()
    }

    public func testRemoteConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome {
        guard let remoteRuntime else {
            throw LerroError.remoteUnavailable("远程模型运行时尚未配置")
        }
        return try await recordingUsage(
            feature: .connectionTest,
            configuration: configuration,
            tokens: \.tokens,
            succeeded: \.succeeded
        ) {
            try await remoteRuntime.testConnection(configuration: configuration)
        }
    }

    /// Runs one remote call and appends a usage record for it. Cancelled calls
    /// record nothing. Recording failures never affect the call.
    private func recordingUsage<Result: Sendable>(
        feature: AIUsageFeature,
        configuration: RemoteProviderConfiguration,
        tokens: (Result) -> AITokenUsage?,
        succeeded: (Result) -> Bool = { _ in true },
        _ call: () async throws -> Result
    ) async throws -> Result {
        let clock = ContinuousClock()
        let date = Date()
        let start = clock.now
        func record(tokens: AITokenUsage?, succeeded: Bool) async {
            try? await usageRecorder?.append(AIUsageRecord(
                date: date,
                feature: feature,
                provider: configuration.provider,
                modelIdentifier: configuration.modelIdentifier,
                tokens: tokens,
                latencyMilliseconds: Self.milliseconds(since: start, clock: clock),
                succeeded: succeeded
            ))
        }
        do {
            let result = try await call()
            await record(tokens: tokens(result), succeeded: succeeded(result))
            return result
        } catch {
            if !(error is CancellationError), !Task.isCancelled {
                await record(tokens: nil, succeeded: false)
            }
            throw error
        }
    }

    private nonisolated static func milliseconds(since start: ContinuousClock.Instant, clock: ContinuousClock) -> Int {
        let components = start.duration(to: clock.now).components
        return Int(components.seconds) * 1_000 + Int(components.attoseconds / 1_000_000_000_000_000)
    }

    private func invocation(for request: IntelligenceRequest) throws -> Invocation {
        let maxTokens = 768
        switch request.mode {
        case .raw:
            preconditionFailure("Raw requests are resolved before runtime routing")
        case .local:
            let prompts = composer.prompts(
                for: request,
                cleanedTranscript: request.transcript
            )
            return Invocation(
                runtime: .local,
                systemPrompt: prompts.system,
                userPrompt: prompts.user,
                maxTokens: maxTokens,
                modelIdentifier: modelIdentifier,
                source: .local
            )
        case .remote:
            guard let configuration = request.remoteProvider else {
                throw LerroError.remoteUnavailable("远程模型配置缺失")
            }
            let prompts = try cloudComposer.prompts(for: request)
            return Invocation(
                runtime: .remote(configuration),
                systemPrompt: prompts.system,
                userPrompt: prompts.user,
                maxTokens: maxTokens,
                modelIdentifier: configuration.modelIdentifier,
                source: .remote
            )
        }
    }

    private nonisolated static func disposition(for task: IntelligenceTask) -> IntelligenceDisposition {
        switch task {
        case .polish, .translate: .insert
        }
    }

    private nonisolated static func finalText(
        from generated: String,
        fallbackTranscript: String,
        task: IntelligenceTask,
        source: IntelligenceResultSource
    ) throws -> String {
        let sanitized = sanitize(generated, fallback: "")
        if !sanitized.isEmpty {
            return sanitized
        }
        if case .polish = task {
            return fallbackTranscript
        }
        if source == .remote {
            throw LerroError.remoteUnavailable("远程模型没有生成有效内容")
        }
        throw LerroError.modelUnavailable("本地模型没有生成有效内容")
    }

    private nonisolated static func sanitize(_ generated: String, fallback: String) -> String {
        var value = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value.replacingOccurrences(of: "```text", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")
                || value.hasPrefix("“") && value.hasSuffix("”")) {
            value.removeFirst()
            value.removeLast()
        }
        return value.isEmpty ? fallback : value
    }

    private struct Invocation: Sendable {
        enum Runtime: Sendable {
            case local
            case remote(RemoteProviderConfiguration)
        }

        let runtime: Runtime
        let systemPrompt: String
        let userPrompt: String
        let maxTokens: Int
        let modelIdentifier: String
        let source: IntelligenceResultSource
    }
}
