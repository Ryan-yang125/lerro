import { currentVersion, type Lang } from "../site";

export interface DemoScenario {
  scene: "chat" | "note" | "mail";
  title: string;
  icon: string;
  sym: string;
  raw: string;
  /** HTML with <span class="fix"> highlights */
  out: string;
}

export interface Point {
  sym: string;
  text: string;
}

export interface HomeCopy {
  meta: { title: string; description: string };
  hero: {
    h1: string;
    /** HTML, contains <br> */
    lede: string;
    download: string;
    github: string;
    req: string;
  };
  demo: {
    aria: string;
    hints: { start: string; speaking: string; polish: string; done: string };
    polishing: string;
    chat: { earlier: string; reply: string; question: string };
    note: { heading: string; lines: string[] };
    mail: { toLabel: string; toName: string; subjectLabel: string; subjectText: string };
    scenarios: DemoScenario[];
  };
  accuracy: {
    eyebrow: string;
    h2: string;
    sub: string;
    rawLabel: string;
    outLabel: string;
    cards: { tag: string; raw: string; out: string }[];
  };
  dictionary: {
    eyebrow: string;
    h2: string;
    sub: string;
    points: Point[];
    mock: {
      title: string;
      segs: { label: string; on?: boolean }[];
      rows: { from: string; to: string; n: string }[];
      add: string;
      ignore: string;
      learned: string;
      chips: { from: string; to: string }[];
    };
  };
  tones: {
    eyebrow: string;
    h2: string;
    sub: string;
    spoken: string;
    cards: { icon: string; sym: string; app: string; rule: string; res: string }[];
  };
  menubar: {
    eyebrow: string;
    h2: string;
    sub: string;
    points: Point[];
    panel: {
      ready: string;
      dictate: string;
      translate: string;
      lastMeta: string;
      lastText: string;
      copy: string;
      paste: string;
      /** HTML with <b> */
      stats: string[];
      mic: string;
      micValue: string;
      smart: string;
      smartValue: string;
    };
  };
  cost: {
    eyebrow: string;
    h2: string;
    sub: string;
    /** HTML, contains <small> */
    num: string;
    cap: string;
    stats: { value: string; label: string }[];
    /** step bodies are HTML, may contain <code> */
    steps: { title: string; body: string }[];
    free: string;
  };
  privacy: {
    eyebrow: string;
    h2: string;
    sub: string;
    items: { sym: string; title: string; body: string }[];
  };
  faq: { heading: string; items: { q: string; a: string }[] };
  end: { h2: string; download: string; req: string };
}

