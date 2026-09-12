---
# worksync-p3wk
title: 'Settings filter rows: seal the positional fallback, label each row'
status: todo
type: chore
created_at: 2026-09-12T01:44:31Z
updated_at: 2026-09-12T01:44:31Z
---

Two advisories from the independent review of PR #7 round 4. Neither gates that
PR; both are real.

## 1. The positional fallback is the original bug, waiting

Filter rows carry a UUID minted when the form opens. A list rendered **unseeded**
falls back to positional ids — which is exactly the defect round 4 fixed: a late
commit after a deletion writes to the wrong row, silently, because the range
check passes.

The reviewer traced the call graph at `f9c5213` and could not reach
"unseeded with entries" through any current route — seeding happens on
`openSettings` and on every append, and is idempotent. So it is not a live
defect.

The hazard is future: a caller that writes `titleMatches` / `titleExcludes`
without `seed`/`appended` silently gets positional ids and the wrong-row write
back. The fallback reads as a safety net but only protects `ForEach` keys, not
the defect.

[ ] Make the fallback loud rather than silent — a debug-only assert when a list
      has entries but no seeded ids, so a missed seed fails in development
      instead of corrupting a user's list in production
[ ] Or remove the fallback and require seeding, if no legitimate unseeded case
      exists

## 2. Row text fields all announce the same label

`+` and `−` are distinct and accurate after round 4. The row `TextField`s
gained a list-level label where they previously had none — but **every row in a
list announces the same string**, so VoiceOver cannot tell which entry is
focused.

[ ] Include the entry (or its position) in each row field's accessibility label

## Related
- PR #7, round 4 (row identity by UUID)
- `worksync-v8xr` — the source-level version of the same identity question
