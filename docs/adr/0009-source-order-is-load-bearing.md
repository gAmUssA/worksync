# ADR-0009 — Source order is load-bearing

Status: accepted
Date: 2026-09-12

## Context

The same occurrence can appear on more than one source calendar (a personal
copy of a work meeting, a flight on both travel and personal). Only one
blocker should be written. Something has to win.

## Decision

Config order is the rule. `SyncPlanner.desiredAcrossSources`
(`Sources/WorkSyncCore/MultiSource.swift`) walks `inputs` as listed, runs
eligibility first, then inserts `EventIdentity` into a claimed set. The first
source that would actually mirror the event keeps it; later sources drop it
as a duplicate.

The settings list is therefore a reorderable `List`, and the config writer
must preserve `[[source]]` order exactly — not alphabetize, not sort by id.

## Consequences

- Reordering two sources in config.toml or in Settings is a semantic change:
  padding, title template, target calendar, and filters of a shared event
  all follow the winner. It is not a cosmetic sort.
- A config writer or UI that sorted sources would silently change who
  supplies blockers. `ConfigWriter` rebuilding the source run in `new`'s
  order is load-bearing, not a layout preference.
- Eligibility runs before the claim, so a source that filters an event out
  does not occupy the identity and block a later source from producing it.
