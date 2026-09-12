# ADR-0001 — Record architecture decisions in ADRs, not in SPEC.md

Status: accepted
Date: 2026-09-12

## Context

`SPEC.md` was written before the implementation, to start the project. It is a
detailed document and it did its job.

But it has been serving two incompatible purposes: describing what the software
should be, and describing what the software is. Those diverged.

Two concrete instances, both found by reviewers rather than by us:

- §11.1 stated the per-source settings form "covers every source field" and
  listed `target_calendar` by name. Four fields had no control at all
  (`target_calendar`, `coalesce_gap_minutes`, `max_duration_minutes`,
  `skip_weekdays`). The claim had been false for some time.
- After that line was corrected, a later change restored the original wording,
  re-asserting the same false claim for four fields.

The failure mode is structural rather than careless. A document that is edited
to track the code will drift whenever an edit is missed, and nothing detects the
drift. Worse, it records only the current state — never why the state is what it
is. The most valuable thing about a decision is the reasoning and the rejected
alternatives, and `SPEC.md` has nowhere to put those.

## Decision

Architecture decisions are recorded as ADRs under `docs/adr/`, written after the
decision is made, and never retroactively edited to match new reality. A changed
decision gets a new ADR that supersedes the old one; the old one stays.

`SPEC.md` is kept as the original design intent and as a description of the
domain. It stops being treated as the authority on what the code does. Where the
two disagree, the code and its ADRs win, and the disagreement is a signal that a
decision was made and not recorded.

## Consequences

- A reader asking "why is it like this" has somewhere to look, including for
  decisions that were deliberately *not* taken.
- ADRs cannot silently rot the way a maintained spec does: an accepted ADR is a
  historical record, so being out of date is a normal, visible state rather than
  a defect.
- It costs discipline. An unrecorded decision is invisible, and nothing enforces
  writing one. The mitigation is that ADRs are cheap and short.
- `SPEC.md` keeps some false statements about current behaviour. That is
  tolerable once it is no longer the authority, but the ones already found
  should still be corrected rather than left as traps.
- Existing decisions are unrecorded. Backfilling every one is not worth it;
  backfilling the ones that are load-bearing, surprising, or expensive to
  rediscover is.
