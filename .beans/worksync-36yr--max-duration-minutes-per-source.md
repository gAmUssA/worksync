---
# worksync-36yr
title: max_duration_minutes (per source)
status: completed
type: feature
priority: normal
created_at: 2026-08-14T02:44:14Z
updated_at: 2026-08-14T03:08:36Z
parent: worksync-xli7
---

From the jbaruch/google-calendar-sync review: they drop events over 4 hours as 'probably out-of-office events and such'. We have min_duration_minutes but no upper bound.

Why it matters: an 8-hour timed conference, or a multi-day timed event (SPEC §9 keeps those unsplit), becomes one enormous solid block on the work calendar — worse than useless, because it hides the real meetings underneath it.

Sketch:
- [x] maxDurationMinutes: Int = 0 (0 = unlimited) on SourceConfig, beside minDurationMinutes
- [x] Parse beside min_duration_minutes; validate with checkNonNegative
- [x] Filter in the eligible closure right after the min-duration check, BEFORE padding — so padding cannot push an event past its own limit and make the filter time-dependent
- [x] Existing blockers for now-excluded events converge out through the normal delete path; no special casing
- [x] Tests: boundary (exactly at the limit is kept), 0 means unlimited, interaction with padding

DRAFT: needs your call on the default (0/unlimited is the safe default; 4h matches theirs).


## Summary of Changes
Default 0 (unlimited). Timed events only, measured pre-padding, clusters exempt. Validation rejects max < min. Verified live: a 45-minute maximum dropped all six 60-minute events.
