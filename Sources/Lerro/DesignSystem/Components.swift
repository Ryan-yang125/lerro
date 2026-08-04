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

struct LerroNavigationButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        NavigationBody(
            label: configuration.label,
            selected: selected,
            isPressed: configuration.isPressed
        )
    }

    private struct NavigationBody<Label: View>: View {
        let label: Label
        let selected: Bool
        let isPressed: Bool
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .foregroundStyle(selected ? LerroTheme.text : LerroTheme.secondaryText)
                .background(background)
                .clipShape(RoundedRectangle(
                    cornerRadius: LerroTheme.navigationRadius,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: LerroTheme.navigationRadius,
                        style: .continuous
                    )
                    .stroke(selected ? LerroTheme.border : Color.clear, lineWidth: 1)
                }
                .offset(y: LerroInteractiveFeedback.offset(
                    isPressed: isPressed,
                    reduceMotion: reduceMotion
                ))
                .opacity(LerroInteractiveFeedback.opacity(
                    isPressed: isPressed,
                    isEnabled: isEnabled
                ))
                .contentShape(RoundedRectangle(
                    cornerRadius: LerroTheme.navigationRadius,
                    style: .continuous
                ))
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : LerroTheme.interactionSpring, value: isPressed)
                .animation(
                    .easeOut(duration: LerroTheme.hoverDuration),
                    value: hovering
                )
        }

        private var background: Color {
            if selected { return LerroTheme.fillSelected }
            if isPressed { return LerroTheme.actionFillHover }
            return hovering ? LerroTheme.fillHover : Color.clear
        }
    }
}

struct LerroCardButtonStyle: ButtonStyle {
    var radius: CGFloat = LerroTheme.cardRadius
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        CardBody(
            label: configuration.label,
            radius: radius,
            selected: selected,
            isPressed: configuration.isPressed
        )
    }

    private struct CardBody<Label: View>: View {
        let label: Label
        let radius: CGFloat
        let selected: Bool
        let isPressed: Bool
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            selected
                                ? LerroTheme.focusBorder
                                : (hovering ? LerroTheme.borderHover : LerroTheme.thinBorder),
                            lineWidth: selected ? 1.5 : 1
                        )
                }
                .shadow(
                    color: hovering ? LerroTheme.cardShadowHover : LerroTheme.cardShadow,
                    radius: hovering ? 4 : 2,
                    x: 0,
                    y: hovering ? 2 : 1
                )
                .offset(y: LerroInteractiveFeedback.offset(
                    isPressed: isPressed,
                    reduceMotion: reduceMotion
                ))
                .opacity(LerroInteractiveFeedback.opacity(
                    isPressed: isPressed,
                    isEnabled: isEnabled
                ))
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : LerroTheme.interactionSpring, value: isPressed)
                .animation(
                    .easeOut(duration: LerroTheme.hoverDuration),
                    value: hovering
                )
        }

        private var background: Color {
            if selected { return LerroTheme.fillSelected }
            return hovering ? LerroTheme.elevated : LerroTheme.topLayer
        }
    }
}

struct LerroPillButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(
            label: configuration.label,
            prominent: prominent,
            destructive: destructive,
            isPressed: configuration.isPressed
        )
    }

    private struct PillBody<Label: View>: View {
        let label: Label
        let prominent: Bool
        let destructive: Bool
        let isPressed: Bool
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .lerroTypography(.captionMedium)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .foregroundStyle(foreground)
                .background(background)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(border, lineWidth: 1)
                }
                .shadow(
                    color: prominent && hovering ? LerroTheme.cardShadowHover : Color.clear,
                    radius: 5,
                    x: 0,
                    y: 2
                )
                .offset(y: LerroInteractiveFeedback.offset(
                    isPressed: isPressed,
                    reduceMotion: reduceMotion
                ))
                .opacity(LerroInteractiveFeedback.opacity(
                    isPressed: isPressed,
                    isEnabled: isEnabled
                ))
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : LerroTheme.interactionSpring, value: isPressed)
                .animation(
                    .easeOut(duration: LerroTheme.hoverDuration),
                    value: hovering
                )
        }

        private var background: Color {
            if destructive {
                return hovering || isPressed
                    ? LerroTheme.red.opacity(0.14)
                    : LerroTheme.red.opacity(0.08)
            }
            if prominent {
                if isPressed { return LerroTheme.primaryActionPressed }
                return hovering ? LerroTheme.primaryActionHover : LerroTheme.primaryAction
            }
            if isPressed { return LerroTheme.actionFillHover }
            return hovering ? LerroTheme.actionFillHover : LerroTheme.actionFill
        }

        private var foreground: Color {
            if destructive { return LerroTheme.red }
            return prominent ? LerroTheme.primaryActionForeground : LerroTheme.text
        }

        private var border: Color {
            if destructive { return LerroTheme.red.opacity(0.48) }
            return prominent ? Color.clear : LerroTheme.border
        }
    }
}

