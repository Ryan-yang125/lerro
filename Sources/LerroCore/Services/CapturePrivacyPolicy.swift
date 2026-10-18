import Foundation

public enum CapturePrivacyPolicy {
    public static func permitsCapture(in context: CapturedContext) -> Bool {
        !context.isSecureField
    }
}
