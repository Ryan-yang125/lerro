import Foundation
import Testing
@testable import LerroCore

@Suite("Pipeline intelligence service")
struct PipelineIntelligenceServiceTests {
    @Test("Loads the local model and preserves the exact transcript in the prompt")
    func loadsThenGeneratesFromExactTranscript() async throws {
        let runtime = FakeLanguageModelRuntime(output: "Polished result")
        let service = PipelineIntelligenceService(
            runtime: runtime,
            modelIdentifier: "test-model"
        )
        let request = IntelligenceRequest(
            task: .polish,
            transcript: "  uh   hello hello ,   type less  ",
            context: CapturedContext(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes"
            ),
            dictionary: [DictionaryEntry(phrase: "type less", replacement: "Lerro")]
        )

        let result = try await service.process(request)
        let events = await runtime.recordedEvents()

        #expect(result.text == "Polished result")
        #expect(result.modelIdentifier == "test-model")
        #expect(result.source == .local)
        #expect(events.count == 2)

        let firstEvent = try #require(events.first)
        guard case .load(let modelIdentifier) = firstEvent else {
            Issue.record("Expected model loading to be the first runtime event")
            return
        }
        #expect(modelIdentifier == "test-model")

        let lastEvent = try #require(events.last)
        guard case .generate(let systemPrompt, let userPrompt, let maxTokens) = lastEvent else {
            Issue.record("Expected generation to follow model loading")
            return
        }
        #expect(systemPrompt.contains("local writing engine"))
        #expect(userPrompt.contains("Application: Notes"))
        #expect(userPrompt.contains("Dictation:\n  uh   hello hello ,   type less  "))
        #expect(userPrompt.contains("hello hello"))
        #expect(maxTokens == 768)
    }

    @Test("Maps every task to its delivery disposition and token budget")
    func mapsTaskDispositions() async throws {
        let cases: [(IntelligenceTask, IntelligenceDisposition, Int)] = [
            (.polish, .insert, 768),
            (.translate, .insert, 768)
        ]

        for (task, expectedDisposition, expectedMaxTokens) in cases {
            let runtime = FakeLanguageModelRuntime(output: "result")
            let service = PipelineIntelligenceService(
                runtime: runtime,
                modelIdentifier: "model-\(task.rawValue)"
            )
            let result = try await service.process(makeRequest(task: task))
            let events = await runtime.recordedEvents()

            #expect(result.disposition == expectedDisposition)
            let lastEvent = try #require(events.last)
            guard case .generate(_, _, let maxTokens) = lastEvent else {
                Issue.record("Expected a generation event for \(task.rawValue)")
                continue
            }
            #expect(maxTokens == expectedMaxTokens)
        }
    }

    @Test("Falls back to the exact transcript for an empty generation")
    func fallsBackForEmptyGeneration() async throws {
        let runtime = FakeLanguageModelRuntime(output: "  \n  ")
        let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "test-model")
        let request = makeRequest(task: .polish, transcript: " uh fallback fallback ")

        let result = try await service.process(request)