struct LerroCard<Content: View>: View {
    private let padding: CGFloat
    private let radius: CGFloat
    @ViewBuilder private let content: Content

    init(
        padding: CGFloat = 16,
        radius: CGFloat = LerroTheme.cardRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(LerroTheme.topLayer)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LerroTheme.thinBorder, lineWidth: 1)
            }
            .shadow(color: LerroTheme.cardShadow, radius: 2, x: 0, y: 1)
    }
}

struct LerroMark: View {
    var size: CGFloat = 28
    var foregroundStyle: Color = .white

    var body: some View {
        Canvas { context, canvas in
            // Keep these normalized points aligned with Brand/source/logo/lerro-symbol.svg.
            let scale = min(canvas.width / 80, canvas.height / 64)
            let origin = CGPoint(
                x: (canvas.width - 80 * scale) / 2,
                y: (canvas.height - 64 * scale) / 2
            )
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }

            var letterLine = Path()
            letterLine.move(to: point(8, 10))
            letterLine.addLine(to: point(8, 42))
            letterLine.addCurve(
                to: point(19, 52),
                control1: point(8, 49),
                control2: point(12, 52)
            )
            letterLine.addLine(to: point(20, 52))
            letterLine.addLine(to: point(20, 38))
            letterLine.addCurve(
                to: point(30, 26),
                control1: point(20, 30),
                control2: point(24, 26)
            )
            letterLine.addCurve(
                to: point(40, 38),
                control1: point(36, 26),
                control2: point(40, 30)
            )
            letterLine.addLine(to: point(40, 52))
            letterLine.addLine(to: point(40, 38))
            letterLine.addCurve(
                to: point(50, 26),
                control1: point(40, 30),
                control2: point(44, 26)
            )
            letterLine.addCurve(
                to: point(60, 38),
                control1: point(56, 26),
                control2: point(60, 30)
            )
            letterLine.addLine(to: point(60, 52))
            context.stroke(
                letterLine,
                with: .color(foregroundStyle),
                style: StrokeStyle(
                    lineWidth: 7 * scale,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            var openO = Path()
            openO.move(to: point(78.34, 35.24))
            openO.addCurve(
                to: point(68, 28),
                control1: point(75.2, 30.7),
                control2: point(72, 28)
            )
            openO.addCurve(
                to: point(57, 39),
                control1: point(61.9, 28),
                control2: point(57, 32.1)
            )
            openO.addCurve(
                to: point(68, 50),
                control1: point(57, 45.9),
                control2: point(61.9, 50)
            )
            openO.addCurve(
                to: point(78.34, 42.76),
                control1: point(72, 50),
                control2: point(75.2, 47.3)
            )
            context.stroke(
                openO,
                with: .color(foregroundStyle),
                style: StrokeStyle(
                    lineWidth: 7 * scale,
                    lineCap: .butt,
                    lineJoin: .round
                )
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct LerroBrandBadge: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 9) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(LerroTheme.brandInk)
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                            .stroke(LerroTheme.brandOutline, lineWidth: 1)
                    }
                LerroMark(
                    size: compact ? 20 : 28,
                    foregroundStyle: LerroTheme.brandLight
                )
            }
            .frame(width: compact ? 28 : 36, height: compact ? 28 : 36)

            if !compact {
                Text("Lerro")
                    .lerroTypography(.heading)
                    .foregroundStyle(LerroTheme.text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lerro")
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

struct LerroIconButton: View {
    let systemName: String
    var help: String = ""
    var selected = false
    var foreground: Color? = nil
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: LerroTheme.navigationIconSize, weight: .medium))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(LerroIconButtonStyle(selected: selected, foreground: foreground))
        .contentShape(Rectangle().inset(by: -6))
        .help(Text(verbatim: localizedHelp))
        .accessibilityLabel(Text(verbatim: localizedHelp))
    }

    private var localizedHelp: String {
        help.isEmpty ? systemName : LerroInterfaceLocalization.string(help, locale: locale)
    }
}

private struct LerroIconButtonStyle: ButtonStyle {
    let selected: Bool
    let foreground: Color?

