# macOS permissions

Lerro requests permissions when an onboarding task or feature needs them and shows
their current state in Onboarding and Settings. The signed bundle identity is
`app.lerro.mac`; macOS binds privacy decisions to this identity and code signature.

## Permission matrix

| Permission | Product use | Framework | Behavior when unavailable |
| --- | --- | --- | --- |
| Microphone | Capture speech for Dictate and Translate, run the onboarding microphone test | AVFoundation | Capture stays blocked and Lerro provides the System Settings route |
| Accessibility | Global shortcut filtering, bounded target context, strict delivery, failure protection, and same-field correction observation | ApplicationServices / CGEventTap | Capture/delivery requiring that boundary fails closed; correction observation ends quietly |

Usage descriptions live in [`config/Info.plist`](../config/Info.plist), entitlements
in [`config/Lerro.entitlements`](../config/Lerro.entitlements), and permission checks
in [`MacPermissionService.swift`](../Sources/LerroMac/System/MacPermissionService.swift).

Apple Speech authorization and language-resource readiness are checked as part of
the Apple Dictate preparation task. Language assets are managed by macOS.

## Identity and consent

Entitlements declare capabilities and usage descriptions explain them. The user
grants each TCC permission in macOS. Release candidates keep a stable app path,
Bundle ID, and Apple signing identity before real-device validation.

Lerro applies safety checks at two points:

1. Capture start records the target application, focused element, complete value,
   selection, and secure-input state. Secure input prevents recording.
2. Immediately before Command-V, strict delivery requires the current application,
   element, value, selection, and secure-input state to match the captured fingerprint.

A focus or value change stops delivery. The final text is copied to the clipboard and
the HUD shows a recovery card with **Copy again** and **Close**.

After a successful AI-processed Dictate, Accessibility can observe that same app and
input element for up to 60 seconds. It reads the current value locally, waits 800 ms
for stable changes, and emits only the smallest diff that intersects the uniquely
located delivered text. New capture, timeout, app/field change, secure input,
unsupported editor, unavailable AX value, or revoked permission ends observation.

## Onboarding permission tasks

The user must:

1. confirm the chosen history and audio policy;
2. grant Microphone and Speech authorization;
3. prepare the selected Speech language resource;
4. complete the microphone level test;
5. grant Accessibility before recording and testing the global shortcut;
6. complete a real Dictate write and a simulated failure-recovery copy.

The page advances from detected success state. Permission copy alone cannot complete
the task.

## Manual verification

Use the final Release app and synthetic text:

1. Start from an undetermined state; verify explanation, system prompt, and blocked state.
2. Grant access; complete the intended onboarding task and a real capture.
3. Revoke access; verify state refresh, active capture cancellation, event-tap stop,
   failed delivery protection, and quiet observer termination.
4. Grant access again, relaunch from the stable app path, and verify recovery.

The Accessibility matrix includes physical Fn/Control/Option/Shift/Command press and
release, configured chords, hold/toggle, matched-key swallowing, Escape cancellation,
event-tap timeout recovery, and duplicate suppression. Delivery validation covers
TextEdit, Notes, browser/ChatGPT, an Electron editor, focus switching, text edits,
selection changes, secure fields, and multi-item pasteboard restoration.

The global event tap starts when Accessibility is available. A foreground permission
refresh cancels active capture before stopping the tap, so a hidden hold release
cannot leave the microphone running.

TCC resets are optional diagnostics. Run them only with explicit approval and scope
them to `app.lerro.mac` and the single affected service.
