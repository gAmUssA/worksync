# ADR-0003 — A blocker's title cannot contain the source event's title, by signature

Status: accepted
Date: 2026-09-12

## Context

The product exists so colleagues see that time is taken without seeing why.
Copying a source event's title, location, attendees, or notes onto the work
calendar would be the whole failure. Convention ("don't assign `event.title`")
is the kind of rule a later change forgets.

## Decision

`SyncPlanner.renderTitle(_:eventStart:calendar:)`
(`Sources/WorkSyncCore/Planner.swift`) takes a template, a start date, and a
calendar. It has no `StoredEvent` and no title string. The only substitutions
are `{date}` and `{weekday}`. Every `DesiredBlock.title` is that rendered
string. `EventKitStore.write` copies `block.title` onto the work event.

`title_matches` / `title_excludes` (`SyncPlanner.matchesTitleFilters`) read the
source title as a Boolean eligibility gate and then discard it. They do not
feed `renderTitle`.

## Consequences

- The privacy invariant is structural. Adding a `{title}` placeholder requires
  changing the function signature and every call site; it cannot happen by
  accident in a template string.
- Users who want the real title on the work calendar cannot have it. That is
  the product, not an unfinished feature.
- Title filters still *read* private titles in process. They must never be
  logged, written into notes, or interpolated into `title_template`.
- Dry-run and error strings that print `block.title` print the template, not
  the source title. That has to stay true.