const zh: HomeCopy = {
  meta: {
    title: "Lerro — Mac 上的语音输入",
    description: "按一下快捷键说话，再按一下，文字写进光标所在的地方。中英文混着说，专有名词也能写对。",
  },
  hero: {
    h1: "说出来，就写好了",
    lede: "按一下快捷键说话，再按一下，文字写进光标所在的地方。<br>中英文混着说，专有名词也能写对。",
    download: "下载 macOS 版",
    github: "GitHub",
    req: "免费开源 · macOS 26 · Apple 芯片",
  },
  demo: {
    aria: "Lerro 听写演示",
    hints: { start: "按一下开始", speaking: "说话中", polish: "AI 润色", done: "已写入" },
    polishing: "AI 润色中…",
    chat: { earlier: "周末那个 demo 你录好了吗", reply: "录好了，晚上发你", question: "新版装好了吗，识别怎么样？" },
    note: { heading: "Lerro 下个版本", lines: ["· 菜单栏面板换成品牌样式", "· 设置里加一页用量"] },
    mail: { toLabel: "收件人", toName: "阿杰", subjectLabel: "主题", subjectText: "官网数据" },
    scenarios: [
      {
        scene: "chat",
        title: "聊天",
        icon: "ic-chat",
        sym: "i-chat",
        raw: "嗯，我测试一下啊，测试一下就是正常说话啊，就是来测试一下英文的专有名词 Codexcloud code deepseak。",
        out: '我测试一下，就是正常说话，来测试一下英文的专有名词：<span class="fix">Codex、Claude Code、DeepSeek</span>。',
      },
      {
        scene: "note",
        title: "笔记",
        icon: "ic-note",
        sym: "i-note",
        raw: "其实这个统计使用情况，但是这个没有统计情况，我其实比较关心说我用了多少头花了多少钱使用情况是怎样的",
        out: '· 我比较关心的是用量统计：用了多少 <span class="fix">token</span>、花了多少钱、使用情况是怎样的。',
      },
      {
        scene: "mail",
        title: "邮件",
        icon: "ic-mail",
        sym: "i-mail",
        raw: "嗯，cloud flare那边能看到真实的访问数据吗？每天有多少PV？",
        out: '<span class="fix">Cloudflare</span> 那边能看到真实的访问数据吗？每天有多少 PV？',
      },
    ],
  },
  accuracy: {
    eyebrow: "写得准",
    h2: "中英混说、专有名词、口头禅，<br>一次写对。",
    sub: "苹果本机识别负责听，AI 再按你的词典改掉认错的词、去掉“嗯”“呃”、补好标点。下面是真实的听写记录。",
    rawLabel: "识别原文",
    outLabel: "写进去的",
    cards: [
      {
        tag: "英文专有名词",
        raw: "嗯，我测试一下啊，测试一下就是正常说话啊，就是来测试一下英文的专有名词 <s>Codexcloud code deepseak</s>。",
        out: "我测试一下，就是正常说话，来测试一下英文的专有名词：<b>Codex、Claude Code、DeepSeek</b>。",
      },
      {
        tag: "中文专有名词",
        raw: "哎，这个<s>极梦</s> AI跟这个<s>小云却</s>是什么关系啊？用哪个比较好玩？",
        out: "这个<b>即梦</b> AI 跟这个<b>小云雀</b>是什么关系啊？用哪个比较好玩？",
      },
      {
        tag: "同音字",
        raw: "其实这个统计使用情况，但是这个没有统计情况，我其实比较关心说我用了多少<s>头</s>花了多少钱使用情况是怎样的",
        out: "其实我比较关心的是用量统计：我用了多少 <b>token</b>、花了多少钱、使用情况是怎样的。",
      },
      {
        tag: "口头禅和标点",
        raw: "所以核心是要优化这个 <s>AAI</s>润色的这个提示词对吧，然后优化之后，然后我们再用历史记录去。呃跑看一下结果。",
        out: "核心是要优化这个 <b>AI</b> 润色的提示词，对吧？优化之后，我们再用历史记录跑一下，看看结果。",
      },
    ],
  },
  dictionary: {
    eyebrow: "词典会学",
    h2: "改过一次，<br>下次就写对。",
    sub: "你身边的人名、公司名、项目名，苹果识别很难一次认对。把写错的词改掉，Lerro 会记下来。",
    points: [
      { sym: "g-dictionary", text: "写入后你手动改了词，AI 判断是认错了，就自动加进词典。" },
      { sym: "g-polish", text: "翻一遍历史记录，把反复认错的词列出来，你点一下加入。" },
    ],
    mock: {
      title: "词典",
      segs: [{ label: "全部 12" }, { label: "自动学习 5" }, { label: "建议 4", on: true }],
      rows: [
        { from: "code x", to: "Codex", n: "×3" },
        { from: "小云却", to: "小云雀", n: "×2" },
        { from: "乐若", to: "Lerro", n: "×2" },
        { from: "swift ui", to: "SwiftUI", n: "×1" },
      ],
      add: "加入",
      ignore: "忽略",
      learned: "最近学到",
      chips: [
        { from: "deepseak", to: "DeepSeek" },
        { from: "cloud flare", to: "Cloudflare" },
        { from: "极梦", to: "即梦" },
      ],
    },
  },
  tones: {
    eyebrow: "应用语气",
    h2: "同一句话，在每个 App 里换个说法。",
    sub: "给常用的 App 写一句语气要求，Lerro 按你当前所在的 App 自动套用。",
    spoken: "嗯那个晚上一起吃饭吗我大概八点到你们先点吧",
    cards: [
      { icon: "ic-chat", sym: "i-chat", app: "聊天", rule: "口语化、简短，保留语气词", res: "晚上一起吃饭吗？我大概八点到，你们先点吧～" },
      { icon: "ic-mail", sym: "i-mail", app: "邮件", rule: "表达清楚、友好，使用完整句子", res: "今晚一起吃饭吗？我大约八点到，你们可以先点餐。" },
      { icon: "ic-team", sym: "i-team", app: "工作群", rule: "直接、专业", res: "今晚聚餐我八点左右到，大家先点。" },
    ],
  },
  menubar: {
    eyebrow: "菜单栏",
    h2: "常用的都在<br>菜单栏里。",
    sub: "上一次听写的结果随时复制或粘贴，今天说了多少字、AI 花了多少钱一眼看到，麦克风和 AI 也在这里切换。",
    points: [
      { sym: "g-translate", text: "换一个快捷键说中文，直接写出英文。" },
      { sym: "g-mic", text: "按下快捷键麦克风立即打开，开头的字不会丢。" },
    ],
    panel: {
      ready: "就绪",
      dictate: "听写",
      translate: "翻译",
      lastMeta: "AI 对话 · 2 分钟前",
      lastText: "把 HUD 结尾的标志直接去掉，开头保持现在的速度。",
      copy: "复制",
      paste: "粘贴 ⌃⌘V",
      stats: ["今天 <b>38</b> 次", "<b>1,920</b> 字", "AI <b>¥0.04</b>"],
      mic: "麦克风",
      micValue: "跟随系统默认",
      smart: "智能处理",
      smartValue: "DeepSeek",
    },
  },
  cost: {
    eyebrow: "AI 润色",
    h2: "用你自己的 DeepSeek Key，<br>一千次听写约 1 块钱。",
    sub: "Lerro 不卖订阅。AI 润色走你自己的 DeepSeek 账号，按实际用量付费，每次花了多少在设置的“用量”里都能看到。",
    num: "¥1<small>/ 1000 次</small>",
    cap: "按 DeepSeek Flash 官方价格估算，每次听写约 1,500 token。",
    stats: [
      { value: "0.95 秒", label: "AI 润色耗时中位数" },
      { value: "¥0.001", label: "每次听写" },
    ],
    steps: [
      { title: "注册 DeepSeek 开放平台", body: "打开 <code>platform.deepseek.com</code>，手机号注册，充值 10 元就够用很久。" },
      { title: "创建 API Key", body: "在“API keys”里新建一个，复制下来。" },
      { title: "粘贴到 Lerro", body: "设置 › 智能，服务商选 DeepSeek，粘贴 Key，点“测试连接”。" },
    ],
    free: "不填 Key 也能用：苹果本机识别，免费，识别结果直接写入。",
  },
  privacy: {
    eyebrow: "隐私",
    h2: "数据留在你的 Mac 上。",
    sub: "语音由苹果在本机识别。开了 AI 润色时，只有识别出的文字会发给你自己配置的 AI 服务商。",
    items: [
      { sym: "g-person", title: "不用注册", body: "没有账号，下载打开就能用。" },
      { sym: "g-chart", title: "没有数据上报", body: "不收集使用数据，不接任何统计服务。" },
      { sym: "g-mic", title: "录音默认不保存", body: "历史只存文字，要保存录音需要你在设置里打开。" },
      { sym: "g-code", title: "代码开源", body: "Apache-2.0 协议，所有代码都在 GitHub 上。" },
    ],
  },
  faq: {
    heading: "常见问题",
    items: [
      { q: "支持哪些 Mac？", a: "需要 Apple 芯片（M1 及以后）和 macOS 26 或更新版本。Lerro 用的苹果语音识别只有 macOS 26 才提供。" },
      { q: "需要开哪些权限？", a: "两个：麦克风用来听写；辅助功能用来响应全局快捷键，并把文字写进当前的输入框。第一次打开时会一步步引导你授权。" },
      { q: "不联网能用吗？", a: "可以。语音识别在本机完成，语言资源下载好之后断网也能听写。AI 润色和翻译需要联网访问你配置的服务商。" },
      { q: "收费吗？", a: "Lerro 免费。AI 润色用的是你自己的 DeepSeek 账号，费用直接付给 DeepSeek，按上面的估算一千次听写约 1 块钱。" },
      { q: "写入失败了怎么办？", a: "写入前 Lerro 会确认你还在原来的输入框里。如果你中途切走了，它会停下来，把结果留在剪贴板里，并提示你粘贴。" },
      { q: "怎么更新？", a: "有新版本时，Lerro 会在窗口里显示更新入口，点一下就会下载并安装。" },
    ],
  },
  end: {
    h2: "试试看。",
    download: "下载 macOS 版",
    req: `${currentVersion} · macOS 26 · Apple 芯片 · 约 4 MB`,
  },
};

