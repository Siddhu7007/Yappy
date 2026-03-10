# Fn Recovery Notes

## Status

As of March 10, 2026, Yappy **kind of works** for the text-field click flow, but this is still a fragile workaround rather than a finished solution.

The current behavior is:

- Yappy can survive more text-field clicks and focus changes than before
- Yappy can often recover even when the normal `Fn` event stream goes bad
- The implementation still needs refinement, especially around permission stability and long-running reliability

## Original Symptom

The failure mode looked like this:

1. Yappy worked right after launch.
2. Clicking into a text box caused the head/mouth motion to stop.
3. Sometimes Wispr Flow still worked, but Yappy stopped moving.
4. In later runs, clicking into a text box and then pressing `Fn` again did nothing at all.

## What We Initially Got Wrong

We spent too much time treating this like an audio-engine problem.

That was partly true in some cases, but the first-order problem was usually higher in the stack:

- the hotkey session was getting torn down by a false `Fn` release
- or the next `Fn` press after a click was never observed

So the mouth stopped moving because speech monitoring had stopped, or never started again.

## What The Logs Showed

The useful pattern in the logs was:

- `event tap flagsChanged ... secondaryFn=false`
- `published hotkey event=released`
- `received hotkey released`
- `SpeechMonitor stopped`

Later, after some fixes, another pattern appeared:

- pointer-down events were still being observed
- but no new live `Fn` press callback arrived after the click
- the app only recovered if a fallback poll noticed that `Fn` was down

That meant the event stream itself was unreliable after focus changes, especially while Input Monitoring was still not clean for the debug app.

## Fixes That Actually Helped

### 1. Stop trusting event-tap `Fn` release immediately

`Fn` releases from the event tap are now treated as provisional instead of authoritative.

Why:

- click and focus changes were producing bad `Fn up` observations
- immediately publishing those releases killed the active Yappy session too early

### 2. Record pointer-down and app-activation changes

We added interaction monitoring for:

- global/local mouse down
- active application changes

This made it possible to recognize when the failure was happening around text-field focus changes.

### 3. Add hotkey release grace

Yappy no longer tears down the speech session immediately on release.

It now keeps the session alive briefly when:

- speech is still active
- speech was active very recently
- a recovery flow is in flight

That helped with short click/focus gaps.

### 4. Add post-click `Fn` state polling

After a click, Yappy now polls the system `Fn` state for a short window.

Why this helped:

- sometimes the event tap never delivered the next `Fn` press
- but the system flags still showed that `Fn` was down

That was the first fix that made the “click text box, then press `Fn`, then speak” flow start working again.

### 5. Add continuous fallback `Fn` polling

The short post-click window was not enough.

In real logs, Yappy sometimes worked once, then the live `Fn` stream degraded again later. After that, the app could miss later `Fn` presses unless the user happened to be inside a recent click window.

So Yappy now also runs a low-frequency background poll of current `Fn` state as a fallback.

This is the main reason it works more reliably now.

## Current Implementation Shape

The hotkey path is now a layered fallback system:

1. HID callbacks when available
2. Event tap callbacks when available
3. Short post-click polling window
4. Continuous low-frequency fallback polling

This is not ideal, but it is much more robust than relying on one hotkey source.

## Why It Still Needs Refinement

The current solution is still heuristic-heavy.

Known weaknesses:

- The debug build still logs `Input Monitoring preflight missing`, which means macOS is not treating the app as fully stable from a permissions perspective.
- Continuous polling is a workaround, not a clean primary architecture.
- The release-grace timings and polling intervals are tuned heuristically, not yet validated across many apps.
- We still do not know whether some target apps are making the event stream worse through focus behavior or other OS-level input edge cases.

## What To Refine Next

### Permissions and signing

- Test with a stable signed build, not only Xcode “Sign to Run Locally”
- Clean up Input Monitoring for the exact built app path
- Decide whether Yappy should fail closed more aggressively when Input Monitoring is not really stable

### Hotkey architecture

- Split `HotkeyMonitor` into smaller pieces if the logic keeps growing
- Separate “signal collection” from “truth resolution” more explicitly
- Consider making one source authoritative only when it has proven healthy during the current hold

### Recovery tuning

- Revisit polling intervals for responsiveness vs cost
- Revisit release grace timing so the app feels less sticky
- Verify behavior across multiple target apps, not just one text field flow

### Logging

- Keep the current debug trace lines
- Continue using `/tmp/yappy-debug.log` as the main field-debugging artifact
- Preserve the distinction between:
  - real live callback observed
  - fallback poll observed `Fn`
  - session stopped because of confirmed release

## Important Files

- `Yappy/Supporting/HotkeyMonitor.swift`
- `Yappy/App/AppCoordinator.swift`
- `Yappy/Supporting/InteractionMonitor.swift`
- `Yappy/Supporting/SpeechActivityMonitor.swift`
- `YappyTests/HotkeyMonitorTests.swift`
- `YappyTests/AppCoordinatorTests.swift`

## Bottom Line

The main lesson is:

This was not primarily a microphone bug. It was a hotkey-state reliability bug that showed up during text-field focus changes.

The current version works by assuming macOS may stop giving reliable live `Fn` callbacks after focus changes, and by adding enough fallback state checks to keep Yappy alive anyway.

That is good enough for now, but it is still a workaround-heavy implementation that should be tightened up later.
