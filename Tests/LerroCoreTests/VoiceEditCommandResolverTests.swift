import Testing
@testable import LerroCore

@Suite("Voice follow-up edit commands")
struct VoiceEditCommandResolverTests {
    @Test("Resolves deterministic Chinese and English commands")
    func resolvesDeterministicCommands() {
        #expect(VoiceEditCommandResolver.resolve("恢复上一版。") == .deterministic(.undo))
        #expect(VoiceEditCommandResolver.resolve("删掉第二句") == .deterministic(.deleteSentence(2)))
        #expect(VoiceEditCommandResolver.resolve("Delete the third sentence.") == .deterministic(.deleteSentence(3)))
        #expect(VoiceEditCommandResolver.resolve("把名字改成 Toni") == .deterministic(
            .replaceExact(source: "名字", replacement: "Toni")
        ))
        #expect(VoiceEditCommandResolver.resolve("Replace Alice with Toni") == .deterministic(
            .replaceExact(source: "Alice", replacement: "Toni")
        ))
        #expect(VoiceEditCommandResolver.resolve("重新听写") == .deterministic(.redictate))
        #expect(VoiceEditCommandResolver.resolve("Start over") == .deterministic(.redictate))
    }

    @Test("Preserves semantic instructions and classifies common operations")
    func resolvesSemanticCommands() {
        #expect(VoiceEditCommandResolver.resolve("把刚才改短一点") == .semantic(
            SemanticVoiceEditRequest(operation: .shorten, instruction: "把刚才改短一点")
        ))
        #expect(VoiceEditCommandResolver.resolve("语气更专业") == .semantic(
            SemanticVoiceEditRequest(operation: .changeTone, instruction: "语气更专业")
        ))
        #expect(VoiceEditCommandResolver.resolve("Translate it into Japanese") == .semantic(
            SemanticVoiceEditRequest(operation: .translate, instruction: "Translate it into Japanese")
        ))
        #expect(VoiceEditCommandResolver.resolve("保留日期，调整一下顺序") == .semantic(
            SemanticVoiceEditRequest(operation: .general, instruction: "保留日期，调整一下顺序")
        ))
        #expect(VoiceEditCommandResolver.resolve("  \n") == nil)
    }

    @Test("Ignores ordinary new dictation without an explicit edit intent")
    func ignoresOrdinaryDictation() {
        #expect(VoiceEditCommandResolver.resolve("明天上午十点开会") == nil)
        #expect(VoiceEditCommandResolver.resolve("I will meet Toni tomorrow") == nil)
        #expect(VoiceEditCommandResolver.resolve("Plans change quickly") == nil)
        #expect(VoiceEditCommandResolver.resolve("Please keep the door open") == nil)
    }

    @Test("Executes exact replacement and sentence deletion locally")
    func executesLocalEdits() throws {
        #expect(try DeterministicVoiceEditor.outcome(
            for: .replaceExact(source: "Toni", replacement: "Tony"),
            currentText: "Hi Toni, Toni will join."
        ) == .replaceText("Hi Tony, Tony will join."))

        #expect(try DeterministicVoiceEditor.outcome(
            for: .deleteSentence(2),
            currentText: "第一句。第二句！第三句？"
        ) == .replaceText("第一句。第三句？"))

        #expect(try DeterministicVoiceEditor.outcome(
            for: .deleteSentence(2),
            currentText: "First sentence. Second sentence! Third sentence?"
        ) == .replaceText("First sentence. Third sentence?"))
    }

    @Test("Returns orchestration outcomes and explicit edit failures")
    func validatesExecutionBoundaries() throws {
        #expect(try DeterministicVoiceEditor.outcome(
            for: .undo,
            currentText: "Current"
        ) == .restorePreviousVersion)
        #expect(try DeterministicVoiceEditor.outcome(
            for: .redictate,
            currentText: "Current"
        ) == .beginRedictation)
        #expect(throws: DeterministicVoiceEditError.sourceTextMissing) {
            try DeterministicVoiceEditor.outcome(
                for: .replaceExact(source: "missing", replacement: "value"),
                currentText: "Current"
            )
        }
        #expect(throws: DeterministicVoiceEditError.sentenceNumberOutOfRange) {
            try DeterministicVoiceEditor.outcome(
                for: .deleteSentence(3),
                currentText: "Only one sentence."
            )
        }
        #expect(throws: DeterministicVoiceEditError.emptyResult) {
            try DeterministicVoiceEditor.outcome(
                for: .deleteSentence(1),
                currentText: "Only one sentence."
            )
        }
    }
}
