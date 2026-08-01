import AudioToolbox
import CoreAudio
import Foundation
import LerroCore

enum CoreAudioHardware {
    struct OutputMuteSnapshot: Sendable {
        let deviceID: AudioDeviceID
        let previousValue: UInt32
        let changedByUs: Bool
    }

    static func inputDevices() -> [AudioInputDevice] {
        let defaultID = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        return allDeviceIDs()
            .filter(hasInputStreams)
            .compactMap { deviceID -> AudioInputDevice? in
                guard let uid = stringProperty(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyDeviceUID,
                    scope: kAudioObjectPropertyScopeGlobal
                ),
                let name = stringProperty(
                    objectID: deviceID,
                    selector: kAudioObjectPropertyName,
                    scope: kAudioObjectPropertyScopeGlobal
                ) else {
                    return nil
                }
                return AudioInputDevice(uid: uid, name: name, isDefault: deviceID == defaultID)
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func inputDeviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { deviceID in
            stringProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceUID,
                scope: kAudioObjectPropertyScopeGlobal
            ) == uid && hasInputStreams(deviceID)
        }
    }

    static func muteDefaultOutput() -> OutputMuteSnapshot? {
        guard let deviceID = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice) else {
            return nil
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable = DarwinBoolean(false)
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue,
              let previousValue = uint32Property(objectID: deviceID, address: &address) else {
            return nil
        }

        let changedByUs = previousValue == 0
        if changedByUs {
            var muted: UInt32 = 1
            let size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muted) == noErr else {
                return nil
            }
        }
        return OutputMuteSnapshot(
            deviceID: deviceID,
            previousValue: previousValue,
            changedByUs: changedByUs
        )
    }

    static func restoreOutputMute(_ snapshot: OutputMuteSnapshot) {
        guard snapshot.changedByUs else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard let currentValue = uint32Property(
            objectID: snapshot.deviceID,
            address: &address
        ), currentValue == 1 else {
            return
        }
        var restoredValue = snapshot.previousValue
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(
            snapshot.deviceID,
            &address,
            0,
            nil,
            size,
            &restoredValue
        )
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var devices = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        ) == noErr else {
            return []
        }
        return devices
    }

    private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return uint32Property(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: &address
        )
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr
            && dataSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        ) == noErr else {
            return nil
        }
        guard let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    private static func uint32Property(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> UInt32? {
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        ) == noErr else {
            return nil
        }
        return value
    }
}
