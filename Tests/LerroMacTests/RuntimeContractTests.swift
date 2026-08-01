import Testing
@testable import LerroMac

@Test func runtimeTargetsMacOS26() {
    #expect(LerroMacRuntime.minimumSystemVersion.majorVersion == 26)
}
