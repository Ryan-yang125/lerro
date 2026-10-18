import AppKit

/// Keeps keyboard focus on the app that was frontmost before the menu bar panel
/// opened, so dictation, translation and paste never target Lerro itself.
@MainActor
final class MenuBarPanelFocus {
    static let shared = MenuBarPanelFocus()

    /// The menu bar panel window, set by the panel view.
    weak var panelWindow: NSWindow?

    private static let activationTimeout: Duration = .milliseconds(500)
    private static let pollInterval: Duration = .milliseconds(20)

    private var targetApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    private init() {}

    /// Starts tracking the most recent frontmost app other than Lerro.
    func start() {
        guard activationObserver == nil else { return }
        record(processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let processIdentifier = application?.processIdentifier
            Task { @MainActor in self?.record(processIdentifier: processIdentifier) }
        }
    }

    func panelDidAppear() {
        record(processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    func closePanel() {
        panelWindow?.close()
    }

    /// Closes the panel, returns focus to the recorded app when Lerro is
    /// frontmost, waits until that app is frontmost (at most 500 ms), then runs
    /// `action`.
    func performInTargetApplication(_ action: @escaping @MainActor () -> Void) {
        closePanel()
        guard lerroIsFrontmost,
              let target = targetApplication,
              !target.isTerminated else {
            action()
            return
        }
        _ = target.activate()
        Task { @MainActor in
            await waitUntilFrontmost(target)
            action()
        }
    }

    private var lerroIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
    }

    private func record(processIdentifier: pid_t?) {
        guard let processIdentifier,
              processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let application = NSRunningApplication(processIdentifier: processIdentifier),
              application.activationPolicy == .regular else { return }
        targetApplication = application
    }

    private func waitUntilFrontmost(_ application: NSRunningApplication) async {
        let deadline = ContinuousClock.now.advanced(by: Self.activationTimeout)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier
                != application.processIdentifier,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.pollInterval)
        }
    }
}
