import Foundation
@preconcurrency import Translation
import LerroCore

/// Traditional on-device Apple Translation. The installed initializer keeps
/// capture runs deterministic: resource acquisition is handled earlier by the
/// SwiftUI preparation host, never while a shortcut session is delivering text.
@available(macOS 26.0, *)
public actor AppleTranslationService: TranslationServicing {
    private var activeSession: (id: UUID, session: TranslationSession)?

    public init() {}

    public func resourceStatus(
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) async -> LanguageResourceStatus {
        let source = Locale.Language(identifier: sourceLanguageIdentifier)
        let target = Locale.Language(identifier: targetLanguageIdentifier)
        let availability = LanguageAvailability()
        switch await availability.status(from: source, to: target) {
        case .installed:
            return LanguageResourceStatus(
                state: .ready,
                sourceLanguageIdentifier: sourceLanguageIdentifier,
                targetLanguageIdentifier: targetLanguageIdentifier,
                message: "翻译资源已准备"
            )
        case .supported:
            return LanguageResourceStatus(
                state: .available,
                sourceLanguageIdentifier: sourceLanguageIdentifier,
                targetLanguageIdentifier: targetLanguageIdentifier,
                message: "需要准备翻译资源"
            )
        case .unsupported:
            return LanguageResourceStatus(
                state: .unsupported,
                sourceLanguageIdentifier: sourceLanguageIdentifier,
                targetLanguageIdentifier: targetLanguageIdentifier,
                message: "此语言组合暂不支持设备端翻译"
            )
        @unknown default:
            return LanguageResourceStatus(
                state: .failed,
                sourceLanguageIdentifier: sourceLanguageIdentifier,
                targetLanguageIdentifier: targetLanguageIdentifier,
                message: "翻译资源状态未知"
            )
        }
    }

    public func translate(
        _ text: String,
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LerroError.emptyTranscription }

        let status = await resourceStatus(
            sourceLanguageIdentifier: sourceLanguageIdentifier,
            targetLanguageIdentifier: targetLanguageIdentifier
        )
        guard status.state == .ready else {
            throw LerroError.translationUnavailable(status.message)
        }

        let session = TranslationSession(
            installedSource: Locale.Language(identifier: sourceLanguageIdentifier),
            target: Locale.Language(identifier: targetLanguageIdentifier)
        )
        let sessionID = UUID()
        activeSession = (id: sessionID, session: session)
        defer {
            if activeSession?.id == sessionID {
                activeSession = nil
            }
        }
        do {
            let response = try await session.translate(trimmed)
            try Task.checkCancellation()
            let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else {
                throw LerroError.translationUnavailable("Apple Translation 未返回文本")
            }
            return translated
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LerroError.translationUnavailable(error.localizedDescription)
        }
    }

    public func cancel() async {
        activeSession?.session.cancel()
        activeSession = nil
    }
}
