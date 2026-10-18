import type { Lang } from "../site";

export type Chrome = {
  htmlLang: string;
  logoLabel: string;
  nav: { features: string; ai: string; privacy: string; changelog: string; switchLabel: string; download: string };
  footer: { changelog: string; privacy: string; switchLabel: string };
};

export const chrome: Record<Lang, Chrome> = {
  zh: {
    htmlLang: "zh-CN",
    logoLabel: "Lerro",
    nav: { features: "功能", ai: "AI 设置", privacy: "隐私", changelog: "更新日志", switchLabel: "EN", download: "下载" },
    footer: { changelog: "更新日志", privacy: "隐私政策", switchLabel: "English" },
  },
  en: {
    htmlLang: "en",
    logoLabel: "Lerro",
    nav: { features: "Features", ai: "AI setup", privacy: "Privacy", changelog: "Changelog", switchLabel: "中文", download: "Download" },
    footer: { changelog: "Changelog", privacy: "Privacy", switchLabel: "中文" },
  },
};
