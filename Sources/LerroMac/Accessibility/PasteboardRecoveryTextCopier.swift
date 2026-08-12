import AppKit
import Foundation
import LerroCore

public struct PasteboardRecoveryTextCopier: RecoveryTextCopying {
    private let pasteboardName: String

    public init() {
        pasteboardName = NSPasteboard.Name.general.rawValue
    }

    init(pasteboardName: String) {
        self.pasteboardName = pasteboardName
    }

    public func copyForRecovery(_ text: String) async throws {
        try await MainActor.run {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(pasteboardName))
            _ = pasteboard.prepareForNewContents(with: .currentHostOnly)
            guard pasteboard.setString(text, forType: .string) else {
                throw LerroError.insertionFailed("无法把结果保存到剪贴板")
            }
        }
    }
}
