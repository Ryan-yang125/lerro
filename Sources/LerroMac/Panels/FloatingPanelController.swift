import AppKit
import SwiftUI

@MainActor
public final class FloatingPanelController {
    private var panel: NSPanel?
    private var hasInstalledContent = false
    private var interactionSize = CGSize(width: 176, height: 48)
    private var interactionBottomInset: CGFloat = 0
    private var allowsInteraction = true
    private let role: Role

    public enum Role: Sendable {
        case passiveHUD
        case interactiveCard
    }

    public init(role: Role) {
        self.role = role
    }

    public func show(
        content: AnyView,
        size: CGSize,
        interactionSize: CGSize? = nil,
        interactionBottomInset: CGFloat = 0,
        allowsInteraction: Bool = true,
        animated: Bool = true
    ) {
        let panel = panel ?? makePanel()
        if !hasInstalledContent {
            panel.contentView = NSHostingView(rootView: content)
            hasInstalledContent = true
        }
        if let interactionSize { self.interactionSize = interactionSize }
        self.interactionBottomInset = interactionBottomInset
        self.allowsInteraction = allowsInteraction
        if panel.frame.size != size {
            panel.setContentSize(size)
        }
        position(panel: panel, size: size)
        self.panel = panel
        if role == .passiveHUD {
            panel.ignoresMouseEvents = !allowsInteraction
        }

        guard !panel.isVisible else { return }
        if animated {
            panel.alphaValue = 0
            orderFront(panel)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            orderFront(panel)
        }
    }

    public func update(content: AnyView, size: CGSize) {
        guard let panel else {
            show(content: content, size: size)
            return
        }
        panel.contentView = NSHostingView(rootView: content)
        hasInstalledContent = true
        position(panel: panel, size: size)
    }

    public func resize(to requestedSize: CGSize, animated: Bool = true) {
        guard let panel else { return }
        let size = constrainedSize(requestedSize)
        guard abs(panel.frame.width - size.width) > 0.5
                || abs(panel.frame.height - size.height) > 0.5 else {
            return
        }
        let targetFrame = targetFrame(for: panel, size: size)
        panel.setFrame(targetFrame, display: true, animate: animated)
    }

    public func hide(animated: Bool = true) {
        guard let panel else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                }
            }
        } else {
            panel.orderOut(nil)
        }
    }

    public func close() {
        panel?.close()
        panel = nil
        hasInstalledContent = false
    }

    private func makePanel() -> NSPanel {
        let styleMask: NSWindow.StyleMask = role == .passiveHUD
            ? [.borderless, .nonactivatingPanel]
            : [.borderless, .utilityWindow]
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )
        panel.allowsKeyWindow = role == .interactiveCard
        panel.isOpaque = false
        panel.title = role == .passiveHUD ? "Lerro HUD" : "Lerro Command"
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = role == .passiveHUD ? .screenSaver : .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .stationary,
            .ignoresCycle
        ]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = role == .passiveHUD ? .none : .utilityWindow
        panel.ignoresMouseEvents = role == .passiveHUD
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = false
        panel.becomesKeyOnlyIfNeeded = role == .passiveHUD
        return panel
    }

    private func position(panel: NSPanel, size: CGSize) {
        panel.setFrame(targetFrame(for: panel, size: constrainedSize(size)), display: true)
    }

    private func targetFrame(for panel: NSPanel, size: CGSize) -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return CGRect(origin: panel.frame.origin, size: size) }
        let visibleFrame = screen.visibleFrame

        let origin: CGPoint
        switch role {
        case .passiveHUD:
            origin = CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY
            )
        case .interactiveCard:
            origin = CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY + 20
            )
        }
        return CGRect(origin: origin, size: size)
    }

    private func constrainedSize(_ requestedSize: CGSize) -> CGSize {
        guard role == .interactiveCard else { return requestedSize }
        let visibleHeight = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? requestedSize.height
        return CGSize(
            width: 800,
            height: min(requestedSize.height, max(1, visibleHeight - 40))
        )
    }

    private func orderFront(_ panel: NSPanel) {
        switch role {
        case .passiveHUD:
            panel.orderFrontRegardless()
        case .interactiveCard:
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    var presentedPanelForTesting: NSPanel? {
        panel
    }
}

private final class KeyablePanel: NSPanel {
    var allowsKeyWindow = false

    override var canBecomeKey: Bool {
        allowsKeyWindow
    }

    override var canBecomeMain: Bool {
        false
    }
}
