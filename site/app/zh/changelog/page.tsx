import { ChangelogPage } from "../../changelog/page";
import { pageMetadata } from "../../i18n";

export const metadata = pageMetadata("zh", "changelog");

export default function ChineseChangelog() { return <ChangelogPage locale="zh" />; }
