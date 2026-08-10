import Foundation
import LerroCore

struct OpenAICompatibleEndpoint: Sendable, Equatable {
    let providerIdentifier: String
    let baseURL: URL
    let modelIdentifier: String
    let requestTimeout: TimeInterval
    let resourceTimeout: TimeInterval
    let maximumResponseBytes: Int

    init(
        providerIdentifier: String,
        baseURL: URL,
        modelIdentifier: String,
        requestTimeout: TimeInterval = 60,
        resourceTimeout: TimeInterval = 120,
        maximumResponseBytes: Int = 2 * 1_024 * 1_024
    ) {
        self.providerIdentifier = providerIdentifier
        self.baseURL = baseURL
        self.modelIdentifier = modelIdentifier
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.maximumResponseBytes = maximumResponseBytes
    }

    var usesDeepSeekExtensions: Bool {
        providerIdentifier.caseInsensitiveCompare("deepseek") == .orderedSame
    }
}

struct OpenAICompatibleMessage: Sendable, Equatable {
    enum Role: String, Sendable, Equatable, Encodable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

struct OpenAICompatibleCompletion: Sendable, Equatable {
    let text: String
    let modelIdentifier: String
}

struct OpenAICompatibleConnectionProbe: Sendable, Equatable {
    let latency: Duration
    let modelIdentifier: String
}

enum OpenAICompatibleRuntimeError: LocalizedError, Sendable, Equatable {
    case invalidEndpoint
    case insecureEndpoint
    case missingCredential
    case invalidRequest
    case authenticationFailed
    case paymentRequired
    case modelUnavailable
    case rateLimited
    case serviceUnavailable
    case redirectBlocked
    case timedOut
    case responseTooLarge
    case invalidResponse
    case emptyResponse
    case networkUnavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "模型服务地址无效"
        case .insecureEndpoint:
            "模型服务需要使用 HTTPS；本机 loopback 服务可以使用 HTTP"
        case .missingCredential:
            "API Key 为空"
        case .invalidRequest:
            "模型服务拒绝了请求参数"
        case .authenticationFailed:
            "API Key 无效或没有访问权限"
        case .paymentRequired:
            "模型账户余额或计费状态不可用"
        case .modelUnavailable:
            "模型名称或服务地址不可用"
        case .rateLimited:
            "模型服务请求过于频繁，请稍后重试"
        case .serviceUnavailable:
            "模型服务暂时不可用"
        case .redirectBlocked:
            "模型服务返回了不安全的重定向"
        case .timedOut:
            "模型服务连接超时"
        case .responseTooLarge:
            "模型服务返回的数据超出安全上限"
        case .invalidResponse:
            "模型服务返回了无法识别的数据"
        case .emptyResponse:
            "模型服务没有返回有效文本"
        case .networkUnavailable:
            "当前无法连接模型服务"
        case .cancelled:
            "模型请求已取消"
        }
    }
}

