---
# worksync-hw8o
title: Reconciliation writes (apply plan)
status: in-progress
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T02:28:51Z
parent: worksync-ud6v
blocked_by:
    - worksync-h8ng
    - worksync-6ubu
    - worksync-xr29
---

SPEC §6/§9. Reconciliation apply through CalendarStore:
- [ ] Create / update-in-place / delete from the SyncPlanner plan (update preferred over delete+create — Exchange notification noise)
- [ ] Hard invariant: deletes only reach events with valid v1 markers (unrepresentable otherwise)
- [ ] Single EKEventStore.commit() batch where possible; on partial failure continue and exit 3
- [ ] Summary line + last-run record (display state only, never planner input)
- [ ] Fake-store integration tests: end-to-end plan+apply; convergence (second pass = zero writes)
