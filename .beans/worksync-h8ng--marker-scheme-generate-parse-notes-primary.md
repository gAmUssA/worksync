---
# worksync-h8ng
title: 'Marker scheme: generate + parse (notes-primary)'
status: todo
type: feature
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T00:35:02Z
parent: worksync-ud6v
---

SPEC §7. Marker scheme worksync://v1/<source_id>/<key>:
- [ ] <key> = SHA-256 first 16 hex of externalIdentifier + occurrenceDate (occurrenceDate, NOT startDate — stable across detached-occurrence moves)
- [ ] Coalesced blocks: hash of sorted constituent identifiers+occurrenceDates
- [ ] Write to BOTH locations: notes last line (PRIMARY — Google CalDAV and Exchange drop the whole url field) AND url (supplementary)
- [ ] Fixed human-readable notes line above the marker
- [ ] Parse: notes last-line first, url fallback; defensive exact-prefix match; tolerate unknown future versions (skip+warn); only v1 ever mutated
- [ ] Unit tests: generation, parsing, either-location round trip, garbage rejection
