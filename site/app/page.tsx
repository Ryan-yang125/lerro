import Image from "next/image";
import { HeroHud } from "./components/HeroHud";
import { SiteFooter, SiteHeader } from "./components/SiteChrome";
import { Disclosure } from "./components/interior/Disclosure";
import { InteriorLink } from "./components/interior/InteriorLink";

const githubUrl = "https://github.com/Ryan-yang125/lerro";
const downloadUrl = "https://updates.lerroapp.com/download/macos/latest";

const paths = [
  {
    index: "01",
    title: "Dictate",
    copy: "Apple Speech transcribes your voice and Lerro places the result at the active cursor.",
    flow: ["Voice", "Apple Speech", "Cursor"],
  },
  {
    index: "02",
    title: "Translate",
    copy: "Speak in one language and write in another with Apple Translation on your Mac.",
    flow: ["Voice", "Apple Speech", "Translation", "Cursor"],
  },
  {
    index: "03",
    title: "Refine",
    copy: "Polish, rewrite, or ask with an optional local MLX model or your own cloud API key.",
    flow: ["Transcript", "MLX or BYOK", "Cursor"],
  },
] as const;

const faqs = [
  {
    question: "Which permissions does Lerro request?",
    answer:
      "Microphone captures the speech you choose to dictate. Accessibility lets the global shortcut work and places finished text at the current cursor. Lerro does not request Input Monitoring or a separate Speech Recognition permission.",
  },
  {
    question: "Does Lerro work offline?",
    answer:
      "Core Dictate, Apple Translation, and optional local MLX processing work offline after their language resources or model are installed. Initial resource setup, update checks, and BYOK cloud requests use a network connection.",
  },
  {
    question: "Why might macOS download a language resource?",
    answer:
      "Apple Speech and Apple Translation manage language resources at the system level. A compatible resource may already be present, so setup can finish immediately; macOS downloads it when the selected language still needs one.",
  },
  {
    question: "Where does my data go?",
    answer:
      "Lerro has no account system, subscription, product analytics, or telemetry. Audio saving is off by default. BYOK sends the transcript and only the context fields you enable to your chosen provider. Lerro's update service receives release requests only.",
  },
  {
    question: "Which Macs are supported?",
    answer:
      "Lerro requires Apple silicon and macOS 26 or later. The optional local model uses about 3.03 GB of storage and is downloaded only after you approve it.",
  },
  {
    question: "How are downloads verified?",
    answer:
      "Every public build is signed with Apple Developer ID, notarized by Apple, and distributed through Lerro's Cloudflare release service. In-app updates verify their signed update metadata before installation.",
  },
] as const;

function Arrow({ direction = "right" }: { direction?: "right" | "up" }) {
  return <span aria-hidden="true">{direction === "right" ? "→" : "↗"}</span>;
}

