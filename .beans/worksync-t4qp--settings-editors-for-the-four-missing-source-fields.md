---
# worksync-t4qp
title: 'Settings UI: editors for the four missing source fields'
status: todo
type: feature
created_at: 2026-09-11T23:55:00Z
updated_at: 2026-09-11T23:55:00Z
---

`SettingsView.sourceDetail` has no control for four per-source fields. They are
config-file-only, and SPEC §11.1 claimed the form covered every source field
until worksync-w2k7 corrected the line.

Found by Copilot reviewing the title-filter editors, and it predates that work:
`target_calendar`, `max_duration_minutes` and `skip_weekdays` were already
missing before the filters landed. `coalesce_gap_minutes` was missing too and
went unnamed in that review.

[ ] `target_calendar` — a calendar popup like `[target]`'s, plus an "inherit the
    target calendar" state for the empty default. Resolver-backed, never free
    text (§11.1: a typo hard-errors the whole sync)
[ ] `coalesce_gap_minutes` — a stepper, and it only means anything while
    `coalesce` is on
[ ] `max_duration_minutes` — a stepper. `0` is "unlimited", not zero minutes, and
    `validate` rejects a non-zero value below `min_duration_minutes`, so the
    control has to express both
[ ] `skip_weekdays` — seven toggles or a segmented picker. `validate` rejects all
    seven (skipping every day mirrors nothing), so the UI should refuse the
    seventh rather than let the save fail
[ ] Update SPEC §11.1 as each one lands; restore the "every source field" wording
    only when the list is empty

## Related
- worksync-w2k7 — the title-filter list editors, and the SPEC correction
