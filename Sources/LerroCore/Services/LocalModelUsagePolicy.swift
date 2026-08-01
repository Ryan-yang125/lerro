import Foundation

public enum LocalModelUsagePolicy {
    public static func requiresModel(
        for mode: CaptureMode,
        enhancementEnabled: Bool
    ) -> Bool {
        switch mode {
        case .dictation:
            enhancementEnabled
        case .translation, .ask:
            true
        }
    }
}

public enum CapturePrivacyPolicy {
    public static func permitsCapture(in context: CapturedContext) -> Bool {
        !context.isSecureField
    }
}
