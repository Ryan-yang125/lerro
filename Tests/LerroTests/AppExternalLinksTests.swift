import Foundation
import Testing
@testable import Lerro

@Suite("App external links")
@MainActor
struct AppExternalLinksTests {
    @Test("Release action opens the repository release list")
    func releasePage() {
        var openedURL: URL?

        let opened = AppExternalLinks.openReleases { url in
            openedURL = url
            return true
        }

        #expect(opened)
        #expect(openedURL?.absoluteString == "https://github.com/Ryan-yang125/lerro/releases")
        #expect(openedURL?.path == "/Ryan-yang125/lerro/releases")
    }

    @Test("Release action preserves opener failure")
    func releasePageFailure() {
        let opened = AppExternalLinks.openReleases { _ in false }

        #expect(!opened)
        #expect(!AppExternalLinks.releasesOpenFailureMessage.isEmpty)
    }
}
