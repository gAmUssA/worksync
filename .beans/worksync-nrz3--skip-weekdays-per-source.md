---
# worksync-nrz3
title: skip_weekdays (per source)
status: draft
type: feature
created_at: 2026-08-14T02:44:14Z
updated_at: 2026-08-14T02:44:14Z
parent: worksync-xli7
---

From the jbaruch/google-calendar-sync review: they skip weekends unconditionally. Blockers on days nobody schedules against are pure noise.

Sketch:
- [ ] skip_weekdays = ["sat", "sun"] parsed to a Set<Int> of Calendar weekday components
- [ ] Filter inside the eligible closure, using the Calendar that desiredBlocks already receives (no new timezone machinery)
- [ ] MUST run before coalescing, or a Friday-night + Saturday-morning pair merges into one cluster whose single start day decides for both. Placing it in eligible gets this for free.
- [ ] Decide and DOCUMENT the rule for events spanning a boundary: their version tests startTime only, so Fri 22:00 -> Sat 01:00 is kept while Sat 23:00 -> Sun is dropped. Either commit to 'start day' or require the whole interval to fall on skipped days.
- [ ] Tests incl. the boundary-spanning case and the coalescing-order case

DRAFT: needs your call on the spanning-event rule.
