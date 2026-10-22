import Foundation
import Testing
import LerroCore
@testable import LerroIntelligence

@Suite("OpenAI-compatible HTTP client", .serialized)
struct OpenAICompatibleHTTPClientTests {
    @Test("Completion uses the fixed DeepSeek endpoint, bearer auth, and disables thinking")
    func completionRequestContract() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.install { request in
            recorder.record(request)
            return .json(
                statusCode: 200,
                object: [
                    "model": "deepseek-flash",
                    "choices": [["message": ["content": "Polished text"]]]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient(apiKey: "test-only-key")
        let result = try await client.complete(
            messages: [
                .init(role: .system, content: "System instructions"),
                .init(role: .user, content: "Synthetic input")
            ],
            maxTokens: 321
        )

        #expect(result.text == "Polished text")
        #expect(result.modelIdentifier == "deepseek-flash")
        let request = try #require(recorder.request)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.httpShouldHandleCookies == false)

        let body = try JSONBody(request)
        #expect(body["model"] as? String == "deepseek-flash")
        #expect(body["temperature"] as? Double == 0)
        #expect(body["max_tokens"] as? Int == 321)
        #expect(body["stream"] == nil)
        let thinking = try #require(body["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "disabled")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[1]["content"] as? String == "Synthetic input")
    }

    @Test("Balance request is an authenticated GET to the user balance path")
    func balanceRequestContract() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.install { request in
            recorder.record(request)
            return .json(
                statusCode: 200,
                object: [
                    "is_available": true,
                    "balance_infos": [[
                        "currency": "CNY",
                        "total_balance": "8.42",
                        "granted_balance": "0.00",
                        "topped_up_balance": "8.42"
                    ]]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let balance = try await makeClient(apiKey: "test-only-key").balance()

        #expect(balance == DeepSeekBalance(
            isAvailable: true,
            total: Decimal(string: "8.42")!,
            currencyCode: "CNY"
        ))
        let request = try #require(recorder.request)
        #expect(request.url?.absoluteString == "https://api.deepseek.com/user/balance")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-key")
        #expect(request.httpBody == nil)
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test("Balance responses that cannot be parsed are rejected")
    func balanceInvalidResponse() async throws {
        MockURLProtocol.install { _ in
            .json(statusCode: 200, object: ["unexpected": true])
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient()
        await #expect(throws: OpenAICompatibleRuntimeError.invalidResponse) {
            try await client.balance()
        }
    }

    @Test("Balance and completion failures map 402 to insufficient balance and 401 to an invalid key")
    func accountErrorMapping() async throws {
        for (statusCode, isBalanceError) in [(402, true), (401, false), (403, false)] {
            MockURLProtocol.install { _ in
                .init(
                    statusCode: statusCode,
                    headers: ["Content-Type": "application/json"],
                    data: Data(#"{"error":"test-only-key"}"#.utf8)
                )
            }
            defer { MockURLProtocol.reset() }

            let client = try makeClient(apiKey: "test-only-key")
            func check(_ error: any Error) {
                guard let error = error as? LerroError else {
                    Issue.record("Expected LerroError for \(statusCode), got \(error)")
                    return
                }
                switch error {
                case .insufficientBalance:
                    #expect(isBalanceError)
                case .invalidAPIKey:
                    #expect(!isBalanceError)
                default:
                    Issue.record("Unexpected LerroError for \(statusCode)")
                }
                #expect(!(error.errorDescription ?? "").contains("test-only-key"))
            }
            do {
                _ = try await client.complete(
                    messages: [.init(role: .user, content: "Synthetic")],
                    maxTokens: 32
                )
                Issue.record("Expected a completion error for \(statusCode)")
            } catch {
                check(error)
            }
            do {
                _ = try await client.balance()
                Issue.record("Expected a balance error for \(statusCode)")
            } catch {
                check(error)
            }
        }
    }

    @Test("Connection test sends one fixed synthetic message")
    func connectionTestIsContextFree() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.install { request in
            recorder.record(request)
            return .json(
                statusCode: 200,
                object: [
                    "model": "deepseek-v4-flash",
                    "choices": [["message": ["content": "OK."]]]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient()
        let probe = try await client.testConnection()

        #expect(probe.latency >= .zero)
        #expect(probe.modelIdentifier == "deepseek-v4-flash")
        let request = try #require(recorder.request)
        let body = try JSONBody(request)
        #expect(body["max_tokens"] as? Int == 8)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(
            messages[0]["content"] as? String
                == OpenAICompatibleHTTPClient.connectionTestPrompt
        )
        let serialized = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(!serialized.contains("transcript"))
        #expect(!serialized.contains("selected_text"))
        #expect(!serialized.contains("window_title"))
    }

    @Test("OpenAI-style usage reports cached prompt tokens")
    func openAIUsage() async throws {
        MockURLProtocol.install { _ in
            .json(
                statusCode: 200,
                object: [
                    "choices": [["message": ["content": "OK"]]],
                    "usage": [
                        "prompt_tokens": 120,
                        "completion_tokens": 30,
                        "prompt_tokens_details": ["cached_tokens": 100]
                    ]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient()
        let result = try await client.complete(
            messages: [.init(role: .user, content: "Synthetic")],
            maxTokens: 32
        )
        #expect(result.tokens == AITokenUsage(
            inputTokens: 120,
            outputTokens: 30,
            cachedInputTokens: 100
        ))
    }

    @Test("DeepSeek-style usage reports prompt cache hits")
    func deepSeekUsage() async throws {
        MockURLProtocol.install { _ in
            .json(
                statusCode: 200,
                object: [
                    "choices": [["message": ["content": "OK"]]],
                    "usage": [
                        "prompt_tokens": 80,
                        "completion_tokens": 12,
                        "prompt_cache_hit_tokens": 64,
                        "prompt_cache_miss_tokens": 16
                    ]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient()
        let result = try await client.complete(
            messages: [.init(role: .user, content: "Synthetic")],
            maxTokens: 32
        )
        #expect(result.tokens == AITokenUsage(
            inputTokens: 80,
            outputTokens: 12,
            cachedInputTokens: 64
        ))
    }

    @Test("A response without usage has nil tokens")
    func missingUsage() async throws {
        MockURLProtocol.install { _ in
            .json(
                statusCode: 200,
                object: ["choices": [["message": ["content": "OK"]]]]
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient()
        let result = try await client.complete(
            messages: [.init(role: .user, content: "Synthetic")],
            maxTokens: 32
        )
        #expect(result.text == "OK")
        #expect(result.tokens == nil)
    }

    @Test("A malformed usage object does not fail the completion")
    func malformedUsage() async throws {
        MockURLProtocol.install { _ in
            .json(
                statusCode: 200,
                object: [
                    "choices": [["message": ["content": "OK"]]],
                    "usage": "x"
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient()
        let result = try await client.complete(
            messages: [.init(role: .user, content: "Synthetic")],
            maxTokens: 32
        )
        #expect(result.text == "OK")
        #expect(result.tokens == nil)
    }

    @Test("Remote runtime surfaces tokens for generation and connection tests")
    func runtimeSurfacesTokens() async throws {
        MockURLProtocol.install { _ in
            .json(
                statusCode: 200,
                object: [
                    "model": "deepseek-v4-flash",
                    "choices": [["message": ["content": "OK"]]],
                    "usage": [
                        "prompt_tokens": 50,
                        "completion_tokens": 5,
                        "prompt_cache_hit_tokens": 40
                    ]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let runtime = OpenAICompatibleRemoteLanguageModelRuntime(
            protocolClasses: [MockURLProtocol.self]
        )
        let configuration = RemoteProviderConfiguration(apiKey: "test-only-key")
        let expected = AITokenUsage(inputTokens: 50, outputTokens: 5, cachedInputTokens: 40)

        let generation = try await runtime.generate(
            configuration: configuration,
            systemPrompt: "System",
            userPrompt: "Synthetic input",
            maxTokens: 32
        )
        #expect(generation.tokens == expected)

        let outcome = try await runtime.testConnection(configuration: configuration)
        #expect(outcome.succeeded)
        #expect(outcome.tokens == expected)
    }

    @Test("Remote runtime conforms to the Core provider contract")
    func remoteRuntimeContract() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.install { request in
            recorder.record(request)
            return .json(
                statusCode: 200,
                object: [
                    "model": "deepseek-v4-flash",
                    "choices": [["message": ["content": "云端结果"]]]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let runtime: any RemoteLanguageModelRuntime =
            OpenAICompatibleRemoteLanguageModelRuntime(
                protocolClasses: [MockURLProtocol.self]
            )
        let configuration = RemoteProviderConfiguration(apiKey: "test-only-key")
        let output = try await runtime.generate(
            configuration: configuration,
            systemPrompt: "System instructions",
            userPrompt: "Synthetic input",
            maxTokens: 96
        )

        #expect(output.text == "云端结果")
        #expect(output.modelIdentifier == "deepseek-v4-flash")
        #expect(output.tokens == nil)
        let request = try #require(recorder.request)
        let body = try JSONBody(request)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["content"] as? String == "System instructions")
        #expect(messages[1]["content"] as? String == "Synthetic input")
    }

    @Test("Connection tests do not cancel an in-flight generation")
    func concurrentConfigurationsStayIndependent() async throws {
        MockURLProtocol.install { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer generation-test-key" {
                return .json(
                    statusCode: 200,
                    object: [
                        "model": "generation-model",
                        "choices": [["message": ["content": "Primary result"]]]
                    ],
                    delay: 0.15
                )
            }
            return .json(
                statusCode: 200,
                object: [
                    "model": "probe-model",
                    "choices": [["message": ["content": "OK"]]]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let runtime = OpenAICompatibleRemoteLanguageModelRuntime(
            protocolClasses: [MockURLProtocol.self]
        )
        let generationConfiguration = RemoteProviderConfiguration(apiKey: "generation-test-key")
        let probeConfiguration = RemoteProviderConfiguration(apiKey: "probe-test-key")

        let generation = Task {
            try await runtime.generate(
                configuration: generationConfiguration,
                systemPrompt: "System",
                userPrompt: "Synthetic input",
                maxTokens: 32
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        let probe = try await runtime.testConnection(configuration: probeConfiguration)

        #expect(probe.succeeded)
        #expect(try await generation.value.text == "Primary result")
    }

    @Test("Remote runtime returns the account balance")
    func runtimeBalance() async throws {
        MockURLProtocol.install { _ in
            .json(
                statusCode: 200,
                object: [
                    "is_available": false,
                    "balance_infos": [["currency": "CNY", "total_balance": "0.00"]]
                ]
            )
        }
        defer { MockURLProtocol.reset() }

        let runtime: any RemoteLanguageModelRuntime =
            OpenAICompatibleRemoteLanguageModelRuntime(protocolClasses: [MockURLProtocol.self])
        let balance = try await runtime.balance(
            configuration: RemoteProviderConfiguration(apiKey: "test-only-key")
        )

        #expect(balance.isEmpty)
        #expect(balance.currencyCode == "CNY")
    }

    @Test(
        "HTTP status codes map to stable safe errors",
        arguments: [
            (302, OpenAICompatibleRuntimeError.redirectBlocked),
            (404, OpenAICompatibleRuntimeError.modelUnavailable),
            (429, OpenAICompatibleRuntimeError.rateLimited),
            (503, OpenAICompatibleRuntimeError.serviceUnavailable)
        ]
    )
    func HTTPErrorMapping(
        statusCode: Int,
        expected: OpenAICompatibleRuntimeError
    ) async throws {
        MockURLProtocol.install { _ in
            .init(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                data: Data(
                    "{\"error\":\"test-only-key Synthetic input private transcript\"}".utf8
                )
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient(apiKey: "test-only-key")
        do {
            _ = try await client.complete(
                messages: [.init(role: .user, content: "private transcript")],
                maxTokens: 32
            )
            Issue.record("Expected an HTTP error")
        } catch let error as OpenAICompatibleRuntimeError {
            #expect(error == expected)
            let description = error.localizedDescription
            #expect(!description.contains("test-only-key"))
            #expect(!description.contains("private transcript"))
            #expect(!description.contains("Synthetic input"))
        }
    }

    @Test("Malformed and empty responses are rejected")
    func malformedAndEmptyResponses() async throws {
        let counter = CallCounter()
        MockURLProtocol.install { _ in
            if counter.next() == 1 {
                return .init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    data: Data("not-json".utf8)
                )
            }
            return .json(
                statusCode: 200,
                object: ["choices": [["message": ["content": "   "]]]]
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient()
        await #expect(throws: OpenAICompatibleRuntimeError.invalidResponse) {
            try await client.complete(
                messages: [.init(role: .user, content: "Synthetic")],
                maxTokens: 32
            )
        }
        await #expect(throws: OpenAICompatibleRuntimeError.emptyResponse) {
            try await client.complete(
                messages: [.init(role: .user, content: "Synthetic")],
                maxTokens: 32
            )
        }
    }

    @Test("Response body limit is enforced")
    func responseSizeLimit() async throws {
        MockURLProtocol.install { _ in
            .init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: Data(repeating: 0x41, count: 65)
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient(maximumResponseBytes: 64)
        await #expect(throws: OpenAICompatibleRuntimeError.responseTooLarge) {
            try await client.complete(
                messages: [.init(role: .user, content: "Synthetic")],
                maxTokens: 32
            )
        }
    }

    @Test("Cancelling a request produces the stable cancellation error")
    func requestCancellation() async throws {
        MockURLProtocol.install { _ in
            .json(
                statusCode: 200,
                object: ["choices": [["message": ["content": "late"]]]],
                delay: 5
            )
        }
        defer { MockURLProtocol.reset() }

        let client = try makeClient()
        let task = Task {
            try await client.complete(
                messages: [.init(role: .user, content: "Synthetic")],
                maxTokens: 32
            )
        }
        await Task.yield()
        task.cancel()

        await #expect(throws: OpenAICompatibleRuntimeError.cancelled) {
            try await task.value
        }
    }

    @Test("Redirect policy allows only the same scheme, host, and port")
    func redirectOriginPolicy() {
        let source = URL(string: "https://api.example.test/v1/chat/completions")!
        #expect(OpenAICompatibleHTTPClient.sameOrigin(
            source,
            URL(string: "https://api.example.test/v2/chat/completions")!
        ))
        #expect(!OpenAICompatibleHTTPClient.sameOrigin(
            source,
            URL(string: "https://other.example.test/v1/chat/completions")!
        ))
        #expect(!OpenAICompatibleHTTPClient.sameOrigin(
            source,
            URL(string: "http://api.example.test/v1/chat/completions")!
        ))
        #expect(!OpenAICompatibleHTTPClient.sameOrigin(
            source,
            URL(string: "https://api.example.test:8443/v1/chat/completions")!
        ))
    }

    @Test("Endpoint defaults tolerate production generation latency")
    func productionTimeoutDefaults() {
        let endpoint = OpenAICompatibleEndpoint()
        #expect(endpoint.baseURL.absoluteString == "https://api.deepseek.com")
        #expect(endpoint.modelIdentifier == "deepseek-flash")
        #expect(endpoint.requestTimeout == 60)
        #expect(endpoint.resourceTimeout == 120)
    }

    @Test("Ephemeral session disables persistent cookies and caches")
    func ephemeralConfiguration() {
        let configuration = OpenAICompatibleHTTPClient.ephemeralSessionConfiguration(
            requestTimeout: 7,
            resourceTimeout: 19
        )
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.timeoutIntervalForRequest == 7)
        #expect(configuration.timeoutIntervalForResource == 19)
    }

    @Test("Transport errors map to stable timeout and network messages")
    func transportErrorSanitization() {
        #expect(
            OpenAICompatibleHTTPClient.sanitized(URLError(.timedOut))
                == .timedOut
        )
        #expect(
            OpenAICompatibleHTTPClient.sanitized(URLError(.cannotConnectToHost))
                == .networkUnavailable
        )
        #expect(
            OpenAICompatibleHTTPClient.sanitized(URLError(.cancelled))
                == .cancelled
        )
    }

    @Test(
        "Live DeepSeek preset connects and generates only when explicitly enabled",
        .enabled(if: Self.liveSmokeEnabled)
    )
    func liveDeepSeekSmoke() async throws {
        let apiKey = try #require(ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"])
        let configuration = RemoteProviderConfiguration(
            apiKey: apiKey
        )
        let runtime = OpenAICompatibleRemoteLanguageModelRuntime()

        let outcome = try await runtime.testConnection(configuration: configuration)
        let output = try await runtime.generate(
            configuration: configuration,
            systemPrompt: "Return polished text only. Preserve all facts.",
            userPrompt: "Um the synthetic release is Tuesday. Actually make that Wednesday.",
            maxTokens: 80
        ).text

        print("LERRO_LIVE_REMOTE_LATENCY_MS=\(outcome.latencyMilliseconds ?? -1)")
        print("LERRO_LIVE_REMOTE_GENERATION=passed")
        #expect(outcome.succeeded)
        #expect(outcome.modelIdentifier == RemoteProviderConfiguration.modelIdentifier)
        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(output.localizedCaseInsensitiveContains("Wednesday"))
        #expect(!output.localizedCaseInsensitiveContains("Tuesday"))
    }

    @Test(
        "Live DeepSeek product prompt repairs noisy Apple Speech text",
        .enabled(if: Self.liveSmokeEnabled)
    )
    func liveDeepSeekProductPromptSmoke() async throws {
        let apiKey = try #require(ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"])
        let configuration = RemoteProviderConfiguration(
            apiKey: apiKey
        )
        let request = IntelligenceRequest(
            task: .polish,
            mode: .remote,
            remoteProvider: configuration,
            transcript: "嗯这个版本周二发布，呃等一下改成周三，然后有三个检查项第一确认签名第二验证公证第三跑隔离环境，就这样",
            context: CapturedContext(
                applicationName: "Codex",
                bundleIdentifier: "com.openai.codex",
                windowTitle: "Synthetic prompt fixture",
                cursorBefore: "团队正在整理一份合成发布计划。"
            ),
            toneInstruction: "清晰、简洁、适合扫读"
        )
        let prompts = try CloudPromptComposer().prompts(for: request)
        let runtime = OpenAICompatibleRemoteLanguageModelRuntime()

        let output = try await runtime.generate(
            configuration: configuration,
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            maxTokens: 320
        ).text

        print("LERRO_LIVE_REMOTE_PRODUCT_PROMPT=passed")
        #expect(output.contains("周三"))
        #expect(output.contains("签名"))
        #expect(output.contains("公证"))
        #expect(output.contains("隔离"))
        #expect(!output.contains("周二"))
    }

    private func makeClient(
        apiKey: String = "test-only-key",
        maximumResponseBytes: Int = 2 * 1_024 * 1_024
    ) throws -> OpenAICompatibleHTTPClient {
        try OpenAICompatibleHTTPClient(
            endpoint: OpenAICompatibleEndpoint(
                maximumResponseBytes: maximumResponseBytes
            ),
            apiKey: apiKey,
            protocolClasses: [MockURLProtocol.self]
        )
    }

    private static var liveSmokeEnabled: Bool {
        ProcessInfo.processInfo.environment["LERRO_LIVE_REMOTE_SMOKE"] == "1"
            && !(ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? "").isEmpty
    }

}

private struct JSONBody {
    private let object: [String: Any]

    init(_ request: URLRequest) throws {
        let data = try #require(request.httpBody)
        object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    subscript(key: String) -> Any? {
        object[key]
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.withLock { storedRequest }
    }

    func record(_ request: URLRequest) {
        var snapshot = request
        if snapshot.httpBody == nil, let stream = snapshot.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            snapshot.httpBodyStream = nil
            snapshot.httpBody = body
        }
        lock.withLock { storedRequest = snapshot }
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: @unchecked Sendable {
        let statusCode: Int
        let headers: [String: String]
        let data: Data
        let delay: TimeInterval

        init(
            statusCode: Int,
            headers: [String: String],
            data: Data,
            delay: TimeInterval = 0
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.data = data
            self.delay = delay
        }

        static func json(
            statusCode: Int,
            object: Any,
            delay: TimeInterval = 0
        ) -> Stub {
            Stub(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                data: try! JSONSerialization.data(withJSONObject: object),
                delay: delay
            )
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Stub

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    private var workItem: DispatchWorkItem?

    static func install(_ handler: @escaping Handler) {
        stateLock.withLock { Self.handler = handler }
    }

    static func reset() {
        stateLock.withLock { handler = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.stateLock.withLock({ Self.handler }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let stub = handler(request)
        let item = DispatchWorkItem { [weak self] in
            guard let self, let url = self.request.url else { return }
            let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            self.client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            self.client?.urlProtocol(self, didLoad: stub.data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        workItem = item
        if stub.delay > 0 {
            DispatchQueue.global().asyncAfter(
                deadline: .now() + stub.delay,
                execute: item
            )
        } else {
            DispatchQueue.global().async(execute: item)
        }
    }

    override func stopLoading() {
        workItem?.cancel()
        workItem = nil
    }
}
