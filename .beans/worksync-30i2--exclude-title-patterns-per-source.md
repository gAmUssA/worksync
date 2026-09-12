---
# worksync-30i2
title: exclude_title_patterns (per source)
status: completed
type: feature
created_at: 2026-08-14T03:10:50Z
updated_at: 2026-09-12T03:37:22Z
---

Exclude events from mirroring by matching their title — e.g. keep "Vacation" or "OOO" out of the work calendar entirely.

## Why this does NOT break the privacy invariant
Reading a source event's title locally to decide whether to mirror it is fine: the title is used as a predicate and never written anywhere. The invariant is that source titles never reach the WORK calendar (SPEC §4.1: titles come from {date}/{weekday} templates only), and this feature does not touch that. Worth stating in the spec, because at a glance it looks like a violation.

## Sketch
- [ ] exclude_title_patterns: [String] on SourceConfig, empty = exclude nothing
- [ ] Filter in the step-3 eligibility pass, so an excluded event never claims a dedup identity — meaning a later source WITHOUT the exclusion can still mirror it, which is the correct and useful behavior
- [ ] Tests: case-insensitivity, no-match, multiple patterns, interaction with dedup (excluded by source A, mirrored by source B)

## Decision needed: matching semantics
1. Case-insensitive SUBSTRING (recommended) — predictable, no invalid-input class, covers the vacation/OOO case
2. Full regex — more powerful, but an invalid pattern becomes a config error and a subtly wrong pattern silently drops real busy time
3. Substring by default, regex opt-in via a separate key or /slash/ syntax

Recommend 1 for v1. Silently dropping busy time is the dangerous failure direction here, so the matching rule should be the one users can predict without testing.

## Related
Complements min/max_duration_minutes and skip_weekdays, which landed in the same filter pass.

## Shipped

Implemented in PR #1 (`feat/source-title-filter`) with the recommended
semantics: option 1, case-insensitive substring, filtered in the step-3
eligibility pass.

Two divergences from this sketch, both deliberate:

- The key is `title_excludes`, not `exclude_title_patterns` — shorter, and it
  pairs with its opposite.
- A second key `title_matches` ships alongside it: an allow-list, for the case
  that motivated the work (mirror only the "Personal Commitment" holds another
  sync tool writes onto a work calendar, not that calendar's real meetings).
  `title_excludes` is applied second, so an event hitting both lists is dropped.

Matching is also diacritic-insensitive, which this sketch did not specify.
A blank entry is rejected as a config error rather than accepted as a no-op,
since `""` matches every title and would silently disable the filter.

SPEC §4.1 now states the privacy reasoning this bean asked for.

## Closed — 2026-09-12

Shipped in v0.3.0 (PR #1) as `title_matches` / `title_excludes`, and given a
Settings UI in v0.4.0 (PR #7).
