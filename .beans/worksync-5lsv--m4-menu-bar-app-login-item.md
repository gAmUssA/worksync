---
# worksync-5lsv
title: 'M4: Menu bar app + login item'
status: completed
type: milestone
priority: normal
created_at: 2026-08-14T00:33:15Z
updated_at: 2026-08-14T03:30:45Z
blocked_by:
    - worksync-xli7
---

SPEC §14 M4. Menubar mode (icon states, menu, timer, pause), SMAppService login item + --headless launchd alternative (SPEC §10), logging/rotation, `worksync status`.

## Acceptance
- [ ] Menu bar icon reflects syncing/ok/error/paused states; Sync now and Pause work (SPEC §15)
- [ ] Every menu bar action works on the tenth invocation exactly as on the first; "Sync now" runs a complete pass every time
- [ ] Quitting the menubar app and re-launching (or login with login item enabled) restores it
- [ ] Wake-from-sleep triggers a pass; pending-pass flag never loses a request
- [ ] Logs rotate at ~/Library/Logs/worksync/worksync.log (5 × 1 MB)


## Summary of Changes
M4 complete: vtool SDK restamp, log rotation, last-run record, status command, menu bar app (NSPanel + scheduler + pause), and launch at login. Verified live against real calendars throughout; app launches, syncs, coexists with the CLI, and quits cleanly. 151 tests green.
