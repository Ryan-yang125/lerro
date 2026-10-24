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
- `src/components/`: `HomePage` (assembles the home sections), `ChangelogPage`, `Nav` (floating pill), `Footer`.
- `src/components/home/`: one component per home section (`Intro`, `Story`, `Apps`, `Speed`, `Features`, `Steps`, `Pricing`, `Compare`, `Privacy`, `Faq`, `TryIt`), plus `Icon` and `avatars.ts` (hand-drawn chat avatars). Sections that animate carry their own `<script>`: `Story` (pinned scroll story WeChat, Mail, Notes), `Speed` (typing race), `Features` (learning meters), `TryIt` (hold the fn key). Shared helpers are in `src/scripts/onview.ts`.
- `src/data/home.ts`: home page copy in both languages (`home.zh`, `home.en`) and the demo content shown inside the mock app windows (`demo`, Chinese on both pages because the dictation examples are Chinese). `src/data/chrome.ts`: footer copy.
- `src/data/releases.ts`: release history.
- `src/styles/global.css`: design tokens, buttons, nav, footer. `home.css`: home page sections. `changelog.css`: changelog page.
- `public/apps/<name>.png`: app icons for the icon grid and demo windows (lowercase names).
- `src/site.ts`: URLs, version, and `localizedPath`.

The site uses a single light theme (paper background). With `prefers-reduced-motion`, animations and transitions are off, the typing race shows its final text, and the pinned story shows each scene in its finished state while scrolling.

## Release history

Add the new release at the top of `releases` in `src/data/releases.ts` with `version`, `build`, `publishedAt`, `downloadUrl`, and `zh` / `en` objects (`publishedLabel`, `summary`, `highlights`). The download URL is the immutable distribution URL `https://updates.lerroapp.com/releases/<version>/<build>/Lerro-macOS-arm64.zip`. Update `currentVersion` in `src/site.ts` and keep older entries unchanged. The download button on the site points to `https://updates.lerroapp.com/download/macos/latest`, which serves the currently published archive.
