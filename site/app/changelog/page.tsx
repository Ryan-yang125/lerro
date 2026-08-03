import type { Metadata } from "next";
import { SiteFooter, SiteHeader } from "../components/SiteChrome";
import { InteriorLink } from "../components/interior/InteriorLink";
import { releases } from "./releases";

const latestDownloadUrl = "https://updates.lerroapp.com/download/macos/latest";

export const metadata: Metadata = {
  title: "Changelog — Lerro",
  description: "Every Lerro release, with concise notes and permanent signed macOS downloads.",
  alternates: { canonical: "/changelog" },
  openGraph: {
    title: "Changelog — Lerro",
    description: "Every Lerro release, with concise notes and permanent signed macOS downloads.",
    url: "https://lerroapp.com/changelog",
  },
};

function Arrow() {
  return <span aria-hidden="true">→</span>;
}

export default function ChangelogPage() {
  return (
    <main>
      <SiteHeader current="changelog" />

      <section className="changelog-hero">
        <p className="eyebrow">Release notes</p>
        <h1>What&apos;s new in Lerro.</h1>
        <p>Every public release in one quiet record, with a permanent signed download attached.</p>
      </section>

      <section className="changelog-list" aria-label="Lerro releases">
        {releases.map((release) => (
          <article className="release-card" key={`${release.version}-${release.build}`}>
            <div className="release-meta">
              <p>Version {release.version}</p>
              <time dateTime={release.publishedAt}>{release.publishedLabel}</time>
            </div>
            <div className="release-content">
              <div className="release-heading">
                <h2>Lerro {release.version}</h2>
                <span>Build {release.build}</span>
              </div>
              <p className="release-summary">{release.summary}</p>
              <ul>
                {release.highlights.map((highlight) => <li key={highlight}>{highlight}</li>)}
              </ul>
              <InteriorLink className="release-download" variant="secondary" href={release.downloadUrl}>
                Download Lerro {release.version} <Arrow />
              </InteriorLink>
            </div>
          </article>
        ))}
      </section>

      <section className="changelog-current" aria-label="Current release">
        <p>Current stable release: Lerro {releases[0].version}, build {releases[0].build}.</p>
        <InteriorLink variant="primary" href={latestDownloadUrl}>Download latest <Arrow /></InteriorLink>
      </section>

      <SiteFooter />
    </main>
  );
}
