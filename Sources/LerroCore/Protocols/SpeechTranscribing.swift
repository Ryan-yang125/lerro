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
}
