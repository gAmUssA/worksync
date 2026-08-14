---
# worksync-4dgw
title: Health indicator in the menu bar
status: todo
type: epic
priority: normal
created_at: 2026-08-14T03:40:03Z
updated_at: 2026-08-14T03:40:03Z
parent: worksync-ikky
blocked_by:
    - worksync-q43e
---

Surface the doctor findings in the menu bar so a broken setup is visible without running anything.

## Icon semantics — one indicator, three states
The icon answers "is WorkSync OK?", so health and sync outcome merge rather than competing for the same pixel:
- [ ] Normal glyph: no doctor errors and the last pass succeeded
- [ ] Warning treatment: doctor warnings only. Deliberately NOT red — this matches the exit-code decision that warnings never fail, and a red icon that turns out to be cosmetic is how users learn to ignore the icon
- [ ] Error treatment: any doctor ERROR, or the last pass failed. Sticky until resolved
- [ ] Paused keeps its own state and outranks health — a paused app is not broken

## When the checks run
They must be fast and local (no network, no calendar scan), which is what makes a cadence affordable:
- [ ] On launch
- [ ] After each sync pass — a pass that just failed on permissions should update the icon immediately
- [ ] On panel open, so opening it never shows a stale verdict
- [ ] NOT on a tight timer: nothing here changes second to second

## Panel
- [ ] Health row at the top: "All checks passed" / "N warnings" / "N problems"
- [ ] Failing checks expand to title + remediation text — the same strings the CLI prints, not a second set that drifts
- [ ] Findings with a destination get a button: Open System Settings (calendar access, notifications, Login Items), Open config, Open log
- [ ] A "Run diagnostics" affordance for an on-demand re-check

## Note on one check
"Something is actually running" reads differently from inside the menu bar app, which is by definition running. It is still worth evaluating: the app can be running while the login item is unregistered, so nothing starts after the next reboot. Phrase it for that case rather than reusing the CLI wording verbatim.
