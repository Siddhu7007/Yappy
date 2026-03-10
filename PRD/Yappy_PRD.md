# Yappy — Product Requirements Document

**Type:** Open-source macOS companion app  
**Distribution:** GitHub (`github.com/[yourhandle]/yappy`) + GitHub Releases (free)  
**Stack:** Swift + SwiftUI + AppKit  
**macOS requirement:** macOS 13 Ventura or later  
**Status:** Pre-build / Planning  

---

## 1. The Idea in One Sentence

Yappy is an open-source desktop pet for voice dictation — a floating animated character that reacts while you speak, turning a utilitarian voice bar into something alive.

---

## 2. Problem

Wispr Flow is technically excellent. Its UI is not interesting.

The Flow Bar is a thin band at the bottom of the screen. It acknowledges that you're speaking, then disappears. There is no personality, no visual reward, and nothing to share or customize.

Meanwhile, an entire culture of "vibe coders," indie hackers, and creative developers has formed around aesthetic-first tooling — custom Raycast themes, Zed color schemes, custom cursors, desktop wallpaper workflows. These users want their environment to feel like theirs.

Dictation is one of the most frequent micro-interactions in a power user's day. There's no reason it should look like a loading bar.

**The gap:** There is no open-source, community-extensible visual skin layer for any dictation tool on macOS.

---

## 3. Why Now

Three things are converging:

1. **AI dictation is going mainstream.** As tools like Wispr become daily workflows for devs and founders, the surface area for a companion skin grows fast.
2. **Desktop pets are having a revival.** Pixel companions (tamagotchi, live2D, virtual pets) are trending on Twitter and TikTok. The cultural appetite already exists.
3. **Open-source app aesthetics are hot.** Projects like Raycast, Linear, and Fig built cult audiences partly through design quality. A beautiful open-source character project gets shared.

---

## 4. Target Users

### Primary
- macOS Wispr Flow users (initial focus)
- Indie builders, vibe coders, devs who care about their environment
- People who'd put a pixel art companion on their desktop

### Secondary
- Artists who want to design and publish character skins
- Developers building branded tools (agency, SaaS, AI assistant) who want a custom dictation visual
- Open-source contributors looking for a fun, low-barrier project

---

## 5. Product Vision

Yappy should feel like:

> "A living mascot that reacts while I talk."

Not a widget. Not a plugin. A **character** — something with personality, expressiveness, and community lore. Think: a pixel frog sitting in the corner of your screen, jaw bouncing as you dictate. Idle animations when you're not speaking. A quick celebration after a long paste. Something you'd screenshot and post.

The goal is for people to say: *"This is Bonzi Buddy for dictation."* That sentence appearing on the internet will be a success signal.

---

## 6. What Yappy Is Not

- **Not** a dictation engine. Wispr (or any other tool) handles all transcription.
- **Not** an integration with Wispr's internals. Yappy only mirrors hotkey state.
- **Not** affiliated with Wispr. Explicit disclaimer required everywhere.
- **Not** intercepting, logging, or reading transcription text — ever.
- **Not** a plugin. It's a standalone app that runs alongside your dictation tool.

---

## 7. Core User Flow

```
User holds dictation hotkey
    → Yappy enters LISTENING mode (character perks up, anticipation bounce)
    → [Wispr starts recording]
    → Yappy enters SPEAKING mode (mouth animates, character bobs)
    → [Wispr processes + pastes text]
User releases hotkey
    → Yappy enters FINISHING mode (quick celebration / settle)
    → Returns to IDLE (subtle float, occasional blink)
```

This is the entire v1 experience. Nothing else matters until this loop is delightful.

---

## 8. Compatibility

Yappy works with **any dictation tool that uses a held hotkey**, including:

- Wispr Flow (primary target)
- macOS built-in Dictation
- Superwhisper
- Any other push-to-talk voice tool

No integration is required. Yappy only listens for the hotkey the user configures. This makes it inherently tool-agnostic.

---

## 9. v1 Scope

### A. Floating overlay window
Always-on-top, non-focus-stealing, transparent background. Defaults to bottom-center of screen. User can drag to reposition; position persists between launches. Hidden from Cmd+Tab and the Dock — it lives in the background like a widget.

### B. Hotkey-linked state machine
User configures the same hotkey in Yappy as in their dictation tool. Yappy watches only for keydown/keyup events on that key. No dictation content access required.

| State | Trigger | Visual |
|---|---|---|
| `idle` | Default | Gentle float, blink every 4–8s |
| `listening` | Hotkey down | Anticipation bounce, mild glow |
| `speaking` | 300ms after hotkey down | Mouth opens/closes, body bobs |
| `finishing` | Hotkey up | Settle + quick pulse |
| `disabled` | User toggle | Character fades to 30% opacity |
| `error` | Permission issue | Red outline, frowning expression |

### C. Animated character rig (two-piece mouth)
PNG-layer-based rig. Each skin is a folder of flat images animated entirely in code:

