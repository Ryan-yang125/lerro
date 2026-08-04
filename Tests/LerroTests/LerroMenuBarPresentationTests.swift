import AppKit
import Testing
import LerroCore
@testable import Lerro

@Suite("Menu bar presentation")
struct LerroMenuBarPresentationTests {
    @Test("Fixture language override applies only to inert fixture runs")
    func fixtureLanguageOverride() {
        #expect(LerroInterfaceLocalization.locale(
            for: .system,
            environment: ["LERRO_FIXTURE_MODE": "1", "LERRO_FIXTURE_LANGUAGE": "en"]
        ).language.languageCode?.identifier == "en")
        #expect(LerroInterfaceLocalization.locale(
            for: .english,
            environment: ["LERRO_FIXTURE_LANGUAGE": "zh-Hans"]
        ).language.languageCode?.identifier == "en")
        #expect(LerroInterfaceLocalization.locale(
            for: .english,
            environment: ["LERRO_FIXTURE_MODE": "1", "LERRO_FIXTURE_LANGUAGE": "zh-Hans"]
        ).language.languageCode?.identifier == "zh")
    }

    @Test("Every capture phase maps to the documented VoiceOver state")
    func accessibilityLabels() {
        for phase in [CapturePhase.idle, .success, .cancelled] {
            #expect(LerroMenuBarPresentation.accessibilityLabel(for: phase, locale: Locale(identifier: "zh-Hans")) == "Lerro，空闲")
        }
        #expect(LerroMenuBarPresentation.accessibilityLabel(for: .listening, locale: Locale(identifier: "zh-Hans")) == "Lerro，正在听写")
        for phase in [CapturePhase.transcribing, .enhancing, .inserting] {
            #expect(LerroMenuBarPresentation.accessibilityLabel(for: phase, locale: Locale(identifier: "zh-Hans")) == "Lerro，正在处理")
        }
        #expect(LerroMenuBarPresentation.accessibilityLabel(for: .failed, locale: Locale(identifier: "zh-Hans")) == "Lerro，需要处理")
        #expect(LerroMenuBarPresentation.accessibilityLabel(for: .listening, locale: Locale(identifier: "en")) == "Lerro is dictating")
    }

    @Test("Every state maps to the matching branded menu asset")
    func assetNames() {
        #expect(LerroMenuBarPresentation.assetName(for: .idle) == "LerroMenuIdleTemplate")
        #expect(LerroMenuBarPresentation.assetName(for: .listening) == "LerroMenuListeningTemplate")
        #expect(LerroMenuBarPresentation.assetName(for: .enhancing) == "LerroMenuProcessingTemplate")
        #expect(LerroMenuBarPresentation.assetName(for: .failed) == "LerroMenuErrorTemplate")
    }

    @Test("Native menu capture actions follow the session state")
    func nativeMenuActionAvailability() {
        for mode in CaptureMode.allCases {
            #expect(LerroNativeMenuPresentation.captureActionEnabled(
                mode: mode,
                phase: .idle,
                activeMode: .dictation
            ))
            #expect(LerroNativeMenuPresentation.captureActionEnabled(
                mode: mode,
                phase: .listening,
                activeMode: mode
            ))
            #expect(!LerroNativeMenuPresentation.captureActionEnabled(
                mode: mode,
                phase: .enhancing,
                activeMode: mode
            ))
        }

        #expect(!LerroNativeMenuPresentation.captureActionEnabled(
            mode: .translation,
            phase: .listening,
            activeMode: .dictation
        ))
    }

    @Test("Native menu titles expose the active shortcut and stay compact")
    func nativeMenuTitles() {
        #expect(LerroNativeMenuPresentation.captureTitle(
            title: "听写",
            activeTitle: "完成听写",
            shortcut: "Fn",
            phase: .idle,
            activeMode: .dictation,
            mode: .dictation
        ) == "听写 · Fn")
        #expect(LerroNativeMenuPresentation.captureTitle(
            title: "听写",
            activeTitle: "完成听写",
            shortcut: "Fn",
            phase: .listening,
            activeMode: .dictation,
            mode: .dictation
        ) == "完成听写 · Fn")

        let longTitle = LerroNativeMenuPresentation.shortTitle(String(repeating: "长", count: 40))
        #expect(longTitle.count == LerroNativeMenuPresentation.maximumTitleCharacters)
        #expect(longTitle.hasSuffix("…"))
    }

    @Test("Template image carries native and Retina representations")
    @MainActor
    func templateImageRepresentations() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = projectRoot
            .appendingPathComponent("Sources/Lerro/Resources/MenuBar", isDirectory: true)
        let image = try #require(LerroMenuBarTemplateImageLoader.load(
            baseURL: resources.appendingPathComponent("LerroMenuIdleTemplate.png"),
            retinaURL: resources.appendingPathComponent("LerroMenuIdleTemplate@2x.png")
        ))
        let bitmapRepresentations = image.representations.compactMap { $0 as? NSBitmapImageRep }

        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(bitmapRepresentations.count == 2)
        #expect(bitmapRepresentations.map(\.pixelsWide).sorted() == [18, 36])
        #expect(bitmapRepresentations.allSatisfy { $0.size == NSSize(width: 18, height: 18) })

        let cachedImage = try #require(LerroMenuBarTemplateImageLoader.load(
            baseURL: resources.appendingPathComponent("LerroMenuIdleTemplate.png"),
            retinaURL: resources.appendingPathComponent("LerroMenuIdleTemplate@2x.png")
        ))
        #expect(cachedImage === image)
    }
}
