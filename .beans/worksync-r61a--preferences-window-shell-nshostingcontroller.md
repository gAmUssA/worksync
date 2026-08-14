---
# worksync-r61a
title: Settings as a panel screen (not a window)
status: todo
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T02:25:52Z
parent: worksync-o7n2
blocked_by:
    - worksync-ccaa
---

SPEC §11.1 / §3.1 rule 5. Preferences window shell:
- [ ] NSHostingController in plain NSWindow; styleMask MUST include .fullSizeContentView (root cause of dead sidebar toggle)
- [ ] NSApp.activate(ignoringOtherApps:true) + makeKeyAndOrderFront; .regular/.accessory flip fallback if fronting is unreliable
- [ ] Sidebar (General + per-source rows) + detail form; collapse via bound NavigationSplitViewVisibility; custom toggle fallback if system button misbehaves — verify against running app
- [ ] Refuses to open when config.toml does not parse; points at "Open config"


## Design change (2026-08-14) — supersedes the separate-NSWindow plan
SPEC §11.1: settings is a screen INSIDE the panel via a screen enum + 44pt back bar. This deletes the NSApp.activate fronting dance, the activation-policy flipping, and the NavigationSplitView-in-plain-NSWindow sidebar defect entirely.
- [ ] screen enum (.dashboard/.settings/.source(id)) on a layout store
- [ ] Screen transitions use pure .offset — never a .transition carrying .opacity (transparency layer leaves .quaternary with no vibrant backdrop -> white flash across cards; no clean SwiftUI fix)
- [ ] Panel auto-fits content height with an animated morph (simplified version acceptable for v1)
- [ ] HARD RULE: config.toml owns anything with headless meaning; UserDefaults owns pure view state only; nothing in both
