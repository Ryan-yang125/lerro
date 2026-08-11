import Foundation
import Testing
import LerroCore
@testable import LerroIntelligence

@Suite("MLX language model runtime")
struct MLXLanguageModelRuntimeTests {
    @Test("Cancelling a load waiter cancels its underlying task")
    func loadWaiterCancellationPropagates() async {
        let probe = CancellationProbe()
        let worker = Task<Int, Error> {
            do {
                try await Task.sleep(for: .seconds(30))
                return 1
            } catch {
                await probe.markCancelled()
                throw error
            }
        }
        let waiter = Task {
            try await MLXLanguageModelRuntime.valuePropagatingCancellation(from: worker)
        }

        await Task.yield()
        waiter.cancel()

        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        #expect(await probe.wasCancelled)
    }

    @Test("Download progress stays bounded and monotonic")
    func downloadProgressIsMonotonic() {
        let cases: [(previous: Double, incoming: Double, expected: Double)] = [
            (0.2, 0.7, 0.7),
            (0.7, 0.2, 0.7),
            (-1.0, 0.4, 0.4),
            (0.8, 2.0, 1.0),
            (0.6, Double.nan, 0.6),
            (Double.nan, 0.3, 0.3)
        ]

        for testCase in cases {
            #expect(MLXLanguageModelRuntime.monotonicProgress(
                previous: testCase.previous,
                incoming: testCase.incoming
            ) == testCase.expected)
        }
    }

    @Test("Public model downloads never inherit Hugging Face credentials")
    func publicDownloadsAreUnauthenticated() async {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appending(path: "LerroIntelligenceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let client = MLXLanguageModelRuntime.publicModelHubClient(
            cacheDirectory: cacheDirectory
        )

        #expect(await client.bearerToken == nil)
    }

    @Test("A persisted checkpoint restores the paused download state")
    func persistedCheckpointRestoresPausedState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LerroCheckpointTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let checkpoint: [String: Any] = [
            "modelIdentifier": "test/model",
            "progress": 0.42,
            "downloadedBytes": 420,
            "totalBytes": 1_000
        ]
        let data = try JSONSerialization.data(withJSONObject: checkpoint)
        try data.write(to: directory.appending(path: ".lerro-model-download.json"))

        let runtime = MLXLanguageModelRuntime(
            defaultModelIdentifier: "test/model",
            modelCacheDirectory: directory
        )
        let status = await runtime.status()

        #expect(status.state == .paused)
        #expect(status.progress == 0.42)
        #expect(status.downloadedBytes == 420)
        #expect(status.totalBytes == 1_000)
    }

    @Test("Stopping a download removes only resumable artifacts")
    func discardRemovesResumableArtifacts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LerroDiscardTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let blobs = directory.appending(path: "models--test--model/blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        let completed = blobs.appending(path: "complete-etag")
        let incomplete = blobs.appending(path: "partial-etag.incomplete")
        let resumeData = blobs.appending(path: "partial-etag.resume-data")
        let hiddenResumeData = blobs.appending(path: ".resume-data")
        try Data("complete".utf8).write(to: completed)
        try Data("partial".utf8).write(to: incomplete)
        try Data("resume".utf8).write(to: resumeData)
        try Data("hidden-resume".utf8).write(to: hiddenResumeData)
        try Data("{}".utf8).write(to: directory.appending(path: ".lerro-model-download.json"))

        try MLXLanguageModelRuntime.removeResumableArtifacts(from: directory)

        #expect(FileManager.default.fileExists(atPath: completed.path))
        #expect(!FileManager.default.fileExists(atPath: incomplete.path))
        #expect(!FileManager.default.fileExists(atPath: resumeData.path))
        #expect(!FileManager.default.fileExists(atPath: hiddenResumeData.path))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appending(path: ".lerro-model-download.json").path
        ))
    }

    @Test(
        "Live cached model loads and generates when explicitly enabled",
        .enabled(if: ProcessInfo.processInfo.environment["LERRO_LIVE_MODEL_SMOKE"] == "1")
    )
    func liveCachedModelSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        let cachePath = try #require(environment["LERRO_LIVE_MODEL_CACHE"])
        let modelIdentifier = environment["LERRO_LIVE_MODEL_ID"]
            ?? "mlx-community/Qwen3.5-4B-MLX-4bit"
        let runtime = MLXLanguageModelRuntime(
            defaultModelIdentifier: modelIdentifier,
            modelCacheDirectory: URL(fileURLWithPath: cachePath, isDirectory: true)
        )
        let service = PipelineIntelligenceService(
            runtime: runtime,
            modelIdentifier: modelIdentifier
        )
        let result = try await service.process(IntelligenceRequest(
            task: .translate,
            transcript: "你好，世界。",
            targetLanguage: "en_US",
            context: CapturedContext(
                applicationName: "Live model release smoke",
                bundleIdentifier: "app.lerro.mac.release-smoke"
            )
        ))
        let output = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        print("LERRO_LIVE_MODEL_OUTPUT=\(output.prefix(240))")
        #expect(!output.isEmpty)
        #expect(result.disposition == .insert)
        #expect(result.modelIdentifier == modelIdentifier)
        #expect(await runtime.status().state == .loaded)
    }
}

private actor CancellationProbe {
    private(set) var wasCancelled = false

    func markCancelled() {
        wasCancelled = true
    }
}
