---
# worksync-8za6
title: Cross-source dedup on (externalId, occurrenceDate)
status: in-progress
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T02:56:36Z
parent: worksync-xli7
blocked_by:
    - worksync-xr29
---

SPEC §5 step 5. Cross-source dedup:
- [ ] Identity tuple (calendarItemExternalIdentifier, occurrenceDate); first-listed source wins
- [ ] Only filter-passing events claim identity (a filtered-out event must not block a later source)
- [ ] Handle calendarItems(withExternalIdentifier:) returning multiple matches
- [ ] Regression tests: within-source recurring series (all occurrences survive); detached occurrence moved (same key -> update); genuine cross-source duplicate (first source wins)
