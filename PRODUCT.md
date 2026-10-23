# Product

## Register

brand

## Users

Lerro is for everyday office workers on an Apple silicon Mac with macOS 26 who
type all day: replying in WeChat, Feishu or DingTalk, writing email to a manager,
putting together a weekly report in Notes or Word. They are not developers and
should not need to learn any settings. Many mix Chinese and English in one
sentence and use names and terms specific to their company. They want it free,
quick to set up, and private, and they pay a few yuan a month for AI cleanup
through their own DeepSeek account only if they turn it on.

## Product purpose

Lerro turns speech into text in any Mac app by the shortest path from voice to
cursor. A user presses a shortcut, speaks, presses it again, and keeps writing.
There is no account, subscription, or hosted Lerro service.

- Apple `SpeechTranscriber` transcribes live, with the microphone opening first.
- Optional AI cleanup through the user's own DeepSeek account removes filler
  words, fixes misheard words, adds punctuation and paragraphs, keeps only the
  final meaning when the user corrects themselves, translates Chinese to English,
  and follows a per-app tone. Names and terms the AI corrects twice are remembered
  automatically.
- Delivery goes to the exact target field through the clipboard and Command-V.
  If the target changed, the text stays on the clipboard with a Copy again card.
- Lerro has no analytics or telemetry. The network is used for Apple's Speech
  language assets, the user's own DeepSeek account, and signed update checks.

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
- Lead with the voice-to-cursor outcome in everyday work: WeChat, email, weekly
  reports.
- Make local, optional-network, and own-DeepSeek-account boundaries clear.
- Keep each page compact and useful for a download decision.
- Keep one product story across the website, README, metadata, screenshots, and
  release notes. The website copy in
  [`site/src/data/home.ts`](site/src/data/home.ts) is the reference wording;
  product claims match [`PRIVACY.md`](PRIVACY.md).

## Accessibility

Target WCAG 2.2 AA on the website: keyboard navigation, visible focus, semantic
landmarks, sufficient contrast, layouts from 320 px, image descriptions, and
reduced-motion alternatives. Screenshots use synthetic content.
