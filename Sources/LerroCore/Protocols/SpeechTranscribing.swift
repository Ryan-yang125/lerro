import Foundation

public protocol SpeechTranscribing: Sendable {
    func availableInputDevices() async -> [AudioInputDevice]
    func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        muteOtherAudio: Bool,
        saveAudio: Bool,
        detectSpeechEndpoint: Bool,
        milestones: @escaping CaptureMilestoneReporter
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error>
    func stop() async throws -> SpeechTranscription
    func cancel() async
    func resourceStatus(localeIdentifier: String) async -> LanguageResourceStatus
    func prepareResources(localeIdentifier: String) async throws -> LanguageResourceStatus
    /// Builds the audio input ahead of a capture without starting the
    /// microphone, so the next `start` opens it sooner.
    func prewarmAudioInput(microphoneDeviceUID: String?) async
}

public extension SpeechTranscribing {
    func prewarmAudioInput(microphoneDeviceUID: String?) async {}

    func resourceStatus(localeIdentifier: String) async -> LanguageResourceStatus {
        LanguageResourceStatus(
            state: .ready,
            sourceLanguageIdentifier: localeIdentifier,
            message: "语音资源已准备"
        )
    }

    func prepareResources(localeIdentifier: String) async throws -> LanguageResourceStatus {
        await resourceStatus(localeIdentifier: localeIdentifier)
    }
}
