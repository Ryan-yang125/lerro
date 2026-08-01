import AppKit
import SwiftUI

public struct WindowConfigurator: NSViewRepresentable {
    private let configure: @MainActor (NSWindow) -> Void

    public init(configure: @escaping @MainActor (NSWindow) -> Void) {
        self.configure = configure
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowReaderView()
        view.onWindowChange = configure
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowReaderView else { return }
        view.onWindowChange = configure
        if let window = view.window {
            configure(window)
        }
    }
}

@MainActor
private final class WindowReaderView: NSView {
    var onWindowChange: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowChange?(window)
        }
    }
}
