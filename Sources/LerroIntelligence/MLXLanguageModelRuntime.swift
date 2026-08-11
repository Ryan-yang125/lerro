import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import OSLog
import Tokenizers
import LerroCore

public actor MLXLanguageModelRuntime: LocalLanguageModelRuntime {
    private struct DownloadCheckpoint: Codable, Equatable, Sendable {
        var modelIdentifier: String
        var progress: Double
        var downloadedBytes: Int64
        var totalBytes: Int64
    }

    private enum LoadInterruption: Sendable {
        case pause
        case discard
    }

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
    private var requestedInterruption: LoadInterruption?
    private var lastProgressDate: Date?
    private var lastProgressBytes: Int64 = 0
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
        let checkpoint = Self.loadDownloadCheckpoint(from: modelCacheDirectory)
        if !isCached, let checkpoint, checkpoint.modelIdentifier == defaultModelIdentifier {
            statusValue = LocalModelStatus(
                state: .paused,
                modelIdentifier: defaultModelIdentifier,
                progress: min(1, max(0, checkpoint.progress)),
                message: "本地模型下载已暂停，可继续下载",
                downloadedBytes: checkpoint.downloadedBytes,
                totalBytes: checkpoint.totalBytes
            )
        } else {
            statusValue = LocalModelStatus(
                state: .ready,
                modelIdentifier: defaultModelIdentifier,
                progress: isCached ? 1 : 0,
                message: isCached
                    ? "模型已缓存在本机，使用时加载"
                    : "首次使用时下载约 3.03 GB 的本地模型"
            )
        }
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
        requestedInterruption = nil
        container = nil
        loadedModelIdentifier = nil
        loadingModelIdentifier = modelIdentifier
        let generation = UUID()
        loadGeneration = generation
        let checkpoint = Self.loadDownloadCheckpoint(from: modelCacheDirectory)
        let resumesCheckpoint = checkpoint?.modelIdentifier == modelIdentifier
        let startingProgress = resumesCheckpoint ? checkpoint?.progress ?? 0 : 0
        let startingBytes = resumesCheckpoint ? checkpoint?.downloadedBytes ?? 0 : 0
        let totalBytes = resumesCheckpoint ? checkpoint?.totalBytes ?? 0 : 0
        lastProgressDate = .now
        lastProgressBytes = startingBytes
        statusValue = LocalModelStatus(
            state: .downloading,
            modelIdentifier: modelIdentifier,
            progress: startingProgress,
            message: startingProgress > 0
                ? "正在继续下载本地模型"
                : "正在检查并下载本地模型",
            downloadedBytes: startingBytes,
            totalBytes: totalBytes
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
                let completedUnitCount = progress.completedUnitCount
                let totalUnitCount = progress.totalUnitCount
                Task {
                    await progressReceiver.recordDownloadProgress(
                        fractionCompleted,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
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
                finishInterruptedLoad(modelIdentifier: modelIdentifier)
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

    public func pauseLoad() async {
        guard let task = loadTask else {
            if statusValue.state == .downloading || statusValue.state == .loading {
                statusValue.state = .paused
                statusValue.message = "本地模型下载已暂停，可继续下载"
                persistDownloadCheckpoint(statusValue)
            }
            return
        }
        requestedInterruption = .pause
        task.cancel()
        _ = await task.result
        if loadTask != nil {
            finishInterruptedLoad(modelIdentifier: statusValue.modelIdentifier)
        }
    }

    public func discardDownload() async throws {
        if let task = loadTask {
            requestedInterruption = .discard
            task.cancel()
            _ = await task.result
        }
        try Self.removeResumableArtifacts(from: modelCacheDirectory)
        loadingModelIdentifier = nil
        loadGeneration = nil
        loadTask = nil
        requestedInterruption = nil
        lastProgressDate = nil
        lastProgressBytes = 0
        statusValue = LocalModelStatus(
            state: .ready,
            modelIdentifier: statusValue.modelIdentifier,
            progress: 0,
            message: "等待下载本地模型"
        )
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
        completedUnitCount: Int64,
        totalUnitCount: Int64,
        modelIdentifier: String,
        generation: UUID
    ) {
        guard loadingModelIdentifier == modelIdentifier,
              loadGeneration == generation else { return }
        let boundedProgress = Self.monotonicProgress(
            previous: statusValue.progress,
            incoming: progress
        )
        let now = Date.now
        let downloadedBytes = max(statusValue.downloadedBytes, completedUnitCount)
        let totalBytes = max(statusValue.totalBytes, totalUnitCount)
        let speed: Double? = if let lastProgressDate,
                                downloadedBytes > lastProgressBytes,
                                now.timeIntervalSince(lastProgressDate) > 0 {
            Double(downloadedBytes - lastProgressBytes) / now.timeIntervalSince(lastProgressDate)
        } else {
            statusValue.bytesPerSecond
        }
        lastProgressDate = now
        lastProgressBytes = downloadedBytes
        statusValue = LocalModelStatus(
            state: boundedProgress >= 1 ? .loading : .downloading,
            modelIdentifier: modelIdentifier,
            progress: boundedProgress,
            message: boundedProgress >= 1
                ? "模型已下载，正在加载"
                : "正在下载本地模型 · \(Int(boundedProgress * 100))%",
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            bytesPerSecond: speed
        )
        persistDownloadCheckpoint(statusValue)
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
        requestedInterruption = nil
        lastProgressDate = nil
        lastProgressBytes = 0
        try? FileManager.default.removeItem(at: Self.downloadCheckpointURL(in: modelCacheDirectory))
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

    private func finishInterruptedLoad(modelIdentifier: String) {
        let interruption = requestedInterruption ?? .pause
        loadingModelIdentifier = nil
        loadGeneration = nil
        loadTask = nil
        requestedInterruption = nil
        lastProgressDate = nil
        lastProgressBytes = statusValue.downloadedBytes

        switch interruption {
        case .pause:
            statusValue.state = .paused
            statusValue.bytesPerSecond = nil
            statusValue.message = "本地模型下载已暂停，可继续下载"
            persistDownloadCheckpoint(statusValue)
        case .discard:
            statusValue = LocalModelStatus(
                state: .ready,
                modelIdentifier: modelIdentifier,
                progress: 0,
                message: "等待下载本地模型"
            )
        }
    }

    private func persistDownloadCheckpoint(_ status: LocalModelStatus) {
        let checkpoint = DownloadCheckpoint(
            modelIdentifier: status.modelIdentifier,
            progress: status.progress,
            downloadedBytes: status.downloadedBytes,
            totalBytes: status.totalBytes
        )
        do {
            try FileManager.default.createDirectory(
                at: modelCacheDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(checkpoint)
            try data.write(to: Self.downloadCheckpointURL(in: modelCacheDirectory), options: .atomic)
        } catch {
            Self.logger.warning(
                "Model download checkpoint could not be saved: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private nonisolated static func downloadCheckpointURL(in directory: URL) -> URL {
        directory.appending(path: ".lerro-model-download.json")
    }

    private nonisolated static func loadDownloadCheckpoint(from directory: URL) -> DownloadCheckpoint? {
        guard let data = try? Data(contentsOf: downloadCheckpointURL(in: directory)) else { return nil }
        return try? JSONDecoder().decode(DownloadCheckpoint.self, from: data)
    }

    nonisolated static func removeResumableArtifacts(from directory: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return }
        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name.hasSuffix(".incomplete") || name.hasSuffix(".resume-data") {
                    try fileManager.removeItem(at: url)
                }
            }
        }
        let checkpointURL = downloadCheckpointURL(in: directory)
        if fileManager.fileExists(atPath: checkpointURL.path) {
            try fileManager.removeItem(at: checkpointURL)
        }
    }

    nonisolated static func publicModelHubClient(cacheDirectory: URL) -> HubClient {
        HubClient(
            host: HubClient.defaultHost,
            bearerToken: nil,
            cache: HubCache(cacheDirectory: cacheDirectory)
        )
    }
}
