import AppKit
import SwiftUI
import Testing
@testable import LerroMac

@Suite("Floating panel window capabilities")
@MainActor
struct FloatingPanelControllerTests {
    @Test("Ask card becomes key without requesting main-window ownership")
    func interactiveCardCapabilities() throws {
        _ = NSApplication.shared
        let controller = FloatingPanelController(role: .interactiveCard)
        controller.show(
            content: AnyView(Text("Synthetic Ask answer")),
            size: CGSize(width: 800, height: 500),
            animated: false
        )
        defer { controller.close() }

        let panel = try #require(controller.presentedPanelForTesting)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test("Passive HUD cannot take key or main-window ownership")
    func passiveHUDCapabilities() throws {
        _ = NSApplication.shared
        let controller = FloatingPanelController(role: .passiveHUD)
        controller.show(
            content: AnyView(Text("Synthetic HUD")),
            size: CGSize(width: 176, height: 48),
            animated: false
        )
        defer { controller.close() }

        let panel = try #require(controller.presentedPanelForTesting)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }
}
