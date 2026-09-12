---
# worksync-t9r4
title: '{title} placeholder: mirror the original event title'
status: declined
type: feature
created_at: 2026-09-11T21:10:07Z
updated_at: 2026-09-11T21:36:03Z
---

Add a `{title}` placeholder to `title_template`, so a source can put the real
event title on the work calendar instead of a sanitized "Busy".

## This one DOES touch the privacy invariant

Unlike `title_matches` / `title_excludes` (worksync-30i2), which read the title
as a predicate and discard it, this writes it onto the work calendar. That is
the exact thing the tool exists to prevent, stated in the README as enforced in
code rather than by convention, and in SPEC §4.1 ("all privacy-safe ... Never
expose source titles"). Not §7 — §7 is the marker scheme, and matters here only
because notes are the primary marker location and must stay marker-only.

So this is not a small template change. It is a decision to make WorkSync able
to behave like an ordinary calendar sync, and it needs an answer to: what stops
someone enabling it on their therapy calendar by accident?

## Why it is still worth considering

Not every source is private. The motivating case is work-to-work: two employers,
two calendars, and the user wants to see on calendar B *which* meeting is
blocking them on calendar A, not just that something is. Colleagues on B already
cannot see A at all, so nothing leaks to a party who did not already have it.

## Shape, if it happens

- [ ] `{title}` in `title_template`, threaded into `SyncPlanner.renderTitle`,
      which today takes `(template, eventStart, calendar)` and deliberately has
      no access to the event — that signature is the current enforcement
- [ ] Per-source, never global: the source is the unit that knows whether its
      calendar is sensitive
- [ ] Opt-in with a loud name. `title_template = "Busy"` must stay the default
      and `worksync init` must not suggest `{title}`
- [ ] `worksync sync --dry-run` already prints the plan; make it obvious in the
      preview that real titles are about to be written, before the first write
- [ ] Consider a length cap and newline stripping — a pasted agenda in a title
      would render badly and could smuggle content into the blocker
- [ ] Marker identity is unaffected: keys hash externalIdentifier +
      occurrenceDate, not the title. But a title EDIT on the source must produce
      an update, so check that reconcile() diffs title (it does — Planner.swift
      compares the block against the managed event)

## Decision needed before any code

1. Ship it opt-in per source, with the dry-run warning above
2. Ship it only when the source and target are both non-personal, which the tool
   cannot actually determine — so really this means "ship it and trust the user"
3. Decline. Keep the invariant absolute and point work-to-work users at
   `target_calendar` + a distinct calendar colour, which conveys "which source"
   without conveying "what"

Option 3 is the status quo and costs nothing. Option 1 is defensible but changes
what the tool promises, and the README/SPEC would both need rewriting rather
than amending — the privacy claim is currently unconditional.

## Related
- worksync-30i2 — title filters, the read-only sibling; shipped in PR #1
- SPEC §7 (marker and privacy invariant), SPEC §4.1 (title_template vocabulary)

## Research — 2026-09-11

Full findings: `.beans/worksync-t9r4--research.md`

**Recommendation: option 3, decline.** Summary of the argument:

- **Industry split is clean.** Availability mirrors (Clockwise's original hold,
  Fantastical's default, OneCal/CalendarBridge with subject off, Calendrz) never
  put the source title on the work calendar. General sync tools (Reclaim
  full-details, Fantastical with the checkbox on) will, and all of them ask
  first. WorkSync's README puts it in the first camp; `{title}` moves it to the
  second while keeping the first camp's slogan.
- **Per-source opt-in is a waiver, not a safety mechanism.** `title_template` is
  a free-text field in Settings — typing `{title}` is the same gesture as typing
  `Busy`, with no confirm alert (unlike source-id rename, which does warn).
  Dry-run is not on the write path: the login item and a bare `worksync sync`
  both write without preview. And a source id is a slug the user typed, not a
  privacy classification.
- **Blast radius is one pass, not a rollout.** Default `window_days = 21`, so
  the first tick rewrites three weeks of blockers. Titles are visible to anyone
  with limited-details sharing, to delegates and EAs regardless of a Private
  flag, on lock-screen notifications, and in eDiscovery / Purview / Vault.
  Turning it off rewrites the live events but does not un-index what already
  synced.
- **The bean's own justification is wrong.** "Colleagues on B cannot see A, so
  nothing leaks" is true of calendar A and false of the copy on B — the copy is
  a new disclosure to every viewer of B, including people who never had A.
- **Coalescing has no honest answer.** A cluster is one blocker spanning several
  events: stamp the first member's title and you mislabel the rest; concatenate
  and you list every private event in the cluster.
- **`--dry-run` and `SyncEngine` error strings interpolate the block title**, so
  `{title}` would put real titles on the default CLI output path — which SPEC
  already forbids for doctor, precisely because that output gets pasted into bug
  reports.

**Two options the bean missed, both preserving the invariant:**

1. Show the source title **locally only** — a "why am I blocked?" inspector in
   the menubar panel. EventKit already has the title on the Mac. This solves the
   actual motivation without writing anything to the work calendar.
2. `target_calendar` + colour + a prefix template, now combined with the shipped
   `title_matches`. Work-to-work "only block me for the standups" is an
   eligibility problem, not a title-copy problem.

**Decision needed from the owner:** close as declined, or open a bean for the
local inspector instead.

## Decision — 2026-09-11

**Declined.** Owner's call, taking the research recommendation.

`{title}` is not added. The privacy invariant stays absolute, and the README
keeps being able to say "enforced in the code rather than by convention" —
`renderTitle` keeps its `(template, eventStart, calendar)` signature with no
access to the event, which is the enforcement.

Work-to-work users are served by what already exists: `target_calendar` plus a
distinct calendar colour for "which source", `{weekday}` / a prefix for "when",
and `title_matches` for "only these events".

Not reopened without a new argument that answers the coalescing problem and the
dry-run/logging leak path, both of which the research showed have no clean
answer.

If the work-to-work itch returns, the successor is the local-only inspector
(research, missed option 1) — show the source title in the menubar panel, on
device, where no colleague or tenant admin can see it. That would be its own
bean, not this one.