actor OpenAICompatibleHTTPClient {
    static let connectionTestPrompt = "Reply exactly OK"

    private let endpoint: OpenAICompatibleEndpoint
    private let apiKey: String
    private let session: URLSession

    init(
        endpoint: OpenAICompatibleEndpoint,
        apiKey: String,
        protocolClasses: [AnyClass]? = nil
    ) throws {
        self.endpoint = endpoint
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !self.apiKey.isEmpty else {
            throw OpenAICompatibleRuntimeError.missingCredential
        }
        guard !endpoint.modelIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw OpenAICompatibleRuntimeError.invalidRequest
        }
        _ = try Self.completionsURL(from: endpoint.baseURL)

        let configuration = Self.ephemeralSessionConfiguration(
            requestTimeout: endpoint.requestTimeout,
            resourceTimeout: endpoint.resourceTimeout,
            protocolClasses: protocolClasses
        )
        session = URLSession(
            configuration: configuration,
            delegate: SameOriginRedirectDelegate(),
            delegateQueue: nil
        )
    }

    func complete(
        messages: [OpenAICompatibleMessage],
        maxTokens: Int
    ) async throws -> OpenAICompatibleCompletion {
        let request = try makeRequest(
            messages: messages,
            maxTokens: maxTokens,
            stream: false
        )
        let (data, response) = try await readResponse(for: request)
        try Self.validate(response: response)
        return try Self.decodeCompletion(
            from: data,
            fallbackModelIdentifier: endpoint.modelIdentifier
        )
    }

    func stream(
        messages: [OpenAICompatibleMessage],
        maxTokens: Int
    ) throws -> AsyncThrowingStream<String, any Error> {
        let request = try makeRequest(
            messages: messages,
            maxTokens: maxTokens,
            stream: true
        )
        let client = self

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await client.consumeStream(
                        request: request,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: Self.sanitized(error))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func testConnection() async throws -> OpenAICompatibleConnectionProbe {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let result = try await complete(
            messages: [
                OpenAICompatibleMessage(
                    role: .user,
                    content: Self.connectionTestPrompt
                )
            ],
            maxTokens: 8
        )
        return OpenAICompatibleConnectionProbe(
            latency: startedAt.duration(to: clock.now),
            modelIdentifier: result.modelIdentifier
        )
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    private func makeRequest(
        messages: [OpenAICompatibleMessage],
        maxTokens: Int,
        stream: Bool
    ) throws -> URLRequest {
        guard !messages.isEmpty, maxTokens > 0 else {
            throw OpenAICompatibleRuntimeError.invalidRequest
        }

        var request = URLRequest(
            url: try Self.completionsURL(from: endpoint.baseURL),
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: endpoint.requestTimeout
        )
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            stream ? "text/event-stream, application/json" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let body = ChatCompletionRequestBody(
            model: endpoint.modelIdentifier,
            messages: messages.map {
                ChatCompletionRequestBody.Message(
                    role: $0.role.rawValue,
                    content: $0.content
                )
            },
            temperature: 0,
            maxTokens: maxTokens,
            stream: stream,
            thinking: endpoint.usesDeepSeekExtensions
                ? ChatCompletionRequestBody.Thinking(type: "disabled")
                : nil
        )
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw OpenAICompatibleRuntimeError.invalidRequest
        }
        return request
    }

    private func readResponse(
        for request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw OpenAICompatibleRuntimeError.invalidResponse
            }
            try Self.validate(response: response)
            try Self.validateResponseSize(
                response,
                maximumBytes: endpoint.maximumResponseBytes
            )

            var data = Data()
            data.reserveCapacity(min(endpoint.maximumResponseBytes, 64 * 1_024))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < endpoint.maximumResponseBytes else {
                    throw OpenAICompatibleRuntimeError.responseTooLarge
                }
                data.append(byte)
            }
            return (data, response)
        } catch {
            throw Self.sanitized(error)
        }
    }

    private func consumeStream(
        request: URLRequest,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw OpenAICompatibleRuntimeError.invalidResponse
            }
            try Self.validate(response: response)
            try Self.validateResponseSize(
                response,
                maximumBytes: endpoint.maximumResponseBytes
            )

            let contentType = response.value(forHTTPHeaderField: "Content-Type")?
                .lowercased() ?? ""
            if contentType.contains("text/event-stream") {
                var decoder = SSEEventDecoder()
                var responseSize = 0
                var didYieldText = false

                for try await byte in bytes {
                    try Task.checkCancellation()
                    responseSize += 1
                    guard responseSize <= endpoint.maximumResponseBytes else {
                        throw OpenAICompatibleRuntimeError.responseTooLarge
                    }

                    for payload in try decoder.append(byte) {
                        if payload == "[DONE]" {
                            guard didYieldText else {
                                throw OpenAICompatibleRuntimeError.emptyResponse
                            }
                            continuation.finish()
                            return
                        }
                        if let text = try Self.decodeStreamDelta(from: payload), !text.isEmpty {
                            didYieldText = true
                            continuation.yield(text)
                        }
                    }
                }

                for payload in try decoder.finish() where payload != "[DONE]" {
                    if let text = try Self.decodeStreamDelta(from: payload), !text.isEmpty {
                        didYieldText = true
                        continuation.yield(text)
                    }
                }
                guard didYieldText else {
                    throw OpenAICompatibleRuntimeError.emptyResponse
                }
                continuation.finish()
                return
            }

            var data = Data()
            data.reserveCapacity(min(endpoint.maximumResponseBytes, 64 * 1_024))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < endpoint.maximumResponseBytes else {
                    throw OpenAICompatibleRuntimeError.responseTooLarge
                }
                data.append(byte)
            }
            let completion = try Self.decodeCompletion(
                from: data,
                fallbackModelIdentifier: endpoint.modelIdentifier
            )
            continuation.yield(completion.text)
            continuation.finish()
        } catch {
            throw Self.sanitized(error)
        }
    }

    nonisolated static func completionsURL(from baseURL: URL) throws -> URL {
        switch RemoteProviderEndpointPolicy.validate(baseURL.absoluteString) {
        case .valid:
            break
        case .insecure:
            throw OpenAICompatibleRuntimeError.insecureEndpoint
        case .invalid:
            throw OpenAICompatibleRuntimeError.invalidEndpoint
        }

        let normalizedPath = baseURL.path
            .split(separator: "/")
            .map(String.init)
        if normalizedPath.suffix(2).map({ $0.lowercased() }) == ["chat", "completions"] {
            return baseURL
        }

        return baseURL
            .appending(path: "chat", directoryHint: .isDirectory)
            .appending(path: "completions", directoryHint: .notDirectory)
    }

    nonisolated static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        guard let firstScheme = first.scheme?.lowercased(),
              let secondScheme = second.scheme?.lowercased(),
              let firstHost = first.host?.lowercased(),
              let secondHost = second.host?.lowercased() else {
            return false
        }
        return firstScheme == secondScheme
            && firstHost == secondHost
            && effectivePort(of: first) == effectivePort(of: second)
    }

    private nonisolated static func effectivePort(of url: URL) -> Int? {
        if let port = url.port {
            return port
        }
        return switch url.scheme?.lowercased() {
        case "https": 443
        case "http": 80
        default: nil
        }
    }

    nonisolated static func ephemeralSessionConfiguration(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        protocolClasses: [AnyClass]? = nil
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = max(1, requestTimeout)
        configuration.timeoutIntervalForResource = max(
            configuration.timeoutIntervalForRequest,
            resourceTimeout
        )
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return configuration
    }

    private nonisolated static func validate(response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 300...399:
            throw OpenAICompatibleRuntimeError.redirectBlocked
        case 400, 409, 422:
            throw OpenAICompatibleRuntimeError.invalidRequest
        case 401, 403:
            throw OpenAICompatibleRuntimeError.authenticationFailed
        case 402:
            throw OpenAICompatibleRuntimeError.paymentRequired
        case 404:
            throw OpenAICompatibleRuntimeError.modelUnavailable
        case 408, 504:
            throw OpenAICompatibleRuntimeError.timedOut
        case 429:
            throw OpenAICompatibleRuntimeError.rateLimited
        case 500...599:
            throw OpenAICompatibleRuntimeError.serviceUnavailable
        default:
            throw OpenAICompatibleRuntimeError.invalidResponse
        }
    }

    private nonisolated static func validateResponseSize(
        _ response: HTTPURLResponse,
        maximumBytes: Int
    ) throws {
        let expectedLength = response.expectedContentLength
        if expectedLength > 0, expectedLength > Int64(maximumBytes) {
            throw OpenAICompatibleRuntimeError.responseTooLarge
        }
    }

    private nonisolated static func decodeCompletion(
        from data: Data,
        fallbackModelIdentifier: String
    ) throws -> OpenAICompatibleCompletion {
        let response: ChatCompletionResponse
        do {
            response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw OpenAICompatibleRuntimeError.invalidResponse
        }
        guard let text = response.choices.first?.message.content.text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw OpenAICompatibleRuntimeError.emptyResponse
        }
        return OpenAICompatibleCompletion(
            text: text,
            modelIdentifier: response.model ?? fallbackModelIdentifier
        )
    }

    private nonisolated static func decodeStreamDelta(from payload: String) throws -> String? {
        guard let data = payload.data(using: .utf8) else {
            throw OpenAICompatibleRuntimeError.invalidResponse
        }
        let response: ChatCompletionStreamResponse
        do {
            response = try JSONDecoder().decode(ChatCompletionStreamResponse.self, from: data)
        } catch {
            throw OpenAICompatibleRuntimeError.invalidResponse
        }
        return response.choices.first?.delta.content?.text
    }

    nonisolated static func sanitized(_ error: any Error) -> OpenAICompatibleRuntimeError {
        if let error = error as? OpenAICompatibleRuntimeError {
            return error
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        if let error = error as? URLError {
            switch error.code {
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timedOut
            default:
                return .networkUnavailable
            }
        }
        return .networkUnavailable
    }
}