- `base.png` — full character minus moving mouth parts
- `mouth_top.png` — hinged from upper edge, rotates up during speaking
- `mouth_bottom.png` — hinged from lower edge, rotates down during speaking
- `blink.png` (optional) — overlay that replaces eyes on blink frame
- `shadow.png` (optional) — drop shadow for depth
- Additional decorative layers as defined in manifest

All animation (translation, rotation, scale, opacity) is code-driven. No sprite sheets. No video. No GIFs.

### D. Skin pack format

```
MySkin/
  manifest.json       ← metadata + animation params
  base.png
  mouth_top.png
  mouth_bottom.png
  blink.png
  shadow.png
  preview.png         ← shown in skin picker
```

`manifest.json`:

```json
{
  "name": "Default Puppet",
  "author": "yourhandle",
  "version": "1.0.0",
  "preview": "preview.png",
  "layers": {
    "base": { "file": "base.png", "anchor": [0.5, 0.5] },
    "mouth_top": { "file": "mouth_top.png", "anchor": [0.5, 1.0], "pivot": "bottom-center" },
    "mouth_bottom": { "file": "mouth_bottom.png", "anchor": [0.5, 0.0], "pivot": "top-center" }
  },
  "animation": {
    "idle_bob_amplitude": 4,
    "idle_bob_duration": 2.0,
    "blink_interval_min": 3.0,
    "blink_interval_max": 8.0,
    "mouth_open_max_degrees": 20,
    "speaking_bob_amplitude": 6
  }
}
```

**The bar for skin creation: 3 PNGs + 1 JSON = a working skin. No code required.**

### E. Settings panel (SwiftUI)
- Active skin picker with preview thumbnail
- Hotkey configuration (with "match your Wispr hotkey" recommendation)
- Avatar size (S / M / L)
- Overlay position reset
- Launch at login toggle
- Reduced motion toggle
- "Show only during dictation" toggle (hides character during idle)

### F. Onboarding (3 screens)
1. **Hotkey** — "What key do you hold to dictate?" + live animation test
2. **Skin** — pick from included skins with preview
3. **Permissions** — plain-English explanation of Input Monitoring + why it's needed

### G. Default skin: "Yappy"
The namesake character. Two-piece puppet mouth, bold cartoon aesthetic. Full idle bob, blink, glow ring on listening, jaw animation on speaking, bounce on finish. This skin needs to be genuinely shareable — it's the primary marketing asset.

---

## 10. Out of Scope for v1

- Phoneme-accurate lip sync
- Audio waveform or microphone level reading
- Transcript text access of any kind
- Hands-free lock mode
- In-app skin marketplace or community browser
- Windows or Linux support
- Animated GIF / video layer skins
- Multiple simultaneous characters
- iCloud or cloud sync for skins
- Custom AI assistant features

---

## 11. Technical Approach

### Stack
- **Swift 5.9+** — all logic
- **AppKit** (`NSPanel`) — overlay window management
- **SwiftUI** — settings and onboarding windows
- **Core Animation** (`CALayer` tree) — GPU-composited character rig, zero dependencies
- **CGEventTap** — global hotkey detection (requires Input Monitoring permission)

### Overlay window
```swift
let panel = NSPanel(
    contentRect: .zero,
    styleMask: [.nonactivatingPanel, .borderless],
    backing: .buffered,
    defer: false
)
panel.level = .floating
panel.isOpaque = false
panel.backgroundColor = .clear
panel.ignoresMouseEvents = false  // allow drag to reposition
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

### Animation engine
`CALayer` transforms driven by `CABasicAnimation` and `CAKeyframeAnimation`. All parameters sourced from `manifest.json` at skin-load time. No recompilation needed to support new skins.

### Integration model
Yappy uses **hotkey mirroring only**:
- Watch for keydown/keyup on user-configured key
- Drive the state machine from those events
- Zero IPC, zero Wispr API, zero Wispr internals
- Works even if Wispr changes its internals or hotkey system

### Implementation note
During real-world debugging on March 10, 2026, the biggest failure mode around clicking into text fields was **not** the speech engine first. The overlay stopped moving because the hotkey session was being torn down, or the next `Fn` press was missed entirely after focus changed. For `Fn`-based dictation, Yappy should treat event-tap releases as provisional, prefer HID or current system flag state when available, and keep a short post-click fallback poll so a missed `Fn` callback does not prevent speech monitoring from starting.

### Permissions

| Permission | Required | Why |
|---|---|---|
| Input Monitoring | Yes | Detect global hotkey when Yappy is not frontmost |
| Accessibility | No (v1) | Only needed for deeper AXObserver-based state detection in future |

### Error handling
If Input Monitoring is denied, Yappy shows the `error` state and directs the user to System Settings. It never silently fails.

---

## 12. Open-Source Repo Structure

```
yappy/
  App/              ← Entry point, AppDelegate, app lifecycle
  Overlay/          ← NSPanel overlay, positioning, drag logic
  Animation/        ← CALayer rig, state machine, animation engine
  SkinEngine/       ← Manifest parsing, layer loading, skin switching
  Settings/         ← SwiftUI preferences window
  Onboarding/       ← SwiftUI onboarding flow
  Assets/           ← App icon, default resources
  ExampleSkins/
    Yappy/          ← Default skin (the namesake character)
    PixelPal/       ← Pixel art skin (community starter template)
  Docs/
    SKIN_SPEC.md    ← Full guide to creating skin packs
    CONTRIBUTING.md
    PERMISSIONS.md  ← Why permissions are needed, plain English
  README.md
  LICENSE
