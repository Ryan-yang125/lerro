import type { APIRoute } from "astro";
import { localizedPath, siteUrl } from "../site";

const pages = ["/", "/changelog"] as const;

export const GET: APIRoute = () => {
  const urls = pages.flatMap((path) =>
    (["zh", "en"] as const).map((lang) => {
      const alternates = [
        { hreflang: "zh-CN", href: siteUrl + localizedPath("zh", path) },
        { hreflang: "en", href: siteUrl + localizedPath("en", path) },
        { hreflang: "x-default", href: siteUrl + localizedPath("zh", path) },
      ]
        .map((a) => `    <xhtml:link rel="alternate" hreflang="${a.hreflang}" href="${a.href}"/>`)
        .join("\n");
      return `  <url>\n    <loc>${siteUrl + localizedPath(lang, path)}</loc>\n${alternates}\n  </url>`;
    }),
  );
  const body = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls.join("\n")}\n</urlset>\n`;
  return new Response(body, { headers: { "Content-Type": "application/xml; charset=utf-8" } });
};