private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let originalURL = response.url ?? task.currentRequest?.url,
              let destinationURL = request.url,
              OpenAICompatibleHTTPClient.sameOrigin(originalURL, destinationURL) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private struct ChatCompletionRequestBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Thinking: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    let thinking: Thinking?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case thinking
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: FlexibleTextContent
        }

        let message: Message
    }

    let model: String?
    let choices: [Choice]
}

private struct ChatCompletionStreamResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: FlexibleTextContent?
        }

        let delta: Delta
    }

    let choices: [Choice]
}

private enum FlexibleTextContent: Decodable {
    struct Part: Decodable {
        let text: String?
    }

    case string(String)
    case parts([Part])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        self = .parts(try container.decode([Part].self))
    }

    var text: String? {
        switch self {
        case .string(let value):
            value
        case .parts(let parts):
            parts.compactMap(\.text).joined()
        }
    }
}

private struct SSEEventDecoder {
    private var lineBuffer = Data()
    private var dataLines: [String] = []

    mutating func append(_ byte: UInt8) throws -> [String] {
        lineBuffer.append(byte)
        guard byte == 0x0A else { return [] }
        return try consumeLine()
    }

    mutating func finish() throws -> [String] {
        var events: [String] = []
        if !lineBuffer.isEmpty {
            events.append(contentsOf: try consumeLine())
        }
        if !dataLines.isEmpty {
            events.append(dataLines.joined(separator: "\n"))
            dataLines.removeAll(keepingCapacity: true)
        }
        return events
    }

    private mutating func consumeLine() throws -> [String] {
        while lineBuffer.last == 0x0A || lineBuffer.last == 0x0D {
            lineBuffer.removeLast()
        }
        guard let line = String(data: lineBuffer, encoding: .utf8) else {
            throw OpenAICompatibleRuntimeError.invalidResponse
        }
        lineBuffer.removeAll(keepingCapacity: true)

        if line.isEmpty {
            guard !dataLines.isEmpty else { return [] }
            let event = dataLines.joined(separator: "\n")
            dataLines.removeAll(keepingCapacity: true)
            return [event]
        }
        guard !line.hasPrefix(":"), line.hasPrefix("data:") else {
            return []
        }
        var value = String(line.dropFirst(5))
        if value.hasPrefix(" ") {
            value.removeFirst()
        }
        dataLines.append(value)
        return []
    }
}
