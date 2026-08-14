---
# worksync-cgsa
title: 'Conflict check: 80% union overlap'
status: todo
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T00:36:15Z
parent: worksync-xli7
blocked_by:
    - worksync-xr29
---

SPEC §5 step 7. skip_if_work_busy conflict check:
- [ ] Overlap = UNION of non-managed busy intervals clipped to block bounds, zero-gap merged, summed / block duration; threshold ≥ 80%
- [ ] Uses the step-6 fetch (no second round trip)
- [ ] Skipped blocks excluded from desired set (newly conflicted -> normal delete path)
- [ ] Unit tests incl. double-booked case where naive summing would wrongly skip
