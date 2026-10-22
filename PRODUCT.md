# Product

## Register

brand

## Users

Lerro is for Apple silicon Mac users on macOS 26 who write throughout the day
and want speech to become correct, editable text at the active cursor. Many mix
Chinese and English in one sentence. They value speed, native macOS behavior,
transparent permissions, and paying only for the AI they use through their own
DeepSeek account.

## Product purpose

Lerro turns speech into text in any Mac app by the shortest path from voice to
cursor. A user presses a shortcut, speaks, presses it again, and keeps writing.
There is no account, subscription, or hosted Lerro service.

- Apple `SpeechTranscriber` transcribes live, with the microphone opening first.
- Optional AI cleanup through the user's own DeepSeek API key
  fixes misheard words, polishes, and translates, using a personal dictionary and
  per-app tone.
- Delivery goes to the exact target field through the clipboard and Command-V.
  If the target changed, the text stays on the clipboard with a Copy again card.
- Corrections the user makes after a write can become dictionary entries.
- Lerro has no analytics or telemetry. The network is used for Apple's Speech
  language assets, the user's own AI endpoint, and signed update checks.

Lerro is open source (Apache-2.0) and in maintenance mode.

## Brand personality

Native, decisive, private. The voice is concise and specific, like a well-made Mac
utility. Claims state exactly which paths stay local and when the network is used.

## Anti-references

- Generic AI landing pages built from repeated equal cards, gradients, and vague
  promises.
- Absolute privacy or offline claims that hide Apple resource downloads, update
  checks, or the user's DeepSeek traffic.
- Decorative effects that compete with the real application screenshots.

## Design principles

- Show the shipped Mac app and its real states.
- Lead with the voice-to-cursor outcome.
- Make local, optional-network, and bring-your-own-key boundaries clear.
- Keep each page compact and useful for a download decision.
- Keep one product story across the website, README, metadata, screenshots, and
  release notes. Product claims match [`PRIVACY.md`](PRIVACY.md).

## Accessibility

Target WCAG 2.2 AA on the website: keyboard navigation, visible focus, semantic
landmarks, sufficient contrast, layouts from 320 px, image descriptions, and
reduced-motion alternatives. Screenshots use synthetic content.
