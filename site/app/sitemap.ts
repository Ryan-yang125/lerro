import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: "https://lerroapp.com/",
      lastModified: new Date("2026-08-04T00:00:00.000Z"),
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: "https://lerroapp.com/changelog",
      lastModified: new Date("2026-08-04T00:00:00.000Z"),
      changeFrequency: "weekly",
      priority: 0.8,
    },
  ];
}
