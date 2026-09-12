# ADR-0003 — Render blocker titles from templates without source-event metadata

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
calendar. It receives no `StoredEvent` or separate source-title argument.
The only substitutions are `{date}` and `{weekday}`. The planner calls it with
`source.titleTemplate` and uses the result for each `DesiredBlock.title` it
produces. `EventKitStore.write` copies `block.title` onto the work event.

`title_matches` / `title_excludes` (`SyncPlanner.matchesTitleFilters`) read the
source title as a Boolean eligibility gate and then discard it. They do not
feed `renderTitle`.

## Consequences

- A `{title}` string in the configured template does not interpolate the source
  title. The current dataflow keeps source metadata out of rendering, but the
  signature alone is not a type-level guarantee: a caller could pass a private
  title as the template string without changing it. Review must preserve both
  the supported substitutions and the origin of the template argument.
- Users who want the real title on the work calendar cannot have it. That is
  the product, not an unfinished feature.
- Title filters still *read* private titles in process. They must never be
  logged, written into notes, or interpolated into `title_template`.
- Dry-run and error strings that print `block.title` print the template, not
  the source title. That has to stay true.
