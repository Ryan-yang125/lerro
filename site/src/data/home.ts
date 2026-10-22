import { currentVersion, type Lang } from "../site";

/** Avatar scene names drawn in components/home/avatars.ts. */
export type AvatarName = "me" | "person2" | "hills" | "sea" | "peak" | "leaf" | "flower" | "cat" | "folder" | "book";

/** App icon file names in public/apps/<name>.png. */
export type AppIcon =
  | "wechat" | "feishu" | "dingtalk" | "wecom" | "mail" | "notes" | "word" | "wps"
  | "pages" | "notion" | "safari" | "chrome" | "chatgpt" | "claude" | "keynote";

/** Token kinds in the speech cloud: f = filler (removed), x = wrong (struck, removed), k = kept and highlighted. */
export type TokenKind = "f" | "x" | "k";

/**
 * Demo content shown inside the mock app windows. Lerro's dictation examples are
 * Chinese recordings, so this block is the same on both language pages.
 */
export const demo = {
  wechat: {
    unread: "3",
    search: "搜索",
    title: "产品小组",
    members: "(6)",
    time: "今天 14:30",
    send: "发送",
    rows: [
      { name: "产品小组", time: "14:32", preview: "周婷：我周三下午可以", group: ["hills", "sea", "leaf", "person2"] as AvatarName[], on: true },
      { name: "妈妈", time: "12:05", preview: "周末回来吃饭吗？做了你爱吃的", avatar: "flower" as AvatarName, badge: true },
      { name: "吴经理", time: "11:40", preview: "方案我看了，整体可以", avatar: "peak" as AvatarName },
      { name: "陈晓", time: "昨天", preview: "[图片]", avatar: "cat" as AvatarName },
      { name: "文件传输助手", time: "昨天", preview: "[文件] 下季度预算.xlsx", avatar: "folder" as AvatarName },
      { name: "周末读书会", time: "星期二", preview: "本周书单已更新", avatar: "book" as AvatarName },
    ],
    messages: [
      { who: "小林", avatar: "sea" as AvatarName, text: "这周大家都挺忙的，周会要不要改个时间？" },
      { who: "周婷", avatar: "person2" as AvatarName, text: "我周三下午可以" },
    ],
  },
  mail: {
    title: "下季度预算",
    toLabel: "收件人：",
    toName: "吴经理",
    ccLabel: "抄送：",
    subjectLabel: "主题：",
  },
  notes: {
    folders: [["备忘录", "24"], ["工作", "9"], ["读书", "6"], ["最近删除", "2"]] as [string, string][],
    list: [
      { title: "周报 10/24", meta: "14:40 本周完成…", on: true },
      { title: "下季度目标", meta: "昨天 OKR 草稿" },
      { title: "面试记录", meta: "星期二" },
      { title: "读书笔记", meta: "上周" },
    ],
    date: "2026年10月24日 14:40",
    title: "周报 10/24",
  },
  scenes: [
    {
      icon: "wechat" as AppIcon,
      field: "field0",
      toks: [["嗯", "f"], ["那个", "f"], ["周会"], ["要不"], ["改到"], ["周二", "x"], ["算了不对", "x"], ["周三", "k"], ["下午"], ["三点吧"], ["我先把"], ["议程"], ["发群里"]] as [string, TokenKind?][],
      final: "周会改到周三下午三点吧，我先把议程发群里。",
    },
    {
      icon: "mail" as AppIcon,
      field: "field1",
      toks: [["吴总您好"], ["关于"], ["下季度的"], ["预算"], ["呃", "f"], ["我们"], ["初步算了"], ["大概"], ["一百二十万"], ["比上季度"], ["多百分之十五"], ["然后", "f"], ["详细表格"], ["在附件里"], ["麻烦您看一下"]] as [string, TokenKind?][],
      final: "吴总您好，\n\n关于下季度预算，我们初步估算约 120 万元，比上季度增加 15%。\n\n详细表格在附件中，麻烦您过目。",
    },
    {
      icon: "notes" as AppIcon,
      field: "field2",
      toks: [["这周"], ["做了三件事"], ["第一个是"], ["新版本上线了"], ["第二个"], ["跟设计"], ["对了下月改版"], ["第三个"], ["就是", "f"], ["招聘"], ["面了五个人"], ["两个不错"]] as [string, TokenKind?][],
      final: "本周完成：\n1. 新版本上线\n2. 和设计对齐下月改版\n3. 招聘面试 5 人，2 人合适",
    },
  ],
  race: "周五前把方案整理好发给吴经理，记得附上预算表和上线时间。",
  tryPhrase: "今天就少打一点字",
  learn: [
    { from: "小林子", to: "小琳" },
    { from: "飞书文当", to: "飞书文档" },
    { from: "OKAR", to: "OKR" },
  ],
  fix: { wrong: "上午十点", right: "下午三点", before: "明天", after: "开会" },
  translate: { zh: "麻烦把报价单发我一下，谢谢", en: "Could you send me the quotation? Thanks." },
  sayChip: "周五前把方案发我",
  apps: ["wechat", "feishu", "dingtalk", "wecom", "mail", "notes", "word", "wps", "pages", "notion", "safari", "chrome", "chatgpt", "claude", "keynote"] as AppIcon[],
};

