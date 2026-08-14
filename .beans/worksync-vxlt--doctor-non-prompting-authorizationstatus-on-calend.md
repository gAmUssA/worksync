---
# worksync-vxlt
title: 'doctor: non-prompting authorizationStatus on CalendarStore'
status: todo
type: task
created_at: 2026-08-14T03:37:43Z
updated_at: 2026-08-14T03:37:43Z
parent: worksync-q43e
---

BLOCKS the access check. A diagnostic must never mutate system permission state.

EventKitStore.requestAccess() deliberately falls through .notDetermined and .writeOnly into requestFullAccessToEvents, which raises a TCC prompt. Doctor calling it would show a permission dialog to someone who ran a diagnostic — and on .notDetermined would then report success for a permission granted TO THE DIAGNOSTIC, hiding that the user never granted it interactively as SPEC §3 requires.
- [ ] CalendarAccess enum in the EventKit-free core (fullAccess/writeOnly/denied/restricted/notDetermined)
- [ ] authorizationStatus() -> CalendarAccess on the CalendarStore protocol, read-only
- [ ] EventKitStore reads EKEventStore.authorizationStatus(for:.event) directly
- [ ] Fake drives all states so CI covers every branch
- [ ] .writeOnly gets its own message: queries succeed and return zero events, so the tool looks healthy while syncing nothing
