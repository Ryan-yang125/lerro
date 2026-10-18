import { defineConfig } from "astro/config";

// Static pages served by the Cloudflare Worker in worker/index.js.
// "file" output (changelog.html, en.html) keeps URLs without trailing slashes.
export default defineConfig({
  site: "https://lerroapp.com",
  trailingSlash: "never",
  build: { format: "file" },
});
