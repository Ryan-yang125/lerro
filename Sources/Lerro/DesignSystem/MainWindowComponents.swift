import AppKit
import SwiftUI
import LerroCore

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
    @Environment(\.colorScheme) private var colorScheme

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
            .background(onAccent ? Color.white.opacity(0.22) : fill, in: shape)
            .overlay { shape.strokeBorder(onAccent ? Color.clear : edge, lineWidth: 0.5) }
            .shadow(color: onAccent ? Color.clear : edge, radius: 0, x: 0, y: 1)
    }

    private var fill: Color { LerroTheme.keycapFill(colorScheme) }
    private var edge: Color { LerroTheme.keycapBorder(colorScheme) }

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

// MARK: Split layout

/// Two children along one axis: the first gets `firstLength`, the second gets
/// the rest. It fills the proposed size and never measures its children. An
/// HStack or VStack asks each child for its size at zero and infinite lengths
/// to rank flexibility, and a ScrollView or List child answers by laying out
/// its whole content, which made every page switch take 100–180 ms.
struct LerroSplitLayout: Layout {
    let axis: Axis
    let firstLength: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else {
            assertionFailure("LerroSplitLayout takes exactly two children")
            return
        }
        let first = min(firstLength, axis == .horizontal ? bounds.width : bounds.height)
        switch axis {
        case .horizontal:
            subviews[0].place(
                at: bounds.origin,
                proposal: ProposedViewSize(width: first, height: bounds.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + first, y: bounds.minY),
                proposal: ProposedViewSize(width: bounds.width - first, height: bounds.height)
            )
        case .vertical:
            subviews[0].place(
                at: bounds.origin,
                proposal: ProposedViewSize(width: bounds.width, height: first)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + first),
                proposal: ProposedViewSize(width: bounds.width, height: bounds.height - first)
            )
        }
    }
}

/// Equal-width columns, top aligned, as tall as the tallest child. Each child
/// is measured once at its column width; an HStack of flexible cards first
/// probes every card at zero and infinite widths.
struct LerroEqualColumns: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
            + spacing * CGFloat(subviews.count - 1)
        let column = columnWidth(in: width, count: subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(in: bounds.width, count: subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (column + spacing), y: bounds.minY),
                proposal: ProposedViewSize(width: column, height: nil)
            )
        }
    }

    private func columnWidth(in width: CGFloat, count: Int) -> CGFloat {
        max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
    }
}

// MARK: Page lifecycle

// All main-window pages stay alive in RootView. These modifiers read
// `session.destination` inside their own body, so a page switch updates only
// the gated control and not the page around it.

private struct LerroPageTextInputModifier: ViewModifier {
    let session: AppSession
    let page: SidebarDestination

    func body(content: Content) -> some View {
        content.disabled(session.destination != page)
    }
}

private struct LerroPageFocusableModifier: ViewModifier {
    let session: AppSession
    let page: SidebarDestination

    func body(content: Content) -> some View {
        content.focusable(session.destination == page)
    }
}

private struct LerroPageVisibilityChangeModifier: ViewModifier {
    let session: AppSession
    let page: SidebarDestination
    let action: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: session.destination == page, initial: true) { _, visible in
            action(visible)
        }
    }
}

extension View {
    /// For text fields: keeps a hidden page's field out of the Tab order.
    func lerroPageTextInput(_ page: SidebarDestination, in session: AppSession) -> some View {
        modifier(LerroPageTextInputModifier(session: session, page: page))
    }

    /// For lists: only the visible page's list can take keyboard focus.
    func lerroPageFocusable(_ page: SidebarDestination, in session: AppSession) -> some View {
        modifier(LerroPageFocusableModifier(session: session, page: page))
    }

    /// Runs `action` with the page's visibility on appear and on every change.
    func onLerroPageVisibilityChange(
        _ page: SidebarDestination,
        in session: AppSession,
        perform action: @escaping (Bool) -> Void
    ) -> some View {
        modifier(LerroPageVisibilityChangeModifier(session: session, page: page, action: action))
    }
}

/// Top bar of a main-window page: the page title on the left and the page's
/// controls on the right. The window has no title bar, so the empty part of
/// this bar drags the window.
struct LerroPageHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: title)
                .font(LerroFont.pageTitle)
                .foregroundStyle(LerroTheme.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, LerroTheme.contentHorizontalPadding)
        .frame(height: LerroTheme.pageHeaderHeight)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}

extension LerroPageHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Search field for a page header.
struct LerroSearchField: View {
    @Binding var text: String
    let prompt: String
    @Environment(\.locale) private var locale
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LerroTheme.tertiaryText)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(verbatim: localizedPrompt)) {
                Text(verbatim: localizedPrompt)
            }
            .textFieldStyle(.plain)
            .font(LerroFont.body)
            .focused($focused)
            .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(LerroTheme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("清除"))
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 200, height: 28)
        .background(
            LerroTheme.fillContainerThin,
            in: RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                .strokeBorder(focused ? LerroTheme.accent : LerroTheme.thinBorder, lineWidth: focused ? 1 : 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private var localizedPrompt: String {
        LerroInterfaceLocalization.string(prompt, locale: locale)
    }
}
