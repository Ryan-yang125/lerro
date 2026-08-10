import Image from "next/image";
import { HeroHud } from "./components/HeroHud";
import { SiteFooter, SiteHeader } from "./components/SiteChrome";
import { Disclosure } from "./components/interior/Disclosure";
import { InteriorLink } from "./components/interior/InteriorLink";
import { downloadUrl, getSiteCopy, githubUrl, pageMetadata, softwareApplicationJsonLd, type Locale } from "./i18n";

export const metadata = pageMetadata("en", "home");

function Arrow({ direction = "right" }: { direction?: "right" | "up" }) {
  return <span aria-hidden="true">{direction === "right" ? "→" : "↗"}</span>;
}

export function HomePage({ locale }: { locale: Locale }) {
  const copy = getSiteCopy(locale);
  const home = copy.home;
  const screenshotPath = `/screenshots/${locale}`;

  return (
    <main lang={locale === "zh" ? "zh-Hans" : home.lang}>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareApplicationJsonLd(locale)) }} />
      <SiteHeader current="home" locale={locale} />

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow"><span className="eyebrow-dot" aria-hidden="true" />{home.nativeVoiceTyping}</p>
          <h1>{home.headline}</h1>
          <p className="hero-lede">{home.lede}</p>
          <div className="hero-actions">
            <InteriorLink variant="primary" href={downloadUrl}>{home.download} <Arrow /></InteriorLink>
            <InteriorLink variant="secondary" href={githubUrl}>{home.source} <Arrow direction="up" /></InteriorLink>
          </div>
          <p className="requirements-inline">{home.requirements}</p>
        </div>

        <div className="product-demo" aria-label={home.demoLabel}>
          <div className="demo-toolbar" aria-hidden="true">
            <span className="traffic-light traffic-light--red" /><span className="traffic-light traffic-light--yellow" /><span className="traffic-light traffic-light--green" />
            <span className="demo-title">{home.demoTitle}</span>
          </div>
          <div className="demo-editor" aria-hidden="true">
            <div className="demo-page">
              <p className="demo-date">{home.demoDate}</p>
              <p className="demo-copy">{home.demoCopy}<span className="text-caret" /></p>
              <div className="demo-tags">{home.demoTags.map((tag) => <span key={tag}>{tag}</span>)}</div>
            </div>
            <HeroHud locale={locale} />
          </div>
          <p className="sr-only">{home.demoDescription}</p>
        </div>
      </section>

      <section className="principle-strip" aria-label="Lerro product principles">
        {home.principles.map((principle) => <span key={principle}>{principle}</span>)}
      </section>

      <section className="section workflow-section" id="workflow">
        <div className="section-intro"><p className="eyebrow">{home.workflowEyebrow}</p><h2>{home.workflowHeadline}</h2><p>{home.workflowCopy}</p></div>
        <div className="path-list">
          {home.paths.map((path) => (
            <article className="path-row" key={path.title}>
              <span className="path-index">{path.index}</span>
              <div className="path-copy"><h3>{path.title}</h3><p>{path.copy}</p>
                <div className="path-flow" aria-label={`${path.title}: ${path.flow.join(" → ")}`}>
                  {path.flow.map((step, index) => <span key={step}><b>{step}</b>{index < path.flow.length - 1 && <i aria-hidden="true">→</i>}</span>)}
                </div>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="section product-section" id="product">
        <div className="section-heading"><div><p className="eyebrow">{home.productEyebrow}</p><h2>{home.productHeadline}</h2></div><p>{home.productCopy}</p></div>
        <figure className="screenshot screenshot--hero">
          <Image src={`${screenshotPath}/${home.screenshots[0].file}`} alt={home.screenshots[0].alt} width={1976} height={1420} sizes="(max-width: 720px) 100vw, 1180px" unoptimized />
        </figure>
        <div className="screenshot-grid">
          {home.screenshots.slice(1).map((screenshot) => (
            <figure className="screenshot" key={screenshot.file}>
              <Image src={`${screenshotPath}/${screenshot.file}`} alt={screenshot.alt} width={1976} height={1420} sizes="(max-width: 900px) 100vw, 50vw" unoptimized />
              <figcaption>{screenshot.caption}</figcaption>
            </figure>
          ))}
        </div>
      </section>

      <section className="section privacy-section" id="privacy"><div className="privacy-panel"><div className="privacy-copy"><p className="eyebrow eyebrow--dark">{home.privacyEyebrow}</p><h2>{home.privacyHeadline}</h2><p>{home.privacyCopy}</p><InteriorLink className="privacy-link" variant="quiet" href={`${githubUrl}/blob/main/PRIVACY.md`}>{home.privacyLink} <Arrow direction="up" /></InteriorLink></div><dl className="privacy-stats">{home.privacyStats.map((stat) => <div key={stat}><dt>0</dt><dd>{stat}</dd></div>)}</dl><div className="network-note" role="note"><strong>{home.networkTitle}</strong><p>{home.networkCopy}</p></div></div></section>

      <section className="section source-section"><div className="source-copy"><p className="eyebrow">{home.sourceEyebrow}</p><h2>{home.sourceHeadline}</h2><p>{home.sourceCopy}</p></div><InteriorLink className="source-card" variant="card" href={githubUrl}><span className="source-card__mark" aria-hidden="true">&lt;/&gt;</span><span><b>Ryan-yang125/lerro</b><small>Swift · SwiftUI · Apple Speech · MLX</small></span><Arrow direction="up" /></InteriorLink></section>

      <section className="section faq-section" id="faq"><div className="faq-heading"><p className="eyebrow">{home.faqEyebrow}</p><h2>{home.faqHeadline}</h2></div><div className="faq-list">{home.faqs.map((faq, index) => <Disclosure key={faq.question} summary={faq.question} defaultOpen={index === 0}><p>{faq.answer}</p></Disclosure>)}</div></section>

      <section className="section download-section" id="download"><div className="download-panel"><div><p className="eyebrow">{home.downloadEyebrow}</p><h2>{home.downloadHeadline}</h2><p>{home.downloadCopy}</p></div><div className="download-actions"><InteriorLink variant="primary" href={downloadUrl}>{home.download} <Arrow /></InteriorLink><a href={locale === "zh" ? "/zh/changelog" : "/changelog"}>{home.changelog} <Arrow /></a></div></div></section>

      <SiteFooter locale={locale} />
    </main>
  );
}

export default function Home() {
  return <HomePage locale="en" />;
}
