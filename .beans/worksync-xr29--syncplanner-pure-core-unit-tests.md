---
# worksync-xr29
title: SyncPlanner pure core + unit tests
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T00:54:03Z
parent: worksync-1838
blocked_by:
    - worksync-yacc
---

SPEC §5/§6/§13. Pure SyncPlanner in WorkSyncCore (desired + existing -> create/update/delete/skip plan), no calendar store:
- [ ] Step-3 filters: declined attendee, source availability == free, all-day gate, min duration
- [ ] Padding, within-source coalescing (gap ≤ coalesce_gap_minutes), never across sources
- [ ] Window restriction by FILTERING only — never truncate/clamp interval bounds (rolling-window convergence invariant)
- [ ] Reconciliation diff keyed by marker key; update-in-place preference; delete only marked events (structurally: existing set pre-restricted to valid v1 markers)
- [ ] Unit tests: interval math incl. padding/coalescing/window edge, plan diff, "two passes = zero writes" convergence


## Summary of Changes
Implemented and covered by the 41-test suite (all green). See Sources/WorkSyncCore, Sources/WorkSyncKit, Sources/worksync.
