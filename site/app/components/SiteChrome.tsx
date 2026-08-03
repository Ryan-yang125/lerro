import Image from "next/image";
import Link from "next/link";
import { InteriorLink } from "./interior/InteriorLink";

const githubUrl = "https://github.com/Ryan-yang125/lerro";
const downloadUrl = "https://updates.lerroapp.com/download/macos/latest";

export function SiteHeader({ current }: { current?: "home" | "changelog" }) {
  return (
    <header className="site-header">
      <Link className="brand" href="/" aria-label="Lerro home">
        <Image src="/lerro-logo.svg" alt="Lerro" width={150} height={40} priority />
      </Link>
      <nav aria-label="Primary navigation">
        <Link href="/#workflow">How it works</Link>
        <Link href="/#product">Product</Link>
        <Link href="/#privacy">Privacy</Link>
        <Link href="/changelog" aria-current={current === "changelog" ? "page" : undefined}>Changelog</Link>
      </nav>
      <div className="header-actions">
        {current === "changelog" ? (
          <Link className="header-text-link" href="/">Home</Link>
        ) : (
          <Link className="header-text-link" href="/changelog">Updates</Link>
        )}
        <InteriorLink className="header-download" variant="primary" href={downloadUrl}>
          <span className="download-label-full">Download for macOS</span>
          <span className="download-label-short">Download</span>
        </InteriorLink>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <Link className="footer-brand" href="/">
        <Image src="/lerro-symbol.svg" alt="" width={40} height={32} />
        <span>Lerro</span>
      </Link>
      <p>Voice to text, native to Mac.</p>
      <div className="footer-links">
        <a href={githubUrl}>GitHub</a>
        <Link href="/changelog">Changelog</Link>
        <a href={downloadUrl}>Download</a>
        <a href={`${githubUrl}/blob/main/PRIVACY.md`}>Privacy</a>
        <a href={`${githubUrl}/blob/main/LICENSE`}>License</a>
      </div>
    </footer>
  );
}
