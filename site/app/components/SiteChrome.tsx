import Image from "next/image";
import Link from "next/link";
import { getSiteCopy, githubUrl, localizePath, type Locale } from "../i18n";
import { InteriorLink } from "./interior/InteriorLink";

const downloadUrl = "https://updates.lerroapp.com/download/macos/latest";

export function SiteHeader({ current, locale }: { current?: "home" | "changelog"; locale: Locale }) {
  const chrome = getSiteCopy(locale).chrome;
  const homePath = localizePath(locale);
  const changelogPath = localizePath(locale, "/changelog");
  const alternateLocale: Locale = locale === "en" ? "zh" : "en";
  const languagePath = localizePath(alternateLocale, current === "changelog" ? "/changelog" : "/");
  return (
    <header className="site-header">
      <Link className="brand" href={homePath} aria-label={`Lerro ${chrome.home}`}>
        <Image src="/lerro-logo.svg" alt="Lerro" width={150} height={40} priority />
      </Link>
      <nav aria-label={chrome.navigation}>
        <Link href={`${homePath}#workflow`}>{chrome.workflow}</Link>
        <Link href={`${homePath}#product`}>{chrome.product}</Link>
        <Link href={`${homePath}#privacy`}>{chrome.privacy}</Link>
        <Link href={changelogPath} aria-current={current === "changelog" ? "page" : undefined}>{chrome.changelog}</Link>
      </nav>
      <div className="header-actions">
        {current === "changelog" ? (
          <Link className="header-text-link" href={homePath}>{chrome.home}</Link>
        ) : (
          <Link className="header-text-link" href={changelogPath}>{chrome.updates}</Link>
        )}
        <Link className="language-switch" href={languagePath} aria-label={getSiteCopy(locale).language.ariaLabel} hrefLang={alternateLocale === "zh" ? "zh-CN" : "en"}>
          {chrome.language}
        </Link>
        <InteriorLink className="header-download" variant="primary" href={downloadUrl}>
          <span className="download-label-full">{chrome.download}</span>
          <span className="download-label-short">{chrome.downloadShort}</span>
        </InteriorLink>
      </div>
    </header>
  );
}

export function SiteFooter({ locale }: { locale: Locale }) {
  const chrome = getSiteCopy(locale).chrome;
  const homePath = localizePath(locale);
  const changelogPath = localizePath(locale, "/changelog");
  return (
    <footer className="site-footer">
      <Link className="footer-brand" href={homePath}>
        <Image src="/lerro-symbol.svg" alt="" width={40} height={32} />
        <span>Lerro</span>
      </Link>
      <p>{chrome.footerTagline}</p>
      <div className="footer-links">
        <a href={githubUrl}>{chrome.github}</a>
        <Link href={changelogPath}>{chrome.changelog}</Link>
        <a href={downloadUrl}>{chrome.downloadShort}</a>
        <a href={`${githubUrl}/blob/main/PRIVACY.md`}>{chrome.privacy}</a>
        <a href={`${githubUrl}/blob/main/LICENSE`}>{chrome.license}</a>
      </div>
    </footer>
  );
}
