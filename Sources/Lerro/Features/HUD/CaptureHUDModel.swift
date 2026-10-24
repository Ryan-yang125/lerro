import Foundation
import LerroCore

/// One HUD capsule morphs between these states. `AppSession` owns the inputs;
/// `CaptureHUDView` owns the presentation of each state.
enum CaptureHUDVisualState: Equatable {
    case idleHidden
    /// Shortcut pressed; the microphone is not ready yet.
    case arming
    /// Recording. Live text, silence warning and the hands-free hint are
    /// sub-presentations of this state.
    case listening
    /// Recording finished and the text is being transcribed, processed by AI
    /// or delivered. Raw dictation keeps the recording look in this state.
    case processing
    case deliveredRawFallback
    case error
    case recovery
    case dictionaryLearned

    static func resolve(
        phase: CapturePhase,
        isStartingCapture: Bool,
        deliveryFeedback: HUDDeliveryFeedback?,
        hasRecoveryPresentation: Bool,
        hasDictionaryLearningToast: Bool
    ) -> Self {
        if isStartingCapture { return .arming }
        switch phase {
        case .listening:
            return .listening
        case .transcribing, .enhancing, .inserting:
            return deliveryFeedback?.visualState ?? .processing
        case .idle, .success, .failed, .cancelled:
            break
        }
        if let state = deliveryFeedback?.visualState, state != .idleHidden { return state }
        if hasRecoveryPresentation { return .recovery }
        if hasDictionaryLearningToast { return .dictionaryLearned }
        if phase == .failed { return .error }
        return .idleHidden
    }

    /// States with a control the pointer can reach.
    var acceptsPointer: Bool {
        switch self {
        case .processing, .error, .recovery, .dictionaryLearned, .listening: true
        case .idleHidden, .arming, .deliveredRawFallback: false
        }
    }
}

/// Set at the Command-V commit point. While the phase is still `.inserting`
/// it hides the capsule instead of letting it fall back to the processing look.
enum HUDDeliveryFeedback: Equatable {
    /// The capsule fades out immediately.
    case delivered
    /// AI processing failed and the raw Apple Speech transcript was written.
    case deliveredRawFallback

    var visualState: CaptureHUDVisualState {
        switch self {
        case .delivered: .idleHidden
        case .deliveredRawFallback: .deliveredRawFallback
        }
    }

    /// How long the notice stays before it clears; `nil` keeps the feedback
    /// until the next capture starts or the capture is cancelled.
    var displayDuration: Duration? {
        switch self {
        case .delivered: nil
        case .deliveredRawFallback: .seconds(2)
        }
    }
}

enum CaptureHUDAnnouncement {
    static func message(
        from previous: CaptureHUDVisualState,
        to current: CaptureHUDVisualState,
        mode: CaptureMode,
        phase: CapturePhase,
        errorMessage: String? = nil
    ) -> String? {
        switch current {
        case .arming: "正在准备麦克风"
        case .listening where previous != .listening:
            switch mode {
            case .dictation: "正在听写"
            case .translation: "正在翻译"
            }
        case .listening: nil
        case .processing:
            switch mode {
            case .dictation: "正在处理听写"
            case .translation: "正在翻译"
            }
        case .deliveredRawFallback: "AI 未响应，已写入原文"
        case .error: errorMessage ?? "听写失败，可以重试"
        case .recovery: "写入失败，内容已复制到剪贴板"
        case .dictionaryLearned: "已将修正加入词典"
        case .idleHidden where phase == .cancelled: "听写已取消"
        case .idleHidden where previous == .processing: "已写入"
        case .idleHidden: nil
        }
    }
}
