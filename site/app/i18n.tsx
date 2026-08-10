import type { Metadata } from "next";

export type Locale = "en" | "zh";

export const siteUrl = "https://lerroapp.com";
export const githubUrl = "https://github.com/Ryan-yang125/lerro";
export const downloadUrl = "https://updates.lerroapp.com/download/macos/latest";

// The English and Simplified Chinese routes use independent captures from the
// matching localized App interface.

export function localizePath(locale: Locale, path = "/") {
  if (locale === "en") return path;
  return path === "/" ? "/zh" : `/zh${path}`;
}

export function alternateLanguages(locale: Locale, path = "/") {
  return {
    canonical: localizePath(locale, path),
    languages: {
      en: path,
      "zh-CN": localizePath("zh", path),
      "x-default": path,
    },
  };
}

export function pageMetadata(locale: Locale, page: "home" | "changelog"): Metadata {
  const copy = getSiteCopy(locale);
  const path = page === "home" ? "/" : "/changelog";
  return {
    title: copy.metadata[page].title,
    description: copy.metadata[page].description,
    alternates: alternateLanguages(locale, path),
    openGraph: {
      type: "website",
      locale: locale === "zh" ? "zh_CN" : "en_US",
      url: `${siteUrl}${localizePath(locale, path)}`,
      siteName: "Lerro",
      title: copy.metadata[page].ogTitle,
      description: copy.metadata[page].description,
      images: [{ url: "/og.png", width: 1280, height: 640, alt: copy.metadata[page].ogTitle }],
    },
    twitter: {
      card: "summary_large_image",
      title: copy.metadata[page].ogTitle,
      description: copy.metadata[page].description,
      images: ["/og.png"],
    },
  };
}

export function softwareApplicationJsonLd(locale: Locale) {
  const copy = getSiteCopy(locale);
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Lerro",
    url: `${siteUrl}${localizePath(locale)}`,
    inLanguage: locale === "zh" ? "zh-Hans" : "en",
    operatingSystem: "macOS 26 or later on Apple silicon",
    applicationCategory: "UtilitiesApplication",
    softwareVersion: "1.4.0",
    description: copy.metadata.home.description,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    downloadUrl,
    softwareHelp: `${siteUrl}${localizePath(locale, "/#faq")}`,
  };
}

