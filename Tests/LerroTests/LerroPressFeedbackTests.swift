import Testing
@testable import Lerro

@Suite("Lerro press feedback")
struct LerroPressFeedbackTests {
    @Test("Pointer down applies immediate scale and opacity feedback")
    func pressedFeedback() {
        #expect(LerroPressFeedback.scale(isPressed: true, reduceMotion: false) == 0.97)
        #expect(LerroPressFeedback.opacity(isPressed: true, isEnabled: true) == 0.82)
        #expect(LerroPressFeedback.duration == 0.09)
    }

    @Test("Reduce Motion keeps opacity feedback and disables scale")
    func reducedMotionFeedback() {
        #expect(LerroPressFeedback.scale(isPressed: true, reduceMotion: true) == 1)
        #expect(LerroPressFeedback.opacity(isPressed: true, isEnabled: true) == 0.82)
    }

    @Test("Released controls return to their resting appearance")
    func releasedFeedback() {
        #expect(LerroPressFeedback.scale(isPressed: false, reduceMotion: false) == 1)
        #expect(LerroPressFeedback.opacity(isPressed: false, isEnabled: true) == 1)
    }

    @Test("Disabled controls preserve the native dimmed state")
    func disabledFeedback() {
        #expect(LerroPressFeedback.opacity(isPressed: false, isEnabled: false) == 0.5)
        #expect(LerroPressFeedback.opacity(isPressed: true, isEnabled: false) == 0.41)
    }

    @Test("Main-window controls respond with a one-point press")
    func interactiveSurfacePressFeedback() {
        #expect(LerroInteractiveFeedback.offset(isPressed: true, reduceMotion: false) == 1)
        #expect(LerroInteractiveFeedback.opacity(isPressed: true, isEnabled: true) == 0.92)
    }

    @Test("Main-window Reduce Motion keeps opacity and removes displacement")
    func interactiveSurfaceReducedMotionFeedback() {
        #expect(LerroInteractiveFeedback.offset(isPressed: true, reduceMotion: true) == 0)
        #expect(LerroInteractiveFeedback.opacity(isPressed: true, isEnabled: true) == 0.92)
    }

    @Test("Main-window disabled controls keep a stable dimmed hierarchy")
    func interactiveSurfaceDisabledFeedback() {
        #expect(LerroInteractiveFeedback.opacity(isPressed: false, isEnabled: false) == 0.48)
        #expect(abs(
            LerroInteractiveFeedback.opacity(isPressed: true, isEnabled: false) - 0.4416
        ) < 0.000_001)
    }

    @Test("Main-window type roles stay on the four-size scale")
    func mainWindowTypographyScale() {
        let sizes = Set([
            LerroTextRole.title.size,
            LerroTextRole.heading.size,
            LerroTextRole.body.size,
            LerroTextRole.label.size,
            LerroTextRole.secondary.size,
            LerroTextRole.caption.size,
            LerroTextRole.captionMedium.size
        ])
        #expect(sizes == [12, 13, 14, 24])
        #expect(LerroTheme.uiTracking == -0.15)
    }
}