```

**License:** MIT — maximum adoption, zero friction for skin creators.

**Community contribution paths:**
- New skin packs (no Swift knowledge required)
- Animation presets
- Alternative hotkey detection implementations
- Accessibility and reduced motion improvements
- macOS version compatibility fixes

**Distribution:**
- GitHub Releases with signed `.dmg`
- Release notes include demo GIF each version
- `brew install --cask yappy` targeted for M4

---

## 13. Positioning & Messaging

**One-liner:** Yappy is an open-source animated desktop pet that reacts while you dictate.

**Taglines to test:**
- "Your voice deserves a face."
- "A mascot for your mouth."
- "The desktop pet for people who talk to their computer."

**README must-haves:**
1. Demo GIF at the top — before any text
2. "Works with Wispr, Superwhisper, macOS Dictation, and anything else"
3. "Not affiliated with Wispr Flow"
4. Setup in under 2 minutes
5. "Make a skin with 3 PNGs and a JSON file"
6. Zero telemetry, zero tracking, open source

---

## 14. Go-to-Market

1. **Character first.** The default Yappy skin needs to be genuinely shareable. Ship nothing until it looks good enough to screenshot.
2. **Demo GIF in README.** 10–15 seconds of the character reacting during real dictation. Perfect loop. This is the primary acquisition asset.
3. **Post on launch day:** r/macapps, r/productivity, Hacker News Show HN, X/Twitter with the GIF.
4. **SKIN_SPEC.md on day one.** Get artists making skins before the app trends. Community skins = sustained word of mouth.
5. **Product Hunt launch** 2 weeks after GitHub organic seeding.
6. **Reach out to Wispr's community.** Their subreddit, Discord, or Twitter replies — these are already your users.

---

## 15. Milestones

### M1 — Prototype
- Floating overlay window renders on screen
- One hardcoded character visible and positioned correctly
- Manual state switching works (keyboard shortcut in debug)
- Idle → Listening → Speaking → Finishing → Idle loop functional
- No settings panel required yet

### M2 — Alpha
- Skin pack format fully working (manifest.json parsing, layer loading)
- Default Yappy skin with complete animation
- Configurable hotkey
- SwiftUI settings panel
- Onboarding flow (3 screens)
- Drag-to-reposition working + position persists

### M3 — Public Launch
- Second built-in skin (PixelPal — pixel art style)
- Signed `.dmg` on GitHub Releases
- README with demo GIF
- SKIN_SPEC.md, CONTRIBUTING.md, PERMISSIONS.md all written
- "Not affiliated with Wispr" disclaimer visible in app and README

### M4 — Community Phase
- Homebrew cask (`brew install --cask yappy`)
- Reduced motion full support
- Launch at login
- GitHub Wiki for community skin gallery (no in-app complexity)
- State smoothing improvements
- macOS 14 Sonoma / 15 Sequoia compatibility verified

---

## 16. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Wispr changes its hotkey system | Integration is hotkey-only, no Wispr API. Change = user reconfigures one field. |
| Permission friction kills onboarding | Plain-English explainer screen, short GIF, minimal permission scope. |
| Users expect transcript awareness | Messaging clear from day one: Yappy is a visual layer only. |
| Trademark / affiliation confusion with Wispr | "Not affiliated with Wispr" in README header, app About screen, and any press. |
| Skin spec too complex for artists | Hard ceiling: 3 PNGs + 1 JSON = working skin. Validate this with a non-developer before launch. |
| Name conflict (Yappy exists in other industries) | Conflicts are in unrelated categories (payments, pet products). For an open-source macOS dev tool, this is acceptable. |

---

## 17. Success Metrics

### 30 days post-launch targets
- 200+ GitHub stars
- 500+ `.dmg` downloads
- 3+ community skin packs submitted via PR
- Demo GIF shared on social 50+ times

### Qualitative signals
- People post screenshots of their character mid-dictation
- Artists reach out wanting to make skins
- Someone writes "this is Bonzi Buddy for dictation" somewhere on the internet

---

## 18. One-Page Summary

Yappy is a free, open-source macOS app that sits alongside your dictation tool and shows an animated character while you speak. It watches for the hotkey you configure — the same one you use in Wispr or any other tool — and drives a simple state machine: idle, listening, speaking, done. The character is rendered as a layer-based PNG rig animated in code via Core Animation. It reads no transcription text, touches no dictation internals, and requires only Input Monitoring permission to function. Skin packs are folders: 3 PNGs + a JSON config file, no code. The default character is a bold cartoon puppet with a two-piece mouth. The secondary direction is pixel art desktop pet. Distribution is free via GitHub Releases. The community hook is skin creation — Yappy ships a full SKIN_SPEC.md on launch day so artists can contribute without touching Swift.
