---
# worksync-ryz6
title: Visual system + Liquid Glass fallbacks
status: completed
type: task
priority: normal
created_at: 2026-08-14T02:25:52Z
updated_at: 2026-08-14T03:30:45Z
parent: worksync-kxg1
blocked_by:
    - worksync-m0b3
---

SPEC §11 visual system, adapted from openusage (MIT).
- [x] ~320pt panel width, 14pt outer padding, 12pt card radius, 44pt top bar
- [x] Cards: NSColor.textBackgroundColor + .fill.quaternary (System Settings grouped-box look); no hand-tuned hex
- [x] Status colors from the system palette so light/dark + accessibility track automatically
- [x] Liquid Glass on chrome ONLY (footer/nav), standard materials in content — Apple's own guidance
- [x] EVERY #available(macOS 26) check in ONE file of paired helpers (glassButtonStyle/barGlass/pinnedFooter); no view contains an availability branch
- [x] Dark mode as app-level NSApp.appearance override + pinned on the panel (it ignores preferredColorScheme; the menu bar's appearance otherwise wins)
- [x] TimelineView(.periodic) for the 'synced Nm ago' line; ticks only while visible
- [x] Motion constants centralized + reduce-motion environment key


## Summary of Changes
320pt panel, 14pt padding, 12pt cards from NSColor.textBackgroundColor + .quaternary, system palette for status colors, glass confined to the footer chrome, and every #available(macOS 26) check in one file of paired helpers (barGlass/glassButton) so no view carries an availability branch. TimelineView keeps the 'synced Nm ago' line ticking only while visible.
