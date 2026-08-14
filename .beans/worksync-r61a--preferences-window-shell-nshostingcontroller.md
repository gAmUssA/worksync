---
# worksync-r61a
title: Preferences window shell (NSHostingController)
status: todo
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T00:36:15Z
parent: worksync-o7n2
blocked_by:
    - worksync-ccaa
---

SPEC §11.1 / §3.1 rule 5. Preferences window shell:
- [ ] NSHostingController in plain NSWindow; styleMask MUST include .fullSizeContentView (root cause of dead sidebar toggle)
- [ ] NSApp.activate(ignoringOtherApps:true) + makeKeyAndOrderFront; .regular/.accessory flip fallback if fronting is unreliable
- [ ] Sidebar (General + per-source rows) + detail form; collapse via bound NavigationSplitViewVisibility; custom toggle fallback if system button misbehaves — verify against running app
- [ ] Refuses to open when config.toml does not parse; points at "Open config"
