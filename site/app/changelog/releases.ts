import type { Locale } from "../i18n";

export type Release = {
  version: string;
  build: string;
  publishedAt: string;
  publishedLabel: string;
  summary: string;
  highlights: readonly string[];
  downloadUrl: string;
};

// Add each published release here. Immutable URLs stay attached to the version
// they shipped with, while the homepage always points to the latest release.
const releases: readonly Release[] = [
  {
    version: "1.4.0",
    build: "10",
    publishedAt: "2026-08-10",
    publishedLabel: "August 10, 2026",
    summary: "Live, reversible voice writing with a controlled hands-free finish.",
    highlights: [
      "The HUD shows the target app and transcript while Apple Speech is still listening.",
      "A focus-safe receipt offers Undo and immediate correction after delivery.",
      "Corrections preserve raw, processed, and corrected lineage and continue app-scoped learning.",
      "Saying “send it” or “发送” can submit in explicitly approved apps after a first-use confirmation.",
      "History records processing route, context sharing, and phase timings without storing new sensitive context text.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.4.0/10/Lerro-macOS-arm64.zip",
  },
  {
    version: "1.3.0",
    build: "9",
    publishedAt: "2026-08-10",
    publishedLabel: "August 10, 2026",
    summary: "Context-aware voice writing that adapts to each Mac app.",
    highlights: [
      "App styles keep mail, chat, documents, and code in the right voice.",
      "Command transforms any selected text with Fn Space or answers from the current context.",
      "Spoken snippets expand locally, while corrections teach app-scoped terms.",
      "A public 60-case benchmark keeps contextual accuracy and latency measurable.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.3.0/9/Lerro-macOS-arm64.zip",
  },
  {
    version: "1.2.0",
    build: "8",
    publishedAt: "2026-08-04",
    publishedLabel: "August 4, 2026",
    summary: "Lerro now speaks English and Simplified Chinese across the app and its public home.",
    highlights: [
      "The app interface now supports English and Simplified Chinese.",
      "The website and public documentation now offer matching English and Simplified Chinese routes.",
      "Release screenshots now ship in language-specific sets for both product surfaces.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.2.0/8/Lerro-macOS-arm64.zip",
  },
  {
    version: "1.1.1",
    build: "7",
    publishedAt: "2026-08-04",
    publishedLabel: "August 4, 2026",
    summary: "Reliable Fn shortcuts that keep macOS Emoji out of the way.",
    highlights: [
      "Built-in Fn and external Globe keys now use one physical-key ownership model.",
      "Every configured Fn sequence stays captured through its final release, including repeated modifier events.",
      "Shortcut monitoring now observes keyboard events only and keeps the same two-permission setup.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.1.1/7/Lerro-macOS-arm64.zip",
  },
  {
    version: "1.1.0",
    build: "6",
    publishedAt: "2026-08-04",
    publishedLabel: "August 4, 2026",
    summary: "Faster shortcuts, deeper Apple Speech, and device-side translation.",
    highlights: [
      "Fn shortcuts now use a cleaner two-permission setup and avoid the Globe menu.",
      "Apple Speech handles live revisions and audio endings more reliably.",
      "Translate now uses Apple Translation on the device, with clearer language-resource setup.",
      "Onboarding, shortcut settings, the idle HUD, and update downloads are easier to use.",
      "The website and GitHub now show the current product, real screenshots, and mirrored release artifacts.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.1.0/6/Lerro-macOS-arm64.zip",
  },
  {
    version: "1.0.3",
    build: "5",
    publishedAt: "2026-08-02",
    publishedLabel: "August 2, 2026",
    summary: "The first public stable update.",
    highlights: [
      "Automatic updates deliver signed, notarized releases inside Lerro.",
      "The public download is verified for macOS 26 on Apple silicon.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.0.3/5/Lerro-macOS-arm64.zip",
  },
];

const chineseReleaseCopy = [
  {
    publishedLabel: "2026 年 8 月 10 日",
    summary: "实时可见、写入可撤回，并提供受控免手完成动作的语音写作。",
    highlights: ["Apple Speech 仍在聆听时，HUD 会显示目标应用与实时转写。", "写入后的焦点安全回执提供撤回和即时修正。", "修正保留原始、处理后与修正后的完整文本沿袭，并继续学习应用级词条。", "首次确认后，在明确授权的应用里说“发送”或“send it”即可提交。", "历史记录处理路径、上下文共享和各阶段耗时，不新增敏感上下文正文存储。"],
  },
  {
    publishedLabel: "2026 年 8 月 10 日",
    summary: "能根据每个 Mac 应用调整表达方式的场景化语音写作。",
    highlights: ["应用语气让邮件、聊天、文档和代码保持合适表达。", "指令默认使用 Fn Space，可处理任意选中文字，也可结合当前上下文回答。", "语音快捷语在本机直接展开，修正会学习应用级词条。", "公开的 60 条固定基准持续衡量场景准确率与延迟。"],
  },
  {
    publishedLabel: "2026 年 8 月 4 日",
    summary: "Lerro 现已在应用和公开官网中支持英文与简体中文。",
    highlights: ["应用界面现已支持英文与简体中文。", "网站和公开文档现已提供对应的英文与简体中文路由。", "发布截图现已按语言提供两套产品界面。"],
  },
  {
    publishedLabel: "2026 年 8 月 4 日",
    summary: "更可靠的 Fn 快捷键，让 macOS Emoji 不再干扰录音。",
    highlights: ["内建 Fn 和外接 Globe 键现在使用统一的物理按键所有权模型。", "每个已配置的 Fn 序列都会持续捕获到最终松开，包括重复的修饰键事件。", "快捷键监听现在仅观察键盘事件，并保持同样的两项权限设置。"],
  },
  {
    publishedLabel: "2026 年 8 月 4 日",
    summary: "更快的快捷键、更深入的 Apple Speech 集成，以及设备端翻译。",
    highlights: ["Fn 快捷键采用更清晰的两项权限设置，并避开 Globe 菜单。", "Apple Speech 更可靠地处理实时修订和音频结束。", "翻译现在在设备端使用 Apple Translation，并提供更清晰的语言资源设置。", "引导、快捷键设置、空闲 HUD 和更新下载都更容易使用。", "网站和 GitHub 现已展示当前产品、真实截图和镜像发布产物。"],
  },
  {
    publishedLabel: "2026 年 8 月 2 日",
    summary: "首个公开稳定版更新。",
    highlights: ["自动更新会在 Lerro 内交付已签名、已公证的发布版本。", "公开下载已针对 Apple 芯片上的 macOS 26 完成验证。"],
  },
] as const;

export function getReleases(locale: Locale): readonly Release[] {
  if (locale === "en") return releases;
  return releases.map((release, index) => ({ ...release, ...chineseReleaseCopy[index] }));
}
