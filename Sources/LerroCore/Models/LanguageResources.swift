import Foundation

/// A user-visible snapshot of an Apple-managed language resource.
///
/// Apple owns download progress for Speech and Translation assets.  Lerro
/// therefore reports the meaningful lifecycle states and never fabricates a
/// byte-level percentage.
public enum LanguageResourceState: String, Codable, Sendable, Equatable {
    case ready
    case available
    case downloading
    case unsupported
    case failed
}

public struct LanguageResourceStatus: Codable, Sendable, Equatable {
    public var state: LanguageResourceState
    public var sourceLanguageIdentifier: String
    public var targetLanguageIdentifier: String?
    public var message: String

    public init(
        state: LanguageResourceState,
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String? = nil,
        message: String = ""
    ) {
        self.state = state
        self.sourceLanguageIdentifier = sourceLanguageIdentifier
        self.targetLanguageIdentifier = targetLanguageIdentifier
        self.message = message
    }
}
