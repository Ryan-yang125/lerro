import Foundation
import Testing
@testable import Lerro

@Suite("Brand glyphs")
struct LerroGlyphTests {
    private static let glyphSources: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Brand/source/icons/Glyphs.xcassets", isDirectory: true)

    private static func svg(_ assetName: String) -> URL {
        glyphSources
            .appendingPathComponent("\(assetName).imageset", isDirectory: true)
            .appendingPathComponent("\(assetName).svg")
    }

    @Test("Every glyph has its source SVG", arguments: LerroGlyph.allCases)
    func glyphSourceExists(glyph: LerroGlyph) {
        #expect(FileManager.default.fileExists(atPath: Self.svg(glyph.assetName).path))
    }

    @Test("Every cursor layer has its source SVG", arguments: LerroGlyph.allCases)
    func cursorSourceExists(glyph: LerroGlyph) {
        guard let cursor = glyph.cursorAssetName else { return }
        #expect(FileManager.default.fileExists(atPath: Self.svg(cursor).path))
    }

    @Test("Cursor layers exist for dictate, polish, home, dictionary and about")
    func cursorGlyphs() {
        let withCursor = Set(LerroGlyph.allCases.filter { $0.cursorAssetName != nil })
        #expect(withCursor == [.dictate, .polish, .home, .dictionary, .about])
    }
}
