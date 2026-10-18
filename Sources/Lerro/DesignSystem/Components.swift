import AppKit
import SwiftUI

enum LerroTextRole {
    case title
    case heading
    case body
    case label
    case secondary
    case caption
    case captionMedium

    var size: CGFloat {
        switch self {
        case .title: LerroTheme.titleSize
        case .heading, .body: LerroTheme.bodySize
        case .label, .secondary: LerroTheme.labelSize
        case .caption, .captionMedium: LerroTheme.captionSize
        }
    }

    var weight: Font.Weight {
        switch self {
        case .title, .heading, .label, .captionMedium: .medium
        case .body, .secondary, .caption: .regular
        }
    }
}

private struct LerroTypographyModifier: ViewModifier {
    let role: LerroTextRole

    func body(content: Content) -> some View {
        content
            .font(.system(size: role.size, weight: role.weight))
            .tracking(LerroTheme.uiTracking)
    }
}

extension View {
    func lerroTypography(_ role: LerroTextRole) -> some View {
        modifier(LerroTypographyModifier(role: role))
    }
}

enum LerroInteractiveFeedback {
    static let pressedOffset: CGFloat = 1
    static let disabledOpacity = 0.48

    static func offset(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        isPressed && !reduceMotion ? pressedOffset : 0
    }

    static func opacity(isPressed: Bool, isEnabled: Bool) -> Double {
        let pressedOpacity = isPressed ? 0.92 : 1
        return pressedOpacity * (isEnabled ? 1 : disabledOpacity)
    }
}

struct LerroMark: View {
    let height: CGFloat
    var blinksOnAppear = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cursorOpacity = 1.0

    var body: some View {
        LerroBrandArtwork(
            size: LerroBrandGeometry.markSize,
            height: height,
            cursorOpacity: cursorOpacity,
            includesLetters: false
        )
        .task {
            guard blinksOnAppear, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.525)) { cursorOpacity = 0.15 }
            try? await Task.sleep(for: .seconds(0.525))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.525)) { cursorOpacity = 1 }
        }
        .accessibilityHidden(true)
    }
}

struct LerroWordmark: View {
    let height: CGFloat

    var body: some View {
        LerroBrandArtwork(
            size: LerroBrandGeometry.wordmarkSize,
            height: height,
            cursorOpacity: 1,
            includesLetters: true
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lerro")
    }
}

private struct LerroBrandArtwork: View {
    let size: CGSize
    let height: CGFloat
    let cursorOpacity: Double
    let includesLetters: Bool

    private var scale: CGFloat { height / size.height }

    var body: some View {
        ZStack(alignment: .topLeading) {
            capsule(LerroBrandGeometry.cursor)
                .foregroundStyle(LerroTheme.brandCursor)
                .opacity(cursorOpacity)
            capsule(LerroBrandGeometry.baseline)
                .foregroundStyle(.foreground)
            if includesLetters {
                LerroWordmarkLetters()
                    .fill(.foreground)
            }
        }
        .frame(width: size.width * scale, height: height, alignment: .topLeading)
    }

    private func capsule(_ rect: CGRect) -> some View {
        Capsule()
            .frame(width: rect.width * scale, height: rect.height * scale)
            .offset(x: rect.minX * scale, y: rect.minY * scale)
    }
}

private struct LerroWordmarkLetters: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.height / LerroBrandGeometry.wordmarkSize.height
        return LerroBrandGeometry.erro
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

struct LerroMenuBarIcon: View {
    let assetName: String
    let fallbackSystemName: String
    let accessibilityLabel: String

    var body: some View {
        Group {
            if let image = templateImage {
                Image(nsImage: image)
                    .renderingMode(.template)
            } else {
                Image(systemName: fallbackSystemName)
                    .symbolRenderingMode(.monochrome)
            }
        }
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    private var templateImage: NSImage? {
        guard let baseURL = Bundle.main.url(
            forResource: assetName,
            withExtension: "png",
            subdirectory: "MenuBar"
        ), let retinaURL = Bundle.main.url(
            forResource: "\(assetName)@2x",
            withExtension: "png",
            subdirectory: "MenuBar"
        ) else {
            return nil
        }
        return LerroMenuBarTemplateImageLoader.load(
            baseURL: baseURL,
            retinaURL: retinaURL
        )
    }
}

@MainActor
enum LerroMenuBarTemplateImageLoader {
    static let logicalSize = NSSize(width: 18, height: 18)

    private struct CacheKey: Hashable {
        let baseURL: URL
        let retinaURL: URL
    }

    private enum CacheEntry {
        case image(NSImage)
        case unavailable
    }

    private static var cache: [CacheKey: CacheEntry] = [:]

    static func load(baseURL: URL, retinaURL: URL) -> NSImage? {
        let key = CacheKey(
            baseURL: baseURL.standardizedFileURL,
            retinaURL: retinaURL.standardizedFileURL
        )
        if let cached = cache[key] {
            switch cached {
            case let .image(image): return image
            case .unavailable: return nil
            }
        }

        guard let baseData = try? Data(contentsOf: baseURL),
              let retinaData = try? Data(contentsOf: retinaURL),
              let baseRepresentation = NSBitmapImageRep(data: baseData),
              let retinaRepresentation = NSBitmapImageRep(data: retinaData) else {
            cache[key] = .unavailable
            return nil
        }

        baseRepresentation.size = logicalSize
        retinaRepresentation.size = logicalSize

        let image = NSImage(size: logicalSize)
        image.addRepresentation(baseRepresentation)
        image.addRepresentation(retinaRepresentation)
        image.isTemplate = true
        cache[key] = .image(image)
        return image
    }
}

enum LerroPressFeedback {
    static let duration = 0.09
    static let pressedScale: CGFloat = 0.97
    static let pressedOpacity = 0.82
    static let disabledOpacity = 0.5

    static func scale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        isPressed && !reduceMotion ? pressedScale : 1
    }

    static func opacity(isPressed: Bool, isEnabled: Bool) -> Double {
        let interactionOpacity = isPressed ? pressedOpacity : 1
        return interactionOpacity * (isEnabled ? 1 : disabledOpacity)
    }
}

struct LerroPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(LerroPressFeedback.scale(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            ))
            .opacity(LerroPressFeedback.opacity(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            ))
            .animation(
                .easeOut(duration: LerroPressFeedback.duration),
                value: configuration.isPressed
            )
    }
}
