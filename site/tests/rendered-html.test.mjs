import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const projectRoot = new URL("../", import.meta.url);

async function render(path = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}-${path}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`https://lerro.pages.dev${path}`, {
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
  assert.match(html, /<title>Lerro — Open-source voice typing for macOS<\/title>/i);
  assert.match(html, /Speak freely\./);
  assert.match(html, /Write clearly\./);
  assert.match(html, /Download for macOS/);
  assert.match(html, />Dictate</);
  assert.match(html, />Translate</);
  assert.match(html, />Ask</);
  assert.match(html, /Apple Speech/);
  assert.match(html, /Your API key/);
  assert.match(html, /Qwen on your Mac/);
  assert.match(html, /System Settings/);
  assert.match(html, /Privacy &amp; Security/);
  assert.match(html, /https:\/\/github\.com\/Ryan-yang125\/lerro\/releases/);
  assert.match(html, /https:\/\/lerro\.pages\.dev/);
  assert.doesNotMatch(html, /releases\/latest|codex-preview|SkeletonPreview|react-loading-skeleton/i);
});

test("publishes crawler metadata for the Pages host", async () => {
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
  assert.match(robots, /Host: https:\/\/lerro\.pages\.dev/);
  assert.match(robots, /Sitemap: https:\/\/lerro\.pages\.dev\/sitemap\.xml/);
  assert.match(sitemap, /<loc>https:\/\/lerro\.pages\.dev\/<\/loc>/);
});

test("keeps the public site free of starter surfaces", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("app/page.tsx", projectRoot), "utf8"),
    readFile(new URL("app/layout.tsx", projectRoot), "utf8"),
    readFile(new URL("package.json", projectRoot), "utf8"),
  ]);

  assert.match(page, /Lerro/);
  assert.match(layout, /https:\/\/lerro\.pages\.dev/);
  assert.match(packageJson, /"name": "lerro-site"/);
  assert.match(packageJson, /"build:pages": "LERRO_STATIC_EXPORT=1 next build"/);
  assert.doesNotMatch(
    `${page}\n${layout}\n${packageJson}`,
    /site-creator|Starter Project|SkeletonPreview|react-loading-skeleton|drizzle|tailwind/i,
  );

  await Promise.all([
    access(new URL("public/lerro-logo.svg", projectRoot)),
    access(new URL("public/lerro-symbol.svg", projectRoot)),
    access(new URL("public/favicon.png", projectRoot)),
    access(new URL("public/og.png", projectRoot)),
  ]);

  await Promise.all([
    assert.rejects(access(new URL("app/_sites-preview", projectRoot))),
    assert.rejects(access(new URL("app/chatgpt-auth.ts", projectRoot))),
    assert.rejects(access(new URL("db", projectRoot))),
    assert.rejects(access(new URL("drizzle.config.ts", projectRoot))),
    assert.rejects(access(new URL("examples", projectRoot))),
  ]);
});
