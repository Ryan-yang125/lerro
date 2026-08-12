import Foundation
import Testing
import LerroCore
@testable import LerroMac

@Suite("Apple speech endpointing")
struct AppleSpeechServiceTests {
    @Test("Quick Dictate waits for speech before starting its silence window")
    func waitsForSpeechBeforeSilence() {
        var tracker = SpeechEndpointTracker()

        #expect(tracker.observe(speechDetected: false) == .none)
        #expect(tracker.markSilenceElapsed() == false)
        #expect(tracker.observe(speechDetected: true) == .speechStarted)
        #expect(tracker.observe(speechDetected: true) == .none)
        #expect(tracker.observe(speechDetected: false) == .silenceBegan)
        #expect(tracker.observe(speechDetected: false) == .none)
        let firstSilenceElapsed = tracker.markSilenceElapsed()
        #expect(firstSilenceElapsed)
        #expect(tracker.markSilenceElapsed() == false)
        #expect(tracker.observe(speechDetected: true) == .none)
    }

    @Test("Speech resuming cancels the pending silence endpoint")
    func resumedSpeechCancelsPendingEndpoint() {
        var tracker = SpeechEndpointTracker()

        #expect(tracker.observe(speechDetected: true) == .speechStarted)
        #expect(tracker.observe(speechDetected: false) == .silenceBegan)
        #expect(tracker.observe(speechDetected: true) == .speechResumed)
        #expect(tracker.markSilenceElapsed() == false)
        #expect(tracker.observe(speechDetected: false) == .silenceBegan)
        let resumedSilenceElapsed = tracker.markSilenceElapsed()
        #expect(resumedSilenceElapsed)
    }

    @Test("A new session gets a fresh speech endpoint lifecycle")
    func resetStartsFreshEndpointLifecycle() {
        var tracker = SpeechEndpointTracker()
        #expect(tracker.observe(speechDetected: true) == .speechStarted)
        #expect(tracker.observe(speechDetected: false) == .silenceBegan)
        let firstSilenceElapsed = tracker.markSilenceElapsed()
        #expect(firstSilenceElapsed)

        tracker.reset()

        #expect(tracker.hasDetectedSpeech == false)
        #expect(tracker.isSpeechActive == false)
        #expect(tracker.hasEmittedSilenceElapsed == false)
        #expect(tracker.observe(speechDetected: true) == .speechStarted)
    }

    @Test("Quick Dictate uses a 1.2 second silence window")
    func silenceWindowDuration() {
        #expect(AppleSpeechService.quickDictateSilenceDuration == .milliseconds(1_200))
    }

    @Test("Speech vocabulary prefers standard replacements, priority, and a 100 phrase cap")
    func contextualVocabularyIsBoundedAndStable() {
        var terms = (0..<105).map {
            SpeechVocabularyTerm(phrase: "spoken-\($0)", replacement: "term-\($0)", priority: $0)
        }
        terms.append(SpeechVocabularyTerm(phrase: "duplicate", replacement: "TERM-104", priority: 999))
        terms.append(SpeechVocabularyTerm(phrase: "blank", replacement: "   ", priority: 998))

        let strings = speechContextualStrings(from: terms)

        #expect(strings.count == 100)
        #expect(strings.first == "TERM-104")
        #expect(strings.dropFirst().first == "blank")
        #expect(strings.filter { $0.lowercased() == "term-104" }.count == 1)
        #expect(strings.contains("spoken-103") == false)
    }

    @Test("Speech vocabulary ignores empty entries and preserves equal-priority order")
    func contextualVocabularyFiltersAndDeduplicates() {
        let terms = [
            SpeechVocabularyTerm(phrase: "  Lerro  ", replacement: "", priority: 1),
            SpeechVocabularyTerm(phrase: "second", replacement: "Codex", priority: 1),
            SpeechVocabularyTerm(phrase: "duplicate", replacement: "lerro", priority: 1),
            SpeechVocabularyTerm(phrase: " ", replacement: " ", priority: 5),
        ]

        #expect(speechContextualStrings(from: terms) == ["Lerro", "Codex"])
        #expect(speechContextualStrings(from: terms, limit: 0).isEmpty)
    }
}
