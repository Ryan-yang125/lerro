import Foundation
import Testing
@testable import Lerro

@Suite("Localization resources")
struct LerroLocalizationResourcesTests {
    @Test("Chinese and English catalogs expose the same keys")
    func catalogsStayInSync() throws {
        let resources = projectRoot.appendingPathComponent("Sources/Lerro/Resources")
        let englishEntries = try catalogEntries(at: resources.appendingPathComponent("en.lproj/Localizable.strings"))
        let chineseEntries = try catalogEntries(at: resources.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))
        let english = Set(englishEntries)
        let chinese = Set(chineseEntries)

        #expect(!english.isEmpty)
        #expect(englishEntries.count == english.count, "English catalog has duplicate keys")
        #expect(chineseEntries.count == chinese.count, "Chinese catalog has duplicate keys")
        #expect(english == chinese)
        #expect(english.contains("界面语言"))
        #expect(english.contains("听写语言"))
    }

    @Test("Provider and resource status messages exposed by the app have catalog coverage")
    func providerAndResourceStatusMessagesHaveCatalogCoverage() throws {
        let resources = projectRoot.appendingPathComponent("Sources/Lerro/Resources")
        let english = try propertyListStrings(at: resources.appendingPathComponent(
            "en.lproj/Localizable.strings"
        ))
        let chinese = try propertyListStrings(at: resources.appendingPathComponent(
            "zh-Hans.lproj/Localizable.strings"
        ))

        // Keep this focused on the message literals assigned to LocalModelStatus
        // or LanguageResourceStatus in RuleBasedIntelligenceService,
        // MLXLanguageModelRuntime, AppleSpeechService,
        // AppleTranslationService, SpeechTranscribing, AppSession, and fixtures.
        let keys: Set<String> = [
            "本地基础处理已就绪",
            "模型已缓存在本机，使用时加载",
            "首次使用时下载约 3.03 GB 的本地模型",
            "正在检查并下载本地模型",
            "本地模型准备已取消",
            "模型已下载，正在加载",
            "正在下载本地模型 · %lld%%",
            "Qwen3.5 4B 已在本机加载",
            "模型已缓存，使用时自动加载",
            "SpeechTranscriber 在当前系统上不可用",
            "此听写语言暂不支持",
            "语音资源已准备",
            "需要准备语音资源",
            "语音资源下载中",
            "语音资源不受支持",
            "语音资源状态未知",
            "翻译资源已准备",
            "需要准备翻译资源",
            "此语言组合暂不支持设备端翻译",
            "翻译资源状态未知",
            "正在检查本地模型",
            "正在检查语音资源",
            "正在检查翻译资源",
            "正在准备语音资源",
            "正在准备翻译资源"
        ]

        #expect(keys.allSatisfy { english[$0] != nil })
        #expect(keys.allSatisfy { english[$0] != $0 })
        #expect(keys.allSatisfy { chinese[$0] != nil })
        #expect(english["正在下载本地模型 · %lld%%"] == "Downloading local model · %lld%%")
    }

    @Test("Cross-module formatted UI messages use locale-specific punctuation")
    func crossModuleFormattedMessagesUseLocalizedPunctuation() throws {
        let resources = projectRoot.appendingPathComponent("Sources/Lerro/Resources")
        let english = try propertyListStrings(at: resources.appendingPathComponent(
            "en.lproj/Localizable.strings"
        ))
        let chinese = try propertyListStrings(at: resources.appendingPathComponent(
            "zh-Hans.lproj/Localizable.strings"
        ))

        #expect(english["%@。%@"] == "%@. %@")
        #expect(chinese["%@。%@"] == "%@。%@")
        #expect(english["%@；%@"] == "%@; %@")
        #expect(chinese["%@；%@"] == "%@；%@")
    }

    @Test("AppSession user-visible messages have catalog and format coverage")
    func appSessionVisibleMessagesHaveCatalogAndFormatCoverage() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Sources/Lerro/App/AppSession.swift"),
            encoding: .utf8
        )
        let catalog = try propertyListStrings(at: projectRoot.appendingPathComponent(
            "Sources/Lerro/Resources/en.lproj/Localizable.strings"
        ))
        let ignoredTriggerWords: Set<String> = ["改写", "重写", "缩短", "扩写", "润色"]
        let ignoredFixturePayloads: Set<String> = ["合成转写", "合成错误"]
        let visibleMessages = try appSessionChineseStringLiterals(in: source)
            .subtracting(ignoredTriggerWords)
            .subtracting(ignoredFixturePayloads)

        #expect(!visibleMessages.isEmpty)
        #expect(
            visibleMessages.allSatisfy { catalog[$0] != nil },
            "Missing AppSession localization keys: \(visibleMessages.filter { catalog[$0] == nil }.sorted())"
        )
        #expect(
            visibleMessages.allSatisfy { catalog[$0] != $0 },
            "English AppSession messages must have translated values: \(visibleMessages.filter { catalog[$0] == $0 }.sorted())"
        )
        let formatMismatches = visibleMessages.filter { key in
            guard key.contains("%@"),
                  let value = catalog[key],
                  let keyPlaceholders = try? formatPlaceholders(in: key),
                  let valuePlaceholders = try? formatPlaceholders(in: value) else {
                return false
            }
            return keyPlaceholders != valuePlaceholders
        }
        #expect(formatMismatches.isEmpty, "AppSession format mismatch: \(formatMismatches.sorted())")
    }

    @Test("Floating panels receive the selected interface locale")
    func floatingPanelLocaleContract() throws {
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Sources/Lerro/App/AppSession.swift"),
            encoding: .utf8
        )
        let localeInjection = ".environment(\\.locale, LerroInterfaceLocalization.locale(for: preferences.appLanguage))"

        #expect(source.components(separatedBy: localeInjection).count - 1 >= 2)
        #expect(source.contains("CaptureHUDView(session: self)"))
        #expect(source.contains("AskAnswerCardView(session: self)"))
    }

    @Test("Common Core, Mac, and Intelligence error details have English coverage")
    func crossModuleErrorDetailsHaveEnglishCoverage() throws {
        let catalog = try propertyListStrings(at: projectRoot.appendingPathComponent(
            "Sources/Lerro/Resources/en.lproj/Localizable.strings"
        ))
        let keys: Set<String> = [
            "另一项文本写入仍在进行",
            "焦点已切换到其他应用，结果已保留在历史记录中",
            "SpeechTranscriber 在当前系统上不可用",
            "不支持语言 %@",
            "无法使用所选麦克风（%@）",
            "Apple Translation 未返回文本",
            "翻译需要完成本地语言模型下载",
            "API 改写需要允许发送选中文字",
            "远程模型运行时尚未配置",
            "本地模型尚未加载"
        ]

        #expect(keys.allSatisfy { catalog[$0] != nil && catalog[$0] != $0 })
        #expect(catalog["不支持语言 %@"] == "Language %@ is not supported")
        #expect(catalog["无法使用所选麦克风（%@）"] == "Could not use the selected microphone (%@)")
    }

    @Test("Both supported languages localize the microphone usage description")
    func infoPlistStringsExist() throws {
        let resources = projectRoot.appendingPathComponent("Sources/Lerro/Resources")
        for language in ["en", "zh-Hans"] {
            let path = resources.appendingPathComponent("\(language).lproj/InfoPlist.strings")
            let values = try propertyListStrings(at: path)
            #expect(values["NSMicrophoneUsageDescription"]?.isEmpty == false)
        }
    }

    @Test("Catalog values preserve every format placeholder")
    func catalogFormatPlaceholdersStayCompatible() throws {
        let resources = projectRoot.appendingPathComponent("Sources/Lerro/Resources")
        for language in ["en", "zh-Hans"] {
            let values = try propertyListStrings(at: resources.appendingPathComponent(
                "\(language).lproj/Localizable.strings"
            ))
            let mismatches = try values.compactMap { key, value -> String? in
                let keyPlaceholders = try formatPlaceholders(in: key)
                let valuePlaceholders = try formatPlaceholders(in: value)
                return keyPlaceholders == valuePlaceholders ? nil : key
            }
            #expect(mismatches.isEmpty, "\(language) format placeholder mismatch: \(mismatches.sorted())")
        }
    }

    @Test("Every Chinese app-copy literal and helper argument has an English catalog key")
    func staticSwiftUILabelsAreCovered() throws {
        let sourceRoot = projectRoot.appendingPathComponent("Sources/Lerro")
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let files = try recursiveSwiftFiles(in: sourceRoot)
        #expect(!sourceFiles.isEmpty)
        let discovered = try Set(
            files.flatMap(staticSwiftUILabels)
                + files.flatMap(chineseAppCopyLiterals)
        )
        let catalog = try catalogKeys(at: projectRoot.appendingPathComponent(
            "Sources/Lerro/Resources/en.lproj/Localizable.strings"
        ))
        let missing = discovered.subtracting(catalog)

        #expect(missing.isEmpty, "Missing English localization keys: \(missing.sorted())")
    }

    @Test("Dynamic SwiftUI copy declares localization or verbatim provenance")
    func dynamicSwiftUICopyHasExplicitProvenance() throws {
        let sourceRoot = projectRoot.appendingPathComponent("Sources/Lerro")
        let files = try recursiveSwiftFiles(in: sourceRoot)
        let violations = try files.flatMap(dynamicSwiftUICopyViolations)

        #expect(
            violations.isEmpty,
            "Dynamic SwiftUI copy must use LocalizedStringKey, localized(...), or verbatim:. \(violations.joined(separator: ", "))"
        )
    }

    @Test("Interpolated Chinese presentation copy uses explicit formatting")
    func interpolatedChinesePresentationCopyIsExplicit() throws {
        let sourceRoot = projectRoot.appendingPathComponent("Sources/Lerro")
        let files = try recursiveSwiftFiles(in: sourceRoot)
        let violations = try files.flatMap(interpolatedChinesePresentationViolations)

        #expect(
            violations.isEmpty,
            "Use LerroInterfaceLocalization formatted copy for interpolated presentation strings. \(violations.joined(separator: ", "))"
        )
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func catalogKeys(at url: URL) throws -> Set<String> {
        Set(try catalogEntries(at: url))
    }

    private func catalogEntries(at url: URL) throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"^\s*\"((?:\\.|[^\"])*)\"\s*="#,
            options: [.anchorsMatchLines]
        )
        let range = NSRange(content.startIndex..., in: content)
        return expression.matches(in: content, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[range])
        }
    }

    private func appSessionChineseStringLiterals(in source: String) throws -> Set<String> {
        let expression = try NSRegularExpression(pattern: #"\"((?:\\.|[^\"\\])*)\""#)
        let range = NSRange(source.startIndex..., in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            let literal = String(source[range])
            guard literal.range(of: #"\p{Han}"#, options: .regularExpression) != nil else { return nil }
            return literal.replacingOccurrences(
                of: #"\\\([^)]*\)"#,
                with: "%@",
                options: .regularExpression
            )
        })
    }

    private func propertyListStrings(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        return try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }

    private func formatPlaceholders(in value: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: #"%(?:[0-9]+\$)?(?:\.[0-9]+)?(?:@|lld|ld|d|f)"#
        )
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let range = Range(match.range, in: value) else { return nil }
            return String(value[range]).replacingOccurrences(
                of: #"^%[0-9]+\$"#,
                with: "%",
                options: .regularExpression
            )
        }.sorted()
    }

    private func recursiveSwiftFiles(in directory: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }

    private func staticSwiftUILabels(in url: URL) throws -> [String] {
        let source = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"(?:Text|Button|Label|Picker|Toggle|TextField|SecureField|alert|help|accessibilityLabel|accessibilityHint|accessibilityValue)\(\"([^\"\\\n]*[\p{Han}][^\"\\\n]*)\""#
        )
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            let key = String(source[range])
            return key.contains("\\(") ? nil : key
        }
    }

    private func chineseAppCopyLiterals(in url: URL) throws -> [String] {
        let appLevelFiles = [
            "LerroApp.swift",
            "MenuBarContentView.swift",
            "RootView.swift",
            "SidebarView.swift"
        ]
        guard url.path.contains("/Features/")
                || url.path.contains("/DesignSystem/")
                || appLevelFiles.contains(url.lastPathComponent) else {
            return []
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"\"((?:\\.|[^\"\\\n])*\p{Han}(?:\\.|[^\"\\\n])*)\""#
        )
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            let key = String(source[range])
            return key.contains("\\(") ? nil : key
        }
    }

    private func dynamicSwiftUICopyViolations(in url: URL) throws -> [String] {
        let source = try String(contentsOf: url, encoding: .utf8)
        let patterns = [
            #"\b(?:Text|Button|Label)\(\s*(?!(?:LocalizedStringKey\(|verbatim:|markdown\(|\"|action:))"#,
            #"(?<![A-Za-z0-9_])\.(?:accessibilityLabel|accessibilityHint|accessibilityValue|help)\(\s*(?!(?:Text\(|localized\(|\"))"#
        ]
        return try patterns.flatMap { pattern in
            try sourceLocations(matching: pattern, in: source, url: url)
        }
    }

    private func interpolatedChinesePresentationViolations(in url: URL) throws -> [String] {
        let source = try String(contentsOf: url, encoding: .utf8)
        let presentationCall = try NSRegularExpression(
            pattern: #"(?:Text|Button|Label|Picker|Toggle|TextField|SecureField|alert|help|accessibilityLabel|accessibilityHint|accessibilityValue)\("#
        )
        let chineseCharacter = try NSRegularExpression(pattern: #"\p{Han}"#)
        return source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            let text = String(line)
            let range = NSRange(text.startIndex..., in: text)
            guard text.contains("\\("), chineseCharacter.firstMatch(in: text, range: range) != nil,
                  presentationCall.firstMatch(in: text, range: range) != nil else {
                return nil
            }
            return "\(url.lastPathComponent):\(index + 1)"
        }
    }

    private func sourceLocations(matching pattern: String, in source: String, url: URL) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: source) else { return nil }
            let line = source[..<matchRange.lowerBound].reduce(into: 1) { count, character in
                if character == "\n" { count += 1 }
            }
            return "\(url.lastPathComponent):\(line)"
        }
    }
}
