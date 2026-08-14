---
# worksync-m0b3
title: 'Status item: icon states + menu'
status: todo
type: feature
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T00:35:51Z
parent: worksync-kxg1
blocked_by:
    - worksync-ccaa
---

SPEC §11. Status item + menu:
- [ ] Template-image icon states: idle/ok, syncing (animated/badged), error (persists until success), paused (dimmed)
- [ ] Menu: last-sync header (shared pass-summary string), per-source counts, Sync now (disabled while running), Pause/Resume, Launch at login, Preferences… (stub until M6), Open config (validate + NSAlert on error), Open log, Quit
- [ ] Config re-read at start of every pass (edits apply without restart)
