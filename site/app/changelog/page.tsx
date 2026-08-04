import { SiteFooter, SiteHeader } from "../components/SiteChrome";
import { InteriorLink } from "../components/interior/InteriorLink";
import { downloadUrl, getSiteCopy, pageMetadata, type Locale } from "../i18n";
import { getReleases } from "./releases";

export const metadata = pageMetadata("en", "changelog");

function Arrow() { return <span aria-hidden="true">→</span>; }

export function ChangelogPage({ locale }: { locale: Locale }) {
  const copy = getSiteCopy(locale).changelog;
  const releases = getReleases(locale);
  return (
    <main lang={locale === "zh" ? "zh-Hans" : "en"}>
      <SiteHeader current="changelog" locale={locale} />
      <section className="changelog-hero"><p className="eyebrow">{copy.eyebrow}</p><h1>{copy.headline}</h1><p>{copy.lede}</p></section>
      <section className="changelog-list" aria-label={copy.releasesLabel}>
        {releases.map((release) => <article className="release-card" key={`${release.version}-${release.build}`}><div className="release-meta"><p>{copy.version} {release.version}</p><time dateTime={release.publishedAt}>{release.publishedLabel}</time></div><div className="release-content"><div className="release-heading"><h2>Lerro {release.version}</h2><span>{copy.build} {release.build}</span></div><p className="release-summary">{release.summary}</p><ul>{release.highlights.map((highlight) => <li key={highlight}>{highlight}</li>)}</ul><InteriorLink className="release-download" variant="secondary" href={release.downloadUrl}>{copy.download} {release.version} <Arrow /></InteriorLink></div></article>)}
      </section>
      <section className="changelog-current" aria-label={copy.current}><p>{copy.current} Lerro {releases[0].version}{locale === "zh" ? "，" : ", "}{copy.build} {releases[0].build}{locale === "zh" ? "。" : "."}</p><InteriorLink variant="primary" href={downloadUrl}>{copy.downloadLatest} <Arrow /></InteriorLink></section>
      <SiteFooter locale={locale} />
    </main>
  );
}

export default function Changelog() { return <ChangelogPage locale="en" />; }
