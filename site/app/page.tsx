import type { CSSProperties } from "react";
import Image from "next/image";

const githubUrl = "https://github.com/Ryan-yang125/lerro";
const releasesUrl = "https://github.com/Ryan-yang125/lerro/releases";

const modes = [
  {
    key: "D",
    title: "Dictate",
    copy: "Speak naturally. Lerro cleans up the sentence and places it at your cursor.",
  },
  {
    key: "T",
    title: "Translate",
    copy: "Say it once, then write it in the language your conversation needs.",
  },
  {
    key: "A",
    title: "Ask",
    copy: "Select text, ask a question, and turn the answer into your next edit.",
  },
];

const intelligenceModes = [
  {
    label: "Raw",
    title: "Apple Speech",
    copy: "Direct transcription with the shortest path from voice to cursor.",
  },
  {
    label: "BYOK",
    title: "Your API key",
    copy: "Use DeepSeek or another OpenAI-compatible provider for fast refinement.",
  },
  {
    label: "Local",
    title: "Qwen on your Mac",
    copy: "Keep model processing offline when local control matters most.",
  },
];

const permissions = [
  ["Microphone", "Captures only the voice you choose to dictate."],
  ["Speech Recognition", "Turns audio into the raw words Lerro works with."],
  ["Accessibility", "Returns the finished text to the active app."],
  ["Input Monitoring", "Lets your chosen shortcut work across macOS."],
];

const faqs = [
  {
    question: "Is Lerro free?",
    answer:
      "Yes. Lerro is an open-source macOS app. You can use raw dictation for free, bring your own model API key, or download the optional local model.",
  },
  {
    question: "Where does my voice data go?",
    answer:
      "Raw transcription uses Apple Speech. Local mode keeps model processing on your Mac. BYOK mode sends the transcript and the context options you enable to your selected provider.",
  },
  {
    question: "Why does Lerro need Accessibility and Input Monitoring?",
    answer:
      "Accessibility lets Lerro paste finished text at the active cursor. Input Monitoring lets a single key or shortcut start dictation from any app. The onboarding flow explains each permission before you grant it.",
  },
  {
    question: "Which Macs are supported?",
    answer:
      "The current preview requires macOS 26 or later on Apple silicon. Local AI also needs roughly 3.03 GB for the optional model download.",
  },
  {
    question: "Why might macOS block the preview the first time?",
    answer:
      "The current public build is a preview. If macOS blocks the first launch, open System Settings, choose Privacy & Security, and use Open Anyway after confirming the download came from the Lerro GitHub repository.",
  },
];

