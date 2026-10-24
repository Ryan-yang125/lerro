import Foundation
import LerroCore

/// Lists the microphones Settings can choose from.
public protocol MicrophoneLevelTesting: Sendable {
    func availableInputDevices() async -> [AudioInputDevice]
}

public actor MicrophoneLevelTester: MicrophoneLevelTesting {
    public init() {}

    public func availableInputDevices() async -> [AudioInputDevice] {
        CoreAudioHardware.inputDevices()
    }
}
