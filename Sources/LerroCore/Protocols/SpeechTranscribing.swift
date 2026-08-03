import Foundation

public protocol SpeechTranscribing: Sendable {
    func availableInputDevices() async -> [AudioInputDevice]
    func start(
        localeIdentifier: String,
        microphoneDeviceUID: String?,
        muteOtherAudio: Bool,
        saveAudio: Bool
    ) async throws -> AsyncThrowingStream<SpeechEvent, any Error>
    func stop() async throws -> SpeechTranscription
    func cancel() async
    func resourceStatus(localeIdentifier: String) async -> LanguageResourceStatus
    func prepareResources(localeIdentifier: String) async throws -> LanguageResourceStatus
}

public extension SpeechTranscribing {
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
