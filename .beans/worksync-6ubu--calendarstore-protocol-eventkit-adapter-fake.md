---
# worksync-6ubu
title: CalendarStore protocol + EventKit adapter + fake
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T00:54:03Z
parent: worksync-1838
blocked_by:
    - worksync-ph6v
---

SPEC §3/§13. CalendarStore protocol in WorkSyncCore (EventKit-free), EventKit adapter in WorkSyncKit, in-memory fake for CI:
- [ ] Protocol: enumerate sources/calendars, fetch events in span, create/update/delete (write ops stubbed until M2)
- [ ] EventKit adapter: predicateForEvents; expose occurrenceDate, calendarItemExternalIdentifier, availability, attendee status, all-day
- [ ] Span discipline: any query >4 years must be chunked into ≤4-year segments and unioned (predicateForEvents silently truncates to 4 years — §8)
- [ ] In-memory fake with same semantics for plan+apply tests


## Summary of Changes
Implemented and covered by the 41-test suite (all green). See Sources/WorkSyncCore, Sources/WorkSyncKit, Sources/worksync.
