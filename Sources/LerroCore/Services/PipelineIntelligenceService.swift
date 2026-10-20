import Foundation

public actor PipelineIntelligenceService: IntelligenceProcessing {
    private let remoteRuntime: (any RemoteLanguageModelRuntime)?
    private let cloudComposer: CloudPromptComposer
    private let dictionaryLearningComposer: DictionaryLearningPromptComposer
    private let usageRecorder: (any AIUsageRepository)?

    public init(
        remoteRuntime: (any RemoteLanguageModelRuntime)? = nil,
        cloudComposer: CloudPromptComposer = CloudPromptComposer(),
        dictionaryLearningComposer: DictionaryLearningPromptComposer = DictionaryLearningPromptComposer(),
        usageRecorder: (any AIUsageRepository)? = nil
    ) {
        self.remoteRuntime = remoteRuntime
        self.cloudComposer = cloudComposer
        self.dictionaryLearningComposer = dictionaryLearningComposer
        self.usageRecorder = usageRecorder
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
        guard let remoteRuntime else {
            throw LerroError.remoteUnavailable("远程模型运行时尚未配置")
        }
        let timed = try await recordingUsage(
            feature: request.usageFeature,
            configuration: invocation.configuration,
            historyEntryID: request.historyEntryID,
            tokens: { $0.generation.tokens }
        ) {
            let clock = ContinuousClock()
            let startedAt = Date()
            let start = clock.now
            let generation = try await remoteRuntime.generate(
                configuration: invocation.configuration,
                systemPrompt: invocation.systemPrompt,
                userPrompt: invocation.userPrompt,
                maxTokens: invocation.maxTokens
            )
            return TimedGeneration(
                generation: generation,
                startedAt: startedAt,
                latencyMilliseconds: Self.milliseconds(since: start, clock: clock)
            )
        }
        let generated = timed.generation.text

        let generatedText = request.task == .polish
            ? CloudPromptComposer.dictateText(from: generated)
            : generated
        let call = AICallTrace(
            prompt: request.task == .translate ? .translate : .dictate,
            promptVersion: request.task == .translate
                ? CloudPromptComposer.translatePromptVersion
                : CloudPromptComposer.dictatePromptVersion,
            provider: invocation.configuration.provider,
            modelIdentifier: invocation.configuration.modelIdentifier,
            userPrompt: invocation.userPrompt,
            response: generated,
            tokens: timed.generation.tokens,
            latencyMilliseconds: timed.latencyMilliseconds,
            startedAt: timed.startedAt
        )

        return IntelligenceResult(
            text: try Self.finalText(
                from: generatedText,
                fallbackTranscript: rawTranscript,
                task: request.task
            ),
            disposition: disposition,
            modelIdentifier: invocation.configuration.modelIdentifier,
            source: .remote,
            call: call
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
        guard let configuration = request.remoteProvider else {
            throw LerroError.remoteUnavailable("远程模型配置缺失")
        }
        guard let remoteRuntime else {
            throw LerroError.remoteUnavailable("远程模型运行时尚未配置")
        }
        let generated = try await recordingUsage(
            feature: .dictionaryLearning,
            configuration: configuration,
            historyEntryID: request.historyEntryID,
            tokens: \.tokens
        ) {
            try await remoteRuntime.generate(
                configuration: configuration,
                systemPrompt: prompts.system,
                userPrompt: prompts.user,
                maxTokens: DictionaryLearningPromptComposer.maximumOutputTokens
            )
        }.text
        let decision = try DictionaryLearningDecision.decodeStrictJSON(generated)
        guard decision.candidates.allSatisfy({ candidate in
            original.localizedCaseInsensitiveContains(candidate.phrase)
                && corrected.localizedCaseInsensitiveContains(candidate.replacement)
        }) else {
            throw DictionaryLearningValidationError.invalidCandidate
        }
        return decision
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
            historyEntryID: nil,
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
        historyEntryID: UUID?,
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
                succeeded: succeeded,
                historyEntryID: historyEntryID
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
        guard let configuration = request.remoteProvider else {
            throw LerroError.remoteUnavailable("远程模型配置缺失")
        }
        let prompts = try cloudComposer.prompts(for: request)
        return Invocation(
            configuration: configuration,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            maxTokens: 768
        )
    }

    private nonisolated static func disposition(for task: IntelligenceTask) -> IntelligenceDisposition {
        switch task {
        case .polish, .translate: .insert
        }
    }

    private nonisolated static func finalText(
        from generated: String,
        fallbackTranscript: String,
        task: IntelligenceTask
    ) throws -> String {
        let sanitized = sanitize(generated, fallback: "")
        if !sanitized.isEmpty {
            return sanitized
        }
        if case .polish = task {
            return fallbackTranscript
        }
        throw LerroError.remoteUnavailable("远程模型没有生成有效内容")
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

    private struct TimedGeneration: Sendable {
        let generation: RemoteGeneration
        let startedAt: Date
        let latencyMilliseconds: Int
    }

    private struct Invocation: Sendable {
        let configuration: RemoteProviderConfiguration
        let systemPrompt: String
        let userPrompt: String
        let maxTokens: Int
    }
}
