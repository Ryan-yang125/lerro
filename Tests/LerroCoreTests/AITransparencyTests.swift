import CryptoKit
import Foundation
import Testing
@testable import LerroCore

@Suite("AI transparency")
struct AITransparencyTests {
    // MARK: Prompt documents

    @Test("Prompt documents keep the sent prompt bytes unchanged")
    func promptHashes() {
        #expect(sha256(AIPromptDocument.document(for: .dictate).fullText)
            == "2d9fe5c9dc6cedced9215d48e7ddc43f842aca348ff7f355fa241dd2fccf89f7")
        #expect(sha256(AIPromptDocument.document(for: .translate).fullText)
            == "a79abd3ac992bf91e8b3f0ddbeeec8020d0e35022ca8de636e4e53d5bf677bae")
        #expect(sha256(AIPromptDocument.document(for: .dictionaryLearning).fullText)
            == "881bce4befb15b02432c8fd9de7994e9e2712810fc88060601fa45f58c70229e")
    }

    @Test("Composers send the document text")
    func composersUseDocuments() throws {
        #expect(CloudPromptComposer.dictateSystemPrompt == AIPromptDocument.document(for: .dictate).fullText)
        #expect(CloudPromptComposer.translateSystemPrompt == AIPromptDocument.document(for: .translate).fullText)
        #expect(DictionaryLearningPromptComposer.systemPrompt
            == AIPromptDocument.document(for: .dictionaryLearning).fullText)

        let request = IntelligenceRequest(
            task: .translate,
            remoteProvider: RemoteProviderConfiguration(),
            transcript: "你好",
            targetLanguage: "en_US",
            context: CapturedContext(applicationName: "Notes")
        )
        #expect(try CloudPromptComposer().prompts(for: request).system
            == AIPromptDocument.document(for: .translate).fullText)
    }

    @Test("Dictate document has the specified sections and nine parsed examples")
    func dictateDocumentStructure() throws {
        let document = AIPromptDocument.document(for: .dictate)

        #expect(document.version == CloudPromptComposer.dictatePromptVersion)
        #expect(document.sections.map(\.id) == ["role", "context", "asr", "edit", "examples", "format"])
        #expect(document.sections.filter(\.isExamples).map(\.id) == ["examples"])
        #expect(document.examples.map(\.id) == Array(1...9))

        let first = try #require(document.examples.first)
        #expect(first.title == "选中文字作上下文")
        #expect(first.said == "补一句预计下周一完成")
        #expect(first.context == [
            AIPromptExampleContext(label: "应用类型", value: "文档"),
            AIPromptExampleContext(label: "光标前", value: "接口联调已经完成。"),
            AIPromptExampleContext(label: "选中", value: "移动端仍在测试。"),
            AIPromptExampleContext(label: "语气", value: "简洁")
        ])
        #expect(first.fixes.isEmpty)
        #expect(first.terms.isEmpty)
        #expect(first.output == "预计下周一完成。")

        let list = document.examples[3]
        #expect(list.output.contains("\n1. 确认签名"))

        let known = document.examples[7]
        #expect(known.title == "识别错误和常用词")
        #expect(known.context.contains(AIPromptExampleContext(label: "常用词", value: "Xcode、Laura")))
        #expect(known.fixes.first == AIWordFix(recognized: "叉扣", corrected: "Xcode"))
        #expect(known.fixes.count == 3)
        #expect(known.terms == ["Xcode", "Laura"])
        #expect(document.examples[8].terms == ["网格搜索", "精准率", "召回率", "Notion"])
        #expect(document.examples.prefix(7).allSatisfy { $0.terms.isEmpty })
        #expect(document.version == "K_input_method_terms_json_v1")
    }

    @Test("Translate and learning documents have no examples")
    func otherDocuments() {
        let translate = AIPromptDocument.document(for: .translate)
        let learning = AIPromptDocument.document(for: .dictionaryLearning)

        #expect(translate.version == "translate_v1")
        #expect(translate.sections.map(\.id) == ["rules"])
        #expect(translate.examples.isEmpty)
        #expect(learning.version == "dictionary_learning_v1")
        #expect(learning.sections.map(\.id) == ["task", "reject", "format", "rules"])
        #expect(learning.examples.isEmpty)
    }

    // MARK: Sent context

    @Test("Sent context reads back what the composer put in the payload")
    func payloadRoundTrip() throws {
        let configuration = RemoteProviderConfiguration(contextSharing: .full)
        let request = IntelligenceRequest(
            task: .polish,
            remoteProvider: configuration,
            transcript: "把叉扣的缓存清一下",
            selectedText: "选中的文字",
            context: CapturedContext(
                applicationName: "Notes",
                windowTitle: "Daily",
                cursorBefore: "前文",
                cursorAfter: "后文"
            ),
            dictionary: [
                DictionaryEntry(phrase: "叉扣", replacement: "Xcode"),
                DictionaryEntry(phrase: "Laura", replacement: "Laura")
            ],
            toneInstruction: "简洁"
        )
        let user = try CloudPromptComposer().prompts(for: request).user

        let context = try #require(AISentContext(userPrompt: user))

        #expect(context.transcript == "把叉扣的缓存清一下")
        #expect(context.applicationName == "Notes")
        #expect(context.windowTitle == "Daily")
        #expect(context.cursorBefore == "前文")
        #expect(context.cursorAfter == "后文")
        #expect(context.selectedText == "选中的文字")
        #expect(context.knownTerms == ["Laura", "Xcode"])
        #expect(context.glossary == [AIGlossaryMapping(phrase: "叉扣", replacement: "Xcode")])
        #expect(context.tone == "简洁")
        #expect(context.targetLanguage == nil)
    }

    @Test("Translate payload carries the target language")
    func translatePayload() throws {
        let request = IntelligenceRequest(
            task: .translate,
            remoteProvider: RemoteProviderConfiguration(),
            transcript: "你好",
            targetLanguage: "en_US",
            context: CapturedContext(applicationName: "Notes")
        )
        let user = try CloudPromptComposer().prompts(for: request).user

        #expect(AISentContext(userPrompt: user)?.targetLanguage == "en_US")
    }

    @Test("Sent context is nil without JSON or a transcript")
    func sentContextRejectsOtherText() {
        #expect(AISentContext(userPrompt: "not json") == nil)
        #expect(AISentContext(userPrompt: #"{"workspace":{}}"#) == nil)
        #expect(AISentContext(userPrompt: #"{"original_span":"a","corrected_span":"b"}"#) == nil)
    }

    // MARK: Fixes

    @Test("Dictate fixes are read from plain and fenced JSON")
    func dictateFixes() {
        let plain = #"{"fixes": [["叉扣", "Xcode"], ["罗拉", "Laura"]], "text": "x"}"#
        let fenced = "```json\n\(plain)\n```"

        let expected = [
            AIWordFix(recognized: "叉扣", corrected: "Xcode"),
            AIWordFix(recognized: "罗拉", corrected: "Laura")
        ]
        #expect(CloudPromptComposer.dictateFixes(from: plain) == expected)
        #expect(CloudPromptComposer.dictateFixes(from: fenced) == expected)
    }

    @Test("Dictate fixes ignore malformed pairs and unparsable output")
    func dictateFixesMalformed() {
        let json = #"{"fixes": [["a"], ["b", "c"], ["d", "e", "f"]], "text": "x"}"#

        #expect(CloudPromptComposer.dictateFixes(from: json) == [AIWordFix(recognized: "b", corrected: "c")])
        #expect(CloudPromptComposer.dictateFixes(from: #"{"text": "x"}"#).isEmpty)
        #expect(CloudPromptComposer.dictateFixes(from: "plain text").isEmpty)
        #expect(CloudPromptComposer.dictateFixes(from: "{broken").isEmpty)
    }

    @Test("Dictate terms are read from plain and fenced JSON")
    func dictateTerms() {
        let plain = #"{"fixes": [["叉扣", "Xcode"]], "terms": ["Xcode"], "text": "x"}"#
        let fenced = "```json\n\(plain)\n```"

        #expect(CloudPromptComposer.dictateTerms(from: plain) == ["Xcode"])
        #expect(CloudPromptComposer.dictateTerms(from: fenced) == ["Xcode"])
    }

    @Test("Dictate terms are empty when missing, malformed or unparsable")
    func dictateTermsMissing() {
        #expect(CloudPromptComposer.dictateTerms(from: #"{"fixes": [], "text": "x"}"#).isEmpty)
        #expect(CloudPromptComposer.dictateTerms(from: #"{"terms": "Xcode", "text": "x"}"#).isEmpty)
        #expect(CloudPromptComposer.dictateTerms(from: #"{"terms": [1, 2], "text": "x"}"#).isEmpty)
        #expect(CloudPromptComposer.dictateTerms(from: "plain text").isEmpty)
        #expect(CloudPromptComposer.dictateTerms(from: "{broken").isEmpty)
    }

    @Test("Trace terms apply to dictate responses only")
    func traceTerms() {
        let response = #"{"fixes": [["a", "Bcd"]], "terms": ["Bcd"], "text": "x"}"#

        #expect(trace(prompt: .dictate, response: response).terms == ["Bcd"])
        #expect(trace(prompt: .translate, response: response).terms.isEmpty)
    }

    @Test("Trace fixes apply to dictate responses only")
    func traceFixes() {
        let response = #"{"fixes": [["a", "b"]], "text": "x"}"#
        let dictate = trace(prompt: .dictate, response: response)
        let translate = trace(prompt: .translate, response: response)

        #expect(dictate.fixes == [AIWordFix(recognized: "a", corrected: "b")])
        #expect(translate.fixes.isEmpty)
        #expect(translate.sentContext == nil)
    }

    // MARK: Cost breakdown

    @Test("Breakdown total equals the cost at peak and off-peak")
    func breakdownMatchesCost() throws {
        let price = try #require(AIModelPrice.builtIn.first { $0.modelIdentifier == "deepseek-flash" })
        let tokens = AITokenUsage(inputTokens: 1_200, outputTokens: 340, cachedInputTokens: 700)
        let peak = Self.shanghaiDate(day: 14, hour: 10)
        let offPeak = Self.shanghaiDate(day: 17, hour: 10)

        let peakCost = price.breakdown(of: tokens, at: peak)
        let offPeakCost = price.breakdown(of: tokens, at: offPeak)

        #expect(peakCost.total == price.cost(of: tokens, at: peak))
        #expect(offPeakCost.total == price.cost(of: tokens, at: offPeak))
        #expect(peakCost.appliedOffPeakFactor == nil)
        #expect(offPeakCost.appliedOffPeakFactor == 0.5)
        #expect(peakCost.lines.map(\.kind) == [.cachedInput, .input, .output])
        #expect(peakCost.lines.map(\.tokens) == [700, 500, 340])
        #expect(peakCost.lines.map(\.pricePerMillion) == [0.04, 2, 8])
        let listTotal = peakCost.lines.reduce(0) { $0 + $1.amount }
        #expect(abs(listTotal - peakCost.total) < 1e-12)
        #expect(abs(listTotal * 0.5 - offPeakCost.total) < 1e-12)
    }

    // MARK: Pipeline

    @Test("Successful remote calls carry the exact exchange and the history ID")
    func pipelineFillsCall() async throws {
        let usage = InMemoryAIUsageRepository()
        let tokens = AITokenUsage(inputTokens: 100, outputTokens: 20, cachedInputTokens: 10)
        let output = #"{"fixes": [["叉扣", "Xcode"]], "text": "用 Xcode。"}"#
        let service = PipelineIntelligenceService(
            remoteRuntime: StubRuntime(output: output, tokens: tokens),
            usageRecorder: usage
        )
        let historyID = UUID()
        let configuration = RemoteProviderConfiguration(apiKey: "test-key")
        let request = IntelligenceRequest(
            task: .polish,
            remoteProvider: configuration,
            transcript: "用叉扣",
            context: CapturedContext(applicationName: "Tests"),
            historyEntryID: historyID
        )
        let expectedUser = try CloudPromptComposer().prompts(for: request).user
        let before = Date()

        let result = try await service.process(request)

        #expect(result.text == "用 Xcode。")
        let call = try #require(result.call)
        #expect(call.prompt == .dictate)
        #expect(call.promptVersion == CloudPromptComposer.dictatePromptVersion)
        #expect(call.modelIdentifier == RemoteProviderConfiguration.modelIdentifier)
        #expect(call.userPrompt == expectedUser)
        #expect(call.response == output)
        #expect(call.tokens == tokens)
        #expect(call.latencyMilliseconds >= 0)
        #expect(call.startedAt >= before)
        #expect(call.fixes == [AIWordFix(recognized: "叉扣", corrected: "Xcode")])

        let records = try await usage.records(since: .distantPast)
        #expect(records.map(\.historyEntryID) == [historyID])
    }

    @Test("Translate calls record the translate prompt kind and version")
    func pipelineTranslateCall() async throws {
        let service = PipelineIntelligenceService(
            remoteRuntime: StubRuntime(output: "Hello"),
            usageRecorder: InMemoryAIUsageRepository()
        )
        let request = IntelligenceRequest(
            task: .translate,
            remoteProvider: RemoteProviderConfiguration(apiKey: "test-key"),
            transcript: "你好",
            targetLanguage: "en_US",
            context: CapturedContext(applicationName: "Tests")
        )

        let call = try #require(try await service.process(request).call)

        #expect(call.prompt == .translate)
        #expect(call.promptVersion == "translate_v1")
        #expect(call.response == "Hello")
        #expect(call.sentContext?.targetLanguage == "en_US")
    }

    @Test("Raw results carry no call")
    func rawResultHasNoCall() async throws {
        let service = PipelineIntelligenceService(remoteRuntime: StubRuntime(output: "unused"))
        let request = IntelligenceRequest(
            task: .polish,
            mode: .raw,
            transcript: "raw",
            context: CapturedContext(applicationName: "Tests")
        )

        #expect(try await service.process(request).call == nil)
    }

    @Test("Dictionary learning and connection test usage records")
    func learningAndConnectionRecords() async throws {
        let usage = InMemoryAIUsageRepository()
        let service = PipelineIntelligenceService(
            remoteRuntime: StubRuntime(output: #"{"candidates":[]}"#),
            usageRecorder: usage
        )
        let historyID = UUID()
        let configuration = RemoteProviderConfiguration(apiKey: "test-key")

        _ = try await service.classifyCorrection(DictionaryLearningRequest(
            mode: .remote,
            remoteProvider: configuration,
            originalSpan: "叉扣",
            correctedSpan: "Xcode",
            applicationName: "Tests",
            historyEntryID: historyID
        ))
        _ = try await service.testRemoteConnection(configuration: configuration)

        let records = try await usage.records(since: .distantPast)
        let byFeature = Dictionary(uniqueKeysWithValues: records.map { ($0.feature, $0.historyEntryID) })
        #expect(byFeature[.dictionaryLearning] == historyID)
        #expect(byFeature[.connectionTest] == .some(nil))
    }

    // MARK: Codable compatibility

    @Test("History entries without an AI call still decode")
    func historyDecodesWithoutAICall() throws {
        let entry = HistoryEntry(mode: .dictation, rawText: "a", finalText: "b", duration: 1, applicationName: "Tests")
        let data = try JSONEncoder().encode(entry)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "aiCall")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: stripped)

        #expect(decoded.aiCall == nil)
        #expect(decoded.id == entry.id)
    }

    @Test("History entries round trip an AI call")
    func historyRoundTripsAICall() throws {
        let call = trace(prompt: .dictate, response: #"{"fixes": [], "text": "x"}"#)
        let entry = HistoryEntry(
            mode: .dictation,
            rawText: "a",
            finalText: "b",
            duration: 1,
            applicationName: "Tests",
            aiCall: call
        )

        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(entry))

        #expect(decoded.aiCall == call)
    }

    @Test("Usage records without a history ID still decode")
    func usageRecordDecodesWithoutHistoryID() throws {
        let record = AIUsageRecord(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            feature: .dictate,
            modelIdentifier: "deepseek-flash",
            tokens: nil,
            latencyMilliseconds: 10,
            succeeded: true
        )
        let data = try JSONEncoder().encode(record)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "historyEntryID")

        let decoded = try JSONDecoder().decode(
            AIUsageRecord.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.historyEntryID == nil)
        #expect(decoded.id == record.id)
    }

    // MARK: Helpers

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func trace(prompt: AIPromptKind, response: String) -> AICallTrace {
        AICallTrace(
            prompt: prompt,
            promptVersion: "v",
            modelIdentifier: "deepseek-flash",
            userPrompt: "{}",
            response: response,
            tokens: AITokenUsage(inputTokens: 10, outputTokens: 5),
            latencyMilliseconds: 120,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func shanghaiDate(day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        // October 2026: the 14th is a Wednesday, the 17th a Saturday.
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? .distantPast
    }
}

private struct StubRuntime: RemoteLanguageModelRuntime {
    let output: String
    var tokens: AITokenUsage?

    func generate(
        configuration: RemoteProviderConfiguration,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> RemoteGeneration {
        RemoteGeneration(text: output, modelIdentifier: RemoteProviderConfiguration.modelIdentifier, tokens: tokens)
    }

    func testConnection(
        configuration: RemoteProviderConfiguration
    ) async throws -> RemoteConnectionTestOutcome {
        .success()
    }

    func balance(
        configuration: RemoteProviderConfiguration
    ) async throws -> DeepSeekBalance {
        DeepSeekBalance(isAvailable: true, total: 1, currencyCode: "CNY")
    }
}
