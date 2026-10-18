import Testing
@testable import LerroCore

@Suite("Text diff")
struct TextDiffTests {
    private func segment(_ kind: TextDiff.Segment.Kind, _ text: String) -> TextDiff.Segment {
        TextDiff.Segment(kind: kind, text: text)
    }

    @Test("Identical strings produce one unchanged segment")
    func identical() {
        #expect(TextDiff.segments(from: "hello world", to: "hello world") == [segment(.same, "hello world")])
    }

    @Test("Pure insertion")
    func insertion() {
        #expect(
            TextDiff.segments(from: "hello world", to: "hello, world") == [
                segment(.same, "hello"),
                segment(.inserted, ","),
                segment(.same, " world")
            ]
        )
    }

    @Test("Pure deletion")
    func deletion() {
        #expect(
            TextDiff.segments(from: "hello, world", to: "hello world") == [
                segment(.same, "hello"),
                segment(.removed, ","),
                segment(.same, " world")
            ]
        )
    }

    @Test("Chinese filler words are removed and punctuation is inserted")
    func chineseFillerWords() {
        let raw = "嗯那个明天下午三点呃把新版那个发布清单发给设计工程团队"
        let final = "明天下午三点把新版发布清单发给设计和工程团队。"
        #expect(
            TextDiff.segments(from: raw, to: final) == [
                segment(.removed, "嗯那个"),
                segment(.same, "明天下午三点"),
                segment(.removed, "呃"),
                segment(.same, "把新版"),
                segment(.removed, "那个"),
                segment(.same, "发布清单发给设计"),
                segment(.inserted, "和"),
                segment(.same, "工程团队"),
                segment(.inserted, "。")
            ]
        )
    }

    @Test("Replacement lists the removed text before the inserted text")
    func replacement() {
        #expect(
            TextDiff.segments(from: "abc", to: "xyz") == [
                segment(.removed, "abc"),
                segment(.inserted, "xyz")
            ]
        )
    }

    @Test("Empty inputs")
    func emptyInputs() {
        #expect(TextDiff.segments(from: "", to: "").isEmpty)
        #expect(TextDiff.segments(from: "", to: "新增") == [segment(.inserted, "新增")])
        #expect(TextDiff.segments(from: "删除", to: "") == [segment(.removed, "删除")])
    }

    @Test("Grapheme clusters stay whole")
    func graphemeClusters() {
        #expect(
            TextDiff.segments(from: "a👨‍👩‍👧b", to: "ab") == [
                segment(.same, "a"),
                segment(.removed, "👨‍👩‍👧"),
                segment(.same, "b")
            ]
        )
    }

    @Test("Two long inputs skip the alignment")
    func longInputCap() {
        let old = String(repeating: "a", count: 2001)
        let new = String(repeating: "a", count: 2000) + "b"
        #expect(
            TextDiff.segments(from: old, to: new) == [
                segment(.removed, old),
                segment(.inserted, new)
            ]
        )
    }

    @Test("A long input against a short one is still aligned")
    func longAgainstShort() {
        let long = String(repeating: "a", count: 3000)
        let result = TextDiff.segments(from: long, to: "aa")
        #expect(result == [segment(.same, "aa"), segment(.removed, String(repeating: "a", count: 2998))])
    }
}
