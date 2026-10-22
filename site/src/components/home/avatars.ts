import type { AvatarName } from "../../data/home";

/** Hand-drawn avatar scenes for the mock chat window. Gradient ids get a per-use suffix so ids stay unique. */
const scenes: Record<AvatarName, string> = {
  me: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#FAD0A6"/><path d="M8 40c1.5-7 6-10 12-10s10.5 3 12 10z" fill="#2F5BFF"/><circle cx="20" cy="18" r="7.5" fill="#F3C6A0"/><path d="M12.3 17c0-5.5 3.6-8.8 8-8.8 4.8 0 8 3.2 7.6 8.6-1.4-2.7-4-4-7.4-4.2-3 .2-5.8 1.7-8.2 4.4z" fill="#2A2522"/></svg>`,
  person2: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#F7DDE6"/><path d="M8 40c1.5-7 6-10 12-10s10.5 3 12 10z" fill="#E88AA6"/><path d="M11 26c-1-9 3-16 9-16s10 6 9 16c-2-1-3-3-3-6H14c0 3-1 5-3 6z" fill="#3A2B2B"/><circle cx="20" cy="19" r="6.8" fill="#F2C9A8"/><path d="M13.5 17.5c1-4 3.7-6 6.5-6s5.5 2 6.5 6c-2.5-1.7-4.8-2.4-6.5-2.4s-4 .7-6.5 2.4z" fill="#3A2B2B"/></svg>`,
  hills: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#FFB78F"/><circle cx="26" cy="16" r="6" fill="#FFF2D6"/><path d="M0 30c8-8 14-8 22-2s12 4 18-2v14H0z" fill="#E7735D"/><path d="M0 34c10-5 18-5 26 0s10 3 14 1v5H0z" fill="#B6503F"/></svg>`,
  sea: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#D4ECFF"/><circle cx="13" cy="15" r="5" fill="#FFFFFF"/><rect y="24" width="40" height="16" fill="#3D8FD8"/><path d="M0 27c4-2 6-2 10 0s6 2 10 0 6-2 10 0 6 2 10 0" stroke="#A9D6FF" stroke-width="1.6" fill="none"/><path d="M0 33c4-2 6-2 10 0s6 2 10 0 6-2 10 0 6 2 10 0" stroke="#7FBDF2" stroke-width="1.4" fill="none"/></svg>`,
  peak: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#B5CDEE"/><path d="M-2 40L16 13l9 12 4-5 13 20z" fill="#4C6F9E"/><path d="M16 13l-4.2 6.3 2.4-.8 1.8 1.6 1.6-1.8 2.3 1.4z" fill="#FFFFFF"/><path d="M-2 40l12-10 8 4 8-6 18 12z" fill="#2E4A72"/></svg>`,
  leaf: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#DDF0D2"/><path d="M8 33C8 18 17 8 33 7c0 16-9 26-25 26z" fill="#4E9A5B"/><path d="M8 33C15 25 21 19 29 11" stroke="#CBEAC0" stroke-width="1.6" fill="none"/><path d="M14 27l-1-6M18 23l-1-6M22 19l-.5-5M15 27l6 .5M19 23l6 .3M23 19l5 .2" stroke="#CBEAC0" stroke-width="1.1"/></svg>`,
  flower: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#FFF0D4"/><g transform="translate(20 18)"><g fill="#F6B73C">${[0, 45, 90, 135, 180, 225, 270, 315].map((a) => `<ellipse rx="3.6" ry="7.5" transform="rotate(${a}) translate(0 -7)"/>`).join("")}</g><circle r="5" fill="#8A5A2B"/></g><path d="M20 26v12" stroke="#5E9B4E" stroke-width="2"/></svg>`,
  cat: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#E8E0F7"/><path d="M10 34c0-9 4.5-15 10-15s10 6 10 15z" fill="#4A4458"/><path d="M12.5 22l1-9 5 5h3l5-5 1 9c0 5-3.5 8-7.5 8s-7.5-3-7.5-8z" fill="#5A536B"/><circle cx="17" cy="22" r="1.3" fill="#F3E58A"/><circle cx="23" cy="22" r="1.3" fill="#F3E58A"/><path d="M19.2 25h1.6l-.8 1z" fill="#E7A3B5"/></svg>`,
  folder: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#11B465"/><path d="M10 13.5h7l2 2.2h11v12.8H10z" fill="#FFFFFF"/><path d="M17 22h7M21.5 19l3 3-3 3" stroke="#11B465" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  book: `<svg viewBox="0 0 40 40"><rect width="40" height="40" fill="#F9D9D3"/><path d="M8 13.5c4-1.5 8-1 12 1.5v14c-4-2.5-8-3-12-1.5zM32 13.5c-4-1.5-8-1-12 1.5v14c4-2.5 8-3 12-1.5z" fill="#FFFFFF" stroke="#D9796A" stroke-width="1.4" stroke-linejoin="round"/></svg>`,
};

export function avatar(name: AvatarName): string {
  return scenes[name];
}
