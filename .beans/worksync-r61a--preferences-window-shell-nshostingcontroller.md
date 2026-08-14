---
# worksync-r61a
title: Settings as a panel screen (not a window)
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T04:39:43Z
parent: worksync-o7n2
blocked_by:
    - worksync-ccaa
---

SPEC §11.1 / §3.1 rule 5. Preferences window shell:
- [x] NSHostingController in plain NSWindow; styleMask MUST include .fullSizeContentView (root cause of dead sidebar toggle)
- [x] NSApp.activate(ignoringOtherApps:true) + makeKeyAndOrderFront; .regular/.accessory flip fallback if fronting is unreliable
- [x] Sidebar (General + per-source rows) + detail form; collapse via bound NavigationSplitViewVisibility; custom toggle fallback if system button misbehaves — verify against running app
- [x] Refuses to open when config.toml does not parse; points at "Open config"


## Design change (2026-08-14) — supersedes the separate-NSWindow plan
SPEC §11.1: settings is a screen INSIDE the panel via a screen enum + 44pt back bar. This deletes the NSApp.activate fronting dance, the activation-policy flipping, and the NavigationSplitView-in-plain-NSWindow sidebar defect entirely.
- [x] screen enum (.dashboard/.settings/.source(id)) on a layout store
- [x] Screen transitions use pure .offset — never a .transition carrying .opacity (transparency layer leaves .quaternary with no vibrant backdrop -> white flash across cards; no clean SwiftUI fix)
- [x] Panel auto-fits content height with an animated morph (simplified version acceptable for v1)
- [x] HARD RULE: config.toml owns anything with headless meaning; UserDefaults owns pure view state only; nothing in both


## Summary of Changes
Screen enum on the model, back bar, pure-offset animation, two fixed per-screen heights with the panel resized top-pinned. Refuses to open on unparseable config.
