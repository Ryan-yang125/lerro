# Lerro website

Public product page for [Lerro](https://github.com/Ryan-yang125/lerro), the open-source macOS voice-typing app.

## Requirements

- Node.js 22.13 or later
- npm

## Local development

```bash
npm install
npm run dev
```

## Verification

```bash
npm run lint
npm run build
npm test
npm run build:pages
```

`npm run build` verifies the vinext/Sites worker build in `dist/`. `npm run build:pages` produces the static Cloudflare Pages artifact in `out/`.

## Deployment

- Production URL: <https://lerro.pages.dev>
- Cloudflare Pages build command: `npm run build:pages`
- Cloudflare Pages output directory: `out`

The download CTA points to the complete [GitHub Releases](https://github.com/Ryan-yang125/lerro/releases) page so preview releases remain discoverable.