function Arrow() {
  return <span aria-hidden="true">↗</span>;
}

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Lerro home">
          <Image src="/lerro-logo.svg" alt="Lerro" width={150} height={40} priority />
        </a>
        <nav aria-label="Primary navigation">
          <a href="#features">Features</a>
          <a href="#privacy">Privacy</a>
          <a href="#faq">FAQ</a>
        </nav>
        <a className="header-cta" href={releasesUrl}>
          <span className="cta-label-full">Download preview</span>
          <span className="cta-label-compact">Download</span>
        </a>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <div className="preview-label">
            <span className="status-dot" aria-hidden="true" />
            Public preview for macOS
          </div>
          <h1>Speak freely.<br />Write clearly.</h1>
          <p className="hero-lede">
            Lerro turns your voice into clean, editable text in any Mac app—
            right where your cursor is waiting.
          </p>
          <div className="hero-actions">
            <a className="button button-primary" href={releasesUrl}>
              Download for macOS <Arrow />
            </a>
            <a className="button button-secondary" href={githubUrl}>
              View source <Arrow />
            </a>
          </div>
          <p className="requirements-inline">
            Free · Open source · macOS 26+ · Apple silicon
          </p>
        </div>

        <div className="product-demo" aria-label="Lerro dictation workflow demonstration">
          <div className="window-bar" aria-hidden="true">
            <span className="traffic-light red" />
            <span className="traffic-light yellow" />
            <span className="traffic-light green" />
            <span className="window-title">Notes</span>
          </div>
          <div className="editor-surface">
            <div className="editor-kicker">Launch notes</div>
            <p className="editor-copy">
              Lerro turns a rough thought into clear text—right where the cursor is.
              <span className="text-caret" aria-hidden="true" />
            </p>
            <div className="demo-hud" aria-hidden="true">
              <span className="hud-key">Fn</span>
              <span className="hud-divider" />
              <span className="hud-content hud-waveform">
                {[8, 15, 24, 13, 29, 18, 9, 22, 12].map((height, index) => (
                  <span
                    className="wave-bar"
                    key={index}
                    style={{ "--bar-height": `${height}px`, "--bar-delay": `${index * -0.07}s` } as CSSProperties}
                  />
                ))}
              </span>
              <span className="hud-content hud-processing">
                <span />
                <span />
                <span />
              </span>
            </div>
            <div className="demo-status" aria-hidden="true">
              <span>Press</span><b>Fn</b><i />
              <span>Speak</span><i />
              <span>Done</span>
            </div>
          </div>
        </div>
      </section>

      <section className="trust-strip" aria-label="Product principles">
        <span>Local-first</span>
        <span>Bring your own key</span>
        <span>No account</span>
        <span>Open source</span>
      </section>

      <section className="section" id="features">
        <div className="section-heading">
          <p className="eyebrow">One shortcut, three modes</p>
          <h2>Your voice can write, translate, or think with you.</h2>
        </div>
        <div className="feature-grid">
          {modes.map((mode) => (
            <article className="feature-card" key={mode.title}>
              <span className="feature-key" aria-hidden="true">{mode.key}</span>
              <h3>{mode.title}</h3>
              <p>{mode.copy}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="section intelligence-section" id="intelligence">
        <div className="section-heading narrow">
          <p className="eyebrow">Choose the right intelligence</p>
          <h2>Fast by default. Smarter when you want it.</h2>
          <p>
            Keep a direct Apple Speech path, bring a fast cloud model, or run the optional model locally.
          </p>
        </div>
        <div className="mode-panel">
          {intelligenceModes.map((mode, index) => (
            <article className={`mode-row ${index === 1 ? "featured" : ""}`} key={mode.label}>
              <div className="mode-label">{mode.label}</div>
              <div>
                <h3>{mode.title}</h3>
                <p>{mode.copy}</p>
              </div>
              {index === 1 && <span className="recommended">Recommended</span>}
            </article>
          ))}
        </div>
      </section>

      <section className="section privacy-section" id="privacy">
        <div className="privacy-intro">
          <p className="eyebrow">Permission with purpose</p>
          <h2>Every permission has one clear job.</h2>
          <p>
            Lerro explains each macOS permission before asking. Audio saving stays off by default, and model context remains under your control.
          </p>
          <a className="text-link" href={`${githubUrl}/blob/main/PRIVACY.md`}>
            Read the privacy model <Arrow />
          </a>
        </div>
        <div className="permission-list">
          {permissions.map(([name, description], index) => (
            <div className="permission-row" key={name}>
              <span className="permission-number">0{index + 1}</span>
              <div>
                <h3>{name}</h3>
                <p>{description}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="section steps-section" id="how-it-works">
        <div className="section-heading">
          <p className="eyebrow">Three steps</p>
          <h2>Ready whenever the cursor is.</h2>
        </div>
        <ol className="steps-list">
          <li>
            <span>1</span>
            <div><h3>Choose a shortcut</h3><p>Use Fn, another modifier, or a combination that feels natural.</p></div>
          </li>
          <li>
            <span>2</span>
            <div><h3>Speak naturally</h3><p>The HUD responds immediately, follows your voice, and shows processing at a glance.</p></div>
          </li>
          <li>
            <span>3</span>
            <div><h3>Keep writing</h3><p>Your finished text lands at the active cursor, ready to edit or send.</p></div>
          </li>
        </ol>
      </section>

      <section className="section download-section" id="download">
        <div className="download-card">
          <div>
            <div className="preview-label on-dark">
              <span className="status-dot" aria-hidden="true" />
              Preview release
            </div>
            <h2>Give your keyboard a voice.</h2>
            <p>Built for macOS 26 or later on Apple silicon.</p>
          </div>
          <div className="download-actions">
            <a className="button button-light" href={releasesUrl}>
              Open releases <Arrow />
            </a>
            <a className="source-link" href={githubUrl}>GitHub repository <Arrow /></a>
          </div>
        </div>
        <div className="gatekeeper-note" role="note">
          <strong>First-launch note</strong>
          <p>
            This is a preview build. If macOS blocks it, confirm the download came from the Lerro GitHub repository, then open System Settings → Privacy &amp; Security → Open Anyway.
          </p>
        </div>
      </section>

      <section className="section faq-section" id="faq">
        <div className="section-heading narrow">
          <p className="eyebrow">Questions, answered</p>
          <h2>Before your first dictation.</h2>
        </div>
        <div className="faq-list">
          {faqs.map((faq) => (
            <details key={faq.question}>
              <summary>{faq.question}<span aria-hidden="true">+</span></summary>
              <p>{faq.answer}</p>
            </details>
          ))}
        </div>
      </section>

      <footer>
        <a className="footer-brand" href="#top">
          <Image src="/lerro-symbol.svg" alt="" width={40} height={32} />
          <span>Lerro</span>
        </a>
        <p>Speak freely. Write clearly.</p>
        <div className="footer-links">
          <a href={githubUrl}>GitHub</a>
          <a href={releasesUrl}>Releases</a>
          <a href={`${githubUrl}/blob/main/PRIVACY.md`}>Privacy</a>
          <a href={`${githubUrl}/blob/main/SECURITY.md`}>Security</a>
          <a href={`${githubUrl}/blob/main/LICENSE`}>License</a>
        </div>
      </footer>
    </main>
  );
}
