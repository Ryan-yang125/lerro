<p align="center">
  <img src="site/public/lerro-logo.svg" width="160" alt="Lerro">
</p>

<h1 align="center">Speak it. It's written.</h1>

<p align="center">
  English · <a href="README.md">简体中文</a>
</p>

<p align="center">
  Press a shortcut and talk, press it again, and the text lands at your cursor.<br>
  Mix Chinese and English freely, and proper nouns come out right.
</p>

<p align="center">
  <a href="https://updates.lerroapp.com/download/macos/latest"><strong>Download for macOS</strong></a>
  · <a href="https://lerroapp.com/en">Website</a>
  · <a href="https://lerroapp.com/en/changelog">Changelog</a>
</p>

<p align="center">
  Free and open source · macOS 26 · Apple silicon
</p>

![Lerro dictating into a chat window](site/public/readme/en-demo.png)

## How it works

1. Press your shortcut (Fn by default) and speak. A small capsule at the bottom
   of the screen shows the live transcript.
2. Press the shortcut again. Lerro writes the text into the field you were
   typing in.
3. If you switched away before it finished, Lerro stops, keeps the text on the
   clipboard, and offers to paste it.

Apple's on-device speech recognition does the listening. With AI cleanup turned
on, DeepSeek fixes misheard words using your dictionary, removes fillers, and
adds punctuation.

![Raw recognition compared with what Lerro wrote](site/public/readme/en-accuracy.png)

## A dictionary that learns

Names of people, companies, and projects are hard to recognize the first time.
When you correct a word Lerro wrote, the AI decides whether it was a
recognition error and adds it to the dictionary.

![Auto-learned dictionary](site/public/readme/en-dictionary.png)

Each app can also have its own tone, for example casual in chat and complete
sentences in email.

## AI cleanup with your own DeepSeek account

Lerro has no subscription. AI cleanup supports only
[DeepSeek](https://platform.deepseek.com) and uses your own account. The app
walks you through three steps: open the site, top up, then create a key and
paste it. Once connected, Lerro shows your account balance. At a hundred or so
dictations a day, it costs about ¥2 a month.

Without AI cleanup, Lerro still works: Apple recognition runs on your Mac for
free and the transcript is written as is.

## Privacy

- No account and no telemetry.
- Speech is recognized on your Mac. With AI cleanup on, only the recognized text
  goes to DeepSeek.
- Recordings are not saved unless you turn it on.

Details are in the [Privacy Policy](PRIVACY.md).

## Install

1. [Download the latest signed and notarized build](https://updates.lerroapp.com/download/macos/latest).
2. Move **Lerro.app** to Applications and open it.
3. Follow the setup to grant Microphone and Accessibility.

Requires an Apple silicon Mac with macOS 26 or later. Lerro updates itself
from inside the app.

## Build from source

See [Development](docs/development.md) for building, testing and releasing,
[Architecture](docs/architecture.md) for how the app is put together, and
[Contributing](CONTRIBUTING.md).

## License

Lerro is open source under [Apache-2.0](LICENSE). First-party documentation and
images use [CC BY 4.0](LICENSES/CC-BY-4.0.txt). See [TRADEMARKS.md](TRADEMARKS.md),
[NOTICE](NOTICE), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
