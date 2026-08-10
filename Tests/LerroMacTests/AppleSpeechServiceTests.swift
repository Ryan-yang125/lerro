import Foundation
import Testing
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
}
