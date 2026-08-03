import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const projectRoot = new URL("../", import.meta.url);

async function render(path = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}-${path}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`https://lerroapp.com${path}`, {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the complete Lerro landing page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Lerro — Native voice typing for macOS<\/title>/i);
  assert.match(html, /Speak\./);
  assert.match(html, /Your Mac writes\./);
  assert.match(html, /Download for macOS/);
  assert.match(html, />Dictate</);
  assert.match(html, />Translate</);
  assert.match(html, />Refine</);
  assert.match(html, /Apple Speech/);
  assert.match(html, /No telemetry/);
  assert.match(html, /does not request Input Monitoring/);
  assert.match(html, /Signed, notarized/);
  assert.match(html, /hero-hud--listening/);
  assert.equal((html.match(/hero-hud__bar/g) ?? []).length, 10);
  assert.match(html, /data-interior-link/);
  assert.match(html, /lerro-home-light\.png/);
  assert.match(html, /lerro-onboarding-shortcuts-light\.png/);
  assert.match(html, /lerro-settings-light\.png/);
  assert.match(html, /https:\/\/updates\.lerroapp\.com\/download\/macos\/latest/);
  assert.match(html, /href="\/changelog"/);
  assert.match(html, /https:\/\/lerroapp\.com/);
  assert.doesNotMatch(html, /releases\/latest|codex-preview|SkeletonPreview|react-loading-skeleton/i);
});

test("server-renders the changelog with permanent release downloads", async () => {
  const response = await render("/changelog");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Changelog — Lerro<\/title>/i);
  assert.match(html, /What(?:&#x27;|&apos;|’)s new in Lerro\./);
  assert.match(html, /Version(?:\s|<[^>]+>)*1\.1\.0/);
  assert.match(html, /Build(?:\s|<[^>]+>)*6/);
  assert.match(html, /August 4, 2026/);
  assert.match(html, /https:\/\/updates\.lerroapp\.com\/releases\/1\.1\.0\/6\/Lerro-macOS-arm64\.zip/);
  assert.match(html, /Version(?:\s|<[^>]+>)*1\.0\.3/);
  assert.match(html, /Build(?:\s|<[^>]+>)*5/);
  assert.match(html, /August 2, 2026/);
  assert.match(html, /https:\/\/updates\.lerroapp\.com\/releases\/1\.0\.3\/5\/Lerro-macOS-arm64\.zip/);
  assert.match(html, /href="\/changelog"/);
});

test("publishes crawler metadata for the custom domain", async () => {
  const [robotsResponse, sitemapResponse] = await Promise.all([
    render("/robots.txt"),
    render("/sitemap.xml"),
  ]);
  assert.equal(robotsResponse.status, 200);
  assert.equal(sitemapResponse.status, 200);

  const [robots, sitemap] = await Promise.all([
    robotsResponse.text(),
    sitemapResponse.text(),
  ]);
  assert.match(robots, /Host: https:\/\/lerroapp\.com/);
  assert.match(robots, /Sitemap: https:\/\/lerroapp\.com\/sitemap\.xml/);
  assert.match(sitemap, /<loc>https:\/\/lerroapp\.com\/<\/loc>/);
  assert.match(sitemap, /<loc>https:\/\/lerroapp\.com\/changelog<\/loc>/);
});

test("keeps the public site free of starter surfaces", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("app/page.tsx", projectRoot), "utf8"),
    readFile(new URL("app/layout.tsx", projectRoot), "utf8"),
    readFile(new URL("package.json", projectRoot), "utf8"),
  ]);

  assert.match(page, /Lerro/);
  assert.match(layout, /https:\/\/lerroapp\.com/);
  assert.match(packageJson, /"name": "lerro-site"/);
  assert.match(packageJson, /"deploy": "npm run build && wrangler deploy"/);
  assert.doesNotMatch(
    `${page}\n${layout}\n${packageJson}`,
    /site-creator|Starter Project|SkeletonPreview|react-loading-skeleton|drizzle|tailwind/i,
  );

  await Promise.all([
    access(new URL("public/lerro-logo.svg", projectRoot)),
    access(new URL("public/lerro-symbol.svg", projectRoot)),
    access(new URL("public/favicon.png", projectRoot)),
    access(new URL("public/og.png", projectRoot)),
    access(new URL("public/screenshots/lerro-home-light.png", projectRoot)),
    access(new URL("public/screenshots/lerro-onboarding-shortcuts-light.png", projectRoot)),
    access(new URL("public/screenshots/lerro-settings-light.png", projectRoot)),
    access(new URL("app/components/interior/README.md", projectRoot)),
  ]);

  await Promise.all([
    assert.rejects(access(new URL("app/_sites-preview", projectRoot))),
    assert.rejects(access(new URL("app/chatgpt-auth.ts", projectRoot))),
    assert.rejects(access(new URL("db", projectRoot))),
    assert.rejects(access(new URL("drizzle.config.ts", projectRoot))),
    assert.rejects(access(new URL("examples", projectRoot))),
  ]);
});
