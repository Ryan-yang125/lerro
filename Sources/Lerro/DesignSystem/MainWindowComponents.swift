import AppKit
import SwiftUI

// MARK: Buttons

/// 28 pt capsule button (24 pt when `compact`). Apply with `.buttonStyle(LerroButtonStyle(.primary))`.
struct LerroButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case destructive
    }

    let kind: Kind
    let compact: Bool

    init(_ kind: Kind, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        Body(
            kind: kind,
            compact: compact,
            label: configuration.label,
            isPressed: configuration.isPressed
        )
    }

    private struct Body<Label: View>: View {
        let kind: Kind
        let compact: Bool
        let label: Label
        let isPressed: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .font(compact ? .system(size: 12, weight: .medium) : LerroFont.bodyEmphasis)
                .lineLimit(1)
                .padding(.horizontal, compact ? 10 : 12)
                .frame(height: compact ? 24 : 28)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .brightness(kind == .primary && hovering ? 0.06 : 0)
                .opacity(isPressed ? 0.8 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: LerroTheme.hoverDuration), value: hovering)
                .animation(.easeOut(duration: LerroTheme.pressDuration), value: isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .primary: LerroTheme.primaryActionForeground
            case .secondary: LerroTheme.text
            case .destructive: LerroTheme.danger
            }
        }

        private var background: Color {
            switch kind {
            case .primary: LerroTheme.accentButton
            case .secondary, .destructive:
                hovering ? LerroTheme.actionFillHover : LerroTheme.actionFill
            }
        }
    }
}

/// 26×26 icon button with a hover fill.
struct LerroIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @Environment(\.locale) private var locale

    init(systemImage: String, help: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(IconStyle())
        .help(Text(verbatim: localizedHelp))
        .accessibilityLabel(Text(verbatim: localizedHelp))
    }

    private var localizedHelp: String {
        LerroInterfaceLocalization.string(help, locale: locale)
    }

    private struct IconStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            Body(label: configuration.label, isPressed: configuration.isPressed)
        }

        private struct Body<Label: View>: View {
            let label: Label
            let isPressed: Bool
            @State private var hovering = false
            @Environment(\.isEnabled) private var isEnabled

            var body: some View {
                label
                    .foregroundStyle(hovering ? LerroTheme.text : LerroTheme.secondaryText)
                    .background(
                        isPressed || hovering ? LerroTheme.fillHover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(isEnabled ? 1 : 0.5)
                    .onHover { hovering = $0 }
                    .animation(.easeOut(duration: LerroTheme.hoverDuration), value: hovering)
            }
        }
    }
}

// MARK: Shortcut keys

/// Renders a shortcut display name such as "⌃⌘V" or "Fn ⇧" as individual keycaps.
struct LerroShortcutKeys: View {
    let displayName: String
    var onAccent = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.keys(in: displayName).enumerated()), id: \.offset) { _, key in
                LerroKeycap(key, onAccent: onAccent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: displayName))
    }

    /// Splits on whitespace; within a token, "Fn" and each modifier glyph are
    /// separate keys and the remainder is one key ("V", "Space", "F5").
    static func keys(in displayName: String) -> [String] {
        let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var keys: [String] = []
        for token in displayName.split(whereSeparator: \.isWhitespace) {
            var rest = Substring(token)
            while !rest.isEmpty {
                if rest.hasPrefix("Fn") {
                    keys.append("Fn")
                    rest = rest.dropFirst(2)
                } else if let first = rest.first, modifierGlyphs.contains(first) {
                    keys.append(String(first))
                    rest = rest.dropFirst()
                } else {
                    keys.append(String(rest))
                    rest = ""
                }
            }
        }
        var merged: [String] = []
        for key in keys {
            if (key == "Up" || key == "Down"), merged.last == "Page" {
                merged[merged.count - 1] = "Page \(key)"
            } else {
                merged.append(key)
            }
        }
        return merged
    }
}

struct LerroKeycap: View {
    let text: String
    /// Translucent white keycap for accent-filled surfaces.
    let onAccent: Bool

    init(_ text: String, onAccent: Bool = false) {
        self.text = text
        self.onAccent = onAccent
    }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(onAccent ? Color.white : LerroTheme.text)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 20)
            .background(onAccent ? Color.white.opacity(0.22) : LerroTheme.keycapFill, in: shape)
            .overlay { shape.strokeBorder(onAccent ? Color.clear : LerroTheme.keycapBorder, lineWidth: 0.5) }
            .shadow(color: onAccent ? Color.clear : LerroTheme.keycapBorder, radius: 0, x: 0, y: 1)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
    }
}

// MARK: App icon

/// Application icon from NSWorkspace, cached by bundle identifier. Falls back
/// to a rounded square with a name-derived colour and the first letter.
struct LerroAppIcon: View {
    let bundleIdentifier: String?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = LerroAppIconCache.icon(for: bundleIdentifier) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Self.color(for: name))
            .overlay {
                Text(verbatim: String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    /// Stable across launches; `String.hashValue` is randomised per process.
    private static func color(for name: String) -> Color {
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.5, brightness: 0.62)
    }
}

@MainActor
private enum LerroAppIconCache {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        if let cached = cache[bundleIdentifier] { return cached }
        let image = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleIdentifier] = image
        return image
    }
}

// MARK: Status, chip, empty state, section header

struct LerroStatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// 24 pt capsule with a light neutral fill.
struct LerroChip<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 6) { content }
            .font(LerroFont.caption)
            .foregroundStyle(LerroTheme.text)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(LerroTheme.actionFill, in: Capsule())
    }
}

struct LerroEmptyState: View {
    let title: String
    let hint: String?

    init(title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }

    var body: some View {
        VStack(spacing: 6) {
            LerroMark(height: 36, blinksOnAppear: true)
                .padding(.bottom, 10)
            Text(LocalizedStringKey(title))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LerroTheme.text)
            if let hint {
                Text(LocalizedStringKey(hint))
                    .font(LerroFont.body)
                    .foregroundStyle(LerroTheme.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LerroSectionHeader: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LerroTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(LocalizedStringKey(actionTitle))
                        .font(LerroFont.caption)
                        .foregroundStyle(LerroTheme.accentText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
