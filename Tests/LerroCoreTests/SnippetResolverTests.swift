import Testing
@testable import LerroCore

@Suite("Snippet resolver")
struct SnippetResolverTests {
    @Test("Expands an exact manual trigger")
    func expandsExactTrigger() throws {
        let entry = DictionaryEntry(phrase: "meeting link", replacement: "https://example.com/meet")

        let result = SnippetResolver.resolve(
            transcript: "  MEETING   LINK ",
            entries: [entry],
            applicationBundleIdentifier: nil
        )

        #expect(try #require(result).replacement == "https://example.com/meet")
    }

    @Test("Prefers the current application and ignores learned replacements")
    func respectsApplicationScope() throws {
        let global = DictionaryEntry(phrase: "sign off", replacement: "Thanks")
        let scoped = DictionaryEntry(
            phrase: "sign off",
            replacement: "Best regards,\nYangrui",
            applicationBundleIdentifier: "com.apple.mail"
        )
        let learned = DictionaryEntry(
            phrase: "sign off",
            replacement: "ignored",
            source: .learned,
            applicationBundleIdentifier: "com.apple.mail"
        )

        let result = SnippetResolver.resolve(
            transcript: "sign off",
            entries: [global, learned, scoped],
            applicationBundleIdentifier: "com.apple.mail"
        )

        #expect(try #require(result).id == scoped.id)
    }

    @Test("Requires the whole utterance to match")
    func rejectsPartialTrigger() {
        let entry = DictionaryEntry(phrase: "intro", replacement: "Hello there")
        #expect(SnippetResolver.resolve(
            transcript: "insert intro please",
            entries: [entry],
            applicationBundleIdentifier: nil
        ) == nil)
    }
}
