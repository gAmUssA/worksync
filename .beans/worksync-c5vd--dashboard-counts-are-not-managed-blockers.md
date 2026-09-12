---
# worksync-c5vd
title: 'The dashboard counts fetched source events, not managed blockers'
status: todo
type: bug
created_at: 2026-09-12T14:30:33Z
updated_at: 2026-09-12T14:30:33Z
---

Found by the SPEC divergence audit (2026-09-12).

SPEC §11 says each source row shows "the count of managed blocks currently on
its target calendar, and its target calendar", with per-source trouble details.

`MenuBarModel.refreshRunCounts` assigns `sourceCounts = diagnostics.fetchedBySource`
— raw **source** events fetched, before filtering, coalescing and window
trimming. `PanelView.content` renders the source id and "… events", and shows
neither the target calendar nor unidentifiable/conflict diagnostics.

So the number a user sees is not the number of blockers WorkSync created, and
will differ whenever a filter, a duration bound, `skip_weekdays`, coalescing or
`skip_if_work_busy` does anything at all — which is the normal case.

This is more misleading than a missing number: it looks authoritative.

[ ] Count managed blockers on the target, or relabel the number for what it is
[ ] Show the target calendar per source, or drop the SPEC claim
[ ] Surface the per-source diagnostics that are already computed