export default function Home() {
  return (
    <main>
      <SiteHeader current="home" />

      <section className="hero" id="top">
        <div className="hero-copy">
          <p className="eyebrow"><span className="eyebrow-dot" aria-hidden="true" />Native voice typing for macOS 26</p>
          <h1>Speak.<br />Your Mac writes.</h1>
          <p className="hero-lede">
            Lerro turns speech into text at your cursor with Apple&apos;s native Speech framework. Fast, accurate, local-first, and open source.
          </p>
          <div className="hero-actions">
            <InteriorLink variant="primary" href={downloadUrl}>
              Download for macOS <Arrow />
            </InteriorLink>
            <InteriorLink variant="secondary" href={githubUrl}>
              View source <Arrow direction="up" />
            </InteriorLink>
          </div>
          <p className="requirements-inline">Free forever · Apple silicon · macOS 26+</p>
        </div>

        <div className="product-demo" aria-label="Animated recreation of Lerro's macOS listening and processing HUD">
          <div className="demo-toolbar" aria-hidden="true">
            <span className="traffic-light traffic-light--red" />
            <span className="traffic-light traffic-light--yellow" />
            <span className="traffic-light traffic-light--green" />
            <span className="demo-title">Untitled</span>
          </div>
          <div className="demo-editor" aria-hidden="true">
            <div className="demo-page">
              <p className="demo-date">AUGUST 4</p>
              <p className="demo-copy">Voice becomes text right where the cursor is.<span className="text-caret" /></p>
              <div className="demo-tags">
                <span>Apple Speech</span>
                <span>On-device</span>
              </div>
            </div>
            <HeroHud />
          </div>
          <p className="sr-only">The HUD listens with a live ten-bar waveform, then displays Lerro&apos;s three-dot processing state.</p>
        </div>
      </section>

      <section className="principle-strip" aria-label="Lerro product principles">
        <span>Apple Speech</span>
        <span>No account</span>
        <span>No telemetry</span>
        <span>Offline after setup</span>
      </section>

      <section className="section workflow-section" id="workflow">
        <div className="section-intro">
          <p className="eyebrow">One shortcut, three paths</p>
          <h2>Fast. Accurate.<br />Straight to the cursor.</h2>
          <p>Lerro keeps the native path short, then adds translation or intelligence only when you choose it.</p>
        </div>
        <div className="path-list">
          {paths.map((path) => (
            <article className="path-row" key={path.title}>
              <span className="path-index">{path.index}</span>
              <div className="path-copy">
                <h3>{path.title}</h3>
                <p>{path.copy}</p>
                <div className="path-flow" aria-label={`${path.title} flow: ${path.flow.join(" to ")}`}>
                  {path.flow.map((step, index) => (
                    <span key={step}>
                      <b>{step}</b>
                      {index < path.flow.length - 1 && <i aria-hidden="true">→</i>}
                    </span>
                  ))}
                </div>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="section product-section" id="product">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Made for macOS</p>
            <h2>Feels native from the first shortcut.</h2>
          </div>
          <p>Configure the keys you already use, see the same responsive HUD across apps, and keep every setting close at hand.</p>
        </div>
        <figure className="screenshot screenshot--hero">
          <Image
            src="/screenshots/lerro-home-light.png"
            alt="Lerro 1.1 home screen showing local activity, shortcuts, and private on-device data"
            width={1976}
            height={1420}
            sizes="(max-width: 720px) 100vw, 1180px"
          />
        </figure>
        <div className="screenshot-grid">
          <figure className="screenshot">
            <Image
              src="/screenshots/lerro-onboarding-shortcuts-light.png"
              alt="Lerro onboarding detecting the Fn shortcut and letting the user choose hold or toggle mode"
              width={1976}
              height={1420}
              sizes="(max-width: 900px) 100vw, 50vw"
            />
            <figcaption>Shortcut setup tests your exact press and release events before you continue.</figcaption>
          </figure>
          <figure className="screenshot">
            <Image
              src="/screenshots/lerro-settings-light.png"
              alt="Lerro shortcut settings for Dictate, Translate, and Ask"
              width={1976}
              height={1420}
              sizes="(max-width: 900px) 100vw, 50vw"
            />
            <figcaption>Dictate, Translate, and Ask each support up to four custom shortcuts.</figcaption>
          </figure>
        </div>
      </section>

      <section className="section privacy-section" id="privacy">
        <div className="privacy-panel">
          <div className="privacy-copy">
            <p className="eyebrow eyebrow--dark">Private by architecture</p>
            <h2>Your voice stays close.</h2>
            <p>
              Apple Speech handles the core transcript. Apple Translation and the optional MLX model run on your Mac after setup. Audio saving stays off by default.
            </p>
            <InteriorLink className="privacy-link" variant="quiet" href={`${githubUrl}/blob/main/PRIVACY.md`}>
              Read the privacy model <Arrow direction="up" />
            </InteriorLink>
          </div>
          <dl className="privacy-stats">
            <div><dt>0</dt><dd>accounts</dd></div>
            <div><dt>0</dt><dd>subscriptions</dd></div>
            <div><dt>0</dt><dd>telemetry events</dd></div>
          </dl>
          <div className="network-note" role="note">
            <strong>Clear network boundaries</strong>
            <p>Language and model setup, signed update checks, and optional BYOK providers use the network. Lerro&apos;s update service never receives audio, transcripts, or app context.</p>
          </div>
        </div>
      </section>

      <section className="section source-section">
        <div className="source-copy">
          <p className="eyebrow">Open by default</p>
          <h2>Inspect every product decision.</h2>
          <p>Lerro is Apache-2.0 licensed. The app, privacy policy, architecture, tests, release scripts, and website are all public.</p>
        </div>
        <InteriorLink className="source-card" variant="card" href={githubUrl}>
          <span className="source-card__mark" aria-hidden="true">&lt;/&gt;</span>
          <span><b>Ryan-yang125/lerro</b><small>Swift · SwiftUI · Apple Speech · MLX</small></span>
          <Arrow direction="up" />
        </InteriorLink>
      </section>

      <section className="section faq-section" id="faq">
        <div className="faq-heading">
          <p className="eyebrow">Questions, answered</p>
          <h2>Before your first dictation.</h2>
        </div>
        <div className="faq-list">
          {faqs.map((faq, index) => (
            <Disclosure key={faq.question} summary={faq.question} defaultOpen={index === 0}>
              <p>{faq.answer}</p>
            </Disclosure>
          ))}
        </div>
      </section>

      <section className="section download-section" id="download">
        <div className="download-panel">
          <div>
            <p className="eyebrow">Lerro 1.1</p>
            <h2>Give your keyboard a voice.</h2>
            <p>Signed, notarized, and ready for Apple silicon Macs running macOS 26 or later.</p>
          </div>
          <div className="download-actions">
            <InteriorLink variant="primary" href={downloadUrl}>Download for macOS <Arrow /></InteriorLink>
            <a href="/changelog">Read the changelog <Arrow /></a>
          </div>
        </div>
      </section>

      <SiteFooter />
    </main>
  );
}
