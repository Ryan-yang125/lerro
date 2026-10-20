import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import worker from "../worker/index.js";

const dist = join(dirname(fileURLToPath(import.meta.url)), "..", "dist");
const read = (file) => readFileSync(join(dist, file), "utf8");

const origin = "https://lerroapp.com";
const githubUrl = "https://github.com/Ryan-yang125/lerro";
const latestDownload = "https://updates.lerroapp.com/download/macos/latest";
const release = (version, build) =>
  `https://updates.lerroapp.com/releases/${version}/${build}/Lerro-macOS-arm64.zip`;
const olderVersions = [
  ["1.6.0", "13"],
  ["1.5.1", "12"],
  ["1.5.0", "11"],
  ["1.4.0", "10"],
  ["1.3.0", "9"],
  ["1.2.0", "8"],
  ["1.1.1", "7"],
  ["1.1.0", "6"],
  ["1.0.3", "5"],
];

const pages = [
  { file: "index.html", lang: "zh-CN", canonical: `${origin}/`, titleIncludes: "Lerro", home: true },
  { file: "en.html", lang: "en", canonical: `${origin}/en`, titleIncludes: "Lerro", home: true },
  { file: "changelog.html", lang: "zh-CN", canonical: `${origin}/changelog`, title: "更新日志 — Lerro" },
  { file: "en/changelog.html", lang: "en", canonical: `${origin}/en/changelog`, title: "Changelog — Lerro" },
];

function textOf(html) {
  return html.replace(/<[^>]+>/g, "").replace(/&#39;|&#x27;|&apos;/g, "'").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim();
}

for (const page of pages) {
  test(`${page.file} metadata`, () => {
    const html = read(page.file);
    assert.match(html, new RegExp(`<html lang="${page.lang}"`));
    const title = html.match(/<title>([^<]*)<\/title>/)?.[1];
    assert.ok(title, "title present");
    if (page.title) assert.equal(title, page.title);
    else assert.ok(title.includes(page.titleIncludes));
    assert.ok(html.includes(`<link rel="canonical" href="${page.canonical}"`));
    for (const [hreflang, suffix] of [["zh-CN", ""], ["en", ""], ["x-default", ""]]) {
      assert.match(html, new RegExp(`<link rel="alternate" hreflang="${hreflang}" href="${origin}[^"]*"`), `${hreflang}${suffix}`);
    }
    assert.ok(html.includes(`property="og:image" content="${origin}/og.png"`));
    assert.ok(html.includes('name="twitter:card" content="summary_large_image"'));
  });

  test(`${page.file} links and no legacy references`, () => {
    const html = read(page.file);
    assert.ok(html.includes(latestDownload), "download URL");
    assert.ok(html.includes(githubUrl), "GitHub link");
    assert.ok(!html.includes("/screenshots/"), "screenshots reference");
    assert.ok(!html.includes("_next"), "_next reference");
    assert.ok(!html.includes("vinext"), "vinext reference");
  });
}

test("hreflang alternates point at the matching page in each language", () => {
  const zh = read("index.html");
  assert.ok(zh.includes(`hreflang="en" href="${origin}/en"`));
  assert.ok(zh.includes(`hreflang="x-default" href="${origin}/"`));
  const enLog = read("en/changelog.html");
  assert.ok(enLog.includes(`hreflang="zh-CN" href="${origin}/changelog"`));
  assert.ok(enLog.includes(`hreflang="en" href="${origin}/en/changelog"`));
});

test("hero headings", () => {
  const h1 = (file) => textOf(read(file).match(/<h1[^>]*>([\s\S]*?)<\/h1>/)[1]);
  assert.equal(h1("index.html"), "说出来，就写好了");
  assert.equal(h1("en.html"), "Speak it. It's written.");
});

for (const [file, lang] of [["changelog.html", "zh"], ["en/changelog.html", "en"]]) {
  test(`${file} lists the newest release first with its immutable URL`, () => {
    const html = read(file);
    const first = html.indexOf("Lerro 1.9.2");
    assert.ok(first >= 0, "1.9.2 present");
    assert.ok(html.includes("https://updates.lerroapp.com/releases/1.9.2/20/Lerro-macOS-arm64.dmg"));
    assert.ok(html.indexOf("Lerro 1.9.1") > first, "1.9.1 listed after 1.9.2");
    assert.ok(html.includes("https://updates.lerroapp.com/releases/1.9.1/19/Lerro-macOS-arm64.dmg"));
    assert.ok(html.indexOf("Lerro 1.9.0") > first, "1.9.0 listed after 1.9.2");
    assert.ok(html.includes("https://updates.lerroapp.com/releases/1.9.0/18/Lerro-macOS-arm64.dmg"));
    assert.ok(html.indexOf("Lerro 1.8.0") > first, "1.8.0 listed after 1.9.2");
    assert.ok(html.includes("https://updates.lerroapp.com/releases/1.8.0/17/Lerro-macOS-arm64.dmg"));
    assert.ok(html.indexOf("Lerro 1.7.2") > first, "1.7.2 listed after 1.9.2");
    assert.ok(html.includes("https://updates.lerroapp.com/releases/1.7.2/16/Lerro-macOS-arm64.dmg"));
    for (const [version, build] of [["1.7.1", "15"], ["1.7.0", "14"], ...olderVersions]) {
      const at = html.indexOf(`Lerro ${version}`);
      assert.ok(at > first, `${version} listed after 1.9.2`);
      assert.ok(html.includes(release(version, build)), `${version} download URL`);
    }
    assert.ok(html.includes(lang === "zh" ? "2026 年 10 月 21 日" : "October 21, 2026"));
  });
}

test("404 page", () => {
  const html = read("404.html");
  assert.match(html, /<html lang="zh-CN"/);
  assert.ok(html.includes('href="/"'));
  assert.ok(html.includes('href="/en"'));
});

test("sitemap lists the four pages with alternates", () => {
  const xml = read("sitemap.xml");
  for (const path of ["/", "/en", "/changelog", "/en/changelog"]) {
    assert.ok(xml.includes(`<loc>${origin}${path}</loc>`), path);
  }
  assert.ok(xml.includes('hreflang="x-default"'));
});

// Worker routing
const env = () => {
  const calls = [];
  return { calls, ASSETS: { fetch: async (request) => (calls.push(request.url), new Response("asset")) } };
};

test("worker redirects www to the apex host with 308", async () => {
  const e = env();
  const res = await worker.fetch(new Request("https://www.lerroapp.com/changelog?x=1"), e);
  assert.equal(res.status, 308);
  assert.equal(res.headers.get("location"), "https://lerroapp.com/changelog?x=1");
  assert.equal(e.calls.length, 0);
});

test("worker redirects legacy /zh routes with 301", async () => {
  for (const [from, to] of [["/zh", "/"], ["/zh/", "/"], ["/zh/changelog", "/changelog"], ["/zh/changelog/", "/changelog"]]) {
    const e = env();
    const res = await worker.fetch(new Request(`https://lerroapp.com${from}`), e);
    assert.equal(res.status, 301, from);
    assert.equal(res.headers.get("location"), `https://lerroapp.com${to}`, from);
    assert.equal(e.calls.length, 0);
  }
});

test("worker serves other paths from static assets", async () => {
  for (const path of ["/", "/en", "/changelog", "/en/changelog", "/og.png"]) {
    const e = env();
    const res = await worker.fetch(new Request(`https://lerroapp.com${path}`), e);
    assert.equal(res.status, 200);
    assert.deepEqual(e.calls, [`https://lerroapp.com${path}`]);
  }
});
