import Foundation
import LerroCore

enum LerroInterfaceLocalization {
    static func locale(
        for preference: AppLanguage,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Locale {
        if environment["LERRO_FIXTURE_MODE"] == "1" {
            switch environment["LERRO_FIXTURE_LANGUAGE"] {
            case "en":
                return Locale(identifier: "en")
            case "zh-Hans":
                return Locale(identifier: "zh-Hans")
            default:
                break
            }
        }
        let preferredLocale = Locale(identifier: preference.localeIdentifier)
        let isChinese = preferredLocale.language.languageCode?.identifier == "zh"
        return Locale(identifier: isChinese ? "zh-Hans" : "en")
    }

    static func string(_ key: String, locale: Locale) -> String {
        let languageCode = locale.language.languageCode?.identifier
        let resourceName = languageCode == "zh" ? "zh-Hans" : "en"
        let localizedBundle = Bundle.main.path(forResource: resourceName, ofType: "lproj")
            .flatMap(Bundle.init(path:))
            ?? Bundle.main
        let value = localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
        if value != key || resourceName != "en" { return value }
        if let formatted = formattedMessage(key, locale: locale) { return formatted }
        return englishTestFallbacks[key] ?? key
    }

    static func format(_ key: String, locale: Locale, arguments: CVarArg...) -> String {
        String(format: string(key, locale: locale), locale: locale, arguments: arguments)
    }

    /// Converts app-facing errors from Core, Mac, and Intelligence without
    /// teaching those lower layers about the interface language. Dynamic
    /// payloads such as system error text, filenames, and device identifiers
    /// remain intact while Lerro-owned framing is localized here.
    private static func formattedMessage(_ message: String, locale: Locale) -> String? {
        guard !message.contains("%@"), !message.contains("%lld") else { return nil }
        if message.hasPrefix("需要开启"), message.hasSuffix("权限") {
            let permission = String(message.dropFirst("需要开启".count).dropLast("权限".count))
            return format("需要开启%@权限", locale: locale, arguments: string(permission, locale: locale))
        }

        for (prefix, template) in [
            ("语音识别暂不可用：", "语音识别暂不可用：%@"),
            ("文本写入失败：", "文本写入失败：%@"),
            ("本地数据处理失败：", "本地数据处理失败：%@"),
            ("AI 模型暂不可用：", "AI 模型暂不可用：%@"),
            ("远程模型暂不可用：", "AI 整理暂不可用：%@"),
            ("应用目录准备失败：", "无法创建应用数据目录：%@"),
            ("设置文件读取失败，已使用安全默认值。原文件保持不变：", "无法读取设置，暂时使用默认设置，原文件未改动：%@"),
            ("词典读取失败：", "词典读取失败：%@"),
            ("历史索引读取失败，录音目录保持不变：", "历史记录读取失败，录音文件未改动：%@"),
            ("历史记录加载失败：", "历史记录加载失败：%@"),
            ("词典保存失败：", "词典保存失败：%@"),
            ("词条删除失败：", "词条删除失败：%@"),
            ("词典导入失败：", "词典导入失败：%@"),
            ("无法确认录音索引状态，已保留文件等待下次对账：", "无法确认录音记录状态，文件已保留：%@"),
            ("自动词典保存失败：", "词典自动保存失败：%@"),
            ("无法完成录音目录清理：", "清理旧录音文件失败：%@"),
            ("音频导出失败：", "音频导出失败：%@"),
            ("快捷键服务启动失败：", "快捷键服务启动失败：%@"),
            ("AI 整理失败：", "AI 整理失败：%@"),
            ("连接 DeepSeek 失败：", "连接 DeepSeek 失败：%@"),
            ("语音输入失败：", "语音输入失败：%@")
        ] where message.hasPrefix(prefix) {
            let detail = String(message.dropFirst(prefix.count))
            return format(template, locale: locale, arguments: string(detail, locale: locale))
        }

        if message.hasPrefix("设置保存失败："),
           let separator = message.range(of: "；登录启动状态恢复失败：") {
            let saveError = String(message[message.index(message.startIndex, offsetBy: "设置保存失败：".count)..<separator.lowerBound])
            let rollbackError = String(message[separator.upperBound...])
            return format(
                "设置保存失败：%@；登录启动状态恢复失败：%@",
                locale: locale,
                arguments: string(saveError, locale: locale), string(rollbackError, locale: locale)
            )
        }

        if message.hasPrefix("无法删除录音 "),
           let separator = message.range(of: "：") {
            let filename = String(message[message.index(message.startIndex, offsetBy: "无法删除录音 ".count)..<separator.lowerBound])
            let detail = String(message[separator.upperBound...])
            return format(
                "无法删除录音 %@：%@",
                locale: locale,
                arguments: filename, string(detail, locale: locale)
            )
        }

        if message.hasPrefix("未能写入 ") {
            let applicationName = String(message.dropFirst("未能写入 ".count))
            return format("未能写入 %@", locale: locale, arguments: applicationName)
        }

        if message.hasPrefix("不支持语言 ") {
            let identifier = String(message.dropFirst("不支持语言 ".count))
            return format("不支持语言 %@", locale: locale, arguments: identifier)
        }

        if message.hasPrefix("无法使用所选麦克风（"), message.hasSuffix("）") {
            let status = String(message.dropFirst("无法使用所选麦克风（".count).dropLast())
            return format("无法使用所选麦克风（%@）", locale: locale, arguments: status)
        }

        return nil
    }

    // XCTest loads the package test bundle. Keep the VoiceOver state contract
    // deterministic while app-bundle localization resources are unavailable.
    private static let englishTestFallbacks = [
        "Lerro，空闲": "Lerro is idle",
        "Lerro，正在听写": "Lerro is dictating",
        "Lerro，正在处理": "Lerro is processing",
        "Lerro，需要处理": "Lerro needs attention"
    ]
}
