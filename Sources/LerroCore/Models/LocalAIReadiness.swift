import Foundation

public struct DeviceCapabilitySnapshot: Codable, Equatable, Sendable {
    public var chipName: String
    public var isAppleSilicon: Bool
    public var supportsMetal: Bool
    public var physicalMemoryBytes: UInt64
    public var availableStorageBytes: Int64

    public init(
        chipName: String,
        isAppleSilicon: Bool,
        supportsMetal: Bool,
        physicalMemoryBytes: UInt64,
        availableStorageBytes: Int64
    ) {
        self.chipName = chipName
        self.isAppleSilicon = isAppleSilicon
        self.supportsMetal = supportsMetal
        self.physicalMemoryBytes = physicalMemoryBytes
        self.availableStorageBytes = availableStorageBytes
    }
}

public enum LocalAIRecommendation: String, Codable, Equatable, Sendable {
    case localRecommended
    case remoteRecommended
    case localUnavailable
}

public struct LocalAIReadiness: Codable, Equatable, Sendable {
    public static let comfortableMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024
    public static let minimumStorageBytes: Int64 = 10 * 1_024 * 1_024 * 1_024

    public var device: DeviceCapabilitySnapshot
    public var recommendation: LocalAIRecommendation
    public var hasComfortableMemory: Bool
    public var hasEnoughStorage: Bool

    public init(device: DeviceCapabilitySnapshot) {
        self.device = device
        hasComfortableMemory = device.physicalMemoryBytes >= Self.comfortableMemoryBytes
        hasEnoughStorage = device.availableStorageBytes >= Self.minimumStorageBytes

        if !device.isAppleSilicon || !device.supportsMetal {
            recommendation = .localUnavailable
        } else if hasComfortableMemory && hasEnoughStorage {
            recommendation = .localRecommended
        } else {
            recommendation = .remoteRecommended
        }
    }
}

public protocol DeviceCapabilityAssessing: Sendable {
    func snapshot() async -> DeviceCapabilitySnapshot
}