        #expect(result.text == " uh fallback fallback ")
        #expect(result.source == .local)
    }

    @Test(
        "Rejects empty non-polish generations",
        arguments: [IntelligenceTask.translate]
    )
    func rejectsEmptyNonPolishGeneration(task: IntelligenceTask) async {
        let runtime = FakeLanguageModelRuntime(output: "  \n  ")
        let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "test-model")

        do {
            _ = try await service.process(makeRequest(task: task))
            Issue.record("Expected an empty \(task.rawValue) generation to fail")
        } catch {
            guard case LerroError.modelUnavailable(let message) = error else {
                Issue.record("Received an unexpected error: \(error)")
                return
            }
            #expect(message == "本地模型没有生成有效内容")
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
            let runtime = FakeLanguageModelRuntime(output: generated)
            let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "test-model")

            let result = try await service.process(makeRequest(task: .polish))

            #expect(result.text == expected)
        }
    }

    @Test("Propagates model loading errors before generation")
    func propagatesLoadError() async {
        let runtime = FakeLanguageModelRuntime(
            output: "unused",
            loadError: .loadFailed
        )
        let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "test-model")
        var receivedError: FakeRuntimeError?

        do {
            _ = try await service.process(makeRequest(task: .polish))
            Issue.record("Expected model loading to fail")
        } catch let error as FakeRuntimeError {
            receivedError = error
        } catch {
            Issue.record("Received an unexpected error type: \(error)")
        }

        #expect(receivedError == .loadFailed)
        let events = await runtime.recordedEvents()
        #expect(events == [.load("test-model")])
    }

    @Test("Propagates generation errors after loading the model")
    func propagatesGenerationError() async {
        let runtime = FakeLanguageModelRuntime(
            output: "unused",
            generationError: .generationFailed
        )
        let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "test-model")
        var receivedError: FakeRuntimeError?

        do {
            _ = try await service.process(makeRequest(task: .polish))
            Issue.record("Expected generation to fail")
        } catch let error as FakeRuntimeError {
            receivedError = error
        } catch {
            Issue.record("Received an unexpected error type: \(error)")
        }

        #expect(receivedError == .generationFailed)
        let events = await runtime.recordedEvents()
        #expect(events.count == 2)
        guard events.count == 2 else { return }
        guard case .load = events[0], case .generate = events[1] else {
            Issue.record("Expected model loading followed by generation")
            return
        }
    }

    @Test("Raw mode preserves transcript bytes and bypasses every model runtime")
    func rawModeBypassesModelRuntimes() async throws {
        let local = FakeLanguageModelRuntime(output: "unused", loadError: .loadFailed)
        let remote = FakeRemoteLanguageModelRuntime(output: "unused")
        let service = PipelineIntelligenceService(
            runtime: local,
            remoteRuntime: remote,
            modelIdentifier: "local-model"
        )
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
        #expect(await local.recordedEvents().isEmpty)
        #expect(await remote.recordedEvents().isEmpty)
    }

    @Test("Remote mode routes only to the configured provider with the exact transcript")
    func remoteModeRoutesToConfiguredProvider() async throws {
        let local = FakeLanguageModelRuntime(output: "unused", loadError: .loadFailed)
        let remote = FakeRemoteLanguageModelRuntime(output: "Remote result")
        let service = PipelineIntelligenceService(
            runtime: local,
            remoteRuntime: remote,
            modelIdentifier: "local-model"
        )
        let configuration = RemoteProviderConfiguration(
            provider: .deepSeek,
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
        #expect(await local.recordedEvents().isEmpty)
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
        let local = FakeLanguageModelRuntime(output: "unused")
        let outcome = RemoteConnectionTestOutcome.success(
            latencyMilliseconds: 42,
            modelIdentifier: "deepseek-v4-flash"
        )
        let remote = FakeRemoteLanguageModelRuntime(output: "unused", connectionOutcome: outcome)
        let service = PipelineIntelligenceService(
            runtime: local,
            remoteRuntime: remote,
            modelIdentifier: "local-model"
        )
        let configuration = RemoteProviderConfiguration(apiKey: "test-key")

        #expect(try await service.testRemoteConnection(configuration: configuration) == outcome)
        #expect(await remote.recordedEvents() == [.testConnection(configuration)])
    }

    @Test("Local AI classifies a bounded correction into a dictionary candidate")
    func classifiesLocalCorrection() async throws {
        let runtime = FakeLanguageModelRuntime(
            output: #"{"candidates":[{"phrase":"乐若","replacement":"Lerro","confidence":0.97}]}"#
        )
        let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "local-model")
        let request = DictionaryLearningRequest(
            mode: .local,
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
        let events = await runtime.recordedEvents()
        #expect(events.count == 2)
        guard case .generate(let system, let user, let tokens) = events.last else {
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
        let local = FakeLanguageModelRuntime(output: "unused", loadError: .loadFailed)
        let remote = FakeRemoteLanguageModelRuntime(output: #"{"candidates":[]}"#)
        let service = PipelineIntelligenceService(
            runtime: local,
            remoteRuntime: remote,
            modelIdentifier: "local-model"
        )
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
        #expect(await local.recordedEvents().isEmpty)
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
        let local = FakeLanguageModelRuntime(output: "unused")
        let remote = FakeRemoteLanguageModelRuntime(output: "unused")
        let service = PipelineIntelligenceService(
            runtime: local,
            remoteRuntime: remote,
            modelIdentifier: "local-model"
        )

        await #expect(throws: LerroError.self) {
            try await service.classifyCorrection(DictionaryLearningRequest(
                mode: .raw,
                originalSpan: "乐若",
                correctedSpan: "Lerro",
                applicationName: "Notes"
            ))
        }
        #expect(await local.recordedEvents().isEmpty)
        #expect(await remote.recordedEvents().isEmpty)
    }

    @Test("Raw mode keeps translation unavailable")
    func rawModeRejectsTranslation() async {
        let service = PipelineIntelligenceService(
            runtime: FakeLanguageModelRuntime(output: "unused"),
            modelIdentifier: "local-model"
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
            runtime: FakeLanguageModelRuntime(
                output: #"{"candidates":[{"phrase":"invented","replacement":"Lerro","confidence":0.9}]}"#
            ),
            modelIdentifier: "local-model"
        )
        await #expect(throws: DictionaryLearningValidationError.self) {
            try await service.classifyCorrection(DictionaryLearningRequest(
                mode: .local,
                originalSpan: "乐若",
                correctedSpan: "Lerro",
                applicationName: "Notes"
            ))
        }
    }

    @Test("Remote dictate records tokens, feature, provider and model")
    func remoteDictateRecordsUsage() async throws {
        let usage = InMemoryAIUsageRepository()
        let tokens = AITokenUsage(inputTokens: 120, outputTokens: 30, cachedInputTokens: 40)
        let configuration = RemoteProviderConfiguration(provider: .deepSeek, apiKey: "test-key")
        let service = makeRemoteService(
            remote: FakeRemoteLanguageModelRuntime(output: "Remote result", tokens: tokens),
            usage: usage
        )

        _ = try await service.process(remoteRequest(task: .polish, configuration: configuration))

        let records = try await usage.records(since: .distantPast)
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.feature == .dictate)
        #expect(record.provider == .deepSeek)
        #expect(record.modelIdentifier == configuration.modelIdentifier)
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

    @Test("Local and raw modes record nothing")
    func localAndRawRecordNothing() async throws {
        let usage = InMemoryAIUsageRepository()
        let service = PipelineIntelligenceService(
            runtime: FakeLanguageModelRuntime(output: "Local result"),
            remoteRuntime: FakeRemoteLanguageModelRuntime(output: "unused"),
            modelIdentifier: "local-model",
            usageRecorder: usage
        )

        _ = try await service.process(makeRequest(task: .polish))
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
        PipelineIntelligenceService(
            runtime: FakeLanguageModelRuntime(output: "unused", loadError: .loadFailed),
            remoteRuntime: remote,
            modelIdentifier: "local-model",
            usageRecorder: usage
        )
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

    private func makeRequest(
        task: IntelligenceTask,
        transcript: String = "Test transcript"
    ) -> IntelligenceRequest {
        IntelligenceRequest(
            task: task,
            transcript: transcript,
            targetLanguage: task == .translate ? "en_US" : nil,
            context: CapturedContext(applicationName: "Tests")
        )
    }
}

private enum FakeRuntimeError: Error, Equatable, Sendable {
    case loadFailed
    case generationFailed
}

private actor FakeLanguageModelRuntime: LocalLanguageModelRuntime {
    enum Event: Equatable, Sendable {
        case load(String)
        case generate(systemPrompt: String, userPrompt: String, maxTokens: Int)
    }

    private let output: String
    private let loadError: FakeRuntimeError?
    private let generationError: FakeRuntimeError?
    private var events: [Event] = []

    init(
        output: String,
        loadError: FakeRuntimeError? = nil,
        generationError: FakeRuntimeError? = nil
    ) {
        self.output = output
        self.loadError = loadError
        self.generationError = generationError
    }

    func load(modelIdentifier: String) throws {
        events.append(.load(modelIdentifier))
        if let loadError {
            throw loadError
        }
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) throws -> String {
        events.append(
            .generate(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens
            )
        )
        if let generationError {
            throw generationError
        }
        return output
    }

    func status() -> LocalModelStatus {
        LocalModelStatus(
            state: .ready,
            modelIdentifier: "fake-runtime",
            progress: 1,
            message: "ready"
        )
    }

    func recordedEvents() -> [Event] {
        events
    }
}

private actor FakeRemoteLanguageModelRuntime: RemoteLanguageModelRuntime {
    enum Event: Equatable, Sendable {
        case generate(RemoteProviderConfiguration, String, String, Int)
        case testConnection(RemoteProviderConfiguration)
    }

    private let output: String
    private let tokens: AITokenUsage?
    private let generationError: (any Error)?
    private let connectionOutcome: RemoteConnectionTestOutcome
    private var events: [Event] = []

    init(
        output: String,
        tokens: AITokenUsage? = nil,
        generationError: (any Error)? = nil,
        connectionOutcome: RemoteConnectionTestOutcome = .success()
    ) {
        self.output = output
        self.tokens = tokens
        self.generationError = generationError
        self.connectionOutcome = connectionOutcome
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
            modelIdentifier: configuration.modelIdentifier,
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

    func recordedEvents() -> [Event] {
        events
    }
}
