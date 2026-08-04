import { HomePage } from "../page";
import { pageMetadata } from "../i18n";

export const metadata = pageMetadata("zh", "home");

export default function ChineseHome() {
  return <HomePage locale="zh" />;
}
