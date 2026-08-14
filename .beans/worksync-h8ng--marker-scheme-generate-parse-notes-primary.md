---
# worksync-h8ng
title: 'Marker scheme: generate + parse (notes-primary)'
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T02:28:51Z
parent: worksync-ud6v
---

SPEC §7. Marker scheme worksync://v1/<source_id>/<key>:
- [x] <key> = SHA-256 first 16 hex of externalIdentifier + occurrenceDate (occurrenceDate, NOT startDate — stable across detached-occurrence moves)
- [x] Coalesced blocks: hash of sorted constituent identifiers+occurrenceDates
- [x] Write to BOTH locations: notes last line (PRIMARY — Google CalDAV and Exchange drop the whole url field) AND url (supplementary)
- [x] Fixed human-readable notes line above the marker
- [x] Parse: notes last-line first, url fallback; defensive exact-prefix match; tolerate unknown future versions (skip+warn); only v1 ever mutated
- [x] Unit tests: generation, parsing, either-location round trip, garbage rejection

## Summary of Changes
Delivered in M1 (Sources/WorkSyncCore/Marker.swift, MarkerTests). Generation uses
occurrenceDate, coalesced keys hash sorted constituents, both locations are produced
(notesBlock + urlString), parsing scans notes bottom-up then falls back to url, unknown
versions parse but are never mutated. Hardened after the Copilot review: extract() no
longer reads only the last line, and ConfigLoader rejects ids containing "/" or line
breaks, which would otherwise corrupt the marker round trip.

Writing markers onto real events is the apply path (worksync-hw8o), not this bean.
