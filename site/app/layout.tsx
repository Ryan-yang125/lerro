import type { Metadata, Viewport } from "next";
import "./globals.css";

const siteUrl = "https://lerro.pages.dev";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: "Lerro — Open-source voice typing for macOS",
  description:
    "Speak naturally and write clearly in any Mac app. Lerro is a free, open-source voice typing tool with raw, BYOK, and local AI modes.",
  applicationName: "Lerro",
  keywords: [
    "voice typing for macOS",
    "open source dictation",
    "macOS speech to text",
    "AI voice typing",
    "Lerro",
  ],
  alternates: { canonical: "/" },
  icons: {
    icon: [{ url: "/favicon.png", type: "image/png" }],
    apple: [{ url: "/favicon.png", type: "image/png" }],
  },
  openGraph: {
    type: "website",
    url: siteUrl,
    siteName: "Lerro",
    title: "Lerro — Speak freely. Write clearly.",
    description: "Free, open-source voice typing built for macOS.",
    images: [{ url: "/og.png", width: 1280, height: 640, alt: "Lerro brand and macOS voice typing preview" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Lerro — Speak freely. Write clearly.",
    description: "Free, open-source voice typing built for macOS.",
    images: ["/og.png"],
  },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#fafafa" },
    { media: "(prefers-color-scheme: dark)", color: "#111111" },
  ],
  colorScheme: "light dark",
};

const softwareApplicationJsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Lerro",
  url: siteUrl,
  operatingSystem: "macOS 26 or later on Apple silicon",
  applicationCategory: "UtilitiesApplication",
  description: "Free, open-source voice typing for macOS.",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
  },
  downloadUrl: "https://github.com/Ryan-yang125/lerro/releases",
  softwareHelp: `${siteUrl}/#faq`,
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        {children}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareApplicationJsonLd) }}
        />
      </body>
    </html>
  );
}
