import Darwin
import Foundation
import Metal
import LerroCore

public struct MacDeviceCapabilityAssessor: DeviceCapabilityAssessing {
    private let storageURL: URL

    public init(storageURL: URL) {
        self.storageURL = storageURL
    }

    public func snapshot() -> DeviceCapabilitySnapshot {
        let capacity = try? storageURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage

        return DeviceCapabilitySnapshot(
            chipName: Self.chipName(),
            isAppleSilicon: Self.isAppleSilicon,
            supportsMetal: MTLCreateSystemDefaultDevice() != nil,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            availableStorageBytes: max(0, capacity ?? 0)
        )
    }

    private static var isAppleSilicon: Bool {
        #if arch(arm64)
            true
        #else
            false
        #endif
    }

    private static func chipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 1 else {
            return isAppleSilicon ? "Apple silicon" : "Mac"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return isAppleSilicon ? "Apple silicon" : "Mac"
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
