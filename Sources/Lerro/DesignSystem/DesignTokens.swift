import AppKit
import SwiftUI

/// Lerro uses a restrained monochrome content palette with adaptive light and
/// dark variants. Key interactions inherit the user's macOS accent color;
/// system status colors remain available for warnings and errors.
enum LerroTheme {
    // MARK: Surfaces

    static let main = adaptive(
        light: rgb(0xFAFAFA),
        dark: rgb(0x161616),
        highContrastLight: rgb(0xFFFFFF),
        highContrastDark: rgb(0x0D0D0D)
    )
    static let mainContrast = adaptive(
        light: rgb(0xF2F2F2),
        dark: rgb(0x202020),
        highContrastLight: rgb(0xEEEEEE),
        highContrastDark: rgb(0x272727)
    )
    static let topLayer = adaptive(
        light: rgb(0xFFFFFF),
        dark: rgb(0x222222),
        highContrastLight: rgb(0xFFFFFF),
        highContrastDark: rgb(0x1A1A1A)
    )
    static let bottomLayer = adaptive(light: rgb(0xF2F2F2), dark: rgb(0x191919))
    static let canvas = main
    static let sidebar = adaptive(light: rgb(0xF1F1F1), dark: rgb(0x1B1B1B))
    static let card = topLayer
    static let elevated = adaptive(light: rgb(0xFFFFFF), dark: rgb(0x292929))
    static let scrim = Color.black.opacity(0.32)

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
    static let disabledText = Color(nsColor: .disabledControlTextColor)
    static let pivotText = adaptive(light: rgb(0xFFFFFF), dark: rgb(0x292929))
    static let brandInk = Color(
        red: 17.0 / 255.0,
        green: 17.0 / 255.0,
        blue: 19.0 / 255.0
    )
    static let brandLight = Color(
        red: 245.0 / 255.0,
        green: 242.0 / 255.0,
        blue: 234.0 / 255.0
    )
    static let brandOutline = Color.white.opacity(0.14)

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
    static let focusBorder = accent
    static let selection = fillSelected
    static let cardShadow = Color.black.opacity(0.07)
    static let cardShadowHover = Color.black.opacity(0.13)

    // MARK: Actions and statuses

    static let accent = Color(nsColor: .controlAccentColor)
    static let accentHover = accent.opacity(0.88)
    static let accentPressed = accent.opacity(0.72)
    static let primaryAction = accent
    static let primaryActionHover = accentHover
    static let primaryActionPressed = accentPressed
    static let primaryActionForeground = Color(nsColor: .alternateSelectedControlTextColor)
    static let green = Color(nsColor: .systemGreen)
    static let red = Color(nsColor: .systemRed)
    static let orange = Color(nsColor: .systemOrange)

    // MARK: Geometry

    static let hubSize = CGSize(width: 1080, height: 750)
    static let hubMinimumSize = CGSize(width: 988, height: 658)
    static let sidebarWidth: CGFloat = 220
    static let contentHorizontalPadding: CGFloat = 28
    static let contentTopPadding: CGFloat = 30
    static let contentBottomPadding: CGFloat = 16
    static let settingsMaximumSize = CGSize(width: 920, height: 640)
    static let settingsMinimumSize = CGSize(width: 760, height: 520)
    static let settingsSidebarWidth: CGFloat = 202
    static let settingsModalCornerRadius: CGFloat = 22
    static let settingsModalHorizontalInset: CGFloat = 16
    static let settingsModalVerticalInset: CGFloat = 12
    static let hudPanelSize = CGSize(width: 184, height: 72)
    static let hudMinimumInteractionSize = CGSize(width: 70, height: 34)
    static let hudContentBottomInset: CGFloat = 18
    static let outerInset: CGFloat = 0
    static let sidebarRadius: CGFloat = 0
    static let navigationRadius: CGFloat = 8
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 8
    static let topDragHeight: CGFloat = 58

    static let navigationIconSize: CGFloat = 14
    static let cardIconSize: CGFloat = 20

    // MARK: Typography

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func displayFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let uiTracking: CGFloat = -0.15
    static let titleSize: CGFloat = 24
    static let bodySize: CGFloat = 14
    static let labelSize: CGFloat = 13
    static let captionSize: CGFloat = 12

    static let hoverDuration = 0.15
    static let pressDuration = 0.10
    static let interactionSpring = Animation.spring(
        response: 0.20,
        dampingFraction: 1.0,
        blendDuration: 0
    )

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

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
