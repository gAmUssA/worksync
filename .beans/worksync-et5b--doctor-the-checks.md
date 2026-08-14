---
# worksync-et5b
title: 'doctor: the checks'
status: completed
type: task
priority: normal
created_at: 2026-08-14T03:37:43Z
updated_at: 2026-08-14T05:18:57Z
parent: worksync-q43e
blocked_by:
    - worksync-3bnt
    - worksync-vxlt
    - worksync-7020
---

Ranked by how often each is the actual answer to 'why isn't this working'.

## Errors
- [ ] 1. Calendar authorization (exit 2, highest precedence; reuse CalendarStoreError.accessDenied text)
- [ ] 2. Config exists/parses/validates (exit 1; on fileNotFound STOP — everything downstream is meaningless)
- [ ] 3. Accounts + calendars resolve unambiguously (exit 1, via resolveAll)
- [ ] 4. Every target calendar is writable — allowsModifications is already populated but only surfaces at write time today, after a pass has done all its reading
- [ ] 5. Something is actually running: SMAppService status (read live, never cached) OR loaded launchd agent OR a live menubar process. Error only when NONE. SPEC §11.2 says this is more often the answer than any reconciliation bug

## Warnings (never change the exit code)
- [ ] 6. Designated requirement is not a bare cdhash. build-app.sh checks this at build time, but CI releases are ad-hoc signed ON PURPOSE (SPEC §12) — so every user of a release tarball is in exactly the state the build script refuses to ship. The symptom (permission mysteriously revoked after an update) looks nothing like the cause
- [ ] 7. Last run stale: now - lastRun > max(3x interval, 30min). Deliberately generous — a closed laptop is not a fault, and a warning that fires every morning is one nobody reads
- [ ] 8. Notification authorization — ONLY when notify != off. All-settings-NotSupported means a mis-assembled or directly-launched bundle (SPEC §3.1 rule 2); name that, do not call it 'denied'
- [ ] 9. Log file meaningfully over 5MB means rotation is broken
