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
    private var detectionTask: Task<Void, Never>?
    private(set) var updateAvailable = false

    private override init() {}

    func startIfEligible(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard updaterController == nil, AppUpdateEnvironment.allowsLiveUpdater(environment) else {
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        installUpdateObservers(for: updaterController!.updater)
        updaterController!.updater.checkForUpdateInformation()
        scheduleUpdateDetection()
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    private func installUpdateObservers(for updater: SPUUpdater) {
        guard updateObserver == nil, noUpdateObserver == nil else { return }
        updateObserver = NotificationCenter.default.addObserver(
            forName: .SUUpdaterDidFindValidUpdate,
            object: updater,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateAvailable = true }
        }
        noUpdateObserver = NotificationCenter.default.addObserver(
            forName: .SUUpdaterDidNotFindUpdate,
            object: updater,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateAvailable = false }
        }
    }

    private func scheduleUpdateDetection() {
        detectionTask?.cancel()
        detectionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AppUpdatePolicy.detectionInterval)
                guard !Task.isCancelled, let updater = self?.updaterController?.updater else {
                    return
                }
                updater.checkForUpdateInformation()
            }
        }
    }
}

enum AppUpdatePolicy {
    static let detectionInterval: Duration = .seconds(86_400)
}

enum AppUpdateEnvironment {
    static func allowsLiveUpdater(_ environment: [String: String]) -> Bool {
        environment["LERRO_FIXTURE_MODE"] != "1"
            && environment["XCTestConfigurationFilePath"] == nil
    }
}

enum AppUpdatePresentation {
    static let availableIcon = "arrow.down.circle.fill"
    static let usesSystemBlue = true
}
