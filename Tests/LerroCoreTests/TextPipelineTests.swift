import Testing
@testable import LerroCore

@Suite("Text pipeline")
struct TextPipelineTests {
    private let pipeline = TextPipeline()

    @Test("Cleans fillers, immediate repetitions, whitespace, and punctuation")
    func cleansSpokenArtifacts() {
        let result = pipeline.clean(
            "  uh   hello hello ,   world  ",
            dictionary: [],
            applicationBundleIdentifier: nil
        )

        #expect(result == "hello, world")
    }

    @Test("Preserves paragraph breaks while collapsing excess whitespace")
    func preservesParagraphBreaks() {
        let result = pipeline.clean(
            "first\t  line\n\n\n\nsecond line",
            dictionary: [],
            applicationBundleIdentifier: nil
        )

        #expect(result == "first line\n\nsecond line")
    }

    @Test("Normalizes whitespace left by English and Chinese filler removal")
    func normalizesWhitespaceAfterRemovingFillers() {
        let english = pipeline.clean(
            "hello um world uh again erm today you know please",
            dictionary: [],
            applicationBundleIdentifier: nil
        )
        let chinese = pipeline.clean(
            "我 嗯 想 那个 今天 呃 就是 开始 然后呢 结束",
            dictionary: [],
            applicationBundleIdentifier: nil
        )

        #expect(english == "hello world again today please")
        #expect(chinese == "我 想 今天 开始 结束")
    }

    @Test("Preserves filler-like text inside English and Chinese words")
    func preservesFillerSubstringsWithoutWordBoundaries() {
        let source = "umbrella uhuru hermit, 那个地方就是这样"

        let result = pipeline.clean(
            source,
            dictionary: [],
            applicationBundleIdentifier: nil
        )

        #expect(result == source)
    }

    @Test("Applies global and matching application dictionary entries")
    func appliesScopedDictionaryEntries() {
        let dictionary = [
            DictionaryEntry(phrase: "type less", replacement: "Lerro"),
            DictionaryEntry(
                phrase: "code x",
                replacement: "Codex",
                applicationBundleIdentifier: "com.openai.codex"
            ),
            DictionaryEntry(
                phrase: "slack app",
                replacement: "Slack",
                applicationBundleIdentifier: "com.tinyspeck.slackmacgap"
            )
        ]

        let result = pipeline.clean(
            "TYPE LESS code x slack app",
            dictionary: dictionary,
            applicationBundleIdentifier: "com.openai.codex"
        )

        #expect(result == "Lerro Codex slack app")
    }

    @Test("Leaves application-scoped entries untouched for another application")
    func excludesDictionaryEntriesFromAnotherApplication() {
        let dictionary = [
            DictionaryEntry(
                phrase: "code x",
                replacement: "Codex",
                applicationBundleIdentifier: "com.openai.codex"
            )
        ]

        let result = pipeline.clean(
            "code x",
            dictionary: dictionary,
            applicationBundleIdentifier: "com.apple.TextEdit"
        )

        #expect(result == "code x")
    }

    @Test("Dictionary replacement respects Latin word boundaries and literal replacement text")
    func dictionaryReplacementDoesNotChangeSubstrings() {
        let dictionary = [
            DictionaryEntry(phrase: "cat", replacement: "$1-cat")
        ]

        let result = pipeline.clean(
            "cat concatenate bobcat CAT",
            dictionary: dictionary,
            applicationBundleIdentifier: nil
        )

        #expect(result == "$1-cat concatenate bobcat $1-cat")
    }
}
