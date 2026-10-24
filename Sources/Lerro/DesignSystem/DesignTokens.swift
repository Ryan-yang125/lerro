import AppKit
import SwiftUI

/// Lerro uses a restrained monochrome content palette with adaptive light and
/// dark variants. Interactions use the Lerro brand blue (`accent`,
/// `accentButton`); system status colors cover success, warning and danger.
enum LerroTheme {
    // MARK: Surfaces

    static let main = adaptive(
        light: rgb(0xFAFAFA),
        dark: rgb(0x161616),
        highContrastLight: rgb(0xFFFFFF),
        highContrastDark: rgb(0x0D0D0D)
    )
    static let topLayer = adaptive(
        light: rgb(0xFFFFFF),
        dark: rgb(0x222222),
        highContrastLight: rgb(0xFFFFFF),
        highContrastDark: rgb(0x1A1A1A)
    )
    static let canvas = main
    static let sidebar = adaptive(light: rgb(0xF1F1F1), dark: rgb(0x1B1B1B))
    static let card = topLayer

    // MARK: Text

    static let text = adaptive(
        light: rgb(0x292929),
        dark: rgb(0xF2F2F2),
        highContrastLight: rgb(0x111111),
        highContrastDark: rgb(0xFFFFFF)
    )
    static let secondaryText = adaptive(
        light: rgb(0x5D5D5D),
        dark: rgb(0xB8B8B8),
        highContrastLight: rgb(0x444444),
        highContrastDark: rgb(0xD2D2D2)
    )
    static let tertiaryText = adaptive(
        light: rgb(0x9E9E9E),
        dark: rgb(0x929292),
        highContrastLight: rgb(0x5D5D5D),
        highContrastDark: rgb(0xC4C4C4)
    )
    static let metadataText = adaptive(
        light: rgb(0x6B6B6B),
        dark: rgb(0xBEBEBE),
        highContrastLight: rgb(0x444444),
        highContrastDark: rgb(0xD8D8D8)
    )
    static let pivotText = adaptive(light: rgb(0xFFFFFF), dark: rgb(0x292929))
    static let brandInk = Color(nsColor: rgb(0x15161A))
    static let brandPaper = Color(nsColor: rgb(0xF6F4EF))
    static let brandBlueOnDark = Color(nsColor: rgb(0x4A6BFF))
    static let brandCursor = adaptive(light: rgb(0x2F5BFF), dark: rgb(0x4A6BFF))

    // MARK: Fill and border

    static let fillContainerThin = adaptive(light: rgb(0xF3F3F3), dark: rgb(0x292929))
    static let fillContainerTough = adaptive(light: rgb(0xE8E8E8), dark: rgb(0x333333))
    static let fillHover = adaptive(
        light: rgb(0xE9E9E9),
        dark: rgb(0x303030),
        highContrastLight: rgb(0xDEDEDE),
        highContrastDark: rgb(0x3D3D3D)
    )
    static let fillSelected = adaptive(
        light: rgb(0xDEDEDE),
        dark: rgb(0x3A3A3A),
        highContrastLight: rgb(0xCECECE),
        highContrastDark: rgb(0x4A4A4A)
    )
    static let actionFill = adaptive(light: rgb(0xEBEBEB), dark: rgb(0x303030))
    static let actionFillHover = adaptive(light: rgb(0xE0E0E0), dark: rgb(0x3A3A3A))
    static let border = adaptive(
        light: rgb(0xD6D6D6),
        dark: rgb(0x444444),
        highContrastLight: rgb(0x858585),
        highContrastDark: rgb(0x787878)
    )
    static let borderHover = adaptive(
        light: rgb(0xBEBEBE),
        dark: rgb(0x5A5A5A),
        highContrastLight: rgb(0x686868),
        highContrastDark: rgb(0x969696)
    )
    static let thinBorder = adaptive(
        light: rgb(0xE3E3E3),
        dark: rgb(0x383838),
        highContrastLight: rgb(0x858585),
        highContrastDark: rgb(0x787878)
    )
    /// Keycap colours are picked from the SwiftUI colour scheme. A dynamic
    /// NSColor fill in the window toolbar kept its light value after the
    /// system switched to dark while the app was running.
    static func keycapFill(_ scheme: ColorScheme) -> Color {
        Color(nsColor: scheme == .dark ? rgb(0x2C2C2F) : rgb(0xFFFFFF))
    }
    static func keycapBorder(_ scheme: ColorScheme) -> Color {
        Color(nsColor: scheme == .dark ? rgb(0xFFFFFF, alpha: 0.14) : rgb(0x000000, alpha: 0.14))
    }
    static let focusBorder = accent
    static let selection = fillSelected

