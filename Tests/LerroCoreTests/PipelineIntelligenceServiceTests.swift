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

    @Test("Accumulates streamed chunks into progressive results")
    func accumulatesStreamedChunks() async throws {
        let runtime = FakeLanguageModelRuntime(
            output: "unused",
            streamChunks: ["Hel", "lo", " ", "world"]
        )
        let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "stream-model")

        let stream = try await service.processStream(makeRequest(task: .polish))
        var results: [IntelligenceResult] = []
        for try await result in stream {
            results.append(result)
        }

        #expect(results.map(\.text) == ["Hel", "Hello", "Hello world"])
        #expect(results.last?.text == "Hello world")
        #expect(results.allSatisfy { $0.disposition == .insert })
        #expect(results.allSatisfy { $0.modelIdentifier == "stream-model" })
        #expect(results.allSatisfy { $0.source == .local })

        let events = await runtime.recordedEvents()
        #expect(events.count == 2)
        guard events.count == 2 else { return }
        guard case .load("stream-model") = events[0],
              case .generateStream(_, _, 768) = events[1] else {
            Issue.record("Expected model loading followed by streamed generation")
            return
        }
    }

    @Test("Empty polish stream falls back to the exact transcript")
    func fallsBackForEmptyPolishStream() async throws {
        let runtime = FakeLanguageModelRuntime(
            output: "unused",
            streamChunks: ["  ", "\n"]
        )
        let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "stream-model")

        let stream = try await service.processStream(
            makeRequest(task: .polish, transcript: " uh fallback fallback ")
        )
        var results: [IntelligenceResult] = []
        for try await result in stream {
            results.append(result)
        }

        #expect(results.map(\.text) == [" uh fallback fallback "])
    }

    @Test(
        "Rejects empty non-polish streams",
        arguments: [IntelligenceTask.translate]
    )
    func rejectsEmptyNonPolishStream(task: IntelligenceTask) async throws {
        let runtime = FakeLanguageModelRuntime(
            output: "unused",
            streamChunks: ["  ", "\n"]
        )
        let service = PipelineIntelligenceService(runtime: runtime, modelIdentifier: "stream-model")
        let stream = try await service.processStream(makeRequest(task: task))

        do {
            for try await _ in stream {}
            Issue.record("Expected an empty \(task.rawValue) stream to fail")
        } catch {
            guard case LerroError.modelUnavailable(let message) = error else {
                Issue.record("Received an unexpected stream error: \(error)")
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
        #expect(result.modelIdentifier == "deepseek-v4-flash")
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
        case generateStream(systemPrompt: String, userPrompt: String, maxTokens: Int)
    }

    private let output: String
    private let streamChunks: [String]?
    private let loadError: FakeRuntimeError?
    private let generationError: FakeRuntimeError?
    private var events: [Event] = []

    init(
        output: String,
        streamChunks: [String]? = nil,
        loadError: FakeRuntimeError? = nil,
        generationError: FakeRuntimeError? = nil
    ) {
        self.output = output
        self.streamChunks = streamChunks
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

    func generateStream(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) throws -> AsyncThrowingStream<String, any Error> {
        events.append(
            .generateStream(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens
            )
        )
        if let generationError {
            throw generationError
        }
        let chunks = streamChunks ?? [output]
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
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
    private let connectionOutcome: RemoteConnectionTestOutcome
    private var events: [Event] = []

    init(
        output: String,
        connectionOutcome: RemoteConnectionTestOutcome = .success()
    ) {
        self.output = output
        self.connectionOutcome = connectionOutcome
    }

    func generate(
        configuration: RemoteProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) -> String {
        events.append(.generate(configuration, systemPrompt, userPrompt, maxTokens))
        return output
    }

    func testConnection(
        configuration: RemoteProviderConfiguration
    ) -> RemoteConnectionTestOutcome {
        events.append(.testConnection(configuration))
        return connectionOutcome
    }

    func recordedEvents() -> [Event] {
        events
    }
}
