import CoreGraphics
import Testing
import LerroCore
@testable import Lerro

@Suite("Capture HUD visual state")
struct CaptureHUDVisualStateTests {
    @Test("Hold preparation stays visible over the previous capture phase")
    func holdPreparationIsVisibleAsWaiting() {
        for phase in [CapturePhase.idle, .success, .failed, .cancelled] {
            #expect(CaptureHUDVisualState.resolve(
                phase: phase,
                isStartingCapture: true,
                isHandsFreeCapture: false
            ) == .waiting)
        }
    }

    @Test("Toggle preparation opens directly into the final hands-free shell")
    func togglePreparationUsesHandsFreeShell() {
        for phase in [CapturePhase.idle, .success, .failed, .cancelled] {
            #expect(CaptureHUDVisualState.resolve(
                phase: phase,
                isStartingCapture: true,
                isHandsFreeCapture: true
            ) == .handsFree)
        }
    }

    @Test("Listening keeps the waveform for hold and hands-free capture")
    func listeningUsesWaveformStates() {
        #expect(CaptureHUDVisualState.resolve(
            phase: .listening,
            isStartingCapture: false,
            isHandsFreeCapture: false
        ) == .listening)
        #expect(CaptureHUDVisualState.resolve(
            phase: .listening,
            isStartingCapture: false,
            isHandsFreeCapture: true
        ) == .handsFree)
    }

    @Test("Every asynchronous completion phase uses processing")
    func completionPhasesUseProcessing() {
        for phase in [CapturePhase.transcribing, .enhancing, .inserting] {
            #expect(CaptureHUDVisualState.resolve(
                phase: phase,
                isStartingCapture: false,
                isHandsFreeCapture: false
            ) == .processing)
        }
    }

    @Test("Completion and cancellation are visually hidden immediately")
    func terminalSuccessStatesAreHidden() {
        for phase in [CapturePhase.success, .cancelled] {
            #expect(CaptureHUDVisualState.resolve(
                phase: phase,
                isStartingCapture: false,
                isHandsFreeCapture: false
            ) == .idleHidden)
        }
        #expect(CaptureHUDVisualState.resolve(
            phase: .inserting,
            isStartingCapture: false,
            isHandsFreeCapture: true,
            isSuppressed: true
        ) == .idleHidden)
    }

    @Test("Delivery receipt replaces the idle shell with an interactive card")
    func deliveryReceiptIsVisible() {
        #expect(CaptureHUDVisualState.resolve(
            phase: .idle,
            isStartingCapture: false,
            isHandsFreeCapture: false,
            hasDeliveryReceipt: true
        ) == .receipt)
        #expect(CaptureHUDVisualState.receipt.size == CGSize(width: 430, height: 68))
        #expect(CaptureHUDAnnouncement.message(
            from: .processing,
            to: .receipt,
            phase: .idle,
            mode: .dictation
        ) == "文本已写入，可以撤回、修正或继续说一句修改")
    }

    @Test("Interaction bounds preserve the minimum discoverability target")
    func interactionBoundsMatchPresentation() {
        #expect(CaptureHUDVisualState.idleHidden.interactionSize(countdownVisible: false)
            == CGSize(width: 70, height: 34))
        #expect(CaptureHUDVisualState.listening.interactionSize(countdownVisible: false)
            == CGSize(width: 70, height: 34))
        #expect(CaptureHUDVisualState.processing.size == CGSize(width: 70, height: 34))
        #expect(CaptureHUDVisualState.processing.interactionSize(countdownVisible: false)
            == CGSize(width: 70, height: 34))
        #expect(CaptureHUDVisualState.handsFree.interactionSize(countdownVisible: false)
            == CGSize(width: 116, height: 34))
        #expect(CaptureHUDVisualState.handsFree.interactionSize(countdownVisible: true)
            == CGSize(width: 156, height: 34))
    }

    @Test("Cancelling during processing announces cancellation")
    func processingCancellationAnnouncementIsAccurate() {
        #expect(CaptureHUDAnnouncement.message(
            from: .processing,
            to: .idleHidden,
            phase: .cancelled,
            mode: .dictation
        ) == "听写已取消")
        #expect(CaptureHUDAnnouncement.message(
            from: .processing,
            to: .idleHidden,
            phase: .idle,
            mode: .dictation
        ) == "听写完成")
    }

    @Test("Capture errors stay inside the HUD announcement channel")
    func captureErrorAnnouncementUsesItsSpecificMessage() {
        #expect(CaptureHUDAnnouncement.message(
            from: .processing,
            to: .error,
            phase: .failed,
            mode: .dictation,
            errorMessage: "没有识别到语音"
        ) == "没有识别到语音")
    }

    @Test("Toggle preparation announces the accepted locked state accurately")
    func togglePreparationAnnouncementIsAccurate() {
        #expect(CaptureHUDAnnouncement.message(
            from: .idleHidden,
            to: .handsFree,
            phase: .idle,
            mode: .dictation,
            isStartingCapture: true
        ) == "已锁定，正在准备麦克风")
    }

    @Test("Processing pulse advances one visible leading dot at a time")
    func processingPulseAdvancesAcrossDots() {
        let first = HUDProcessingPulse(elapsed: 0, reduceMotion: false)
        let second = HUDProcessingPulse(
            elapsed: HUDProcessingPulse.cycleDuration / 3,
            reduceMotion: false
        )
        let third = HUDProcessingPulse(
            elapsed: HUDProcessingPulse.cycleDuration * 2 / 3,
            reduceMotion: false
        )

        #expect(first.energies.count == HUDProcessingPulse.dotCount)
        #expect(first.energies[0] > 0.999)
        #expect(second.energies[1] > 0.999)
        #expect(third.energies[2] > 0.999)
    }

    @Test("Reduced Motion keeps the processing indicator stable")
    func reducedMotionProcessingPulseIsStable() {
        let first = HUDProcessingPulse(elapsed: 0, reduceMotion: true)
        let later = HUDProcessingPulse(elapsed: 42, reduceMotion: true)

        #expect(first == later)
        #expect(first.energies == [0.18, 1, 0.18])
    }

    @Test("Processing dots use the system accent without changing pulse behavior")
    func processingIndicatorUsesSystemAccent() {
        #expect(HUDProcessingIndicatorStyle.usesSystemAccent)
        #expect(HUDProcessingPulse.dotCount == 3)
        #expect(HUDProcessingPulse.cycleDuration == 0.72)
    }

    @Test("Completion phases keep one processing presentation until commit suppression")
    func processingPresentationIsContinuousUntilCommit() {
        for phase in [CapturePhase.transcribing, .enhancing, .inserting] {
            #expect(CaptureHUDVisualState.resolve(
                phase: phase,
                isStartingCapture: false,
                isHandsFreeCapture: true
            ) == .processing)
        }

        #expect(CaptureHUDVisualState.resolve(
            phase: .inserting,
            isStartingCapture: false,
            isHandsFreeCapture: true,
            isSuppressed: true
        ) == .idleHidden)
    }

    @Test("Listening waveform separates room tone from speech")
    func listeningWaveformHasClearDynamicRange() {
        var quiet = HUDWaveformResponse(seed: 1)
        quiet.advance(level: 0.2, mode: .listening, reduceMotion: false)
        var speech = HUDWaveformResponse(seed: 1)
        speech.advance(level: 0.5, mode: .listening, reduceMotion: false)
        var loudSpeech = HUDWaveformResponse(seed: 1)
        loudSpeech.advance(level: 0.72, mode: .listening, reduceMotion: false)

        #expect(maximumHeight(of: quiet) < 5)
        #expect(maximumHeight(of: speech) > 14)
        #expect(maximumHeight(of: loudSpeech) == HUDWaveformResponse.maximumBarHeight)
    }

    @Test("Speech pulses migrate instead of preserving a fixed bar ranking")
    func listeningWaveformMovesItsPeak() {
        var response = HUDWaveformResponse(seed: 42)
        var peakIndices = Set<Int>()

        for _ in 0..<20 {
            response.advance(level: 0.56, mode: .listening, reduceMotion: false)
            if let peak = response.normalizedBars.enumerated().max(by: {
                $0.element < $1.element
            })?.offset {
                peakIndices.insert(peak)
            }
        }

        #expect(peakIndices.count >= 4)
    }

    @Test("Waveform response is deterministic for a captured seed and audio stream")
    func listeningWaveformCanBeReproduced() {
        var first = HUDWaveformResponse(seed: 0xC0FFEE)
        var second = HUDWaveformResponse(seed: 0xC0FFEE)
        let levels: [Float] = [0.18, 0.47, 0.61, 0.36, 0.2, 0.54]

        for level in levels {
            first.advance(level: level, mode: .listening, reduceMotion: false)
            second.advance(level: level, mode: .listening, reduceMotion: false)
        }

        #expect(first == second)
    }

    @Test("Room tone settles a speech pulse back to baseline")
    func listeningWaveformReleasesQuickly() {
        var response = HUDWaveformResponse(seed: 7)
        response.advance(level: 0.72, mode: .listening, reduceMotion: false)
        let speechHeight = maximumHeight(of: response)

        for _ in 0..<8 {
            response.advance(level: 0.16, mode: .listening, reduceMotion: false)
        }

        #expect(speechHeight == HUDWaveformResponse.maximumBarHeight)
        #expect(maximumHeight(of: response) < 5)
    }

    @Test("Hands-free preparation keeps a quiet static waveform until audio is ready")
    func armingWaveformIsStableAndQuiet() {
        var response = HUDWaveformResponse(seed: 9)
        let samples = (0..<4).map { _ in
            response.advance(level: 0.8, mode: .arming, reduceMotion: false)
            return response.normalizedBars
        }

        #expect(samples.allSatisfy { bars in bars.allSatisfy { $0 == 0 } })
    }

    @Test("Reduced Motion keeps distinct quiet and speech levels")
    func reducedMotionWaveformUsesStableEnergyBands() {
        var quiet = HUDWaveformResponse(seed: 11)
        quiet.advance(level: 0.2, mode: .listening, reduceMotion: true)
        var speech = HUDWaveformResponse(seed: 12)
        speech.advance(level: 0.6, mode: .listening, reduceMotion: true)
        let stableSpeechBars = speech.normalizedBars
        speech.advance(level: 0.6, mode: .listening, reduceMotion: true)

        #expect(maximumHeight(of: quiet) < 5)
        #expect(maximumHeight(of: speech) == HUDWaveformResponse.maximumBarHeight)
        #expect(speech.normalizedBars == stableSpeechBars)
    }

    private func maximumHeight(of response: HUDWaveformResponse) -> CGFloat {
        response.normalizedBars.indices.map(response.barHeight(at:)).max()
            ?? HUDWaveformResponse.minimumBarHeight
    }
}