export interface HomeCopy {
  meta: { title: string; description: string };
  nav: { how: string; price: string; faq: string; download: string };
  hero: {
    /** h1 is `line1`, a line break, then `soft` (dimmed) and `rest`; spaces are part of the strings. */
    h1: { line1: string; soft: string; rest: string };
    lead: string;
    download: string;
    story: string;
    req: string;
    scroll: string;
  };
  story: {
    steps: [string, string, string, string];
    hudListening: string;
    hudPolishing: string;
    key: { line1: string; line2: string };
    scenes: { app: string; titles: [string, string, string, string] }[];
  };
  apps: { lead: string; names: string[] };
  speed: {
    h2: { pre: string; em: string; post: string };
    lead: string;
    typing: string;
    talking: string;
    unit: string;
    done: string;
  };
  features: {
    eyebrow: string;
    h2: string;
    learn: { h3: string; p: string; remembered: string };
    tone: { h3: string; p: string; items: string[] };
    fix: { h3: string; p: string };
    translate: { h3: string; p: string };
    menu: { h3: string; p: string; rows: [string, string][] };
  };
  how: {
    eyebrow: string;
    h2: string;
    lead: string;
    steps: { h3: string; p: string }[];
    permissions: [string, string];
    note: string;
  };
  price: {
    eyebrow: string;
    h2: [string, string];
    free: { tag: string; amount: string; items: string[] };
    ai: { tag: string; amount: string; unit: string; items: string[]; fine: string };
  };
  privacy: {
    eyebrow: string;
    h2: [string, string];
    items: string[];
    orbs: [string, string, string, string];
  };
  faq: { h2: string; items: { q: string; a: string }[] };
  final: {
    h2: string;
    lead: string;
    idle: string;
    short: string;
    written: string;
    download: string;
    req: string;
  };
}

