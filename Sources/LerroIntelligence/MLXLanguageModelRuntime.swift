import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import OSLog
import Tokenizers
import LerroCore

public actor MLXLanguageModelRuntime: LocalLanguageModelRuntime {
    private static let logger = Logger(
        subsystem: "app.lerro.mac",
        category: "model-cache"
    )
    private var container: ModelContainer?
    private var loadedModelIdentifier: String?
    private var loadingModelIdentifier: String?
    private var loadGeneration: UUID?
    private var loadTask: Task<ModelContainer, Error>?
    private var idleUnloadTask: Task<Void, Never>?
    private var statusValue: LocalModelStatus
    private let modelCacheDirectory: URL

    public init(defaultModelIdentifier: String, modelCacheDirectory: URL) {
        self.modelCacheDirectory = modelCacheDirectory
        let isCached = FileManager.default.fileExists(
            atPath: Self.cacheMarkerURL(
                for: defaultModelIdentifier,
                in: modelCacheDirectory
            ).path
        )
        statusValue = LocalModelStatus(
            state: .ready,
            modelIdentifier: defaultModelIdentifier,
            progress: isCached ? 1 : 0,
            message: isCached
                ? "模型已缓存在本机，使用时加载"
                : "首次使用时下载约 3.03 GB 的本地模型"
        )
    }

    public func load(modelIdentifier: String) async throws {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        if loadedModelIdentifier == modelIdentifier, container != nil {
            return
        }

        if loadingModelIdentifier == modelIdentifier,
           let generation = loadGeneration,
           let loadTask {
            let loadedContainer = try await Self.valuePropagatingCancellation(from: loadTask)
            try Task.checkCancellation()
            try commitLoadedContainer(
                loadedContainer,
                modelIdentifier: modelIdentifier,
                generation: generation
            )
            return
        }

        loadTask?.cancel()
        container = nil
        loadedModelIdentifier = nil
        loadingModelIdentifier = modelIdentifier
        let generation = UUID()
        loadGeneration = generation
        statusValue = LocalModelStatus(
            state: .downloading,
            modelIdentifier: modelIdentifier,
            progress: 0,
            message: "正在检查并下载本地模型"
        )

        let configuration = ModelConfiguration(
            id: modelIdentifier,
            extraEOSTokens: ["<|im_end|>"]
        )
        let hubClient = Self.publicModelHubClient(cacheDirectory: modelCacheDirectory)
        let progressReceiver = self
        let task = Task<ModelContainer, Error> {
            try await loadModelContainer(
                from: #hubDownloader(hubClient),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration
            ) { progress in
                let fractionCompleted = progress.fractionCompleted
                Task {
                    await progressReceiver.recordDownloadProgress(
                        fractionCompleted,
                        modelIdentifier: modelIdentifier,
                        generation: generation
                    )
                }
            }
        }
        loadTask = task

        do {
            let loadedContainer = try await Self.valuePropagatingCancellation(from: task)
            try Task.checkCancellation()
            try commitLoadedContainer(
                loadedContainer,
                modelIdentifier: modelIdentifier,
                generation: generation
            )
        } catch is CancellationError {
            if loadGeneration == generation {
                loadingModelIdentifier = nil
                loadGeneration = nil
                loadTask = nil
                statusValue = LocalModelStatus(
                    state: .ready,
                    modelIdentifier: modelIdentifier,
                    progress: 0,
                    message: "本地模型准备已取消"
                )
            }
            throw CancellationError()
        } catch {
            guard loadGeneration == generation else { throw CancellationError() }
            loadingModelIdentifier = nil
            loadGeneration = nil
            loadTask = nil
            statusValue = LocalModelStatus(
                state: .failed,
                modelIdentifier: modelIdentifier,
                progress: 0,
                message: error.localizedDescription
            )
            throw LerroError.modelUnavailable(error.localizedDescription)
        }
    }

    public func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        let chunks = try await generateStream(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens
        )
        var output = ""
        for try await chunk in chunks {
            output += chunk
        }
        return output
    }

    public func generateStream(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, any Error> {
        guard let container else {
            throw LerroError.modelUnavailable("本地模型尚未加载")
        }
        idleUnloadTask?.cancel()
        idleUnloadTask = nil

        let input = UserInput(
            chat: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            additionalContext: ["enable_thinking": false]
        )
        let prepared = try await container.prepare(input: input)
        let generation = try await container.generate(
            input: prepared,
            parameters: GenerateParameters(maxTokens: maxTokens, temperature: 0.2)
        )
        let runtime = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await event in generation {
                        try Task.checkCancellation()
                        if case .chunk(let text) = event {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await runtime.generationDidFinish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func status() -> LocalModelStatus {
        statusValue
    }

    nonisolated static func monotonicProgress(
        previous: Double,
        incoming: Double
    ) -> Double {
        let boundedPrevious = previous.isFinite
            ? min(max(previous, 0), 1)
            : 0
        let boundedIncoming = incoming.isFinite
            ? min(max(incoming, 0), 1)
            : boundedPrevious
        return max(boundedPrevious, boundedIncoming)
    }

    nonisolated static func valuePropagatingCancellation<Value: Sendable>(
        from task: Task<Value, Error>
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func recordDownloadProgress(
        _ progress: Double,
        modelIdentifier: String,
        generation: UUID
    ) {
        guard loadingModelIdentifier == modelIdentifier,
              loadGeneration == generation else { return }
        let boundedProgress = Self.monotonicProgress(
            previous: statusValue.progress,
            incoming: progress
        )
        statusValue = LocalModelStatus(
            state: boundedProgress >= 1 ? .loading : .downloading,
            modelIdentifier: modelIdentifier,
            progress: boundedProgress,
            message: boundedProgress >= 1
                ? "模型已下载，正在加载"
                : "正在下载本地模型 · \(Int(boundedProgress * 100))%"
        )
    }

    private func commitLoadedContainer(
        _ loadedContainer: ModelContainer,
        modelIdentifier: String,
        generation: UUID
    ) throws {
        if loadedModelIdentifier == modelIdentifier, container != nil {
            return
        }
        guard loadingModelIdentifier == modelIdentifier,
              loadGeneration == generation else {
            throw CancellationError()
        }

        container = loadedContainer
        loadedModelIdentifier = modelIdentifier
        loadingModelIdentifier = nil
        loadGeneration = nil
        loadTask = nil
        do {
            try FileManager.default.createDirectory(
                at: modelCacheDirectory,
                withIntermediateDirectories: true
            )
            try Data().write(
                to: Self.cacheMarkerURL(for: modelIdentifier, in: modelCacheDirectory),
                options: .atomic
            )
        } catch {
            Self.logger.warning(
                "Model loaded; cache marker could not be saved: \(error.localizedDescription, privacy: .public)"
            )
        }
        statusValue = LocalModelStatus(
            state: .loaded,
            modelIdentifier: modelIdentifier,
            progress: 1,
            message: "Qwen3.5 4B 已在本机加载"
        )
    }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        let modelIdentifier = loadedModelIdentifier
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5 * 60))
            guard !Task.isCancelled else { return }
            await self?.releaseLoadedModel(expectedIdentifier: modelIdentifier)
        }
    }

    private func generationDidFinish() {
        scheduleIdleUnload()
    }

    private func releaseLoadedModel(expectedIdentifier: String?) {
        guard loadedModelIdentifier == expectedIdentifier else { return }
        container = nil
        loadedModelIdentifier = nil
        idleUnloadTask = nil
        statusValue = LocalModelStatus(
            state: .ready,
            modelIdentifier: expectedIdentifier ?? statusValue.modelIdentifier,
            progress: 1,
            message: "模型已缓存，使用时自动加载"
        )
    }

    private nonisolated static func cacheMarkerURL(
        for modelIdentifier: String,
        in directory: URL
    ) -> URL {
        let filename = modelIdentifier
            .replacingOccurrences(of: "/", with: "--")
            .replacingOccurrences(of: ":", with: "-")
        return directory.appending(path: ".\(filename).ready")
    }

    nonisolated static func publicModelHubClient(cacheDirectory: URL) -> HubClient {
        HubClient(
            host: HubClient.defaultHost,
            bearerToken: nil,
            cache: HubCache(cacheDirectory: cacheDirectory)
        )
    }
}
