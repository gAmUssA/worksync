---
# worksync-hw8o
title: Reconciliation writes (apply plan)
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T02:36:10Z
parent: worksync-ud6v
blocked_by:
    - worksync-h8ng
    - worksync-6ubu
    - worksync-xr29
---

SPEC §6/§9. Reconciliation apply through CalendarStore:
- [x] Create / update-in-place / delete from the SyncPlanner plan (update preferred over delete+create — Exchange notification noise)
- [x] Hard invariant: deletes only reach events with valid v1 markers (unrepresentable otherwise)
- [x] Single EKEventStore.commit() batch where possible; on partial failure continue and exit 3
- [x] Summary line + last-run record (display state only, never planner input)
- [x] Fake-store integration tests: end-to-end plan+apply; convergence (second pass = zero writes)


## Summary of Changes
CalendarStore write ops (staged + single commit), SyncEngine.apply with per-write failure collection, marker written to notes AND url, store-layer marker re-verification before delete. Verified live on iCloud: create 6 -> 0-write second pass -> 6 in-place updates -> 6 deletes -> clean.
