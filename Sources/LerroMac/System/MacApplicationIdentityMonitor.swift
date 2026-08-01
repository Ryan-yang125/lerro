import AppKit
import Foundation
import LerroCore

public struct MacApplicationIdentityMonitor: ApplicationIdentityMonitoring {
    public init() {}

    public func legacyApplicationIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: ApplicationIdentity.legacyBundleIdentifier
        ).isEmpty
    }
}
