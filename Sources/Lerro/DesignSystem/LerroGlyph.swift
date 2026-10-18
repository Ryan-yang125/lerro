import AppKit
import SwiftUI

/// Brand glyphs compiled into `Assets.car` from `Brand/source/icons/Glyphs.xcassets`.
enum LerroGlyph: String, CaseIterable, Sendable {
    case dictate, polish, translate, mic, home, history, dictionary, tones
    case allApps = "all-apps"
    case usage, general, shortcuts, privacy, about, update

    var assetName: String { "glyph-\(rawValue)" }

    /// Name of the cursor-only layer that sits on top of the full glyph.
    var cursorAssetName: String? {
        switch self {
        case .dictate, .polish, .home, .dictionary, .about: "glyph-\(rawValue)-cursor"
        default: nil
        }
    }

    /// Single-color template image for places that only accept an Image (Labels, menus).
    var image: Image { Image(assetName).renderingMode(.template) }

    /// Settings tab image. Tab items draw a fixed-size image, and the catalog's
    /// 16/32 px bitmaps blur when stretched, so this redraws the vector at the
    /// tab's point size for every backing scale.
    @MainActor
    func tabImage(pointSize: CGFloat = 24) -> Image {
        guard let source = NSImage(named: assetName) else { return image }
        let size = NSSize(width: pointSize, height: pointSize)
        let rendered = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        rendered.isTemplate = true
        return Image(nsImage: rendered)
    }
}

/// Glyph drawn in the current foreground style, with the cursor layer in the brand accent.
struct LerroGlyphView: View {
    let glyph: LerroGlyph
    var size: CGFloat = 16
    var accentCursor = true

    var body: some View {
        ZStack {
            Image(glyph.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
            if accentCursor, let cursor = glyph.cursorAssetName {
                Image(cursor)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(LerroTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
