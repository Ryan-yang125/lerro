import AppKit
import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdateController: NSObject {
    static let shared = AppUpdateController()

    private var updaterController: SPUStandardUpdaterController?
    private var updateObserver: NSObjectProtocol?
    private var noUpdateObserver: NSObjectProtocol?
    private(set) var updateAvailable = false
    private(set) var availableVersion: String?

    private override init() {}

    func startIfEligible(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if AppUpdateEnvironment.showsFixtureUpdate(environment) {
            updateAvailable = true
            availableVersion = "1.9.1"
            return
        }
        guard updaterController == nil, AppUpdateEnvironment.allowsLiveUpdater(environment) else {
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        updaterController = controller
        installUpdateObservers(for: controller.updater)
    }

    func checkForUpdates() {
        guard let updaterController else { return }
        NSApp.activate()
        updaterController.checkForUpdates(nil)
    }

    private func installUpdateObservers(for updater: SPUUpdater) {
        guard updateObserver == nil, noUpdateObserver == nil else { return }
        updateObserver = NotificationCenter.default.addObserver(
            forName: .SUUpdaterDidFindValidUpdate,
            object: updater,
            queue: .main
        ) { [weak self] notification in
            let item = notification.userInfo?[SUUpdaterAppcastItemNotificationKey] as? SUAppcastItem
            let version = item?.displayVersionString
            Task { @MainActor in
                self?.updateAvailable = true
                self?.availableVersion = version
            }
        }
        noUpdateObserver = NotificationCenter.default.addObserver(
            forName: .SUUpdaterDidNotFindUpdate,
            object: updater,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAvailable = false
                self?.availableVersion = nil
            }
        }
    }
}

extension AppUpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            if !NSApp.isActive { NSApp.activate() }
        } else {
            updateAvailable = true
            availableVersion = update.displayVersionString
        }
    }
}

enum AppUpdateEnvironment {
    static func allowsLiveUpdater(_ environment: [String: String]) -> Bool {
        environment["LERRO_FIXTURE_MODE"] != "1"
            && environment["XCTestConfigurationFilePath"] == nil
    }

    static func showsFixtureUpdate(_ environment: [String: String]) -> Bool {
        environment["LERRO_FIXTURE_MODE"] == "1"
            && environment["LERRO_FIXTURE_UPDATE_AVAILABLE"] == "1"
    }
}
