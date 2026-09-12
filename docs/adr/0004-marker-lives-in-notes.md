# ADR-0004 — The marker lives in notes, with the URL as a supplementary copy

Status: accepted
Date: 2026-09-12

## Context

Managed events have to be recognizable later so a sync can update or delete
them and a purge can find them. EventKit exposes a URL field, which is the
obvious place for `worksync://v1/<source_id>/<key>`. The original design cites
URL loss through Google CalDAV and Exchange as the reason not to rely on it.
That backend behavior was not independently verified by the implementation
audit. If a backend drops the only marker copy, the next pass cannot recognize
the blocker and can create a duplicate.

## Decision

The primary copy is the last lines of notes: a fixed header plus the marker
URL (`Marker.notesBlock` in `Sources/WorkSyncCore/Marker.swift`).
`EventKitStore.write` sets `event.notes = block.marker.notesBlock` and also
`event.url = URL(string: block.marker.urlString)` as a supplementary copy.
`Marker.extract(url:notes:)` reads either.

## Consequences

- Notes are reserved for the marker when a blocker is created or updated;
  `EventKitStore.write` replaces them with the fixed block. This is not an
  every-pass repair: `SyncPlanner.reconcile` does not compare notes or URL, so
  a notes-only edit does not trigger an update. If neither field retains a
  readable marker, the event is no longer recognized as managed.
- Source notes, location, and attendees still never copy onto the blocker;
  notes are reserved for the marker.
- Either surviving marker copy permits recognition. A backend that strips the
  URL needs the notes copy; a backend that strips both defeats this mechanism.
- `Marker.parse` / `extract` must keep accepting a marker from either
  location, including events whose URL was stripped after we wrote both.
