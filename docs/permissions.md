# macOS permissions

Lerro requests permissions at the moment a feature needs them and shows the
current state in onboarding and Settings. The final signed bundle identity is
`app.lerro.mac`; macOS associates privacy decisions with that identity and its
code signature.

## Permission matrix

| Permission | Product use | Requested by | Behavior when unavailable |
| --- | --- | --- | --- |
| Microphone | Capture speech after a user starts Dictate, Translate, Ask, Rewrite, or Hands-free | AVFoundation | Capture remains unavailable and the app presents the relevant System Settings route |
| Accessibility | Read limited focused-element context, deliver text, and run the active shortcut filter | ApplicationServices / CGEventTap | Context, direct delivery, and shortcut swallowing fail closed; the answer can remain available for explicit user action |

Usage descriptions live in [`config/Info.plist`](../config/Info.plist).
Entitlements live in [`config/Lerro.entitlements`](../config/Lerro.entitlements).
Permission checks and prompts are implemented in
[`MacPermissionService.swift`](../Sources/LerroMac/System/MacPermissionService.swift).

## Identity and consent

Entitlements declare capabilities and usage descriptions explain them. The user
still grants each TCC permission in macOS. A new Bundle ID or signing identity
can create a new permission record, so release candidates use a stable path,
Bundle ID, and Apple signing identity before the real-device matrix begins.

Lerro applies privacy checks according to the delivery mode:

1. Before recording, to avoid capturing while a secure input field is focused.
2. Before selection-aware Rewrite delivery, to confirm the original process or
   bundle, current secure-input state, focused element, and unchanged selection.

Ordinary Dictate and Translate insertion follows the keyboard focus present when
Command-V is committed. A focus change during model processing changes the final
destination.

## Manual verification

Use the final Release app and synthetic text. For every permission:

1. Start from an undetermined state and verify the explanation and system prompt.
2. Grant access and verify the intended feature.
3. Revoke access in System Settings and verify the app refreshes to a blocked
   state, cancels an active capture, and stops the global event tap.
4. Grant access again, relaunch from the stable app path, and verify recovery.

The Accessibility matrix includes physical Fn/Control/Option/Shift/Command
press and release, configured chords, hold and toggle modes, swallowed matched
keys, Escape cancellation, event-tap timeout recovery, and duplicate event
suppression. Accessibility validation includes TextEdit plus representative
third-party editors, focus switching, non-empty selections, secure fields, and
clipboard restoration with multiple item types.

The global event tap starts when Accessibility is available. A foreground
permission refresh cancels an active capture before
stopping the tap, so a hidden hold release cannot leave the microphone running.

TCC resets are optional diagnostic operations. Run them only with explicit user
approval and scope them to `app.lerro.mac` and the single affected service.