    // MARK: Actions and statuses

    /// Cursor, selection, links, switches and the current-day bar.
    static let accent = adaptive(
        light: rgb(0x2F5BFF),
        dark: rgb(0x4A6BFF),
        highContrastLight: rgb(0x1F46E0),
        highContrastDark: rgb(0x7D95FF)
    )
    /// Accent-coloured text on a window surface (links, small labels).
    static let accentText = adaptive(
        light: rgb(0x2F5BFF),
        dark: rgb(0x7D95FF),
        highContrastLight: rgb(0x1F46E0),
        highContrastDark: rgb(0x9DB0FF)
    )
    /// Primary button fill; text on it is always white.
    static let accentButton = adaptive(
        light: rgb(0x2F5BFF),
        dark: rgb(0x3557F0),
        highContrastLight: rgb(0x1F46E0),
        highContrastDark: rgb(0x2A47D6)
    )
    /// Selected-row background.
    static let accentSoft = adaptive(
        light: rgb(0x2F5BFF, alpha: 0.10),
        dark: rgb(0x4A6BFF, alpha: 0.18),
        highContrastLight: rgb(0x1F46E0, alpha: 0.16),
        highContrastDark: rgb(0x7D95FF, alpha: 0.26)
    )
    /// Home activity heatmap, level 0 (no use) to 4 (most words).
    static let heatmap: [Color] = [
        adaptive(light: rgb(0xEBEBEB), dark: rgb(0x262626)),
        adaptive(light: rgb(0xC9D4FF), dark: rgb(0x1F2A57)),
        adaptive(light: rgb(0x93A9FF), dark: rgb(0x2A3F99)),
        adaptive(light: rgb(0x5C7DFF), dark: rgb(0x3A5AE0)),
        adaptive(light: rgb(0x2F5BFF), dark: rgb(0x6F8BFF))
    ]
    static let primaryAction = accentButton
    static let primaryActionForeground = Color.white
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let green = success
    static let red = danger
    static let orange = warning

    // MARK: Capture HUD

    static let hudInk = brandInk
    static let hudPaper = brandPaper
    static let hudCursor = brandBlueOnDark
    static let hudSecondaryText = hudPaper.opacity(0.6)
    static let hudWarning = Color(nsColor: .systemOrange)
    static let hudError = Color(nsColor: .systemRed)
    static let hudCapsuleHeight: CGFloat = 40
    static let hudHorizontalPadding: CGFloat = 16
    static let hudContentSpacing: CGFloat = 10
    static let hudLiveTextMaximumWidth: CGFloat = 400

    // MARK: Geometry

    static let hubMinimumSize = CGSize(width: 988, height: 658)
    static let sidebarWidth: CGFloat = 220
    static let contentHorizontalPadding: CGFloat = 28
    static let hudPanelSize = CGSize(width: 560, height: 120)
    static let hudContentBottomInset: CGFloat = 18
    static let navigationRadius: CGFloat = 8
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 8

    // MARK: Typography

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }


    static let uiTracking: CGFloat = -0.15

    static let hoverDuration = 0.15
    static let pressDuration = 0.10

    private static func adaptive(
        light: NSColor,
        dark: NSColor,
        highContrastLight: NSColor? = nil,
        highContrastDark: NSColor? = nil
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .darkAqua,
                .accessibilityHighContrastAqua,
                .aqua
            ])
            switch match {
            case .accessibilityHighContrastDarkAqua:
                return highContrastDark ?? dark
            case .darkAqua:
                return dark
            case .accessibilityHighContrastAqua:
                return highContrastLight ?? light
            default:
                return light
            }
        })
    }

    private static func rgb(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Static fonts for the main window. Apply with `.font(LerroFont.body)`.
enum LerroFont {
    static let pageTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    /// History detail body text.
    static let detail = Font.system(size: 16)
    static let stat = Font.system(size: 30, weight: .semibold).monospacedDigit()
    /// Home page figures. Large sizes resolve to SF Pro Display.
    static let heroNumber = Font.system(size: 46, weight: .bold).monospacedDigit()
    static let heroUnit = Font.system(size: 20, weight: .semibold)
    static let cardValue = Font.system(size: 26, weight: .bold).monospacedDigit()
    static let cardUnit = Font.system(size: 13, weight: .semibold)
    static let streakValue = Font.system(size: 22, weight: .bold).monospacedDigit()
    static let streakUnit = Font.system(size: 12, weight: .semibold)
    static let cardDelta = Font.system(size: 11.5, weight: .semibold).monospacedDigit()
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let axisLabel = Font.system(size: 10.5)
    static let caption = Font.system(size: 12)
    static let footnote = Font.system(size: 11)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
}
