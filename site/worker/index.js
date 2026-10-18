// Cloudflare Worker for lerroapp.com: host and legacy-route redirects in front
// of the static Astro build in dist/.

const legacyRoutes = new Map([
  ["/zh", "/"],
  ["/zh/", "/"],
  ["/zh/changelog", "/changelog"],
  ["/zh/changelog/", "/changelog"],
]);

export default {
  /**
   * @param {Request} request
   * @param {{ ASSETS: { fetch(request: Request): Promise<Response> } }} env
   */
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname === "www.lerroapp.com") {
      url.protocol = "https:";
      url.hostname = "lerroapp.com";
      return Response.redirect(url.toString(), 308);
    }

    const target = legacyRoutes.get(url.pathname);
    if (target) {
      url.pathname = target;
      return Response.redirect(url.toString(), 301);
    }

    return env.ASSETS.fetch(request);
  },
};
