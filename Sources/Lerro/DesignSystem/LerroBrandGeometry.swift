import SwiftUI

/// Lerro mark and wordmark geometry, matching Brand/source/logo. Brand units,
/// origin at the top-left, y grows downward.
enum LerroBrandGeometry {
    /// A cursor standing on a baseline with a gap between them.
    static let markSize = CGSize(width: 36, height: 61)
    /// Corner radius is half the width.
    static let cursor = CGRect(x: 0, y: 0, width: 10, height: 46)
    /// Corner radius is half the height.
    static let baseline = CGRect(x: 0, y: 52, width: 36, height: 9)

    /// The mark at the origin followed by the outlined letters "erro".
    static let wordmarkSize = CGSize(width: 162.7, height: 61)
    /// Outlined "erro" in wordmark coordinates, set in Inter SemiBold (SIL OFL).
    static let erro: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 57.7, y: 61.86))
        p.addCurve(to: CGPoint(x: 75, y: 49.32), control1: CGPoint(x: 66.55, y: 61.86), control2: CGPoint(x: 73.57, y: 56.74))
        p.addLine(to: CGPoint(x: 66.55, y: 49.32))
        p.addCurve(to: CGPoint(x: 57.92, y: 54.73), control1: CGPoint(x: 65.51, y: 52.55), control2: CGPoint(x: 62.46, y: 54.73))
        p.addCurve(to: CGPoint(x: 48.1, y: 44.45), control1: CGPoint(x: 51.83, y: 54.73), control2: CGPoint(x: 48.32, y: 50.61))
        p.addLine(to: CGPoint(x: 75.46, y: 44.45))
        p.addLine(to: CGPoint(x: 75.46, y: 41.98))
        p.addCurve(to: CGPoint(x: 57.34, y: 22.32), control1: CGPoint(x: 75.46, y: 30.38), control2: CGPoint(x: 68.23, y: 22.32))
        p.addCurve(to: CGPoint(x: 39.26, y: 42.13), control1: CGPoint(x: 46.74, y: 22.32), control2: CGPoint(x: 39.26, y: 30.63))
        p.addCurve(to: CGPoint(x: 57.7, y: 61.86), control1: CGPoint(x: 39.26, y: 53.59), control2: CGPoint(x: 46.35, y: 61.86))
        p.closeSubpath()
        p.move(to: CGPoint(x: 48.17, y: 38.22))
        p.addCurve(to: CGPoint(x: 57.49, y: 29.48), control1: CGPoint(x: 48.78, y: 32.81), control2: CGPoint(x: 52.26, y: 29.48))
        p.addCurve(to: CGPoint(x: 66.8, y: 38.22), control1: CGPoint(x: 62.71, y: 29.48), control2: CGPoint(x: 66.22, y: 32.81))
        p.closeSubpath()
        p.move(to: CGPoint(x: 79.39, y: 61))
        p.addLine(to: CGPoint(x: 88.41, y: 61))
        p.addLine(to: CGPoint(x: 88.41, y: 39.58))
        p.addCurve(to: CGPoint(x: 96.04, y: 30.7), control1: CGPoint(x: 88.41, y: 33.67), control2: CGPoint(x: 91.74, y: 30.7))
        p.addCurve(to: CGPoint(x: 100.3, y: 30.99), control1: CGPoint(x: 97.83, y: 30.7), control2: CGPoint(x: 99.62, y: 30.88))
        p.addLine(to: CGPoint(x: 100.3, y: 22.97))
        p.addCurve(to: CGPoint(x: 97.37, y: 22.82), control1: CGPoint(x: 99.59, y: 22.89), control2: CGPoint(x: 98.58, y: 22.82))
        p.addCurve(to: CGPoint(x: 88.2, y: 29.45), control1: CGPoint(x: 92.5, y: 22.82), control2: CGPoint(x: 89.6, y: 25.11))
        p.addLine(to: CGPoint(x: 88.09, y: 29.45))
        p.addLine(to: CGPoint(x: 88.09, y: 23.18))
        p.addLine(to: CGPoint(x: 79.39, y: 23.18))
        p.closeSubpath()
        p.move(to: CGPoint(x: 103.69, y: 61))
        p.addLine(to: CGPoint(x: 112.72, y: 61))
        p.addLine(to: CGPoint(x: 112.72, y: 39.58))
        p.addCurve(to: CGPoint(x: 120.34, y: 30.7), control1: CGPoint(x: 112.72, y: 33.67), control2: CGPoint(x: 116.05, y: 30.7))
        p.addCurve(to: CGPoint(x: 124.61, y: 30.99), control1: CGPoint(x: 122.14, y: 30.7), control2: CGPoint(x: 123.93, y: 30.88))
        p.addLine(to: CGPoint(x: 124.61, y: 22.97))
        p.addCurve(to: CGPoint(x: 121.67, y: 22.82), control1: CGPoint(x: 123.89, y: 22.89), control2: CGPoint(x: 122.89, y: 22.82))
        p.addCurve(to: CGPoint(x: 112.5, y: 29.45), control1: CGPoint(x: 116.8, y: 22.82), control2: CGPoint(x: 113.9, y: 25.11))
        p.addLine(to: CGPoint(x: 112.39, y: 29.45))
        p.addLine(to: CGPoint(x: 112.39, y: 23.18))
        p.addLine(to: CGPoint(x: 103.69, y: 23.18))
        p.closeSubpath()
        p.move(to: CGPoint(x: 144.04, y: 61.86))
        p.addCurve(to: CGPoint(x: 162.7, y: 42.13), control1: CGPoint(x: 155.18, y: 61.86), control2: CGPoint(x: 162.7, y: 53.87))
        p.addCurve(to: CGPoint(x: 144.04, y: 22.32), control1: CGPoint(x: 162.7, y: 30.38), control2: CGPoint(x: 155.18, y: 22.32))
        p.addCurve(to: CGPoint(x: 125.38, y: 42.13), control1: CGPoint(x: 132.9, y: 22.32), control2: CGPoint(x: 125.38, y: 30.38))
        p.addCurve(to: CGPoint(x: 144.04, y: 61.86), control1: CGPoint(x: 125.38, y: 53.87), control2: CGPoint(x: 132.9, y: 61.86))
        p.closeSubpath()
        p.move(to: CGPoint(x: 144.04, y: 54.3))
        p.addCurve(to: CGPoint(x: 134.51, y: 42.13), control1: CGPoint(x: 138.2, y: 54.3), control2: CGPoint(x: 134.51, y: 49.68))
        p.addCurve(to: CGPoint(x: 144.04, y: 29.88), control1: CGPoint(x: 134.51, y: 34.53), control2: CGPoint(x: 138.24, y: 29.88))
        p.addCurve(to: CGPoint(x: 153.53, y: 42.13), control1: CGPoint(x: 149.8, y: 29.88), control2: CGPoint(x: 153.53, y: 34.57))
        p.addCurve(to: CGPoint(x: 144.04, y: 54.3), control1: CGPoint(x: 153.53, y: 49.65), control2: CGPoint(x: 149.84, y: 54.3))
        p.closeSubpath()
        return p
    }()
}
