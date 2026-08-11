import Testing
@testable import LerroCore

@Suite("Local AI readiness")
struct LocalAIReadinessTests {
    @Test("Comfortable Apple silicon Macs recommend local AI")
    func localRecommendation() {
        let readiness = LocalAIReadiness(device: snapshot(memoryGB: 16, storageGB: 40))

        #expect(readiness.recommendation == .localRecommended)
        #expect(readiness.hasComfortableMemory)
        #expect(readiness.hasEnoughStorage)
    }

    @Test("Constrained memory recommends an API provider")
    func memoryRecommendation() {
        let readiness = LocalAIReadiness(device: snapshot(memoryGB: 8, storageGB: 40))

        #expect(readiness.recommendation == .remoteRecommended)
        #expect(!readiness.hasComfortableMemory)
    }

    @Test("Constrained storage recommends an API provider")
    func storageRecommendation() {
        let readiness = LocalAIReadiness(device: snapshot(memoryGB: 24, storageGB: 6))

        #expect(readiness.recommendation == .remoteRecommended)
        #expect(!readiness.hasEnoughStorage)
    }

    @Test("Missing platform support disables local AI")
    func unsupportedRecommendation() {
        let device = DeviceCapabilitySnapshot(
            chipName: "Unsupported",
            isAppleSilicon: false,
            supportsMetal: false,
            physicalMemoryBytes: 32 * 1_024 * 1_024 * 1_024,
            availableStorageBytes: 100 * 1_024 * 1_024 * 1_024
        )

        #expect(LocalAIReadiness(device: device).recommendation == .localUnavailable)
    }

    @Test("Remote AI readiness requires endpoint, model, and key")
    func remoteReadiness() {
        var configuration = RemoteProviderConfiguration(
            provider: .custom,
            baseURL: "https://example.com/v1",
            modelIdentifier: "example-model",
            apiKey: "secret"
        )

        #expect(configuration.isReadyForUse)
        configuration.apiKey = "  "
        #expect(!configuration.isReadyForUse)
    }

    private func snapshot(memoryGB: UInt64, storageGB: Int64) -> DeviceCapabilitySnapshot {
        DeviceCapabilitySnapshot(
            chipName: "Apple silicon",
            isAppleSilicon: true,
            supportsMetal: true,
            physicalMemoryBytes: memoryGB * 1_024 * 1_024 * 1_024,
            availableStorageBytes: storageGB * 1_024 * 1_024 * 1_024
        )
    }
}
