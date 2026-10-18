import Testing
@testable import LerroCore

@Suite("Correction hunks")
struct CorrectionHunksTests {
    @Test("A substitution inside a sentence keeps its context from the final text")
    func substitution() {
        let hunks = CorrectionHunkExtractor.hunks(
            raw: "我昨天做了史册，结果不错",
            final: "我昨天做了实测，结果不错"
        )
        #expect(hunks == [
            CorrectionHunk(
                original: "史册",
                corrected: "实测",
                contextBefore: "我昨天做了",
                contextAfter: "，结果不错"
            )
        ])
    }

    @Test("Pure deletions are dropped")
    func deletion() {
        #expect(CorrectionHunkExtractor.hunks(raw: "然后我去开会", final: "我去开会").isEmpty)
    }

    @Test("Pure insertions are dropped")
    func insertion() {
        #expect(CorrectionHunkExtractor.hunks(raw: "我去开会", final: "我去开会吧").isEmpty)
    }

    @Test("Function word swaps are dropped")
    func functionWordSwap() {
        #expect(CorrectionHunkExtractor.hunks(raw: "他做的很好", final: "他做得很好").isEmpty)
    }

    @Test("Punctuation-only changes are dropped")
    func punctuationOnly() {
        #expect(CorrectionHunkExtractor.hunks(raw: "你好,世界", final: "你好，世界").isEmpty)
    }

    @Test("Case-only changes are dropped")
    func caseOnly() {
        #expect(CorrectionHunkExtractor.hunks(raw: "我用iphone", final: "我用iPhone").isEmpty)
    }

    @Test("Sides longer than the limit are dropped and sides at the limit are kept")
    func sideLength() {
        let limit = CorrectionHunkExtractor.maximumSideCharacters
        let over = CorrectionHunkExtractor.hunks(
            raw: "前" + String(repeating: "甲", count: limit + 1) + "后",
            final: "前" + String(repeating: "乙", count: limit + 1) + "后"
        )
        #expect(over.isEmpty)
        let atLimit = CorrectionHunkExtractor.hunks(
            raw: "前" + String(repeating: "甲", count: limit) + "后",
            final: "前" + String(repeating: "乙", count: limit) + "后"
        )
        #expect(atLimit.count == 1)
    }

    @Test("Several substitutions in one sentence produce one hunk each")
    func multipleHunks() {
        let hunks = CorrectionHunkExtractor.hunks(raw: "史册显示糊涂涨了", final: "实测显示富途涨了")
        #expect(hunks.map(\.original) == ["史册", "糊涂"])
        #expect(hunks.map(\.corrected) == ["实测", "富途"])
        #expect(hunks[0].contextBefore == "")
        #expect(hunks[0].contextAfter == "显示富途涨了")
        #expect(hunks[1].contextBefore == "实测显示")
        #expect(hunks[1].contextAfter == "涨了")
    }

    @Test("Context is limited to 40 characters of the final text")
    func contextLimit() {
        let limit = CorrectionHunkExtractor.contextCharacters
        let hunks = CorrectionHunkExtractor.hunks(
            raw: String(repeating: "甲", count: 50) + "史册" + String(repeating: "乙", count: 50),
            final: String(repeating: "甲", count: 50) + "实测" + String(repeating: "乙", count: 50)
        )
        #expect(hunks.count == 1)
        #expect(hunks[0].contextBefore == String(repeating: "甲", count: limit))
        #expect(hunks[0].contextAfter == String(repeating: "乙", count: limit))
    }
}
