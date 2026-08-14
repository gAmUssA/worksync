---
# worksync-ud6v
title: 'M2: Reconciliation writes, markers, purge'
status: in-progress
type: milestone
priority: normal
created_at: 2026-08-14T00:33:15Z
updated_at: 2026-08-14T02:28:40Z
blocked_by:
    - worksync-dopp
---

SPEC §14 M2. Full reconciliation writes, marker scheme, purge, single-source operation end to end.

## Acceptance
- [ ] Running sync twice in a row with no source changes performs zero writes (SPEC §15)
- [ ] Deleting or moving a personal event is reflected on the work calendar within one sync interval
- [ ] Marking a source event "Free" removes its blocker on the next pass; busy again restores it
- [ ] `purge` removes every worksync-managed event and nothing else, including strays on no-longer-targeted calendars
- [ ] Never deletes anything lacking a valid v1 marker (structurally enforced)
