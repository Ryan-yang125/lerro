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
