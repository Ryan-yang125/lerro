# Lerro website

Public product page for [Lerro](https://github.com/Ryan-yang125/lerro), the open-source macOS voice-typing app.

The visual system follows the Interior material and interaction language used
by Motion Lexicon. Adapted press, ripple, and disclosure components live under
`app/components/interior/`; the upstream MIT notice is preserved in the root
`NOTICE`. The animated Hero HUD follows the dimensions and timing of Lerro's
native macOS HUD.

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
```

`npm run build` verifies the Vinext Worker build in `dist/`.

## Deployment

- Production URL: <https://lerroapp.com>
- Worker deployment: `npm run deploy`
- `www.lerroapp.com` permanently redirects to the apex domain.

The download CTA points to <https://updates.lerroapp.com/download/macos/latest>. The
distribution Worker serves only the currently published, signed macOS archive from
private Cloudflare R2 storage.

## Release history

- Public release notes live at <https://lerroapp.com/changelog>.
- Add a new published entry to `app/changelog/releases.ts` with its immutable
  distribution URL: `https://updates.lerroapp.com/releases/<version>/<build>/Lerro-macOS-arm64.zip`.
- Keep older entries unchanged. The distribution Worker resolves those URLs from
  its published D1 metadata and private R2 archive.
