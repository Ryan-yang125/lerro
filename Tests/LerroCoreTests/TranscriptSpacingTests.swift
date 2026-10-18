import Testing
@testable import LerroCore

@Suite("Transcript spacing")
struct TranscriptSpacingTests {
    @Test(
        "SpeechTranscriber output is normalized",
        arguments: [
            ("我刚看了一下这个 inmage to studio的这个数据。", "我刚看了一下这个 inmage to studio的这个数据。"),
            ("哦 ，我想让你从这个 system design。", "哦，我想让你从这个 system design。"),
            ("什么意思啊 ？你说英文我看不懂啊。", "什么意思啊？你说英文我看不懂啊。"),
            ("嗯 ，可以的 ，我用下来没问题 ，", "嗯，可以的，我用下来没问题，"),
            ("单只上限 25%，然后", "单只上限 25%，然后"),
            ("flag  bar flag", "flag bar flag"),
            ("  前后有空格  ", "前后有空格"),
            ("（ 测试 ）", "（测试）"),
            ("他说 「 好 」 。", "他说「好」。"),
            ("", ""),
        ]
    )
    func normalizes(input: String, expected: String) {
        #expect(TranscriptSpacing.normalize(input) == expected)
    }

    @Test("Runs of tabs and spaces collapse to one space between words")
    func collapsesMixedRuns() {
        #expect(TranscriptSpacing.normalize("hello \t world") == "hello world")
    }
}
