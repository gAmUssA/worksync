---
# worksync-kss0
title: General + per-source forms with resolver popups
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T04:39:43Z
parent: worksync-o7n2
blocked_by:
    - worksync-r61a
    - worksync-7uh2
    - worksync-c69a
---

SPEC §11.1. Forms:
- [x] General/target: window_days, interval_minutes, log_level, notify, change_driven, target account/calendar (timezone not exposed)
- [x] Resolver-backed popups for every account/calendar field, fed by the worksync calendars enumeration (a popup cannot typo)
- [x] Per-source form: every source field incl. toggles and minute knobs
- [x] Save through the shared config writer only — no UI-only write path


## Note
Forms now live in the panel's settings screen, not a window (SPEC §11.1).


## Summary of Changes
Resolver-backed account/calendar popups from the live enumeration; target picker offers writable calendars only. A saved value that no longer resolves stays listed as '(not found)' so opening settings cannot silently rewrite config. General and per-source forms cover the documented fields.
