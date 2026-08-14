---
# worksync-ryz6
title: Visual system + Liquid Glass fallbacks
status: todo
type: task
priority: normal
created_at: 2026-08-14T02:25:52Z
updated_at: 2026-08-14T02:26:08Z
parent: worksync-kxg1
blocked_by:
    - worksync-m0b3
---

SPEC §11 visual system, adapted from openusage (MIT).
- [ ] ~320pt panel width, 14pt outer padding, 12pt card radius, 44pt top bar
- [ ] Cards: NSColor.textBackgroundColor + .fill.quaternary (System Settings grouped-box look); no hand-tuned hex
- [ ] Status colors from the system palette so light/dark + accessibility track automatically
- [ ] Liquid Glass on chrome ONLY (footer/nav), standard materials in content — Apple's own guidance
- [ ] EVERY #available(macOS 26) check in ONE file of paired helpers (glassButtonStyle/barGlass/pinnedFooter); no view contains an availability branch
- [ ] Dark mode as app-level NSApp.appearance override + pinned on the panel (it ignores preferredColorScheme; the menu bar's appearance otherwise wins)
- [ ] TimelineView(.periodic) for the 'synced Nm ago' line; ticks only while visible
- [ ] Motion constants centralized + reduce-motion environment key