    func makeBody(configuration: Configuration) -> some View {
        IconBody(
            label: configuration.label,
            selected: selected,
            foreground: foreground,
            isPressed: configuration.isPressed
        )
    }

    private struct IconBody<Label: View>: View {
        let label: Label
        let selected: Bool
        let foreground: Color?
        let isPressed: Bool
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .foregroundStyle(foreground ?? (selected ? LerroTheme.text : LerroTheme.secondaryText))
                .background(background)
                .clipShape(RoundedRectangle(
                    cornerRadius: LerroTheme.navigationRadius,
                    style: .continuous
                ))
                .offset(y: LerroInteractiveFeedback.offset(
                    isPressed: isPressed,
                    reduceMotion: reduceMotion
                ))
                .opacity(LerroInteractiveFeedback.opacity(
                    isPressed: isPressed,
                    isEnabled: isEnabled
                ))
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : LerroTheme.interactionSpring, value: isPressed)
                .animation(.easeOut(duration: LerroTheme.hoverDuration), value: hovering)
        }

        private var background: Color {
            if selected { return LerroTheme.fillSelected }
            if isPressed { return LerroTheme.actionFillHover }
            return hovering ? LerroTheme.fillHover : Color.clear
        }
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .lerroTypography(selected ? .label : .secondary)
                .foregroundStyle(selected ? LerroTheme.text : LerroTheme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(selected ? LerroTheme.topLayer : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(LerroPressButtonStyle())
    }
}

struct ShortcutBadge: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .lerroTypography(.captionMedium)
            .foregroundStyle(LerroTheme.secondaryText)
            .padding(.horizontal, 9)
            .frame(minWidth: 40, minHeight: 28)
            .background(LerroTheme.fillContainerTough)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(LerroTheme.border, lineWidth: 1)
            }
    }
}

struct LerroPageTitle: View {
    let title: String
    var size: CGFloat = LerroTheme.titleSize
    @Environment(\.locale) private var locale

    var body: some View {
        Text(verbatim: LerroInterfaceLocalization.string(title, locale: locale))
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(LerroTheme.text)
            .tracking(LerroTheme.uiTracking)
            .accessibilityAddTraits(.isHeader)
    }
}

struct LerroSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: LerroTheme.navigationIconSize, weight: .medium))
                .foregroundStyle(LerroTheme.tertiaryText)
            TextField(LocalizedStringKey(placeholder), text: $text)
                .textFieldStyle(.plain)
                .lerroTypography(.body)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LerroTheme.tertiaryText)
                }
                .buttonStyle(LerroPressButtonStyle())
                .help("清空搜索")
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(LerroTheme.fillContainerThin)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LerroTheme.border, lineWidth: 1)
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: LerroTheme.cardIconSize, weight: .regular))
                .foregroundStyle(LerroTheme.tertiaryText)
            Text(LocalizedStringKey(title))
                .lerroTypography(.heading)
                .foregroundStyle(LerroTheme.text)
            Text(LocalizedStringKey(detail))
                .lerroTypography(.secondary)
                .foregroundStyle(LerroTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
