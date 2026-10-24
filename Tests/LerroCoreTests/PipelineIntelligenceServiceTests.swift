import Foundation
import Testing
@testable import LerroCore

@Suite("Pipeline intelligence service")
struct PipelineIntelligenceServiceTests {
    @Test("Maps every task to its token budget")
    func mapsTaskTokenBudgets() async throws {
        let cases: [(IntelligenceTask, Int)] = [
            (.polish, 768),
            (.translate, 768)
        ]

        for (task, expectedMaxTokens) in cases {
            let remote = FakeRemoteLanguageModelRuntime(output: "result")
            let service = makeRemoteService(remote: remote, usage: InMemoryAIUsageRepository())
            _ = try await service.process(remoteRequest(task: task))
            let events = await remote.recordedEvents()

            let lastEvent = try #require(events.last)
            guard case .generate(_, _, _, let maxTokens) = lastEvent else {
                Issue.record("Expected a generation event for \(task.rawValue)")
                continue
            }
            #expect(maxTokens == expectedMaxTokens)
        }
    }

    @Test("Falls back to the exact transcript for an empty generation")
    func fallsBackForEmptyGeneration() async throws {
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: "  \n  "),
            usage: InMemoryAIUsageRepository()
        )
        let request = remoteRequest(task: .polish)

        let result = try await service.process(request)

        #expect(result.text == request.transcript)
        #expect(result.source == .remote)
    }

    @Test("Rejects an empty translation generation")
    func rejectsEmptyTranslationGeneration() async {
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: "  \n  "),
            usage: InMemoryAIUsageRepository()
        )

        do {
            _ = try await service.process(remoteRequest(task: .translate))
            Issue.record("Expected an empty translate generation to fail")
        } catch {
            guard case LerroError.remoteUnavailable(let message) = error else {
                Issue.record("Received an unexpected error: \(error)")
                return
            }
            #expect(message == "AI 没有返回有效内容")
        }
    }

    @Test("Removes code fences and wrapping quotation marks")
    func sanitizesGeneratedText() async throws {
        let cases = [
            ("```text\nHello\n```", "Hello"),
            ("```\nHello\n```", "Hello"),
            ("\"Hello\"", "Hello"),
            ("“你好”", "你好")
        ]

        for (generated, expected) in cases {
            let service = makeRemoteService(
                remote: FakeRemoteLanguageModelRuntime(output: generated),
                usage: InMemoryAIUsageRepository()
            )

            let result = try await service.process(remoteRequest(task: .translate))

            #expect(result.text == expected)
        }
    }

    @Test("Propagates generation errors")
    func propagatesGenerationError() async {
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(
                output: "unused",
                generationError: FakeRuntimeError.generationFailed
            ),
            usage: InMemoryAIUsageRepository()
        )
        var receivedError: FakeRuntimeError?

        do {
            _ = try await service.process(remoteRequest(task: .polish))
            Issue.record("Expected generation to fail")
        } catch let error as FakeRuntimeError {
            receivedError = error
        } catch {
            Issue.record("Received an unexpected error type: \(error)")
        }

        #expect(receivedError == .generationFailed)
    }

    @Test("Raw mode preserves transcript bytes and bypasses every model runtime")
    func rawModeBypassesModelRuntimes() async throws {
        let remote = FakeRemoteLanguageModelRuntime(output: "unused")
        let service = PipelineIntelligenceService(remoteRuntime: remote)
        let request = IntelligenceRequest(
            task: .polish,
            mode: .raw,
            transcript: "  exact raw transcript  ",
            context: CapturedContext(applicationName: "Tests")
        )

        let result = try await service.process(request)

        #expect(result.text == "  exact raw transcript  ")
        #expect(result.modelIdentifier == "raw-transcript")
        #expect(result.source == .raw)
        #expect(await remote.recordedEvents().isEmpty)
    }

    @Test("Remote mode routes only to the remote runtime with the exact transcript")
    func remoteModeRoutesToRemoteRuntime() async throws {
        let remote = FakeRemoteLanguageModelRuntime(output: "Remote result")
        let service = PipelineIntelligenceService(remoteRuntime: remote)
        let configuration = RemoteProviderConfiguration(
            apiKey: "test-key",
            contextSharing: .balanced
        )
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: configuration,
            transcript: "  exact remote transcript  ",
            context: CapturedContext(applicationName: "Notes")
        )

        let result = try await service.process(request)
        let events = await remote.recordedEvents()

        #expect(result.text == "Remote result")
        #expect(result.modelIdentifier == "deepseek-flash")
        #expect(result.source == .remote)
        #expect(events.count == 1)
        guard case .generate(let savedConfiguration, _, let userPrompt, 768) = events.first else {
            Issue.record("Expected one remote generation")
            return
        }
        #expect(savedConfiguration == configuration)
        #expect(userPrompt.contains(#""transcript":"  exact remote transcript  ""#))
    }

    @Test("Remote dictate delivers the text field of the JSON response")
    func remoteDictateUsesJSONText() async throws {
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(
                output: #"{"fixes":[["程序华","程序化"]],"text":"用程序化完全代替 AI 识图。"}"#
            ),
            usage: InMemoryAIUsageRepository()
        )

        let result = try await service.process(remoteRequest(task: .polish))

        #expect(result.text == "用程序化完全代替 AI 识图。")
    }

    @Test("Remote dictate falls back to the raw transcript when the JSON is broken")
    func remoteDictateBrokenJSONFallsBack() async throws {
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: #"{"fixes":[],"text":"cut off"#),
            usage: InMemoryAIUsageRepository()
        )
        let request = remoteRequest(task: .polish)

        let result = try await service.process(request)

        #expect(result.text == request.transcript)
    }

    @Test("Remote dictate keeps plain text output when the model skips the JSON format")
    func remoteDictateKeepsPlainText() async throws {
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: "Plain polished text."),
            usage: InMemoryAIUsageRepository()
        )

        let result = try await service.process(remoteRequest(task: .polish))

        #expect(result.text == "Plain polished text.")
    }

    @Test("Remote translate does not read JSON text")
    func remoteTranslateIgnoresJSONFormat() async throws {
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: "Hello"),
            usage: InMemoryAIUsageRepository()
        )

        let result = try await service.process(remoteRequest(task: .translate))

        #expect(result.text == "Hello")
    }

    @Test("Remote connection testing delegates to the remote runtime")
    func delegatesRemoteConnectionTest() async throws {
        let outcome = RemoteConnectionTestOutcome.success(
            latencyMilliseconds: 42,
            modelIdentifier: "deepseek-v4-flash"
        )
        let remote = FakeRemoteLanguageModelRuntime(output: "unused", connectionOutcome: outcome)
        let service = PipelineIntelligenceService(remoteRuntime: remote)
        let configuration = RemoteProviderConfiguration(apiKey: "test-key")

        #expect(try await service.testRemoteConnection(configuration: configuration) == outcome)
        #expect(await remote.recordedEvents() == [.testConnection(configuration)])
    }

    @Test("Balance lookup delegates to the remote runtime and records no usage")
    func delegatesBalanceLookup() async throws {
        let usage = InMemoryAIUsageRepository()
        let balance = DeepSeekBalance(isAvailable: true, total: 3, currencyCode: "CNY")
        let remote = FakeRemoteLanguageModelRuntime(output: "unused", balanceResult: balance)
        let service = makeRemoteService(remote: remote, usage: usage)
        let configuration = RemoteProviderConfiguration(apiKey: "test-key")

        #expect(try await service.remoteBalance(configuration: configuration) == balance)
        #expect(await remote.recordedEvents() == [.balance(configuration)])
        #expect(try await usage.records(since: .distantPast).isEmpty)
    }

    @Test("Balance lookup without a runtime fails as unavailable")
    func balanceWithoutRuntimeFails() async {
        let service = PipelineIntelligenceService()
        await #expect(throws: LerroError.self) {
            try await service.remoteBalance(configuration: RemoteProviderConfiguration(apiKey: "test-key"))
        }
    }

    @Test("Remote AI classifies a bounded correction into a dictionary candidate")
    func classifiesRemoteCorrectionCandidate() async throws {
        let remote = FakeRemoteLanguageModelRuntime(
            output: #"{"candidates":[{"phrase":"乐若","replacement":"Lerro","confidence":0.97}]}"#
        )
        let service = PipelineIntelligenceService(remoteRuntime: remote)
        let request = DictionaryLearningRequest(
            mode: .remote,
            remoteProvider: RemoteProviderConfiguration(apiKey: "test-key"),
            originalSpan: "乐若",
            correctedSpan: "Lerro",
            contextBefore: String(repeating: "前", count: 200),
            contextAfter: String(repeating: "后", count: 200),
            applicationName: "ChatGPT",
            bundleIdentifier: "com.openai.chat"
        )

        let decision = try await service.classifyCorrection(request)

        #expect(decision.candidates == [
            DictionaryLearningCandidate(phrase: "乐若", replacement: "Lerro", confidence: 0.97)
        ])
        #expect(request.contextBefore?.count == DictionaryLearningRequest.maximumContextCharacters)
        #expect(request.contextAfter?.count == DictionaryLearningRequest.maximumContextCharacters)
        let events = await remote.recordedEvents()
        #expect(events.count == 1)
        guard case .generate(_, let system, let user, let tokens) = events.last else {
            Issue.record("Expected correction generation")
            return
        }
        #expect(system.contains("明天 to 昨天"))
        #expect(system.contains("zero to three candidates"))
        #expect(user.contains(#""original_span":"乐若""#))
        #expect(user.contains(#""corrected_span":"Lerro""#))
        #expect(tokens == DictionaryLearningPromptComposer.maximumOutputTokens)
    }

    @Test("Remote correction classification sends only the bounded correction payload")
    func classifiesRemoteCorrection() async throws {
        let remote = FakeRemoteLanguageModelRuntime(output: #"{"candidates":[]}"#)
        let service = PipelineIntelligenceService(remoteRuntime: remote)
        let configuration = RemoteProviderConfiguration(apiKey: "test-key")
        let decision = try await service.classifyCorrection(DictionaryLearningRequest(
            mode: .remote,
            remoteProvider: configuration,
            originalSpan: "明天",
            correctedSpan: "昨天",
            contextBefore: "我们原来说",
            contextAfter: "要开会",
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes"
        ))

        #expect(decision == .noLearning)
        let events = await remote.recordedEvents()
        #expect(events.count == 1)
        guard case .generate(let saved, _, let user, let tokens) = events.first else {
            Issue.record("Expected one remote correction generation")
            return
        }
        #expect(saved == configuration)
        #expect(user.contains(#""original_span":"明天""#))
        #expect(!user.contains("test-key"))
        #expect(tokens == DictionaryLearningPromptComposer.maximumOutputTokens)
    }

    @Test("Raw mode rejects automatic dictionary learning without model calls")
    func rawModeRejectsDictionaryLearning() async {
        let remote = FakeRemoteLanguageModelRuntime(output: "unused")
        let service = PipelineIntelligenceService(remoteRuntime: remote)

        await #expect(throws: LerroError.self) {
            try await service.classifyCorrection(DictionaryLearningRequest(
                mode: .raw,
                originalSpan: "乐若",
                correctedSpan: "Lerro",
                applicationName: "Notes"
            ))
        }
        #expect(await remote.recordedEvents().isEmpty)
    }

    @Test("Raw mode keeps translation unavailable")
    func rawModeRejectsTranslation() async {
        let service = PipelineIntelligenceService(
            remoteRuntime: FakeRemoteLanguageModelRuntime(output: "unused")
        )
        await #expect(throws: LerroError.self) {
            try await service.process(IntelligenceRequest(
                task: .translate,
                mode: .raw,
                transcript: "你好",
                targetLanguage: "en_US",
                context: CapturedContext(applicationName: "Tests")
            ))
        }
    }

    @Test("Correction classification rejects malformed or hallucinated output")
    func rejectsInvalidCorrectionOutput() async {
        let invalidOutputs = [
            #"```json\n{"candidates":[]}\n```"#,
            #"{"candidates":[],"explanation":"none"}"#,
            #"{"candidates":[{"phrase":"same","replacement":"same","confidence":1}]}"#,
            #"{"candidates":[{"phrase":"a","replacement":"A","confidence":1},{"phrase":"b","replacement":"B","confidence":1},{"phrase":"c","replacement":"C","confidence":1},{"phrase":"d","replacement":"D","confidence":1}]}"#
        ]
        for output in invalidOutputs {
            #expect(throws: DictionaryLearningValidationError.self) {
                try DictionaryLearningDecision.decodeStrictJSON(output)
            }
        }

        let service = PipelineIntelligenceService(
            remoteRuntime: FakeRemoteLanguageModelRuntime(
                output: #"{"candidates":[{"phrase":"invented","replacement":"Lerro","confidence":0.9}]}"#
            )
        )
        await #expect(throws: DictionaryLearningValidationError.self) {
            try await service.classifyCorrection(DictionaryLearningRequest(
                mode: .remote,
                remoteProvider: RemoteProviderConfiguration(apiKey: "test-key"),
                originalSpan: "乐若",
                correctedSpan: "Lerro",
                applicationName: "Notes"
            ))
        }
    }

    @Test("Remote dictate records tokens, feature and model")
    func remoteDictateRecordsUsage() async throws {
        let usage = InMemoryAIUsageRepository()
        let tokens = AITokenUsage(inputTokens: 120, outputTokens: 30, cachedInputTokens: 40)
        let configuration = RemoteProviderConfiguration(apiKey: "test-key")
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: "Remote result", tokens: tokens),
            usage: usage
        )

        _ = try await service.process(remoteRequest(task: .polish, configuration: configuration))

        let records = try await usage.records(since: .distantPast)
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.feature == .dictate)
        #expect(record.modelIdentifier == RemoteProviderConfiguration.modelIdentifier)
        #expect(record.tokens == tokens)
        #expect(record.succeeded)
    }

    @Test("Remote translate records the translate feature")
    func remoteTranslateRecordsUsage() async throws {
        let usage = InMemoryAIUsageRepository()
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: "Hello"),
            usage: usage
        )

        _ = try await service.process(remoteRequest(task: .translate))

        let records = try await usage.records(since: .distantPast)
        #expect(records.map(\.feature) == [.translate])
        #expect(records.first?.tokens == nil)
        #expect(records.first?.succeeded == true)
    }

    @Test("An explicit usage feature overrides the task default")
    func honorsExplicitUsageFeature() async throws {
        let usage = InMemoryAIUsageRepository()
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: "Preview"),
            usage: usage
        )

        _ = try await service.process(remoteRequest(task: .polish, usageFeature: .tonePreview))

        #expect(try await usage.records(since: .distantPast).map(\.feature) == [.tonePreview])
    }

    @Test("A failed remote call records an unsuccessful request and rethrows")
    func recordsRemoteFailure() async throws {
        let usage = InMemoryAIUsageRepository()
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(
                output: "unused",
                tokens: AITokenUsage(inputTokens: 1, outputTokens: 1),
                generationError: FakeRuntimeError.generationFailed
            ),
            usage: usage
        )

        await #expect(throws: FakeRuntimeError.generationFailed) {
            try await service.process(remoteRequest(task: .polish))
        }

        let records = try await usage.records(since: .distantPast)
        #expect(records.count == 1)
        #expect(records.first?.succeeded == false)
        #expect(records.first?.tokens == nil)
    }

    @Test("A cancelled remote call records nothing")
    func cancellationRecordsNothing() async throws {
        let usage = InMemoryAIUsageRepository()
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(
                output: "unused",
                generationError: CancellationError()
            ),
            usage: usage
        )

        await #expect(throws: CancellationError.self) {
            try await service.process(remoteRequest(task: .polish))
        }

        #expect(try await usage.records(since: .distantPast).isEmpty)
    }

    @Test("Remote correction classification records dictionary learning usage")
    func correctionClassificationRecordsUsage() async throws {
        let usage = InMemoryAIUsageRepository()
        let tokens = AITokenUsage(inputTokens: 50, outputTokens: 5)
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: #"{"candidates":[]}"#, tokens: tokens),
            usage: usage
        )

        _ = try await service.classifyCorrection(DictionaryLearningRequest(
            mode: .remote,
            remoteProvider: RemoteProviderConfiguration(apiKey: "test-key"),
            originalSpan: "明天",
            correctedSpan: "昨天",
            applicationName: "Notes"
        ))

        let records = try await usage.records(since: .distantPast)
        #expect(records.map(\.feature) == [.dictionaryLearning])
        #expect(records.first?.tokens == tokens)
    }

    @Test("Connection tests record tokens and the outcome")
    func connectionTestRecordsUsage() async throws {
        let usage = InMemoryAIUsageRepository()
        let tokens = AITokenUsage(inputTokens: 8, outputTokens: 1)
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(
                output: "unused",
                connectionOutcome: .success(latencyMilliseconds: 42, tokens: tokens)
            ),
            usage: usage
        )

        _ = try await service.testRemoteConnection(
            configuration: RemoteProviderConfiguration(apiKey: "test-key")
        )

        let records = try await usage.records(since: .distantPast)
        #expect(records.map(\.feature) == [.connectionTest])
        #expect(records.first?.tokens == tokens)
        #expect(records.first?.succeeded == true)
    }

    @Test("A connection test that throws records an unsuccessful request")
    func failedConnectionTestRecordsUsage() async throws {
        let usage = InMemoryAIUsageRepository()
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(
                output: "unused",
                generationError: FakeRuntimeError.generationFailed
            ),
            usage: usage
        )

        await #expect(throws: FakeRuntimeError.generationFailed) {
            try await service.testRemoteConnection(
                configuration: RemoteProviderConfiguration(apiKey: "test-key")
            )
        }

        let records = try await usage.records(since: .distantPast)
        #expect(records.map(\.feature) == [.connectionTest])
        #expect(records.first?.succeeded == false)
        #expect(records.first?.tokens == nil)
    }

    @Test("Raw mode records nothing")
    func rawModeRecordsNothing() async throws {
        let usage = InMemoryAIUsageRepository()
        let service = PipelineIntelligenceService(
            remoteRuntime: FakeRemoteLanguageModelRuntime(output: "unused"),
            usageRecorder: usage
        )

        _ = try await service.process(IntelligenceRequest(
            task: .polish,
            mode: .raw,
            transcript: "raw text",
            context: CapturedContext(applicationName: "Tests")
        ))

        #expect(try await usage.records(since: .distantPast).isEmpty)
    }

    private func makeRemoteService(
        remote: FakeRemoteLanguageModelRuntime,
        usage: InMemoryAIUsageRepository
    ) -> PipelineIntelligenceService {
        PipelineIntelligenceService(remoteRuntime: remote, usageRecorder: usage)
    }

    private func remoteRequest(
        task: IntelligenceTask,
        configuration: RemoteProviderConfiguration = RemoteProviderConfiguration(apiKey: "test-key"),
        usageFeature: AIUsageFeature? = nil
    ) -> IntelligenceRequest {
        IntelligenceRequest(
            task: task,
            mode: .remote,
            remoteProvider: configuration,
            transcript: "Test transcript",
            targetLanguage: task == .translate ? "en_US" : nil,
            context: CapturedContext(applicationName: "Tests"),
            usageFeature: usageFeature
        )
    }

}

