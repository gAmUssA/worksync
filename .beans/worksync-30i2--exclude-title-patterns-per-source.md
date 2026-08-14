---
# worksync-30i2
title: exclude_title_patterns (per source)
status: draft
type: feature
created_at: 2026-08-14T03:10:50Z
updated_at: 2026-08-14T03:10:50Z
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
