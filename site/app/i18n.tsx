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
    softwareVersion: "1.6.0",
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
        description: "Native macOS voice typing with centered live preview, safe delivery, automatic dictionary learning, and optional local or remote AI.",
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
      lede: "Press your shortcut, follow the live transcript, then press again to write. Apple Speech keeps the core path immediate; optional AI adds polish, translation, automatic vocabulary learning, and per-app tone.",
      download: "Download for macOS", source: "View source", requirements: "Free forever · Apple silicon · macOS 26+",
      demoTitle: "Untitled", demoDate: "AUGUST 13", demoCopy: "Voice becomes context-aware text right where the cursor is.", demoTags: ["Apple Speech", "App-aware"],
      demoLabel: "Animated recreation of Lerro's centered live transcript", demoDescription: "The centered HUD expands smoothly with the live transcript, processes the result, writes at the captured cursor, and disappears after success.",
      principles: ["Apple Speech", "AI is optional", "No telemetry", "Open source"],
      workflowEyebrow: "One shortcut, one clear path", workflowHeadline: <>See every word.<br />Straight to the cursor.</>,
      workflowCopy: "Press once to speak, watch the centered preview grow, then press again to finish. A successful delivery ends there; a recovery card appears only when writing fails.",
      paths: [
        { index: "01", title: "Dictate", copy: "Apple Speech uses your app-aware dictionary, while Lerro previews every word and safely writes the final text.", flow: ["Shortcut", "Live preview", "Apple Speech", "Cursor"] },
        { index: "02", title: "Polish", copy: "Your selected local or remote AI applies dictionary terms and the tone saved for the current app.", flow: ["Apple Speech", "Dictionary + tone", "Selected AI", "Cursor"] },
        { index: "03", title: "Translate", copy: "Speak naturally and let the selected local or remote AI translate the final transcript before delivery.", flow: ["Apple Speech", "Selected AI", "Translation", "Cursor"] },
      ],
      productEyebrow: "Lerro Personalization", productHeadline: "It learns your words. It fits every app.", productCopy: "Correct a recently dictated name or term and AI can add the useful mapping to your app-aware dictionary. Personalization keeps each app's icon, tone, AI preview, and enablement in one first-level page.",
      screenshots: [
        { file: "lerro-home-light.png", alt: "Lerro home screen with recent dictation and personalization status" },
        { file: "lerro-onboarding-shortcuts-light.png", alt: "Lerro onboarding recording and testing the user's actual dictation shortcut", caption: "The eight-step onboarding advances through verified actions, from permissions and AI choice to a real first dictation." },
        { file: "lerro-settings-light.png", alt: "Lerro settings for Dictate and Translate shortcuts", caption: "Manual finish is the default. Quick Dictate is an optional setting that finishes after a short silence." },
      ],
      privacyEyebrow: "Private by architecture", privacyHeadline: "Your voice stays close.", privacyCopy: "Apple Speech handles the core transcript. Optional intelligence runs through the local MLX model or the remote provider you configure. Audio saving stays off by default.", privacyLink: "Read the privacy model",
      privacyStats: ["accounts", "subscriptions", "telemetry events"], networkTitle: "Clear network boundaries", networkCopy: "Remote polish and translation send the transcript and enabled context to your provider. Automatic learning sends the smallest recent correction span for classification. Local AI keeps both operations on your Mac.",
      sourceEyebrow: "Open by default", sourceHeadline: "Inspect every product decision.", sourceCopy: "Lerro is Apache-2.0 licensed. The app, privacy policy, architecture, tests, release scripts, and website are all public.",
      faqEyebrow: "Questions, answered", faqHeadline: "Before your first dictation.",
      faqs: [
        { question: "Which permissions does Lerro request?", answer: "Microphone and Speech Recognition power Apple dictation. Accessibility enables the global shortcut, captures the target field, writes finished text, and observes a recent correction when automatic dictionary learning is enabled." },
        { question: "Does Lerro work offline?", answer: "Core Apple dictation works after its language resources are ready. The optional local MLX model keeps polish, translation, app tone, and dictionary learning offline after its 3.03 GB download. Remote AI uses your configured provider." },
        { question: "Why might macOS download a language resource?", answer: "Apple Speech manages dictation resources at the system level. A compatible resource may already be present; macOS downloads one when the selected language needs it." },
        { question: "Where does my data go?", answer: "Lerro has no account system, subscription, product analytics, or telemetry. Audio saving is off by default. Your configured remote provider receives only the transcript, enabled context, or minimal correction span required for the AI action. Local AI keeps those actions on your Mac." },
        { question: "Which Macs are supported?", answer: "Lerro requires Apple silicon and macOS 26 or later. The optional local model uses about 3.03 GB of storage and is downloaded only after you approve it." },
        { question: "How are downloads verified?", answer: "Every public build is signed with Apple Developer ID, notarized by Apple, and distributed through Lerro's Cloudflare release service. In-app updates verify their signed update metadata before installation." },
      ],
      downloadEyebrow: "Lerro 1.6", downloadHeadline: "Speak. Preview. Write. Done.", downloadCopy: "Signed, notarized, and ready for Apple silicon Macs running macOS 26 or later.", changelog: "Read the changelog",
    },
    changelog: {
      eyebrow: "Release notes", headline: "What's new in Lerro.", lede: "Every public release in one quiet record, with a permanent signed download attached.",
      releasesLabel: "Lerro releases", version: "Version", build: "Build", download: "Download Lerro", current: "Current stable release:", downloadLatest: "Download latest",
    },
  },
  zh: {
    language: { label: "EN", ariaLabel: "切换到英文" },
    metadata: {
      home: { title: "Lerro — macOS 原生语音输入", ogTitle: "Lerro — 开口说话，Mac 为你打字。", description: "原生 macOS 语音输入，提供居中实时预览、安全写入、自动词典学习，以及可选的本地或远端 AI。" },
      changelog: { title: "更新日志 — Lerro", ogTitle: "更新日志 — Lerro", description: "Lerro 的每一次发布，包含简明说明和永久有效的已签名 macOS 下载链接。" },
    },
    chrome: { home: "首页", workflow: "工作方式", product: "产品", privacy: "隐私", changelog: "更新日志", updates: "更新", navigation: "主要导航", download: "下载 macOS 版", downloadShort: "下载", footerTagline: "原生 Mac 的语音转文字。", github: "GitHub", license: "许可证", language: "EN" },
    home: {
      lang: "zh-CN", nativeVoiceTyping: "macOS 26 原生语音输入", headline: <>开口说话。<br />Mac 为你打字。</>,
      lede: "按下快捷键，实时查看转写，再按一次完成写入。Apple Speech 保持核心路径即时可用；可选 AI 提供润色、翻译、自动词典学习和应用语气。", download: "下载 macOS 版", source: "查看源代码", requirements: "永久免费 · Apple 芯片 · macOS 26+",
      demoTitle: "未命名文稿", demoDate: "8 月 13 日", demoCopy: "语音会根据当前应用，在光标处变成合适的文字。", demoTags: ["Apple Speech", "感知应用"], demoLabel: "Lerro 居中实时转写动态演示", demoDescription: "HUD 随实时转写从中心平滑扩宽，完成处理后写入锁定的光标，成功后立即消失。",
      principles: ["Apple Speech", "AI 可选", "无遥测", "开源"], workflowEyebrow: "一个快捷键，一条清晰路径", workflowHeadline: <>字字可见。<br />直达光标。</>, workflowCopy: "按一下开始说话，居中预览随文字增长，再按一下完成。成功写入后流程立即结束；写入失败时才显示恢复卡。",
      paths: [
        { index: "01", title: "听写", copy: "Apple Speech 使用当前应用的词典，Lerro 实时预览每个字并安全写入最终文本。", flow: ["快捷键", "实时预览", "Apple Speech", "光标"] },
        { index: "02", title: "润色", copy: "已选择的本地或远端 AI 会使用词典词条和当前应用保存的语气。", flow: ["Apple Speech", "词典与语气", "已选 AI", "光标"] },
        { index: "03", title: "翻译", copy: "自然说话，由已选择的本地或远端 AI 在写入前翻译最终转写。", flow: ["Apple Speech", "已选 AI", "翻译", "光标"] },
      ],
      productEyebrow: "Lerro 个性化", productHeadline: "学会你的词，适应每个应用。", productCopy: "修改刚刚听写的人名或术语后，AI 可以将有价值的映射加入应用词典。个性化一级页面集中管理应用图标、语气、AI 预览和启用状态。",
      screenshots: [
        { file: "lerro-home-light.png", alt: "Lerro 中文首页，显示最近听写和个性化状态" },
        { file: "lerro-onboarding-shortcuts-light.png", alt: "Lerro 引导录制并测试用户实际使用的听写快捷键", caption: "八步操作型引导逐项验证权限、AI 选择、快捷键和第一次真实听写。" },
        { file: "lerro-settings-light.png", alt: "Lerro 听写与翻译快捷键设置", caption: "手动结束为默认方式；Quick Dictate 可选开启，并在短暂静音后结束。" },
      ],
      privacyEyebrow: "隐私源于架构", privacyHeadline: "你的声音始终留在身边。", privacyCopy: "Apple Speech 处理核心转写。可选智能能力通过本地 MLX 模型或你配置的远端服务商运行。默认关闭音频保存。", privacyLink: "查看隐私模型", privacyStats: ["个账户", "个订阅", "条遥测事件"], networkTitle: "清晰的网络边界", networkCopy: "远端润色和翻译会把转写与启用的上下文发送给你的服务商。自动学习只发送最近修改的最小片段用于分类。本地 AI 会在 Mac 上完成这些操作。",
      sourceEyebrow: "默认开放", sourceHeadline: "查看每一个产品决策。", sourceCopy: "Lerro 使用 Apache-2.0 许可证。应用、隐私政策、架构、测试、发布脚本和网站都已公开。", faqEyebrow: "常见问题", faqHeadline: "开始第一次听写前。",
      faqs: [
        { question: "Lerro 会请求哪些权限？", answer: "麦克风和语音识别用于 Apple 听写。辅助功能用于全局快捷键、锁定目标输入框、写入文字，并在开启自动词典学习时观察一次最近修改。" },
        { question: "Lerro 可以离线使用吗？", answer: "Apple 听写的语言资源就绪后即可完成核心听写。可选的本地 MLX 模型下载 3.03 GB 后，可离线完成润色、翻译、应用语气和词典学习。远端 AI 使用你配置的服务商。" },
        { question: "为什么 macOS 可能下载语言资源？", answer: "Apple Speech 在系统层面管理听写资源。兼容资源可能已经存在；所选语言需要资源时，macOS 会自动下载。" },
        { question: "我的数据会发送到哪里？", answer: "Lerro 没有账户系统、订阅、产品分析或遥测。默认关闭音频保存。你配置的远端服务商只会收到 AI 操作所需的转写、已启用上下文或最小修正片段。本地 AI 会在 Mac 上完成这些操作。" },
        { question: "支持哪些 Mac？", answer: "Lerro 需要 Apple 芯片和 macOS 26 或更高版本。可选的本地模型约占用 3.03 GB 存储空间，并且只会在你确认后下载。" },
        { question: "如何验证下载？", answer: "每个公开构建均使用 Apple Developer ID 签名、通过 Apple 公证，并由 Lerro 的 Cloudflare 发布服务分发。应用内更新会在安装前验证其已签名的更新元数据。" },
      ],
      downloadEyebrow: "Lerro 1.6", downloadHeadline: "说话、预览、写入、完成。", downloadCopy: "已签名、已公证，适用于运行 macOS 26 或更高版本的 Apple 芯片 Mac。", changelog: "阅读更新日志",
    },
    changelog: { eyebrow: "发布说明", headline: "Lerro 的最新变化。", lede: "每一次公开发布都记录在这里，并附上永久有效的已签名下载链接。", releasesLabel: "Lerro 发布记录", version: "版本", build: "构建", download: "下载 Lerro", current: "当前稳定版本：", downloadLatest: "下载最新版" },
  },
} as const;

export function getSiteCopy(locale: Locale) {
  return copy[locale];
}
