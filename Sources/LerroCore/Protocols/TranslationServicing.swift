import Foundation

/// Device-local translation. Implementations must never silently route text
/// to a network provider.
public protocol TranslationServicing: Sendable {
    func resourceStatus(
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) async -> LanguageResourceStatus

    func translate(
        _ text: String,
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) async throws -> String

    func cancel() async
}

public extension TranslationServicing {
    func cancel() async {}
}
