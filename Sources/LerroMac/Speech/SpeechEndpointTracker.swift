import Foundation

enum SpeechEndpointTransition: Equatable {
    case none
    case speechStarted
    case silenceBegan
    case speechResumed
}

struct SpeechEndpointTracker {
    private(set) var hasDetectedSpeech = false
    private(set) var isSpeechActive = false
    private(set) var hasEmittedSilenceElapsed = false

    mutating func observe(speechDetected: Bool) -> SpeechEndpointTransition {
        guard !hasEmittedSilenceElapsed else { return .none }

        if speechDetected {
            let isFirstSpeech = !hasDetectedSpeech
            let resumedAfterSilence = hasDetectedSpeech && !isSpeechActive
            hasDetectedSpeech = true
            isSpeechActive = true
            if isFirstSpeech { return .speechStarted }
            if resumedAfterSilence { return .speechResumed }
            return .none
        }

        guard hasDetectedSpeech, isSpeechActive else { return .none }
        isSpeechActive = false
        return .silenceBegan
    }

    mutating func markSilenceElapsed() -> Bool {
        guard hasDetectedSpeech,
              !isSpeechActive,
              !hasEmittedSilenceElapsed else {
            return false
        }
        hasEmittedSilenceElapsed = true
        return true
    }

    mutating func reset() {
        self = SpeechEndpointTracker()
    }
}
