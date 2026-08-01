import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import Speech
import LerroCore

public struct MacPermissionService: PermissionChecking {
    public init() {}

    public func microphoneAuthorized() async -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func speechAuthorized() async -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func accessibilityAuthorized(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func inputMonitoringAuthorized(prompt: Bool) -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        return prompt ? CGRequestListenEventAccess() : false
    }
}