private enum FakeRuntimeError: Error, Equatable, Sendable {
    case generationFailed
}

private actor FakeRemoteLanguageModelRuntime: RemoteLanguageModelRuntime {
    enum Event: Equatable, Sendable {
        case generate(RemoteProviderConfiguration, String, String, Int)
        case testConnection(RemoteProviderConfiguration)
        case balance(RemoteProviderConfiguration)
    }

    private let output: String
    private let tokens: AITokenUsage?
    private let generationError: (any Error)?
    private let connectionOutcome: RemoteConnectionTestOutcome
    private let balanceResult: DeepSeekBalance
    private var events: [Event] = []

    init(
        output: String,
        tokens: AITokenUsage? = nil,
        generationError: (any Error)? = nil,
        connectionOutcome: RemoteConnectionTestOutcome = .success(),
        balanceResult: DeepSeekBalance = DeepSeekBalance(isAvailable: true, total: 8, currencyCode: "CNY")
    ) {
        self.output = output
        self.tokens = tokens
        self.generationError = generationError
        self.connectionOutcome = connectionOutcome
        self.balanceResult = balanceResult
    }

    func generate(
        configuration: RemoteProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) throws -> RemoteGeneration {
        events.append(.generate(configuration, systemPrompt, userPrompt, maxTokens))
        if let generationError {
            throw generationError
        }
        return RemoteGeneration(
            text: output,
            modelIdentifier: RemoteProviderConfiguration.modelIdentifier,
            tokens: tokens
        )
    }

    func testConnection(
        configuration: RemoteProviderConfiguration
    ) throws -> RemoteConnectionTestOutcome {
        events.append(.testConnection(configuration))
        if let generationError {
            throw generationError
        }
        return connectionOutcome
    }

    func balance(
        configuration: RemoteProviderConfiguration
    ) throws -> DeepSeekBalance {
        events.append(.balance(configuration))
        if let generationError {
            throw generationError
        }
        return balanceResult
    }

    func recordedEvents() -> [Event] {
        events
    }
}
