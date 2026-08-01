import AppKit
import SwiftUI

/// Public Brand Kit mirror of the runtime tokens in `LerroTheme`.
enum LerroTokens {
    enum Colors {
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
        static let sidebar = adaptive(light: rgb(0xF1F1F1), dark: rgb(0x1B1B1B))
        static let elevated = adaptive(light: rgb(0xFFFFFF), dark: rgb(0x292929))
        static let scrim = Color.black.opacity(0.32)

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

        static let accent = Color(nsColor: .controlAccentColor)
        static let accentHover = accent.opacity(0.88)
        static let accentPressed = accent.opacity(0.72)
        static let primaryAction = accent
        static let primaryActionHover = accentHover
        static let primaryActionPressed = accentPressed
        static let primaryActionForeground = Color(
            nsColor: .alternateSelectedControlTextColor
        )

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
        static let success = Color(nsColor: .systemGreen)
        static let warning = Color(nsColor: .systemOrange)
        static let error = Color(nsColor: .systemRed)

        // Compatibility aliases for earlier Brand Kit consumers.
        static let window = main
        static let surface = topLayer
        static let label = text
        static let secondaryLabel = secondaryText
        static let tertiaryLabel = tertiaryText
        static let separator = thinBorder

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

    enum Typography {
        static let titleSize: CGFloat = 24
        static let bodySize: CGFloat = 14
        static let labelSize: CGFloat = 13
        static let captionSize: CGFloat = 12
        static let tracking: CGFloat = -0.15

        static let title = Font.system(size: titleSize, weight: .medium)
        static let heading = Font.system(size: bodySize, weight: .medium)
        static let body = Font.system(size: bodySize, weight: .regular)
        static let label = Font.system(size: labelSize, weight: .medium)
        static let secondary = Font.system(size: labelSize, weight: .regular)
        static let caption = Font.system(size: captionSize, weight: .regular)
        static let captionMedium = Font.system(size: captionSize, weight: .medium)
        static let mono = Font.system(size: captionSize, weight: .regular, design: .monospaced)
    }

    enum Spacing {
        static let x1: CGFloat = 4
        static let x2: CGFloat = 8
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x6: CGFloat = 24
        static let x8: CGFloat = 32
    }

    enum Radius {
        static let navigation: CGFloat = 8
        static let control: CGFloat = 8
        static let card: CGFloat = 16
        static let surface = card
        static let panel = card
    }

    enum Icon {
        static let navigation: CGFloat = 14
        static let card: CGFloat = 20
    }

    enum Motion {
        static let hoverSeconds = 0.15
        static let pressSeconds = 0.10
        static let pressedOffset: CGFloat = 1
        static let pressedOpacity = 0.92
        static let disabledOpacity = 0.48

        static let interactionSpring = Animation.spring(
            response: 0.20,
            dampingFraction: 1.0,
            blendDuration: 0
        )
        static let crossfade = Animation.easeOut(duration: 0.16)
        static let panel = Animation.easeOut(duration: 0.18)
        static let momentumSpring = Animation.spring(
            response: 0.36,
            dampingFraction: 0.82,
            blendDuration: 0.05
        )

        // Protected HUD baseline. Runtime ownership remains in CaptureHUDView.
        static let hudSurface = Animation.interpolatingSpring(
            mass: 0.9,
            stiffness: 420,
            damping: 36,
            initialVelocity: 0
        )
        static let hudCrossfade = Animation.interpolatingSpring(
            mass: 0.8,
            stiffness: 260,
            damping: 34,
            initialVelocity: 0
        )
        static let hudProcessing = Animation.timingCurve(
            0.23,
            1,
            0.32,
            1,
            duration: 0.08
        )
        static let hudControlDisclosure = Animation.timingCurve(
            0.05,
            0.6,
            0.4,
            0.95,
            duration: 0.20
        )
        static let hudControlOpacity = Animation.easeOut(duration: 0.10)

        static func stateChange(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : interactionSpring
        }
    }

    enum Shape {
        static let primaryAction = "capsule"
    }

    enum MenuBar {
        static let sourcePointSize: CGFloat = 24
        static let compactPointSize: CGFloat = 16
        static let regularPointSize: CGFloat = 18
        static let accessibilityLabelPrefix = "Lerro"
    }
}
