import Testing
@testable import LerroCore

@Test func packageLoads() {
    #expect(UserPreferences().recognitionLocaleIdentifier == "zh_CN")
}
