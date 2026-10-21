export type Lang = "zh" | "en";

export const siteUrl = "https://lerroapp.com";
export const githubUrl = "https://github.com/Ryan-yang125/lerro";
export const privacyUrl = `${githubUrl}/blob/main/PRIVACY.md`;
export const downloadUrl = "https://updates.lerroapp.com/download/macos/latest";
export const currentVersion = "1.9.3";

/** Chinese lives at the root; English under /en. `path` is "/" or "/changelog". */
export function localizedPath(lang: Lang, path: "/" | "/changelog" = "/"): string {
  if (lang === "zh") return path;
  return path === "/" ? "/en" : `/en${path}`;
}