const zh: HomeCopy = {
  meta: {
    title: "Lerro — Mac 上的语音输入",
    description: "按一下快捷键说话，再按一下，文字写进光标所在的地方。中英文混着说，专有名词也能写对。",
  },
  nav: { how: "怎么开始", price: "价格", faq: "常见问题", download: "免费下载" },
  hero: {
    h1: { line1: "说出来，", soft: "就", rest: "写好了" },
    lead: "回微信、写邮件、整理周报，按一下快捷键说就行。口头禅自动去掉，说错的地方自动改好，标点和分段也帮你加上。",
    download: "免费下载 Mac 版",
    story: "往下看它怎么工作",
    req: "macOS 26 · Apple 芯片 · 免费、开源、不用注册",
    scroll: "往下滚动",
  },
  story: {
    steps: ["按一下", "说出来", "AI 整理", "写进去"],
    hudListening: "正在听…",
    hudPolishing: "AI 正在整理…",
    key: { line1: "按一下开始", line2: "再按一下结束" },
    scenes: [
      { app: "在微信里回消息", titles: ["按一下 fn，开始说", "想到哪说到哪", "AI 帮你整理", "写进去，发出去"] },
      { app: "在邮件里写给领导", titles: ["换个 App，接着说", "说一大段也没关系", "AI 分好段、写清数字", "一封像样的邮件"] },
      { app: "在备忘录里写周报", titles: ["想到什么说什么", "说「第一、第二」", "AI 帮你排成清单", "周报写好了"] },
    ],
  },
  apps: {
    lead: "光标在哪儿，字就写到哪儿",
    names: ["微信", "飞书", "钉钉", "企业微信", "邮件", "备忘录", "Word", "WPS", "Pages", "Notion", "Safari", "Chrome", "ChatGPT", "Claude", "Keynote"],
  },
  speed: {
    h2: { pre: "说话比打字", em: "快 4 倍", post: "" },
    lead: "同一句话，上面一个字一个字敲，下面张嘴说完就写好了。",
    typing: "打字",
    talking: "用 Lerro 说",
    unit: "字",
    done: "写好了",
  },
  features: {
    eyebrow: "越用越顺手",
    h2: "它会记住你的说话习惯",
    learn: {
      h3: "常说的名字和词，会自己记住",
      p: "同事的名字、公司的产品、行业里的说法，第一次可能写错。AI 改对两次以后，Lerro 就记下来了，不用你手动加。",
      remembered: "已记住",
    },
    tone: {
      h3: "在哪个 App，用哪种口吻",
      p: "给每个 App 设一句要求，切过去自动换。",
      items: ["微信：轻松一点，可以带语气词", "邮件：完整句子，礼貌", "备忘录：要点清楚，便于扫读"],
    },
    fix: { h3: "说错了，直接改口", p: "说「不对」「改成」，只留下你最后的意思。" },
    translate: { h3: "说中文，写英文", p: "换一个快捷键，说中文直接写出英文。" },
    menu: {
      h3: "菜单栏里随手可用",
      p: "上一句没写进去？在菜单栏里一键复制。",
      rows: [["今天", "38 次 · 1,920 字"], ["上一句", "粘贴 ⌃⌘V"], ["AI 花费", "¥0.04"]],
    },
  },
  how: {
    eyebrow: "两分钟装好",
    h2: "三步，开口就能用",
    lead: "不用注册账号，不用会编程。",
    steps: [
      { h3: "下载，拖进「应用程序」", p: "和装其他 Mac 软件一样。" },
      { h3: "打开，允许两个权限", p: "麦克风用来听你说话，辅助功能用来把字写进去。" },
      { h3: "按一下快捷键，开始说", p: "再按一下结束，字就写在光标那里。" },
    ],
    permissions: ["麦克风", "辅助功能"],
    note: "装好就能用，完全免费。想让文字更通顺，再开一下 AI 整理。",
  },
  price: {
    eyebrow: "价格",
    h2: ["免费用，", "想更聪明再花几毛钱"],
    free: { tag: "基础版", amount: "免费", items: ["苹果本机识别，说什么写什么", "所有 App 里都能用", "不用注册，没有次数限制"] },
    ai: {
      tag: "开启 AI 整理",
      amount: "¥1",
      unit: "/ 约 1000 次",
      items: ["去掉口头禅，自动改错字、加标点", "按 App 换口吻，中译英", "常说的词会自己记住"],
      fine: "用你自己的 DeepSeek 账号，按用量付费，充 10 块够用很久。Lerro 的引导会一步步带你填好。",
    },
  },
  privacy: {
    eyebrow: "隐私",
    h2: ["你说的话，", "留在你自己的 Mac 上"],
    items: [
      "语音由苹果在本机识别，录音默认不保存。",
      "不用注册账号，Lerro 没有服务器收你的数据。",
      "开了 AI 整理，只有文字会发给你自己的 DeepSeek 账号，每次发了什么都能在历史里看到。",
      "代码开源，任何人都可以检查。",
    ],
    orbs: ["语音 · 本机识别", "历史 · 本机", "词典 · 本机", "Key · 本机"],
  },
  faq: {
    h2: "常见问题",
    items: [
      { q: "需要会编程吗？", a: "不需要。下载、拖进「应用程序」、打开，就能用。想开 AI 整理，App 里有三步指引：打开 DeepSeek 官网、充值、创建并粘贴一串密钥，照着点就行。" },
      { q: "真的免费吗？", a: "Lerro 本身免费，没有会员和订阅。只有开 AI 整理时，DeepSeek 会按用量收费，每天说一百多次，一个月 2 块钱左右，余额和花费在 Lerro 里都看得到。" },
      { q: "能在哪些软件里用？", a: "基本所有能打字的地方：微信、飞书、钉钉、企业微信、邮件、备忘录、Word、浏览器、ChatGPT……光标在哪儿，字就写到哪儿。" },
      { q: "说话有口音、中英文夹杂，能识别吗？", a: "普通话带点口音没问题，中英文混着说也能写对。常说的专有名词写错了，AI 改对两次以后，Lerro 会自己记住。" },
      { q: "有 Windows 版或手机版吗？", a: "目前只有 Mac 版，需要 macOS 26 和 Apple 芯片（M1 及以后的 Mac）。" },
      { q: "说的话会被上传吗？", a: "语音只在你的 Mac 上识别。开了 AI 整理时，只有识别出来的文字会发给你自己的 DeepSeek 账号；不开就完全不联网处理。" },
    ],
  },
  final: {
    h2: "按住试试",
    lead: "按住下面这个键，像用 Lerro 那样说一句，松开就写好了。",
    idle: "按住 fn",
    short: "再按久一点试试",
    written: "写好了：",
    download: "免费下载 Mac 版",
    req: `${currentVersion} · macOS 26 · Apple 芯片 · 约 4 MB`,
  },
};

