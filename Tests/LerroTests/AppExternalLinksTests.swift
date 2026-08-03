import Testing
@testable import Lerro

@Suite("Application updates")
struct AppExternalLinksTests {
    @Test("Live update checks run outside fixture and test processes")
    func allowsLiveUpdater() {
        #expect(AppUpdateEnvironment.allowsLiveUpdater([:]))
        #expect(AppUpdateEnvironment.allowsLiveUpdater(["LERRO_FIXTURE_MODE": "0"]))
    }

    @Test("Fixtures and tests never start a network updater")
    func keepsFixtureAndTestProcessesOffline() {
        #expect(!AppUpdateEnvironment.allowsLiveUpdater(["LERRO_FIXTURE_MODE": "1"]))
        #expect(!AppUpdateEnvironment.allowsLiveUpdater(["XCTestConfigurationFilePath": "/tmp/test.xctest"]))
    }

    @Test("Available updates use the dedicated blue download affordance")
    func presentsAvailableUpdateClearly() {
        #expect(AppUpdatePresentation.availableIcon == "arrow.down.circle.fill")
        #expect(AppUpdatePresentation.usesSystemBlue)
        #expect(AppUpdatePolicy.detectionInterval == .seconds(86_400))
    }
}
