# Yappy

Yappy is an open-source macOS companion app for held-hotkey dictation. It shows a floating animated character that reacts to real microphone activity while you speak.

- Built with Swift, SwiftUI, and AppKit
- Works alongside push-to-talk dictation tools like Wispr Flow
- Uses live mic level for movement, not transcript access

## Current Fix Note

The biggest text-field click bug was not primarily a speech-engine failure. The session was being torn down, or the next `Fn` press was being missed after focus changed.

The fix path now does three things:

- treats event-tap `Fn` releases as provisional instead of immediately authoritative
- records pointer-down activity so click-adjacent releases can be confirmed more carefully
- briefly polls current system `Fn` state after a click so a missed post-click `Fn` press can still start dictation

This keeps Yappy from losing the speaking/listening session just because focus changed into a text box.

## Permissions

Yappy needs:

- `Input Monitoring` to detect the global dictation hotkey reliably
- `Microphone` to drive head and mouth motion from live voice input

## Product Note

See [PRD/Yappy_PRD.md](PRD/Yappy_PRD.md) for the full product requirements document.