const en: HomeCopy = {
  meta: {
    title: "Lerro — Voice typing for Mac",
    description:
      "Press a shortcut and speak, press it again, and the text is written where your cursor is. Mix Chinese and English freely, and proper nouns come out right.",
  },
  nav: { how: "Get started", price: "Pricing", faq: "FAQ", download: "Download" },
  hero: {
    h1: { line1: "Speak it. ", soft: "It's", rest: " written." },
    lead: "Reply on WeChat, write an email, or put together a weekly report: press a shortcut and talk. Filler words are removed, corrections are applied, and punctuation and paragraphs are added for you.",
    download: "Download Lerro for Mac",
    story: "See how it works",
    req: "macOS 26 · Apple silicon · Free, open source, no sign-up",
    scroll: "Scroll down",
  },
  story: {
    steps: ["Press", "Speak", "AI cleanup", "Written"],
    hudListening: "Listening…",
    hudPolishing: "AI is tidying up…",
    key: { line1: "Press once to start", line2: "Press again to finish" },
    scenes: [
      { app: "Replying in WeChat", titles: ["Press fn and start talking", "Say whatever comes to mind", "AI tidies it up", "Written and sent"] },
      { app: "Writing to your manager in Mail", titles: ["Switch apps and keep talking", "A long passage is fine", "AI adds paragraphs and clear numbers", "A proper email"] },
      { app: "Writing a weekly report in Notes", titles: ["Say what comes to mind", "Say \"first, second\"", "AI turns it into a list", "Report done"] },
    ],
  },
  apps: {
    lead: "Wherever your cursor is, the text goes there",
    names: ["WeChat", "Feishu", "DingTalk", "WeCom", "Mail", "Notes", "Word", "WPS", "Pages", "Notion", "Safari", "Chrome", "ChatGPT", "Claude", "Keynote"],
  },
  speed: {
    h2: { pre: "Speaking is ", em: "4x faster", post: " than typing" },
    lead: "The same sentence: typed one character at a time on top, spoken and written in one go below.",
    typing: "Typing",
    talking: "Speaking with Lerro",
    unit: "chars",
    done: "Done",
  },
  features: {
    eyebrow: "Gets easier the more you use it",
    h2: "It remembers how you talk",
    learn: {
      h3: "Names and terms you use often are remembered",
      p: "A colleague's name, your company's product, or industry jargon may come out wrong the first time. After the AI corrects one twice, Lerro remembers it. You don't have to add anything by hand.",
      remembered: "Remembered",
    },
    tone: {
      h3: "A different tone in each app",
      p: "Set one instruction per app. Switch apps and the tone switches with you.",
      items: ["WeChat: casual, a friendly tone is fine", "Mail: full sentences, polite", "Notes: clear key points, easy to scan"],
    },
    fix: { h3: "Correct yourself mid-sentence", p: "Say \"no, wait\" or \"change that to\", and only your final meaning is kept." },
    translate: { h3: "Speak Chinese, write English", p: "Use a different shortcut, and what you say in Chinese is written in English." },
    menu: {
      h3: "Handy in the menu bar",
      p: "Last sentence didn't land? Copy it from the menu bar in one click.",
      rows: [["Today", "38 times · 1,920 characters"], ["Last sentence", "Paste ⌃⌘V"], ["AI cost", "¥0.04"]],
    },
  },
  how: {
    eyebrow: "Set up in two minutes",
    h2: "Three steps, then just talk",
    lead: "No account to create, no coding needed.",
    steps: [
      { h3: "Download and drag to Applications", p: "Same as installing any Mac app." },
      { h3: "Open it and allow two permissions", p: "Microphone lets it hear you. Accessibility lets it type the text for you." },
      { h3: "Press the shortcut and start talking", p: "Press again to finish, and the text appears at your cursor." },
    ],
    permissions: ["Microphone", "Accessibility"],
    note: "It works right after install and is completely free. Turn on AI cleanup if you want smoother text.",
  },
  price: {
    eyebrow: "Pricing",
    h2: ["Free to use.", "Pay a few cents for smarter text."],
    free: {
      tag: "Basic",
      amount: "Free",
      items: ["Apple's speech recognition on your Mac: what you say is what's written", "Works in every app", "No sign-up, no usage limit"],
    },
    ai: {
      tag: "With AI cleanup",
      amount: "¥1",
      unit: "/ about 1,000 uses",
      items: ["Removes filler words, fixes typos, adds punctuation", "Changes tone per app, translates Chinese to English", "Remembers words you use often"],
      fine: "Uses your own DeepSeek account and charges by usage. Adding ¥10 lasts a long time. Lerro's guide walks you through setup step by step.",
    },
  },
  privacy: {
    eyebrow: "Privacy",
    h2: ["What you say", "stays on your Mac"],
    items: [
      "Apple recognizes your speech on this Mac, and recordings are not saved by default.",
      "No account needed. Lerro has no server collecting your data.",
      "With AI cleanup on, only text is sent, and only to your own DeepSeek account. You can see what was sent in History.",
      "The code is open source, so anyone can inspect it.",
    ],
    orbs: ["Speech · on this Mac", "History · local", "Dictionary · local", "Key · local"],
  },
  faq: {
    h2: "FAQ",
    items: [
      { q: "Do I need to know programming?", a: "No. Download it, drag it to Applications, open it, and it works. To turn on AI cleanup, the app has a three-step guide: open the DeepSeek site, top up, then create a key and paste it. Just follow the buttons." },
      { q: "Is it really free?", a: "Lerro itself is free, with no membership or subscription. Only when AI cleanup is on does DeepSeek charge by usage: at a hundred or so dictations a day, that comes to about ¥2 a month, and you can see your balance and spending in Lerro." },
      { q: "Which apps does it work in?", a: "Almost anywhere you can type: WeChat, Feishu, DingTalk, WeCom, Mail, Notes, Word, your browser, ChatGPT and more. Wherever your cursor is, the text goes there." },
      { q: "Does it handle accents and mixed Chinese and English?", a: "Mandarin with a light accent is fine, and mixing Chinese and English works too. If a name or term you use often comes out wrong, Lerro remembers it after the AI corrects it twice." },
      { q: "Is there a Windows or phone version?", a: "Only Mac for now. It needs macOS 26 and Apple silicon (an M1 or later Mac)." },
      { q: "Is what I say uploaded?", a: "Speech is recognized only on your Mac. With AI cleanup on, only the recognized text is sent to your own DeepSeek account. With it off, nothing is processed over the network." },
    ],
  },
  final: {
    h2: "Hold to try",
    lead: "Hold the key below, say a sentence the way you would with Lerro, and let go to see it written.",
    idle: "Hold fn",
    short: "Hold a little longer",
    written: "Written: ",
    download: "Download Lerro for Mac",
    req: `${currentVersion} · macOS 26 · Apple silicon · about 4 MB`,
  },
};

export const home: Record<Lang, HomeCopy> = { zh, en };
