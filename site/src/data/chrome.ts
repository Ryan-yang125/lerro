import type { Lang } from "../site";

export type Chrome = {
  htmlLang: string;
  footer: { openSource: string; privacy: string; changelog: string; switchLabel: string; owners: string };
};

export const chrome: Record<Lang, Chrome> = {
  zh: {
    htmlLang: "zh-CN",
    footer: { openSource: "开源于 GitHub", privacy: "隐私", changelog: "更新日志", switchLabel: "English", owners: "App 名称和图标归各自所有者所有。" },
  },
  en: {
    htmlLang: "en",
    footer: { openSource: "Open source on GitHub", privacy: "Privacy", changelog: "Changelog", switchLabel: "中文", owners: "App names and icons belong to their respective owners." },
  },
};
