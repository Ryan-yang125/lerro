import type { Metadata, Viewport } from "next";
import "./globals.css";

const siteUrl = "https://lerroapp.com";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: "Lerro — Native voice typing for macOS",
  description:
    "Fast, local-first voice typing powered by Apple Speech on macOS 26. Free, open source, and private by architecture.",
  applicationName: "Lerro",
  keywords: [
    "voice typing for macOS",
    "open source dictation",
    "macOS speech to text",
    "Apple Speech macOS 26",
    "local voice typing",
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
    title: "Lerro — Speak. Your Mac writes.",
    description: "Native Apple Speech voice typing for macOS 26. Fast, local-first, and open source.",
    images: [{ url: "/og.png", width: 1280, height: 640, alt: "Lerro native voice typing for macOS" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Lerro — Speak. Your Mac writes.",
    description: "Native Apple Speech voice typing for macOS 26. Fast, local-first, and open source.",
    images: ["/og.png"],
  },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#efeeea" },
    { media: "(prefers-color-scheme: dark)", color: "#141312" },
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
  softwareVersion: "1.1.0",
  description: "Native Apple Speech voice typing for macOS 26 with on-device translation and optional local MLX refinement.",
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
  },
  downloadUrl: "https://updates.lerroapp.com/download/macos/latest",
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
