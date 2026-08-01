import Foundation
import ServiceManagement
import LerroCore

public struct MacLoginItemManager: LoginItemManaging {
    public init() {}

    public func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public func reconcileAfterIdentityMigration(
        enabled: Bool
    ) throws -> LoginItemIdentityMigrationStatus {
        let service = SMAppService.mainApp
        let initialStatus = service.status
        switch initialStatus {
        case .enabled, .requiresApproval:
            // An in-place app update can leave the prior main-app registration
            // attached to the bundle URL. Remove it before registering Lerro.
            try service.unregister()
        case .notRegistered:
            break
        case .notFound:
            return .requiresUserReview
        @unknown default:
            return .requiresUserReview
        }

        if enabled {
            try service.register()
            return service.status == .enabled ? .completed : .requiresUserReview
        }

        // A not-registered status cannot prove that a separately installed
        // legacy bundle has no stale Login Items entry.
        return initialStatus == .notRegistered ? .requiresUserReview : .completed
    }
}
