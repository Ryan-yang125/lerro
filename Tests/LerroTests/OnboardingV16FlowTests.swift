import Testing
@testable import Lerro

@Suite("V1.6 onboarding flow")
struct OnboardingV16FlowTests {
    @Test("Onboarding contains eight task steps in product order")
    func taskStepsAreOrdered() {
        #expect(OnboardingStep.allCases == [
            .privacy,
            .speech,
            .ai,
            .shortcut,
            .dictation,
            .recovery,
            .dictionary,
            .tone
        ])
    }

    @Test("Every step has one concise action title and icon")
    func stepPresentationIsComplete() {
        for step in OnboardingStep.allCases {
            #expect(!step.title.isEmpty)
            #expect(!step.shortTitle.isEmpty)
            #expect(!step.icon.isEmpty)
        }
    }
}
