import Foundation
import Testing
import LerroCore
@testable import Lerro

@Suite("Capture HUD model")
struct CaptureHUDModelTests {
    private func resolve(
        _ phase: CapturePhase,
        isStarting: Bool = false,
        feedback: HUDDeliveryFeedback? = nil,
        recovery: Bool = false,
        toast: Bool = false
    ) -> CaptureHUDVisualState {
        CaptureHUDVisualState.resolve(
            phase: phase,
            isStartingCapture: isStarting,
            deliveryFeedback: feedback,
            hasRecoveryPresentation: recovery,
            hasDictionaryLearningToast: toast
        )
    }

    @Test("Starting capture always resolves to arming")
    func startingCaptureIsArming() {
        let phases: [CapturePhase] = [
            .idle, .listening, .transcribing, .enhancing, .inserting, .success, .failed, .cancelled
        ]
        for phase in phases {
            #expect(resolve(
                phase,
                isStarting: true,
                feedback: .delivered,
                recovery: true,
                toast: true
            ) == .arming)
        }
    }

    @Test("Listening outranks feedback, recovery and toast")
    func listeningOutranksOverlays() {
        #expect(resolve(.listening) == .listening)
        #expect(resolve(
            .listening,
            feedback: .deliveredRawFallback,
            recovery: true,
            toast: true
        ) == .listening)
    }

    @Test("Processing phases show processing or the delivery feedback")
    func processingPhases() {
        for phase in [CapturePhase.transcribing, .enhancing, .inserting] {
            #expect(resolve(phase) == .processing)
            #expect(resolve(phase, recovery: true, toast: true) == .processing)
            #expect(resolve(phase, feedback: .delivered) == .idleHidden)
            #expect(resolve(phase, feedback: .delivered, recovery: true, toast: true) == .idleHidden)
            #expect(resolve(phase, feedback: .deliveredRawFallback) == .deliveredRawFallback)
        }
    }

    @Test("Resting phases prefer feedback, then recovery, then toast")
    func restingPhasePriority() {
        for phase in [CapturePhase.idle, .success] {
            #expect(resolve(phase, feedback: .delivered) == .idleHidden)
            #expect(resolve(phase, feedback: .delivered, recovery: true, toast: true) == .recovery)
            #expect(resolve(phase, feedback: .delivered, toast: true) == .dictionaryLearned)
            #expect(resolve(phase, feedback: .deliveredRawFallback) == .deliveredRawFallback)
            #expect(resolve(phase, recovery: true, toast: true) == .recovery)
            #expect(resolve(phase, toast: true) == .dictionaryLearned)
            #expect(resolve(phase) == .idleHidden)
        }
        #expect(resolve(.failed, recovery: true) == .recovery)
        #expect(resolve(.failed, toast: true) == .dictionaryLearned)
        #expect(resolve(.failed) == .error)
        #expect(resolve(.cancelled) == .idleHidden)
    }

    @Test("Only states with a reachable control accept the pointer")
    func pointerAcceptance() {
        let accepting: [CaptureHUDVisualState] = [
            .listening, .processing, .error, .recovery, .dictionaryLearned
        ]
        let ignoring: [CaptureHUDVisualState] = [
            .idleHidden, .arming, .deliveredRawFallback
        ]
        for state in accepting { #expect(state.acceptsPointer) }
        for state in ignoring { #expect(!state.acceptsPointer) }
    }

    @Test("Delivery feedback maps to its state and display duration")
    func deliveryFeedbackMapping() {
        #expect(HUDDeliveryFeedback.delivered.visualState == .idleHidden)
        #expect(HUDDeliveryFeedback.deliveredRawFallback.visualState == .deliveredRawFallback)
        #expect(HUDDeliveryFeedback.delivered.displayDuration == nil)
        #expect(HUDDeliveryFeedback.deliveredRawFallback.displayDuration == .seconds(2))
    }
}
