import SwiftUI
@preconcurrency import Translation

/// Keeps Apple's resource-confirmation UI inside SwiftUI while runtime
/// captures use the installed-resource-only TranslationSession initializer.
struct TranslationResourcePreparationHost: View {
    @Bindable var session: AppSession

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .overlay {
                if let requestID = session.translationPreparationRequestID {
                    TranslationResourcePreparationTask(
                        session: session,
                        requestID: requestID,
                        sourceLanguageIdentifier: session.translationPreparationSourceLanguageIdentifier,
                        targetLanguageIdentifier: session.translationPreparationTargetLanguageIdentifier
                    )
                    .id(requestID)
                }
            }
    }
}

private struct TranslationResourcePreparationTask: View {
    @Bindable var session: AppSession
    let requestID: UUID
    let sourceLanguageIdentifier: String
    let targetLanguageIdentifier: String
    @State private var configuration: TranslationSession.Configuration?

    init(
        session: AppSession,
        requestID: UUID,
        sourceLanguageIdentifier: String,
        targetLanguageIdentifier: String
    ) {
        self.session = session
        self.requestID = requestID
        self.sourceLanguageIdentifier = sourceLanguageIdentifier
        self.targetLanguageIdentifier = targetLanguageIdentifier
        _configuration = State(initialValue: TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceLanguageIdentifier),
            target: Locale.Language(identifier: targetLanguageIdentifier)
        ))
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { translationSession in
                do {
                    try await translationSession.prepareTranslation()
                    await MainActor.run {
                        session.completeTranslationResourcePreparation(
                            requestID: requestID,
                            errorMessage: nil
                        )
                    }
                } catch {
                    let errorMessage = error.localizedDescription
                    await MainActor.run {
                        session.completeTranslationResourcePreparation(
                            requestID: requestID,
                            errorMessage: errorMessage
                        )
                    }
                }
                configuration = nil
            }
    }
}
