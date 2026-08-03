import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import LerroCore

public struct MacPermissionService: PermissionChecking {
    public init() {}

    public func microphoneAuthorized() async -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func accessibilityAuthorized(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

}
