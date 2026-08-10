import Testing
@testable import LerroCore

@Suite("Voice finish action")
struct VoiceFinishActionResolverTests {
    @Test("Chinese and English suffixes are removed only at the end")
    func resolvesSupportedSuffixes() {
        #expect(VoiceFinishActionResolver.resolve("今晚七点见，发送。") == VoiceFinishResolution(
            text: "今晚七点见",
            requestsSubmit: true
        ))
        #expect(VoiceFinishActionResolver.resolve("See you at seven. Send it.") == VoiceFinishResolution(
            text: "See you at seven",
            requestsSubmit: true
        ))
        #expect(!VoiceFinishActionResolver.resolve("Please send it tomorrow").requestsSubmit)
    }

    @Test("A finish phrase without message content remains ordinary dictation")
    func requiresMessageContent() {
        #expect(VoiceFinishActionResolver.resolve("发送") == VoiceFinishResolution(
            text: "发送",
            requestsSubmit: false
        ))
        #expect(VoiceFinishActionResolver.resolve("send it") == VoiceFinishResolution(
            text: "send it",
            requestsSubmit: false
        ))
    }

    @Test("Only identified standard text fields are eligible")
    func validatesTargetPolicy() {
        let safe = CapturedContext(
            applicationName: "Messages",
            processIdentifier: 42,
            bundleIdentifier: "com.apple.MobileSMS",
            role: "AXTextArea"
        )
        #expect(VoiceFinishActionResolver.permitsSubmit(in: safe))

        var search = safe
        search.subrole = "AXSearchField"
        #expect(!VoiceFinishActionResolver.permitsSubmit(in: search))

        var terminal = safe
        terminal.bundleIdentifier = "com.apple.Terminal"
        #expect(!VoiceFinishActionResolver.permitsSubmit(in: terminal))

        var secure = safe
        secure.isSecureField = true
        #expect(!VoiceFinishActionResolver.permitsSubmit(in: secure))
    }
}
