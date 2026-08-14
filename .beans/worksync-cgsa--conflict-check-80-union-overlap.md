---
# worksync-cgsa
title: 'Conflict check: 80% union overlap'
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T03:01:10Z
parent: worksync-xli7
blocked_by:
    - worksync-xr29
---

SPEC §5 step 7. skip_if_work_busy conflict check:
- [x] Overlap = UNION of non-managed busy intervals clipped to block bounds, zero-gap merged, summed / block duration; threshold ≥ 80%
- [x] Uses the step-6 fetch (no second round trip)
- [x] Skipped blocks excluded from desired set (newly conflicted -> normal delete path)
- [x] Unit tests incl. double-booked case where naive summing would wrongly skip


## Summary of Changes
SyncPlanner.applyConflictSkips drops blocks covered >=80% by real work events, measured as the union of clipped busy intervals. Our own blockers (any marker version) and declined/Free work events are excluded from the busy set. Reuses the step-6 fetch. Verified live: 6 blocks with the flag off, 4 skipped with it on.
