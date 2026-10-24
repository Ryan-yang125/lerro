import AppKit
import Foundation
import LerroCore

/// Fixture-only UI benchmark, active when `LERRO_FIXTURE_MODE=1` and
/// `LERRO_FIXTURE_BENCHMARK` is `page-switch` or `focus`. Results go to stdout
/// as `BENCHMARK ...` lines and the app terminates afterwards.
///
/// Measurement boundary of `page-switch`: from setting `session.destination`
/// to the next main run loop `beforeWaiting`. The observer runs at the latest
/// order, after the Core Animation commit of the SwiftUI update, so the span
/// covers view update, layout and commit of the switch but not GPU
/// presentation. Wall time and main thread CPU time are both recorded.
@MainActor
enum FixtureBenchmark {
    private static let pages: [SidebarDestination] = [.home, .history, .dictionary, .appTones]

    static func runIfRequested(_ session: AppSession) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LERRO_FIXTURE_MODE"] == "1",
              let mode = environment["LERRO_FIXTURE_BENCHMARK"] else { return }
        let rounds = environment["LERRO_FIXTURE_BENCHMARK_ROUNDS"].flatMap(Int.init) ?? 8
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            switch mode {
            case "page-switch": await pageSwitch(session, rounds: rounds)
            case "focus": await focus(session)
            default: emit("BENCHMARK error unknown_mode=\(mode)")
            }
            NSApp.terminate(nil)
        }
    }

    // MARK: Page switch

    /// Resumes the armed continuation at the first `beforeWaiting` after `arm`.
    @MainActor
    private final class SwitchProbe {
        private var start: (wall: CFAbsoluteTime, cpu: UInt64)?
        private var continuation: CheckedContinuation<(wall: Double, cpu: Double), Never>?
        private var observer: CFRunLoopObserver?

        init() {
            observer = CFRunLoopObserverCreateWithHandler(
                nil, CFRunLoopActivity.beforeWaiting.rawValue, true, Int.max
            ) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.fire() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        func measure(_ change: () -> Void) async -> (wall: Double, cpu: Double) {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                start = (CFAbsoluteTimeGetCurrent(), clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID))
                change()
            }
        }

        private func fire() {
            guard let start, let continuation else { return }
            let wall = (CFAbsoluteTimeGetCurrent() - start.wall) * 1_000
            let cpu = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start.cpu) / 1_000_000
            self.start = nil
            self.continuation = nil
            continuation.resume(returning: (wall, cpu))
        }

        func stop() {
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            observer = nil
        }
    }

    private static func pageSwitch(_ session: AppSession, rounds: Int) async {
        let probe = SwitchProbe()
        var wall: [SidebarDestination: [Double]] = [:]
        var cpu: [SidebarDestination: [Double]] = [:]
        for round in 0..<max(rounds, 2) {
            for page in pages {
                let sample = await probe.measure { session.destination = page }
                if round > 0 {
                    wall[page, default: []].append(sample.wall)
                    cpu[page, default: []].append(sample.cpu)
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        probe.stop()
        for page in pages {
            let times = (wall[page] ?? []).sorted()
            let cpuTimes = (cpu[page] ?? []).sorted()
            emit(
                "BENCHMARK page-switch page=\(page.rawValue)"
                + " median_ms=\(format(median(times)))"
                + " min_ms=\(format(times.first ?? 0))"
                + " max_ms=\(format(times.last ?? 0))"
                + " cpu_median_ms=\(format(median(cpuTimes)))"
                + " n=\(times.count)"
            )
        }
    }

    // MARK: Focus

    /// Checks that Tab never moves keyboard focus into a control on a hidden
    /// page, and that switching pages does not leave focus on the old page.
    private static func focus(_ session: AppSession) async {
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.contentView != nil && $0.frame.width > 600
        }) else {
            emit("BENCHMARK focus result=fail reason=no_window")
            return
        }
        var passed = true
        for page in pages {
            session.destination = page
            try? await Task.sleep(for: .milliseconds(400))
            window.makeFirstResponder(nil)

            var tabHiddenHits = 0
            for _ in 0..<8 {
                sendTab(to: window)
                try? await Task.sleep(for: .milliseconds(150))
                if let view = responderView(window.firstResponder), effectiveAlpha(view) == 0 {
                    tabHiddenHits += 1
                }
            }

            var switchKeptFocus = 0
            let other: SidebarDestination = page == .home ? .history : .home
            for _ in 0..<3 {
                sendTab(to: window)
                try? await Task.sleep(for: .milliseconds(150))
                let before = window.firstResponder
                session.destination = other
                try? await Task.sleep(for: .milliseconds(300))
                let after = window.firstResponder
                if let view = responderView(after),
                   effectiveAlpha(view) == 0 || (before is NSView && after === before) {
                    switchKeptFocus += 1
                }
                session.destination = page
                try? await Task.sleep(for: .milliseconds(300))
            }

            if tabHiddenHits > 0 || switchKeptFocus > 0 { passed = false }
            emit(
                "BENCHMARK focus page=\(page.rawValue)"
                + " tab_hidden_hits=\(tabHiddenHits) switch_kept_focus=\(switchKeptFocus)"
            )
        }
        emit("BENCHMARK focus result=\(passed ? "pass" : "fail")")
    }

    /// In-process key event; nothing is posted system-wide.
    private static func sendTab(to window: NSWindow) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ) else { return }
        window.sendEvent(event)
    }

    /// The view that owns focus; a field editor resolves to its text field.
    private static func responderView(_ responder: NSResponder?) -> NSView? {
        if let editor = responder as? NSTextView, editor.isFieldEditor,
           let owner = editor.delegate as? NSView {
            return owner
        }
        return responder as? NSView
    }

    /// Product of `alphaValue` up the superview chain. 0 means a hidden page.
    private static func effectiveAlpha(_ view: NSView) -> CGFloat {
        var alpha: CGFloat = 1
        var current: NSView? = view
        while let node = current {
            alpha *= node.alphaValue
            current = node.superview
        }
        return alpha
    }

    // MARK: Output

    private static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
        try? FileHandle.standardOutput.synchronize()
    }
}
