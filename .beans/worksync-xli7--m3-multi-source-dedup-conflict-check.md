---
# worksync-xli7
title: 'M3: Multi-source, dedup, conflict check'
status: todo
type: milestone
priority: normal
created_at: 2026-08-14T00:33:15Z
updated_at: 2026-08-14T00:33:43Z
blocked_by:
    - worksync-ud6v
---

SPEC §14 M3. Multi-source with per-source target calendars, cross-source dedup, conflict check.

## Acceptance
- [ ] Two configured sources (busy + travel) produce correctly titled blockers on two different work calendars (SPEC §15)
- [ ] Recoloring in Calendar.app persists across syncs (tool never touches calendar color)
- [ ] Moving a single detached occurrence of a recurring event reconciles as one update, not delete+create
- [ ] Within-source recurring series: all occurrences survive dedup (regression-tested)
- [ ] skip_if_work_busy uses union-overlap ≥ 80%, correct for double-booked work calendars