const en: HomeCopy = {
  meta: {
    title: "Lerro — Voice typing for Mac",
    description:
      "Press a shortcut and speak, press it again, and the text is written where your cursor is. Mix Chinese and English freely, and proper nouns come out right.",
  },
  hero: {
    h1: "Speak it. It's written.",
    lede: "Press a shortcut and speak, press it again, and the text is written where your cursor is.<br>Mix Chinese and English freely, and proper nouns come out right.",
    download: "Download for macOS",
    github: "GitHub",
    req: "Free and open source · macOS 26 · Apple silicon",
  },
  demo: {
    aria: "Lerro dictation demo",
    hints: { start: "Press to start", speaking: "Listening", polish: "AI polish", done: "Written" },
    polishing: "Polishing with AI…",
    chat: {
      earlier: "Did you record the weekend demo?",
      reply: "Done, I'll send it tonight",
      question: "Is the new version installed? How is the recognition?",
    },
    note: { heading: "Lerro next release", lines: ["· Brand the menu bar panel", "· Add a usage page to Settings"] },
    mail: { toLabel: "To", toName: "Jie", subjectLabel: "Subject", subjectText: "Website data" },
    scenarios: [
      { ...zh.demo.scenarios[0], title: "Chat" },
      { ...zh.demo.scenarios[1], title: "Notes" },
      { ...zh.demo.scenarios[2], title: "Mail" },
    ],
  },
  accuracy: {
    eyebrow: "Accurate",
    h2: "Mixed languages, proper nouns, filler words,<br>written right the first time.",
    sub: "Apple's on-device recognition does the listening. AI then fixes misheard words using your dictionary, removes fillers like “um”, and adds punctuation. These are real dictation records.",
    rawLabel: "Recognized text",
    outLabel: "Written output",
    cards: [
      { ...zh.accuracy.cards[0], tag: "English proper nouns" },
      { ...zh.accuracy.cards[1], tag: "Chinese proper nouns" },
      { ...zh.accuracy.cards[2], tag: "Homophones" },
      { ...zh.accuracy.cards[3], tag: "Fillers and punctuation" },
    ],
  },
  dictionary: {
    eyebrow: "Dictionary that learns",
    h2: "Correct it once,<br>get it right next time.",
    sub: "Apple's recognition rarely gets the names of people, companies and projects around you right on the first try. Fix a wrong word and Lerro remembers it.",
    points: [
      { sym: "g-dictionary", text: "When you edit a word after it is written, AI decides whether it was misheard and adds it to the dictionary automatically." },
      { sym: "g-polish", text: "Lerro reads through your history, lists words that are repeatedly misheard, and you add them with one click." },
    ],
    mock: {
      ...zh.dictionary.mock,
      title: "Dictionary",
      segs: [{ label: "All 12" }, { label: "Auto-learned 5" }, { label: "Suggestions 4", on: true }],
      add: "Add",
      ignore: "Ignore",
      learned: "Recently learned",
    },
  },
  tones: {
    eyebrow: "App tones",
    h2: "One sentence, said differently in each app.",
    sub: "Write a tone rule for each app you use. Lerro applies it automatically based on the app you are in.",
    spoken: zh.tones.spoken,
    cards: [
      { ...zh.tones.cards[0], app: "Chat", rule: "Casual and short, keeps filler particles" },
      { ...zh.tones.cards[1], app: "Mail", rule: "Clear and friendly, full sentences" },
      { ...zh.tones.cards[2], app: "Work group", rule: "Direct and professional" },
    ],
  },
  menubar: {
    eyebrow: "Menu bar",
    h2: "Everything you use<br>is in the menu bar.",
    sub: "Copy or paste your last dictation at any time, see at a glance how much you dictated today and what AI cost, and switch the microphone and AI here.",
    points: [
      { sym: "g-translate", text: "Use a different shortcut to speak Chinese and get English written." },
      { sym: "g-mic", text: "The microphone opens as soon as you press the shortcut, so the first words are kept." },
    ],
    panel: {
      ready: "Ready",
      dictate: "Dictate",
      translate: "Translate",
      lastMeta: "AI Chat · 2 min ago",
      lastText: zh.menubar.panel.lastText,
      copy: "Copy",
      paste: "Paste ⌃⌘V",
      stats: ["Today <b>38</b> dictations", "<b>1,920</b> characters", "AI <b>¥0.04</b>"],
      mic: "Microphone",
      micValue: "System default",
      smart: "AI processing",
      smartValue: "DeepSeek",
    },
  },
  cost: {
    eyebrow: "AI polish",
    h2: "Use your own DeepSeek key.<br>About ¥1 per 1,000 dictations.",
    sub: "Lerro has no subscription. AI polish runs on your own DeepSeek account and you pay for actual usage. The cost of each dictation is shown under Usage in Settings.",
    num: "¥1<small>/ 1,000 dictations</small>",
    cap: "Estimated from DeepSeek Flash official pricing, about 1,500 tokens per dictation.",
    stats: [
      { value: "0.95 s", label: "Median AI polish time" },
      { value: "¥0.001", label: "Per dictation" },
    ],
    steps: [
      { title: "Sign up for the DeepSeek Platform", body: "Open <code>platform.deepseek.com</code>, register with a phone number, and top up ¥10, which lasts a long time." },
      { title: "Create an API key", body: "Create a new one under “API keys” and copy it." },
      { title: "Paste it into Lerro", body: "In Settings › Smart, choose DeepSeek as the provider, paste the key, and click “Test connection”." },
    ],
    free: "No key is needed to start: Apple's on-device recognition is free and the recognized text is written as is.",
  },
  privacy: {
    eyebrow: "Privacy",
    h2: "Your data stays on your Mac.",
    sub: "Apple recognizes speech on your Mac. When AI polish is on, only the recognized text is sent to the AI provider you configured.",
    items: [
      { sym: "g-person", title: "No sign-up", body: "There is no account. Download it and start using it." },
      { sym: "g-chart", title: "No data reporting", body: "No usage data is collected and no analytics service is connected." },
      { sym: "g-mic", title: "Recordings are not saved by default", body: "History stores text only. Saving recordings requires turning it on in Settings." },
      { sym: "g-code", title: "Open source", body: "Licensed under Apache-2.0. All code is on GitHub." },
    ],
  },
  faq: {
    heading: "FAQ",
    items: [
      { q: "Which Macs are supported?", a: "A Mac with Apple silicon (M1 or later) running macOS 26 or newer. The Apple speech recognition that Lerro uses is only available on macOS 26." },
      { q: "Which permissions does it need?", a: "Two. Microphone is used for dictation. Accessibility is used to respond to the global shortcut and to write text into the active input field. The first launch walks you through each permission." },
      { q: "Does it work offline?", a: "Yes. Speech recognition runs on your Mac, and once the language resources are downloaded you can dictate without a connection. AI polish and translation need a connection to the provider you configured." },
      { q: "Does it cost anything?", a: "Lerro is free. AI polish uses your own DeepSeek account and you pay DeepSeek directly, which is about ¥1 per 1,000 dictations by the estimate above." },
      { q: "What happens if writing fails?", a: "Before writing, Lerro checks that you are still in the original input field. If you switched away, it stops, keeps the result on the clipboard, and tells you to paste it." },
      { q: "How do I update?", a: "When a new version is available, Lerro shows an update button in its window. One click downloads and installs it." },
    ],
  },
  end: {
    h2: "Give it a try.",
    download: "Download for macOS",
    req: `${currentVersion} · macOS 26 · Apple silicon · about 4 MB`,
  },
};

export const home: Record<Lang, HomeCopy> = { zh, en };
