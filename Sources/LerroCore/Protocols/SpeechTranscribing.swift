import Foundation

public protocol SpeechTranscribing: Sendable {
    func availableInputDevices() async -> [AudioInputDevice]
    func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        saveAudio: Bool,
        milestones: @escaping CaptureMilestoneReporter
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error>
    /// Lowers the system output audio while the current session's microphone
    /// is open. A no-op when no session is running or output is already
    /// lowered; `endAudioCapture`, `stop` and `cancel` restore it.
    func lowerOtherAudio() async
    /// Stops the microphone and restores the output audio that `lowerOtherAudio` lowered.
    /// Idempotent; `stop` calls it first, and a session can call it earlier to
    /// play a sound before the final transcript is ready.
    func endAudioCapture() async
    func stop() async throws -> SpeechTranscription
    func cancel() async
    func resourceStatus(localeIdentifier: String) async -> LanguageResourceStatus
    func prepareResources(localeIdentifier: String) async throws -> LanguageResourceStatus
    /// Builds the audio input ahead of a capture without starting the
    /// microphone, so the next `start` opens it sooner.
    func prewarmAudioInput(microphoneDeviceUID: String?) async
    /// Starts the microphone for a capture that may follow and keeps its
    /// audio in memory only. The next `start` for the same device adopts it.
    /// A no-op while a session runs, when already prearmed, or when the input
    /// is a Bluetooth device.
    func prearmMicrophone(microphoneDeviceUID: String?) async
    /// Stops a prearmed microphone and drops its audio. A no-op without one.
    func discardPrearmedMicrophone() async
}

public extension SpeechTranscribing {
    func prewarmAudioInput(microphoneDeviceUID: String?) async {}
    func prearmMicrophone(microphoneDeviceUID: String?) async {}
    func discardPrearmedMicrophone() async {}

    func resourceStatus(localeIdentifier: String) async -> LanguageResourceStatus {
        LanguageResourceStatus(
            state: .ready,
            sourceLanguageIdentifier: localeIdentifier,
            message: "语音资源已就绪"
        )
    }

    func prepareResources(localeIdentifier: String) async throws -> LanguageResourceStatus {
        await resourceStatus(localeIdentifier: localeIdentifier)
    }
}
