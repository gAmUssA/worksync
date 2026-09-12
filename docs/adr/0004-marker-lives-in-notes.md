# ADR-0004 — The marker lives in notes, with the URL as a supplementary copy

Status: accepted
Date: 2026-09-12

## Context

Managed events have to be recognizable later so a sync can update or delete
them and a purge can find them. EventKit exposes a URL field, which is the
obvious place for `worksync://v1/<source_id>/<key>`. Google CalDAV and
Exchange drop that field on round-trip, so a URL-only marker would be
forgotten and the next pass would create a duplicate.

## Decision

The primary copy is the last lines of notes: a fixed header plus the marker
URL (`Marker.notesBlock` in `Sources/WorkSyncCore/Marker.swift`).
`EventKitStore.write` sets `event.notes = block.marker.notesBlock` and also
`event.url = URL(string: block.marker.urlString)` as a supplementary copy.
`Marker.extract(url:notes:)` reads either.

## Consequences

- Notes on a managed event are not a user-editable field. Anything a user (or
  another tool) puts there is overwritten on the next pass. The header line
  exists to say so.
- Source notes, location, and attendees still never copy onto the blocker;
  notes are reserved for the marker.
- A store that kept the URL would still work; a store that drops it still
  finds the event via notes. Removing the notes copy would silently break
  Google and Exchange users.
- `Marker.parse` / `extract` must keep accepting a marker from either
  location, including events whose URL was stripped after we wrote both.
