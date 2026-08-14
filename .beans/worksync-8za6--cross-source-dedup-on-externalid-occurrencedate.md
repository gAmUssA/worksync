---
# worksync-8za6
title: Cross-source dedup on (externalId, occurrenceDate)
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T03:01:10Z
parent: worksync-xli7
blocked_by:
    - worksync-xr29
---

SPEC §5 step 5. Cross-source dedup:
- [x] Identity tuple (calendarItemExternalIdentifier, occurrenceDate); first-listed source wins
- [x] Only filter-passing events claim identity (a filtered-out event must not block a later source)
- [x] Handle calendarItems(withExternalIdentifier:) returning multiple matches
- [x] Regression tests: within-source recurring series (all occurrences survive); detached occurrence moved (same key -> update); genuine cross-source duplicate (first source wins)


## Summary of Changes
SyncPlanner.desiredAcrossSources resolves duplicates in config order on the (externalIdentifier, occurrenceDate) tuple, after per-source eligibility so a filtered-out event never claims an identity. Verified live twice: two sources on one calendar (6 dropped from the second) and a genuine cross-backend duplicate between the iCloud and Google Family calendars.
