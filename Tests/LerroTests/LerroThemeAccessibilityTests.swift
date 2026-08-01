import AppKit
import SwiftUI
import Testing
@testable import Lerro

@Suite("Lerro neutral theme accessibility")
@MainActor
struct LerroThemeAccessibilityTests {
    private let appearances: [NSAppearance.Name] = [
        .aqua,
        .darkAqua,
        .accessibilityHighContrastAqua,
        .accessibilityHighContrastDarkAqua
    ]

    @Test("Content palette resolves to grayscale in every appearance")
    func contentPaletteIsMonochrome() throws {
        let colors = [
            LerroTheme.main,
            LerroTheme.sidebar,
            LerroTheme.topLayer,
            LerroTheme.text,
            LerroTheme.secondaryText,
            LerroTheme.tertiaryText,
            LerroTheme.metadataText,
            LerroTheme.pivotText,
            LerroTheme.fillHover,
            LerroTheme.fillSelected,
            LerroTheme.border,
            LerroTheme.thinBorder
        ]

        for appearance in appearances {
            for color in colors {
                let components = try components(of: color, appearance: appearance)
                #expect(abs(components.red - components.green) < 0.002)
                #expect(abs(components.green - components.blue) < 0.002)
            }
        }
    }

    @Test("Interactive accent follows the macOS control accent color")
    func accentUsesSystemSemanticColor() throws {
        for appearance in appearances {
            let actual = try components(of: LerroTheme.accent, appearance: appearance)
            let expected = try components(
                of: Color(nsColor: .controlAccentColor),
                appearance: appearance
            )
            #expect(actual.isApproximatelyEqual(to: expected))

            let action = try components(of: LerroTheme.primaryAction, appearance: appearance)
            #expect(action.isApproximatelyEqual(to: expected))
        }
    }

    @Test("Essential text maintains readable contrast")
    func textContrast() throws {
        for appearance in appearances {
            let background = try components(of: LerroTheme.main, appearance: appearance)
            let primary = try components(of: LerroTheme.text, appearance: appearance)
            let secondary = try components(of: LerroTheme.secondaryText, appearance: appearance)
            let metadata = try components(of: LerroTheme.metadataText, appearance: appearance)

            #expect(contrast(primary, background) >= 7)
            #expect(contrast(secondary, background) >= 4.5)
            #expect(contrast(metadata, background) >= 4.5)
        }
    }

    @Test("Primary action foreground follows the system selected-control semantic")
    func actionForegroundUsesSystemSemanticColor() throws {
        for appearance in appearances {
            let foreground = try components(
                of: LerroTheme.primaryActionForeground,
                appearance: appearance
            )
            let expected = try components(
                of: Color(nsColor: .alternateSelectedControlTextColor),
                appearance: appearance
            )
            #expect(foreground.isApproximatelyEqual(to: expected))
        }
    }

    @Test("Increase Contrast strengthens structural boundaries")
    func highContrastBoundaries() throws {
        let lightNormal = try luminance(of: LerroTheme.main, appearance: .aqua)
        let lightBorder = try luminance(of: LerroTheme.thinBorder, appearance: .aqua)
        let lightHigh = try luminance(of: LerroTheme.main, appearance: .accessibilityHighContrastAqua)
        let lightHighBorder = try luminance(
            of: LerroTheme.thinBorder,
            appearance: .accessibilityHighContrastAqua
        )
        #expect(abs(lightHigh - lightHighBorder) >= abs(lightNormal - lightBorder))

        let darkNormal = try luminance(of: LerroTheme.main, appearance: .darkAqua)
        let darkBorder = try luminance(of: LerroTheme.thinBorder, appearance: .darkAqua)
        let darkHigh = try luminance(
            of: LerroTheme.main,
            appearance: .accessibilityHighContrastDarkAqua
        )
        let darkHighBorder = try luminance(
            of: LerroTheme.thinBorder,
            appearance: .accessibilityHighContrastDarkAqua
        )
        #expect(abs(darkHigh - darkHighBorder) >= abs(darkNormal - darkBorder))
    }

    @Test("Hover and selection remain visually distinct")
    func interactionStatesAreDistinct() throws {
        for appearance in appearances {
            let resting = try luminance(of: LerroTheme.main, appearance: appearance)
            let hover = try luminance(of: LerroTheme.fillHover, appearance: appearance)
            let selected = try luminance(of: LerroTheme.fillSelected, appearance: appearance)
            #expect(abs(resting - hover) >= 0.01)
            #expect(abs(hover - selected) >= 0.01)
        }
    }

    private func luminance(
        of color: Color,
        appearance: NSAppearance.Name
    ) throws -> Double {
        relativeLuminance(try components(of: color, appearance: appearance))
    }

    private func components(
        of color: Color,
        appearance: NSAppearance.Name
    ) throws -> RGB {
        let appearance = try #require(NSAppearance(named: appearance))
        let dynamicColor = NSColor(color)
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = dynamicColor.usingColorSpace(.sRGB)
        }
        let color = try #require(resolved)
        return RGB(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }

    private func contrast(_ foreground: RGB, _ background: RGB) -> Double {
        let brighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (brighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: RGB) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        func isApproximatelyEqual(to other: Self) -> Bool {
            abs(red - other.red) < 0.002
                && abs(green - other.green) < 0.002
                && abs(blue - other.blue) < 0.002
        }
    }
}
