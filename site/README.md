# Lerro website

Public site for [Lerro](https://github.com/Ryan-yang125/lerro), the open-source macOS voice-typing app. Production: <https://lerroapp.com>.

## Stack

Astro 7 static build in `dist/`, served by a Cloudflare Worker with static assets (`worker/index.js`, `wrangler.jsonc`). The Worker redirects `www` to the apex host (308) and the legacy `/zh` routes to `/` and `/changelog` (301); every other request goes to the static assets.

## Routes

| Path | Page |
| --- | --- |
| `/` | Home, Chinese |
| `/en` | Home, English |
| `/changelog` | Changelog, Chinese |
| `/en/changelog` | Changelog, English |
| `/zh`, `/zh/changelog` | Redirect to `/`, `/changelog` |

## Commands

Requires Node.js 22.12 or later.

```bash
npm ci
npm run dev      # local dev server
npm run lint     # astro check
npm run build    # static build into dist/
npm test         # tests read dist/, so build first
npm run deploy   # build, then wrangler deploy
```

## Structure

- `src/layouts/Base.astro`: head metadata, nav, footer.
- `src/components/`: `HomePage`, `ChangelogPage`, `Nav`, `Footer`, `Glyphs` (SVG sprite), `HeroDemo`.
- `src/data/home.ts`: home page copy in both languages. `src/data/chrome.ts`: nav and footer copy.
- `src/data/releases.ts`: release history.
- `src/styles/global.css`: design tokens and shared styles. `changelog.css`: changelog page.
- `src/site.ts`: URLs, version, and `localizedPath`.

## Release history

Add the new release at the top of `releases` in `src/data/releases.ts` with `version`, `build`, `publishedAt`, `downloadUrl`, and `zh` / `en` objects (`publishedLabel`, `summary`, `highlights`). The download URL is the immutable distribution URL `https://updates.lerroapp.com/releases/<version>/<build>/Lerro-macOS-arm64.zip`. Update `currentVersion` in `src/site.ts` and keep older entries unchanged. The download button on the site points to `https://updates.lerroapp.com/download/macos/latest`, which serves the currently published archive.
