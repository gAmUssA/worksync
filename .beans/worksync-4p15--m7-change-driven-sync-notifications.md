---
# worksync-4p15
title: 'M7: Change-driven sync + notifications'
status: todo
type: milestone
priority: normal
created_at: 2026-08-14T00:33:15Z
updated_at: 2026-08-14T00:33:43Z
blocked_by:
    - worksync-5lsv
---

SPEC §14 M7. Change-driven sync and desktop notifications (SPEC §11.2). Both menu bar-only, config-gated, additive to the timer.

## Acceptance
- [ ] With notify = "always", a completed pass posts a native notification banner; with "errors", only failures do (SPEC §15)
- [ ] Lock-skipped passes post nothing
- [ ] change_driven fast path triggers a debounced pass on EKEventStoreChanged; own-write echo suppressed (5s window)
- [ ] Timer + wake pass remain fully functional when the notification never fires (degrades to polling silently)
