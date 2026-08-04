export type Release = {
  version: string;
  build: string;
  publishedAt: string;
  publishedLabel: string;
  summary: string;
  highlights: readonly string[];
  downloadUrl: string;
};

// Add each published release here. Immutable URLs stay attached to the version
// they shipped with, while the homepage always points to the latest release.
export const releases: readonly Release[] = [
  {
    version: "1.1.1",
    build: "7",
    publishedAt: "2026-08-04",
    publishedLabel: "August 4, 2026",
    summary: "Reliable Fn shortcuts that keep macOS Emoji out of the way.",
    highlights: [
      "Built-in Fn and external Globe keys now use one physical-key ownership model.",
      "Every configured Fn sequence stays captured through its final release, including repeated modifier events.",
      "Shortcut monitoring now observes keyboard events only and keeps the same two-permission setup.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.1.1/7/Lerro-macOS-arm64.zip",
  },
  {
    version: "1.1.0",
    build: "6",
    publishedAt: "2026-08-04",
    publishedLabel: "August 4, 2026",
    summary: "Faster shortcuts, deeper Apple Speech, and device-side translation.",
    highlights: [
      "Fn shortcuts now use a cleaner two-permission setup and avoid the Globe menu.",
      "Apple Speech handles live revisions and audio endings more reliably.",
      "Translate now uses Apple Translation on the device, with clearer language-resource setup.",
      "Onboarding, shortcut settings, the idle HUD, and update downloads are easier to use.",
      "The website and GitHub now show the current product, real screenshots, and mirrored release artifacts.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.1.0/6/Lerro-macOS-arm64.zip",
  },
  {
    version: "1.0.3",
    build: "5",
    publishedAt: "2026-08-02",
    publishedLabel: "August 2, 2026",
    summary: "The first public stable update.",
    highlights: [
      "Automatic updates deliver signed, notarized releases inside Lerro.",
      "The public download is verified for macOS 26 on Apple silicon.",
    ],
    downloadUrl:
      "https://updates.lerroapp.com/releases/1.0.3/5/Lerro-macOS-arm64.zip",
  },
];
