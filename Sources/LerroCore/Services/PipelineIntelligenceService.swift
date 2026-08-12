import Foundation

public actor PipelineIntelligenceService: IntelligenceProcessing {
    private let runtime: any LocalLanguageModelRuntime
    private let remoteRuntime: (any RemoteLanguageModelRuntime)?
    private let composer: PromptComposer
    private let cloudComposer: CloudPromptComposer
    private let dictionaryLearningComposer: DictionaryLearningPromptComposer
    private var modelIdentifier: String

    public init(
        runtime: any LocalLanguageModelRuntime,
        remoteRuntime: (any RemoteLanguageModelRuntime)? = nil,
        modelIdentifier: String,
        pipeline: TextPipeline = TextPipeline(),
        composer: PromptComposer = PromptComposer(),
        cloudComposer: CloudPromptComposer = CloudPromptComposer(),
        dictionaryLearningComposer: DictionaryLearningPromptComposer = DictionaryLearningPromptComposer()
    ) {
        self.runtime = runtime
        self.remoteRuntime = remoteRuntime
        self.modelIdentifier = modelIdentifier
        self.composer = composer
        self.cloudComposer = cloudComposer
        self.dictionaryLearningComposer = dictionaryLearningComposer
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
            generated = try await remoteRuntime.generate(
                configuration: configuration,
                systemPrompt: invocation.systemPrompt,
                userPrompt: invocation.userPrompt,
                maxTokens: invocation.maxTokens
            )
        }

        return IntelligenceResult(
            text: try Self.finalText(
                from: generated,
                fallbackTranscript: rawTranscript,
                task: request.task,
                source: invocation.source
            ),
            disposition: disposition,
            modelIdentifier: invocation.modelIdentifier,
            source: invocation.source
        )
    }

    public func processStream(
        _ request: IntelligenceRequest
    ) async throws -> AsyncThrowingStream<IntelligenceResult, any Error> {
        let rawTranscript = request.transcript
        guard !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LerroError.emptyTranscription
        }
        let disposition = Self.disposition(for: request.task)

        if request.mode == .raw {
            guard request.task == .polish else {
                throw LerroError.modelUnavailable("翻译需要启用 AI")
            }
            let result = IntelligenceResult(
                text: rawTranscript,
                disposition: disposition,
                modelIdentifier: "raw-transcript",
                source: .raw
            )
            return AsyncThrowingStream { continuation in
                continuation.yield(result)
                continuation.finish()
            }
        }

        let invocation = try invocation(for: request)
        let tokenStream: AsyncThrowingStream<String, any Error>
        switch invocation.runtime {
        case .local:
            try await runtime.load(modelIdentifier: invocation.modelIdentifier)
            tokenStream = try await runtime.generateStream(
                systemPrompt: invocation.systemPrompt,
                userPrompt: invocation.userPrompt,
                maxTokens: invocation.maxTokens
            )
        case .remote(let configuration):
            guard let remoteRuntime else {
                throw LerroError.remoteUnavailable("远程模型运行时尚未配置")
            }
            tokenStream = try await remoteRuntime.generateStream(
                configuration: configuration,
                systemPrompt: invocation.systemPrompt,
                userPrompt: invocation.userPrompt,
                maxTokens: invocation.maxTokens
            )
        }

        let currentModelIdentifier = invocation.modelIdentifier
        let source = invocation.source
        return AsyncThrowingStream { continuation in
            let task = Task {
                var generated = ""
                var lastEmitted = ""
                do {
                    for try await chunk in tokenStream {
                        try Task.checkCancellation()
                        generated += chunk
                        let partial = Self.sanitize(generated, fallback: "")
                        guard !partial.isEmpty, partial != lastEmitted else { continue }
                        lastEmitted = partial
                        continuation.yield(IntelligenceResult(
                            text: partial,
                            disposition: disposition,
                            modelIdentifier: currentModelIdentifier,
                            source: source
                        ))
                    }
                    let finalText = try Self.finalText(
                        from: generated,
                        fallbackTranscript: rawTranscript,
                        task: request.task,
                        source: source
                    )
                    if finalText != lastEmitted {
                        continuation.yield(IntelligenceResult(
                            text: finalText,
                            disposition: disposition,
                            modelIdentifier: currentModelIdentifier,
                            source: source
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
            generated = try await remoteRuntime.generate(
                configuration: configuration,
                systemPrompt: prompts.system,
                userPrompt: prompts.user,
                maxTokens: DictionaryLearningPromptComposer.maximumOutputTokens
            )
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
        return try await remoteRuntime.testConnection(configuration: configuration)
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
