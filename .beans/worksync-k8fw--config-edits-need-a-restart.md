---
# worksync-k8fw
title: 'Interval and log level changes need a restart'
status: todo
type: bug
created_at: 2026-09-12T14:30:56Z
updated_at: 2026-09-12T14:30:56Z
---

Found by the SPEC divergence audit (2026-09-12).

SPEC §11 says config edits apply "on the next sync without a restart", and that
the timer fires every current `interval_minutes`.

`StatusItemController.startScheduler` reads `model.intervalMinutes` **once**
into a repeating Timer, and nothing recreates it on save. `MenuBarModel` builds
its `Logger` once with the initial `log_level`.

Sync *planning* does reload config, so filters, padding, calendars and the rest
do apply on the next pass — the SPEC claim is true for those. It is false for
the two things that are read at construction: cadence and app log filtering.

A user who changes `interval_minutes` from 60 to 5 and waits will conclude the
setting does nothing.

[ ] Recreate the timer when `interval_minutes` changes
[ ] Re-apply `log_level` to the logger on save
[ ] Or state the restart requirement in the settings UI, and in an ADR
