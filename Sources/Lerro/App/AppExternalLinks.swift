import AppKit
import Foundation

@MainActor
enum AppExternalLinks {
    static let releasesURL = URL(string: "https://github.com/Ryan-yang125/lerro/releases")!
    static let releasesOpenFailureMessage = "无法打开 Lerro 发布页面，请稍后重试。"

    @discardableResult
    static func openReleases(
        using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        opener(releasesURL)
    }
}
