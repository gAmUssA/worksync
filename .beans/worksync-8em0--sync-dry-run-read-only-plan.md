---
# worksync-8em0
title: sync --dry-run (read-only plan)
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T01:49:25Z
parent: worksync-1838
blocked_by:
    - worksync-xr29
    - worksync-c69a
    - worksync-pg25
---

SPEC §5 step 9 / §14 M1. `worksync sync --dry-run`: run the full pipeline read-only and print the plan without mutating.
- [ ] Wire config -> resolution -> fetch -> planner -> printed plan
- [ ] Summary line format: created=N updated=N deleted=N skipped=N unchanged=N
- [ ] Exit codes 0/1/2 correct in dry-run mode


## Summary of Changes
Verified live against real calendars: fetched 9 events from iCloud Family, expanded recurrences, applied filters, printed 6 CREATEs + summary line, exit 0, zero mutations. Missing/invalid config exits 1; non-dry-run apply correctly refuses until M2.
