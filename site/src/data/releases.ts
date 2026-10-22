import type { Lang } from "../site";

export type ReleaseCopy = {
  publishedLabel: string;
  summary: string;
  highlights: readonly string[];
};

export type Release = {
  version: string;
  build: string;
  publishedAt: string;
  downloadUrl: string;
  zh: ReleaseCopy;
  en: ReleaseCopy;
};

export type LocalizedRelease = ReleaseCopy & Pick<Release, "version" | "build" | "publishedAt" | "downloadUrl">;

// Newest first. Add each published release at the top with its immutable
// distribution URL; older entries stay unchanged.
export const releases: readonly Release[] = [
  {
    version: "1.10.0",
    build: "22",
    publishedAt: "2026-10-22",
    downloadUrl: "https://updates.lerroapp.com/releases/1.10.0/22/Lerro-macOS-arm64.dmg",
    zh: {
      publishedLabel: "2026 年 10 月 22 日",
      summary: "新手引导和设置重做，开 AI 整理只要三步。",
      highlights: [
        "新手引导从 8 步减到 4 步：打开权限、试说一次、选要不要开 AI 整理、记住快捷键。",
        "开 AI 整理有三步指引：登录 DeepSeek 开放平台、充值、创建 Key 后粘贴回来，粘贴后自动连上。首次设置、首页和设置里都能找到。",
        "AI 整理只支持 DeepSeek，余额从 DeepSeek 官方读取，显示在侧边栏和设置里；余额用完时照常写原文，并提示去充值。",
        "设置从 6 页并成 5 页：通用、听写、AI 整理、隐私、关于。用量明细放进 AI 整理页。",
      ],
    },
    en: {
      publishedLabel: "October 22, 2026",
      summary: "Onboarding and Settings are rebuilt, and AI cleanup takes three steps to turn on.",
      highlights: [
        "Onboarding goes from eight steps to four: grant permissions, dictate once, choose whether to use AI cleanup, and learn the shortcuts.",
        "A three-step guide turns on AI cleanup: sign in to the DeepSeek platform, top up, then create a key and paste it, which connects automatically. It appears in onboarding, on Home and in Settings.",
        "AI cleanup supports DeepSeek only. The balance is read from DeepSeek and shown in the sidebar and Settings; when it runs out, Lerro writes the raw text and points you to top up.",
        "Settings go from six tabs to five: General, Dictation, AI Cleanup, Privacy and About. Usage details live in the AI Cleanup tab.",
      ],
    },
  },
  {
    version: "1.9.3",
    build: "21",
    publishedAt: "2026-10-22",
    downloadUrl: "https://updates.lerroapp.com/releases/1.9.3/21/Lerro-macOS-arm64.dmg",
    zh: {
      publishedLabel: "2026 年 10 月 22 日",
      summary: "词典会自己学：常被听错的名字和术语，自动记下来。",
      highlights: [
        "AI 在两次不同的听写里都纠正过的专有名词（人名、产品、公司、缩写、行业词），会自动加进词典。每个词都写着被听成过什么、来自哪几条听写，不想要可以直接删。",
        "首页新增「这周 Lerro 学会了几个词」；历史详情里，被记住的改词会标出「已记住」。",
        "词典里的词会记录实际用了多少次，发给 AI 的是用得最多的那些。",
        "去掉「从历史找词」和「快捷语」。",
      ],
    },
    en: {
      publishedLabel: "October 22, 2026",
      summary: "The dictionary learns on its own: names and terms that keep getting misheard are remembered.",
      highlights: [
        "Names, products, companies, acronyms and jargon that the AI corrects in two separate dictations are added to the dictionary automatically. Each shows what it was misheard as and which dictations it came from, and can be removed.",
        "Home shows what Lerro learned this week; in History, remembered corrections are marked.",
        "Dictionary words record how often they are used, and the most used ones are sent to the AI.",
        "Find Words in History and dictionary snippets are removed.",
      ],
    },
  },
  {
    version: "1.9.2",
    build: "20",
    publishedAt: "2026-10-21",
    downloadUrl: "https://updates.lerroapp.com/releases/1.9.2/20/Lerro-macOS-arm64.dmg",
    zh: {
      publishedLabel: "2026 年 10 月 21 日",
      summary: "修好偶尔听不到开始音效的问题。",
      highlights: [
        "开启「录音时降低其他声音」时，Mac 闲置一阵后开始音效有时听不到。现在会等开始音效放完再降低其他声音，麦克风照常立刻打开。",
        "去掉「说完自动结束」设置：它依赖的苹果语音检测实际不报告结果，一直没有生效。",
      ],
    },
    en: {
      publishedLabel: "October 21, 2026",
      summary: "The start sound no longer goes missing.",
      highlights: [
        "With lowering other audio enabled, the start sound was sometimes silent after the Mac had been idle. Lerro now waits for the start sound to finish before lowering other audio; the microphone still opens right away.",
        "The “Stop automatically when you finish speaking” setting is removed. It relied on Apple's speech detector, which reports nothing in practice, so it never took effect.",
      ],
    },
  },
  {
    version: "1.9.1",
    build: "19",
    publishedAt: "2026-10-20",
    downloadUrl: "https://updates.lerroapp.com/releases/1.9.1/19/Lerro-macOS-arm64.dmg",
    zh: {
      publishedLabel: "2026 年 10 月 20 日",
      summary: "新版本更容易发现。",
      highlights: [
        "每 4 小时检查一次新版本。正在用 Lerro 时直接弹出更新窗口；Lerro 在后台时，菜单栏图标出现小圆点，菜单栏面板第一行和主窗口侧边栏显示更新入口。",
        "下载和安装仍然由你点了才开始。",
      ],
    },
    en: {
      publishedLabel: "October 20, 2026",
      summary: "New versions are easier to notice.",
      highlights: [
        "Lerro checks for a new version every 4 hours. When you are using Lerro, the update window opens; when it is in the background, the menu bar icon gets a dot and the menu bar panel and main window sidebar show an update button.",
        "Downloading and installing still start only when you click.",
      ],
    },
  },
  {
    version: "1.9.0",
    build: "18",
    publishedAt: "2026-10-20",
    downloadUrl: "https://updates.lerroapp.com/releases/1.9.0/18/Lerro-macOS-arm64.dmg",
    zh: {
      publishedLabel: "2026 年 10 月 20 日",
      summary: "AI 做了什么、看到了什么、花了多少钱，每条听写都能看到。",
      highlights: [
        "历史详情新增「AI 处理」：AI 改了哪些词、去掉了哪些口头词，发给它的内容（你说的话、应用、词典、语气，以及哪些上下文没有发送），这次花了多少钱和怎么算的。原始请求和返回也能打开看。",
        "设置 › 用量新增调用记录，每次 AI 调用一行，点一下跳到对应的历史记录。",
        "设置 › 智能新增提示词查看：听写润色、翻译、自动学词三份提示词按段展示，配中文说明，示例做成卡片。",
        "侧边栏收起后可以用窗口左上角的按钮或 ⌃⌘S 重新打开。",
      ],
    },
    en: {
      publishedLabel: "October 20, 2026",
      summary: "See what the AI did, what it was sent, and what it cost for every dictation.",
      highlights: [
        "History adds an AI section: the words the AI corrected and the fillers it removed, what it was sent (your words, app, dictionary, tone, and which context was not sent), and what the call cost with the calculation. The raw request and reply are one click away.",
        "Settings › Usage lists every AI call; select one to open its history entry.",
        "Settings › Intelligence shows the dictation, translation and dictionary-learning prompts section by section, with the examples as cards.",
        "A collapsed sidebar comes back with the button at the top left of the window or ⌃⌘S.",
      ],
    },
  },
  {
    version: "1.8.0",
    build: "17",
    publishedAt: "2026-10-19",
    downloadUrl: "https://updates.lerroapp.com/releases/1.8.0/17/Lerro-macOS-arm64.dmg",
    zh: {
      publishedLabel: "2026 年 10 月 19 日",
      summary: "新首页统计面板，录音开始和结束有提示音。",
      highlights: [
        "首页改成统计面板：累计字数、节省时间、说话速度、听写时长和次数，一年的听写热力图和连续天数，常用 App 和常用时段。",
        "开始和结束录音时各有一声短提示音，可在 设置 › 通用 › 提示音 关闭。",
        "开启“录音时降低其他声音”后，麦克风一关，其他声音就恢复。",
        "侧边栏、设置和菜单栏图标换成 SF Symbols。",
      ],
    },
    en: {
      publishedLabel: "October 19, 2026",
      summary: "A new Home dashboard, and short sounds when a capture starts and stops.",
      highlights: [
        "Home is a usage dashboard: total characters, time saved, speaking speed, dictation time and count, a year of activity as a heatmap with streaks, most-used apps and hours.",
        "A short sound plays when a capture starts and stops. Turn it off in Settings › General › Sounds.",
        "With lowering other audio enabled, other audio returns as soon as the microphone closes.",
        "Sidebar, Settings and menu bar icons use SF Symbols.",
      ],
    },
  },
  {
    version: "1.7.2",
    build: "16",
    publishedAt: "2026-10-19",
    downloadUrl: "https://updates.lerroapp.com/releases/1.7.2/16/Lerro-macOS-arm64.dmg",
    zh: {
      publishedLabel: "2026 年 10 月 19 日",
      summary: "官网下载改成安装镜像：打开后把 Lerro 拖进“应用程序”就装好了。",
      highlights: [
        "官网下载的是已签名、已公证的 DMG 安装镜像。打开后，Lerro 和“应用程序”文件夹并排放在品牌背景上，拖过去即可安装。",
        "App 内自动更新照旧，不受影响。",
      ],
    },
    en: {
      publishedLabel: "October 19, 2026",
      summary: "The website download is now a disk image: open it and drag Lerro into Applications.",
      highlights: [
        "The website download is a signed and notarized DMG. It opens with Lerro next to the Applications folder on a branded background; drag it across to install.",
        "In-app updates work as before.",
      ],
    },
  },
  {
    version: "1.7.1",
    build: "15",
    publishedAt: "2026-10-19",
    downloadUrl: "https://updates.lerroapp.com/releases/1.7.1/15/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 10 月 19 日",
      summary: "更轻的 Lerro：移除本地 AI 模式，安装包从 11.7 MB 减到约 4 MB。",
      highlights: [
        "移除本地 AI 模式（在 Mac 上运行的 Qwen 模型）和约 3 GB 的模型下载。AI 润色和翻译使用你自己配置的 API，比如 DeepSeek。",
        "之前选了本地 AI 的设置会自动切换为只用苹果识别，其他设置保持不变。",
        "安装包从 11.7 MB 减到约 4 MB。",
      ],
    },
    en: {
      publishedLabel: "October 19, 2026",
      summary: "A lighter Lerro: the local AI mode is removed and the download drops from 11.7 MB to about 4 MB.",
      highlights: [
        "The local AI mode (the Qwen model running on your Mac) and its 3 GB download are removed. AI polish and translation use the API you configure, such as DeepSeek.",
        "If you had chosen local AI, Lerro switches to Apple-only recognition. Your other settings stay the same.",
        "The download drops from 11.7 MB to about 4 MB.",
      ],
    },
  },
  {
    version: "1.7.0",
    build: "14",
    publishedAt: "2026-10-19",
    downloadUrl: "https://updates.lerroapp.com/releases/1.7.0/14/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 10 月 19 日",
      summary: "全新的品牌与界面，中英混说识别更准，润色会像输入法一样改正听错的词。",
      highlights: [
        "新的品牌标志：一个光标立在基线上，组成 Lerro 的 L，强调色换成墨水蓝。应用图标、主窗口、侧栏和引导页都已按新品牌重做。",
        "听写 HUD 变成一颗墨黑色的玻璃胶囊，录音、实时文字、润色中和失败提示都在同一颗胶囊里切换，写入成功后直接淡出。",
        "菜单栏图标打开一个新面板，显示当前状态和录音计时、听写与翻译按钮、上一次的结果，以及今天的听写次数、字数和 AI 花费，还能直接切换麦克风和智能模式。",
        "语音识别改用 Apple SpeechTranscriber。在 40 段真实录音里，中英混说中的英文单词识别率从 39% 提高到 62%，也不会再整句丢字。",
        "AI 润色像输入法一样改正听错的词：把不通顺的词换成读音相同或相近的词，并去掉“嗯”“那个”这类口头语。在最近的听写里，8 处识别错误改对了 6 处，之前只改对 2 处。",
        "词典新增“建议”：Lerro 对比历史里听写原文和润色结果，列出可能是识别错误的词和出现次数，由你决定加入或忽略。自动学到的词条现在对所有应用生效。",
        "麦克风会先于语音分析器打开，每次听写开头的几个字不再被截掉。",
        "设置里新增“用量”页，显示远端 AI 在今天、7 天和 30 天内的 token、请求数和估算费用，并按功能和模型分类统计。",
      ],
    },
    en: {
      publishedLabel: "October 19, 2026",
      summary: "A new brand and interface, better mixed Chinese–English recognition, and AI polish that fixes misheard words like an input method.",
      highlights: [
        "A new brand mark: a cursor standing on a baseline forms the L of Lerro, with ink blue as the accent color. The app icon, main window, sidebar, and onboarding follow the new look.",
        "The dictation HUD is now a single ink-black glass capsule. Recording, live text, polishing, and failure notices all change inside the same capsule, and it fades out as soon as the text is written.",
        "The menu bar icon opens a new panel with the current status and recording timer, Dictate and Translate buttons, your last result, today's dictations, words and AI cost, and pickers to switch the microphone and intelligence mode.",
        "Speech recognition now uses Apple SpeechTranscriber. On 40 real recordings it recognized 62% of the English words in mixed Chinese–English speech, up from 39%, and no longer drops whole phrases.",
        "AI polish fixes misheard words the way an input method does: it replaces words that do not fit with words that sound the same or similar, and removes fillers. On recent dictations it fixed 6 of 8 misrecognitions, up from 2 of 8.",
        "The dictionary has a new Suggestions view. Lerro compares the raw and polished text of past dictations, lists likely recognition errors with how often they occurred, and you choose to add or ignore each one. Terms Lerro learns now apply in every app.",
        "The microphone opens before the speech analyzer is ready, so the first words of a dictation are no longer cut off.",
        "Settings has a new Usage page with remote AI tokens, requests, and estimated cost for today, 7 days, and 30 days, broken down by feature and model.",
      ],
    },
  },
  {
    version: "1.6.0",
    build: "13",
    publishedAt: "2026-08-13",
    downloadUrl: "https://updates.lerroapp.com/releases/1.6.0/13/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 13 日",
      summary: "专注于实时预览、安全写入和自动学习词汇的完整听写路径。",
      highlights: [
        "按下快捷键开始说话，居中转写随内容平滑扩宽，再按一次完成写入；成功后 HUD 立即消失。",
        "应用、输入框、文本值、选区和安全输入状态都会在写入前严格校验；失败文本保留在剪贴板，并显示紧凑恢复卡。",
        "AI 会判断用户对刚听写的人名与术语修改是否值得学习，自动加入应用词典，并同时用于 Apple Speech 与 AI 提示词。",
        "个性化成为一级页面，通过应用 Grid 管理真实图标、应用语气、启用状态和 AI 预览。",
        "八步操作型引导会真实验证隐私选择、Apple 听写、AI 选择、快捷键、首次听写、失败恢复、词典学习和应用语气。",
        "默认顺序为 Apple 听写、远端 AI、本地 AI；3.03 GB 本地模型支持后台下载、暂停、继续、停止和重启续传。",
        "生产入口已移除 Ask、Rewrite、语音跟进修改、成功回执和 Apple Translation；翻译由所选远端或本地 AI 执行，Quick Dictate 保留为默认关闭的可选项。",
      ],
    },
    en: {
      publishedLabel: "August 13, 2026",
      summary: "A focused voice-typing path with live preview, safe delivery, and vocabulary that learns.",
      highlights: [
        "Press your shortcut to speak, follow a centered transcript that expands smoothly, then press again to write; the HUD disappears immediately after success.",
        "Strict app, input field, value, selection, and secure-input checks protect the captured target; failed deliveries remain on the clipboard with a compact recovery card.",
        "AI classifies useful corrections to recently dictated names and terms, adds them to the app-aware dictionary, and feeds the same vocabulary to Apple Speech and AI prompts.",
        "Personalization is now a first-level page with an app grid, real icons, per-app tone, enablement, and AI preview.",
        "The eight-step onboarding verifies real actions for privacy, Apple dictation, AI choice, shortcuts, first dictation, recovery, dictionary learning, and app tone.",
        "Apple dictation is the default, followed by remote AI and local AI; the 3.03 GB local download supports background progress, pause, resume, stop, and restart recovery.",
        "Ask, Rewrite, spoken follow-up edits, success receipts, and Apple Translation have left the active product; Translate uses the selected remote or local AI, while Quick Dictate remains optional and off by default.",
      ],
    },
  },
  {
    version: "1.5.1",
    build: "12",
    publishedAt: "2026-08-11",
    downloadUrl: "https://updates.lerroapp.com/releases/1.5.1/12/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 11 日",
      summary: "从选择 AI 到完成第一套工作流，一次引导全部学会。",
      highlights: [
        "九步引导完整教授 AI 设置、权限、快捷键、Quick Dictate、回执、语音修改与全部工具。",
        "Lerro 根据这台 Mac 的芯片、Metal、内存和可用空间推荐本地 AI 或 API 模型。",
        "Onboarding 内可直接配置 Provider、Model、API Key、上下文并完成连接测试。",
        "本地模型支持后台下载、暂停、继续、重启恢复和明确停止。",
        "本地 AI 准备期间，Quick Dictate 继续使用 Apple Speech。",
      ],
    },
    en: {
      publishedLabel: "August 11, 2026",
      summary: "A complete first run, from choosing AI to the first finished workflow.",
      highlights: [
        "A nine-step guide teaches AI setup, permissions, shortcuts, Quick Dictate, receipts, spoken editing, and the full toolkit.",
        "Lerro recommends local AI or an API model from this Mac's chip, Metal support, memory, and free storage.",
        "OpenAI-compatible Provider, model, API key, context choices, and connection testing are available inside onboarding.",
        "Local model downloads continue in the background and support pause, resume, restart recovery, and explicit stop.",
        "Quick Dictate stays available through Apple Speech while local AI is still preparing.",
      ],
    },
  },
  {
    version: "1.5.0",
    build: "11",
    publishedAt: "2026-08-10",
    downloadUrl: "https://updates.lerroapp.com/releases/1.5.0/11/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 10 日",
      summary: "Lerro 写完以后，继续说一句就能修改。",
      highlights: [
        "Quick Dictate 按一次 Fn 开始，在说完并短暂静音后自动收尾。",
        "继续说一句即可撤销、删除指定句、精确替换，或交给已选模型完成语义改写。",
        "每次修改都绑定同一应用、焦点输入框与已写入文本指纹。",
        "版本链支持连续修改与恢复上一版。",
        "历史记录保留原始写入及其修改沿袭，便于复核。",
      ],
    },
    en: {
      publishedLabel: "August 10, 2026",
      summary: "Keep speaking to revise what Lerro just wrote.",
      highlights: [
        "Quick Dictate starts with one Fn press and finishes after speech followed by a short silence.",
        "Say a follow-up to undo, delete a sentence, replace an exact phrase, or request a semantic rewrite.",
        "Every accepted edit stays bound to the same app, focused field, and delivered text fingerprint.",
        "A version chain supports repeated edits and restoring the prior version.",
        "History keeps the original delivery and its revision lineage for review.",
      ],
    },
  },
  {
    version: "1.4.0",
    build: "10",
    publishedAt: "2026-08-10",
    downloadUrl: "https://updates.lerroapp.com/releases/1.4.0/10/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 10 日",
      summary: "实时可见、写入可撤回，并提供受控免手完成动作的语音写作。",
      highlights: [
        "Apple Speech 仍在聆听时，HUD 会显示目标应用与实时转写。",
        "写入后的焦点安全回执提供撤回和即时修正。",
        "修正保留原始、处理后与修正后的完整文本沿袭，并继续学习应用级词条。",
        "首次确认后，在明确授权的应用里说“发送”或“send it”即可提交。",
        "历史记录处理路径、上下文共享和各阶段耗时，不新增敏感上下文正文存储。",
      ],
    },
    en: {
      publishedLabel: "August 10, 2026",
      summary: "Live, reversible voice writing with a controlled hands-free finish.",
      highlights: [
        "The HUD shows the target app and transcript while Apple Speech is still listening.",
        "A focus-safe receipt offers Undo and immediate correction after delivery.",
        "Corrections preserve raw, processed, and corrected lineage and continue app-scoped learning.",
        "Saying “send it” or “发送” can submit in explicitly approved apps after a first-use confirmation.",
        "History records processing route, context sharing, and phase timings without storing new sensitive context text.",
      ],
    },
  },
  {
    version: "1.3.0",
    build: "9",
    publishedAt: "2026-08-10",
    downloadUrl: "https://updates.lerroapp.com/releases/1.3.0/9/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 10 日",
      summary: "能根据每个 Mac 应用调整表达方式的场景化语音写作。",
      highlights: [
        "应用语气让邮件、聊天、文档和代码保持合适表达。",
        "指令默认使用 Fn Space，可处理任意选中文字，也可结合当前上下文回答。",
        "语音快捷语在本机直接展开，修正会学习应用级词条。",
        "公开的 60 条固定基准持续衡量场景准确率与延迟。",
      ],
    },
    en: {
      publishedLabel: "August 10, 2026",
      summary: "Context-aware voice writing that adapts to each Mac app.",
      highlights: [
        "App styles keep mail, chat, documents, and code in the right voice.",
        "Command transforms any selected text with Fn Space or answers from the current context.",
        "Spoken snippets expand locally, while corrections teach app-scoped terms.",
        "A public 60-case benchmark keeps contextual accuracy and latency measurable.",
      ],
    },
  },
  {
    version: "1.2.0",
    build: "8",
    publishedAt: "2026-08-04",
    downloadUrl: "https://updates.lerroapp.com/releases/1.2.0/8/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 4 日",
      summary: "Lerro 现已在应用和公开官网中支持英文与简体中文。",
      highlights: [
        "应用界面现已支持英文与简体中文。",
        "网站和公开文档现已提供对应的英文与简体中文路由。",
        "发布截图现已按语言提供两套产品界面。",
      ],
    },
    en: {
      publishedLabel: "August 4, 2026",
      summary: "Lerro now speaks English and Simplified Chinese across the app and its public home.",
      highlights: [
        "The app interface now supports English and Simplified Chinese.",
        "The website and public documentation now offer matching English and Simplified Chinese routes.",
        "Release screenshots now ship in language-specific sets for both product surfaces.",
      ],
    },
  },
  {
    version: "1.1.1",
    build: "7",
    publishedAt: "2026-08-04",
    downloadUrl: "https://updates.lerroapp.com/releases/1.1.1/7/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 4 日",
      summary: "更可靠的 Fn 快捷键，让 macOS Emoji 不再干扰录音。",
      highlights: [
        "内建 Fn 和外接 Globe 键现在使用统一的物理按键所有权模型。",
        "每个已配置的 Fn 序列都会持续捕获到最终松开，包括重复的修饰键事件。",
        "快捷键监听现在仅观察键盘事件，并保持同样的两项权限设置。",
      ],
    },
    en: {
      publishedLabel: "August 4, 2026",
      summary: "Reliable Fn shortcuts that keep macOS Emoji out of the way.",
      highlights: [
        "Built-in Fn and external Globe keys now use one physical-key ownership model.",
        "Every configured Fn sequence stays captured through its final release, including repeated modifier events.",
        "Shortcut monitoring now observes keyboard events only and keeps the same two-permission setup.",
      ],
    },
  },
  {
    version: "1.1.0",
    build: "6",
    publishedAt: "2026-08-04",
    downloadUrl: "https://updates.lerroapp.com/releases/1.1.0/6/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 4 日",
      summary: "更快的快捷键、更深入的 Apple Speech 集成，以及设备端翻译。",
      highlights: [
        "Fn 快捷键采用更清晰的两项权限设置，并避开 Globe 菜单。",
        "Apple Speech 更可靠地处理实时修订和音频结束。",
        "翻译现在在设备端使用 Apple Translation，并提供更清晰的语言资源设置。",
        "引导、快捷键设置、空闲 HUD 和更新下载都更容易使用。",
        "网站和 GitHub 现已展示当前产品、真实截图和镜像发布产物。",
      ],
    },
    en: {
      publishedLabel: "August 4, 2026",
      summary: "Faster shortcuts, deeper Apple Speech, and device-side translation.",
      highlights: [
        "Fn shortcuts now use a cleaner two-permission setup and avoid the Globe menu.",
        "Apple Speech handles live revisions and audio endings more reliably.",
        "Translate now uses Apple Translation on the device, with clearer language-resource setup.",
        "Onboarding, shortcut settings, the idle HUD, and update downloads are easier to use.",
        "The website and GitHub now show the current product, real screenshots, and mirrored release artifacts.",
      ],
    },
  },
  {
    version: "1.0.3",
    build: "5",
    publishedAt: "2026-08-02",
    downloadUrl: "https://updates.lerroapp.com/releases/1.0.3/5/Lerro-macOS-arm64.zip",
    zh: {
      publishedLabel: "2026 年 8 月 2 日",
      summary: "首个公开稳定版更新。",
      highlights: [
        "自动更新会在 Lerro 内交付已签名、已公证的发布版本。",
        "公开下载已针对 Apple 芯片上的 macOS 26 完成验证。",
      ],
    },
    en: {
      publishedLabel: "August 2, 2026",
      summary: "The first public stable update.",
      highlights: [
        "Automatic updates deliver signed, notarized releases inside Lerro.",
        "The public download is verified for macOS 26 on Apple silicon.",
      ],
    },
  },
];

export function getReleases(lang: Lang): readonly LocalizedRelease[] {
  return releases.map(({ zh, en, ...base }) => ({ ...base, ...(lang === "zh" ? zh : en) }));
}
