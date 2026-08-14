---
# worksync-uldt
title: Per-source target calendars + routing
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T03:01:10Z
parent: worksync-xli7
blocked_by:
    - worksync-xr29
---

SPEC §4.1/§4.2. Per-source target calendars:
- [x] target_calendar routing (empty = [target].calendar); fetch managed events across ALL target calendars in window
- [x] Never auto-create calendars — error + instruct user (Exchange may restrict creation)
- [x] Per-source title templates ({date}, {weekday} only; privacy-safe)
- [x] Update path handles target-calendar change for an existing key


## Summary of Changes
Routing was already resolved per source in M1 (Resolver.targetCalendars); M3 wired it through the multi-source planner and verified live: iCloud/Family -> Work and Google/Family -> Home in one pass, 11 blocks split correctly, second pass zero writes.