const copy = {
  en: {
    language: { label: "中文", ariaLabel: "Switch to Simplified Chinese" },
    metadata: {
      home: {
        title: "Lerro — Native voice typing for macOS",
        ogTitle: "Lerro — Speak. Your Mac writes.",
        description: "Live, local-first voice typing with safe undo, correction learning, and hands-free send on macOS 26.",
      },
      changelog: {
        title: "Changelog — Lerro",
        ogTitle: "Changelog — Lerro",
        description: "Every Lerro release, with concise notes and permanent signed macOS downloads.",
      },
    },
    chrome: {
      home: "Home", workflow: "How it works", product: "Product", privacy: "Privacy", changelog: "Changelog", updates: "Updates", navigation: "Primary navigation",
      download: "Download for macOS", downloadShort: "Download", footerTagline: "Voice to text, native to Mac.",
      github: "GitHub", license: "License", language: "中文",
    },
    home: {
      lang: "en", nativeVoiceTyping: "Native voice typing for macOS 26", headline: <>Speak.<br />Your Mac writes.</>,
      lede: "See words while you speak, undo or correct after delivery, and teach Lerro once. Apple Speech stays at the center of a local-first, open-source Mac workflow.",
      download: "Download for macOS", source: "View source", requirements: "Free forever · Apple silicon · macOS 26+",
      demoTitle: "Untitled", demoDate: "AUGUST 10", demoCopy: "Voice becomes context-aware text right where the cursor is.", demoTags: ["Apple Speech", "App-aware"],
      demoLabel: "Animated recreation of Lerro Live and its delivery receipt", demoDescription: "The HUD shows the target app and live transcript, processes the result, then offers a safe delivery receipt.",
      principles: ["Apple Speech", "No account", "No telemetry", "Offline after setup"],
      workflowEyebrow: "One shortcut, three paths", workflowHeadline: <>Fast. Accurate.<br />Straight to the cursor.</>,
      workflowCopy: "Lerro keeps the native path short, then adds translation or intelligence only when you choose it.",
      paths: [
        { index: "01", title: "Dictate", copy: "Apple Speech transcribes your voice and Lerro places the result at the active cursor.", flow: ["Voice", "Apple Speech", "Cursor"] },
        { index: "02", title: "Translate", copy: "Speak in one language and write in another with Apple Translation on your Mac.", flow: ["Voice", "Apple Speech", "Translation", "Cursor"] },
        { index: "03", title: "Command", copy: "Transform selected text or answer with app context using an optional local MLX model or your own API key.", flow: ["Selection or context", "MLX or BYOK", "Result"] },
      ],
      productEyebrow: "Lerro Live", productHeadline: "Visible while speaking. Reversible after writing.", productCopy: "Follow the transcript in real time, undo or correct from a focus-safe receipt, and say “send it” in apps you explicitly approve.",
      screenshots: [
        { file: "lerro-home-light.png", alt: "Lerro 1.4 home screen showing exact personalization counts and Command shortcut" },
        { file: "lerro-onboarding-shortcuts-light.png", alt: "Lerro onboarding detecting the Fn shortcut and letting the user choose hold or toggle mode", caption: "Shortcut setup tests your exact press and release events before you continue." },
        { file: "lerro-settings-light.png", alt: "Lerro shortcut settings for Dictate, Translate, and Command", caption: "Dictate, Translate, and Command each support up to four custom shortcuts." },
      ],
      privacyEyebrow: "Private by architecture", privacyHeadline: "Your voice stays close.", privacyCopy: "Apple Speech handles the core transcript. Apple Translation and the optional MLX model run on your Mac after setup. Audio saving stays off by default.", privacyLink: "Read the privacy model",
      privacyStats: ["accounts", "subscriptions", "telemetry events"], networkTitle: "Clear network boundaries", networkCopy: "Language and model setup, signed update checks, and optional BYOK providers use the network. Lerro's update service never receives audio, transcripts, or app context.",
      sourceEyebrow: "Open by default", sourceHeadline: "Inspect every product decision.", sourceCopy: "Lerro is Apache-2.0 licensed. The app, privacy policy, architecture, tests, release scripts, and website are all public.",
      faqEyebrow: "Questions, answered", faqHeadline: "Before your first dictation.",
      faqs: [
        { question: "Which permissions does Lerro request?", answer: "Microphone captures the speech you choose to dictate. Accessibility lets the global shortcut work and places finished text at the current cursor. Lerro does not request Input Monitoring or a separate Speech Recognition permission." },
        { question: "Does Lerro work offline?", answer: "Core Dictate, Apple Translation, and optional local MLX processing work offline after their language resources or model are installed. Initial resource setup, update checks, and BYOK cloud requests use a network connection." },
        { question: "Why might macOS download a language resource?", answer: "Apple Speech and Apple Translation manage language resources at the system level. A compatible resource may already be present, so setup can finish immediately; macOS downloads it when the selected language still needs one." },
        { question: "Where does my data go?", answer: "Lerro has no account system, subscription, product analytics, or telemetry. Audio saving is off by default. BYOK sends the transcript and only the context fields you enable to your chosen provider. Lerro's update service receives release requests only." },
        { question: "Which Macs are supported?", answer: "Lerro requires Apple silicon and macOS 26 or later. The optional local model uses about 3.03 GB of storage and is downloaded only after you approve it." },
        { question: "How are downloads verified?", answer: "Every public build is signed with Apple Developer ID, notarized by Apple, and distributed through Lerro's Cloudflare release service. In-app updates verify their signed update metadata before installation." },
      ],
      downloadEyebrow: "Lerro 1.4", downloadHeadline: "Speak with a visible, reversible finish.", downloadCopy: "Signed, notarized, and ready for Apple silicon Macs running macOS 26 or later.", changelog: "Read the changelog",
    },
    changelog: {
      eyebrow: "Release notes", headline: "What's new in Lerro.", lede: "Every public release in one quiet record, with a permanent signed download attached.",
      releasesLabel: "Lerro releases", version: "Version", build: "Build", download: "Download Lerro", current: "Current stable release:", downloadLatest: "Download latest",
    },
  },
  zh: {
    language: { label: "EN", ariaLabel: "切换到英文" },
    metadata: {
      home: { title: "Lerro — macOS 原生语音输入", ogTitle: "Lerro — 开口说话，Mac 为你打字。", description: "在 macOS 26 上实时显示转写、支持安全撤回与修正学习，并可确认后免手发送。" },
      changelog: { title: "更新日志 — Lerro", ogTitle: "更新日志 — Lerro", description: "Lerro 的每一次发布，包含简明说明和永久有效的已签名 macOS 下载链接。" },
    },
    chrome: { home: "首页", workflow: "工作方式", product: "产品", privacy: "隐私", changelog: "更新日志", updates: "更新", navigation: "主要导航", download: "下载 macOS 版", downloadShort: "下载", footerTagline: "原生 Mac 的语音转文字。", github: "GitHub", license: "许可证", language: "EN" },
    home: {
      lang: "zh-CN", nativeVoiceTyping: "macOS 26 原生语音输入", headline: <>开口说话。<br />Mac 为你打字。</>,
      lede: "说话时实时看见文字，写入后可以撤回或修正，教一次以后持续记住。Apple Speech 始终位于本地优先、开源的 Mac 工作流中心。", download: "下载 macOS 版", source: "查看源代码", requirements: "永久免费 · Apple 芯片 · macOS 26+",
      demoTitle: "未命名文稿", demoDate: "8 月 10 日", demoCopy: "语音会根据当前应用，在光标处变成合适的文字。", demoTags: ["Apple Speech", "感知应用"], demoLabel: "Lerro Live 与写入回执的动态演示", demoDescription: "HUD 显示目标应用与实时转写，处理完成后提供安全写入回执。",
      principles: ["Apple Speech", "无需账户", "无遥测", "完成设置后可离线使用"], workflowEyebrow: "一个快捷键，三种路径", workflowHeadline: <>快速、准确。<br />直达光标。</>, workflowCopy: "Lerro 保持原生路径简洁，在你选择时加入翻译或智能处理。",
      paths: [
        { index: "01", title: "听写", copy: "Apple Speech 转写你的语音，Lerro 将结果放入当前光标处。", flow: ["语音", "Apple Speech", "光标"] },
        { index: "02", title: "翻译", copy: "用一种语言说话，通过 Mac 上的 Apple Translation 写出另一种语言。", flow: ["语音", "Apple Speech", "翻译", "光标"] },
        { index: "03", title: "指令", copy: "使用可选的本地 MLX 模型或自己的 API Key 处理选中文字，或结合应用上下文回答。", flow: ["选区或上下文", "MLX 或 BYOK", "结果"] },
      ],
      productEyebrow: "Lerro Live", productHeadline: "说的时候看得见，写完以后能撤回。", productCopy: "实时跟随转写，通过焦点安全回执撤回或修正；在明确授权的应用里说“发送”即可免手提交。",
      screenshots: [
        { file: "lerro-home-light.png", alt: "Lerro 1.4 中文首页，显示准确的个性化计数和指令快捷键" },
        { file: "lerro-onboarding-shortcuts-light.png", alt: "Lerro 中文引导识别 Fn 快捷键，并让用户选择按住或切换模式", caption: "快捷键设置会测试每一次准确的按下和松开事件，再继续下一步。" },
        { file: "lerro-settings-light.png", alt: "Lerro 中文快捷键设置，包含听写、翻译和指令", caption: "听写、翻译和指令各自支持最多四个自定义快捷键。" },
      ],
      privacyEyebrow: "隐私源于架构", privacyHeadline: "你的声音始终留在身边。", privacyCopy: "Apple Speech 处理核心转写。设置完成后，Apple Translation 和可选的 MLX 模型都在你的 Mac 上运行。默认不会保存音频。", privacyLink: "查看隐私模型", privacyStats: ["个账户", "个订阅", "条遥测事件"], networkTitle: "清晰的网络边界", networkCopy: "语言和模型设置、已签名更新检查，以及可选的 BYOK 服务商需要联网。Lerro 的更新服务从不接收音频、转写内容或应用上下文。",
      sourceEyebrow: "默认开放", sourceHeadline: "查看每一个产品决策。", sourceCopy: "Lerro 使用 Apache-2.0 许可证。应用、隐私政策、架构、测试、发布脚本和网站都已公开。", faqEyebrow: "常见问题", faqHeadline: "开始第一次听写前。",
      faqs: [
        { question: "Lerro 会请求哪些权限？", answer: "麦克风用于采集你选择听写的语音。辅助功能让全局快捷键工作，并将完成的文字放入当前光标处。Lerro 不会请求输入监控或单独的语音识别权限。" },
        { question: "Lerro 可以离线使用吗？", answer: "语言资源或模型安装完成后，核心听写、Apple Translation 和可选的本地 MLX 处理均可离线使用。首次资源设置、更新检查和 BYOK 云端请求需要网络连接。" },
        { question: "为什么 macOS 可能下载语言资源？", answer: "Apple Speech 和 Apple Translation 在系统层面管理语言资源。兼容资源可能已存在，因此设置可立即完成；当所选语言仍需要资源时，macOS 会下载它。" },
        { question: "我的数据会发送到哪里？", answer: "Lerro 没有账户系统、订阅、产品分析或遥测。默认关闭音频保存。BYOK 会将转写内容，以及你启用的上下文字段发送给你选择的服务商。Lerro 的更新服务仅接收发布请求。" },
        { question: "支持哪些 Mac？", answer: "Lerro 需要 Apple 芯片和 macOS 26 或更高版本。可选的本地模型约占用 3.03 GB 存储空间，并且只会在你确认后下载。" },
        { question: "如何验证下载？", answer: "每个公开构建均使用 Apple Developer ID 签名、通过 Apple 公证，并由 Lerro 的 Cloudflare 发布服务分发。应用内更新会在安装前验证其已签名的更新元数据。" },
      ],
      downloadEyebrow: "Lerro 1.4", downloadHeadline: "让语音输入看得见，也能安全撤回。", downloadCopy: "已签名、已公证，适用于运行 macOS 26 或更高版本的 Apple 芯片 Mac。", changelog: "阅读更新日志",
    },
    changelog: { eyebrow: "发布说明", headline: "Lerro 的最新变化。", lede: "每一次公开发布都记录在这里，并附上永久有效的已签名下载链接。", releasesLabel: "Lerro 发布记录", version: "版本", build: "构建", download: "下载 Lerro", current: "当前稳定版本：", downloadLatest: "下载最新版" },
  },
} as const;

export function getSiteCopy(locale: Locale) {
  return copy[locale];
}
