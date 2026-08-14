---
# worksync-fkyu
title: 'Scheduler: timer, wake, pending-pass, pause'
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T03:30:45Z
parent: worksync-kxg1
blocked_by:
    - worksync-m0b3
---

SPEC §11. Scheduler:
- [x] Timer every interval_minutes; pass on launch; pass on NSWorkspace.didWakeNotification
- [x] Single pass at a time via the shared flock; sync work off the main thread; menu stays responsive
- [x] Pending-pass flag: a request during an in-flight/lock-skipped pass re-runs after it finishes — never lost
- [x] Pause/Resume persisted in UserDefaults, survives restart
- [x] Manual check: "Sync now" x10 runs a complete pass every time (latch-detection)


## Summary of Changes
Timer every interval_minutes, pass on launch, wake-from-sleep observer, shared flock via PassRunner so CLI and menubar never collide, pending-request flag so a Sync now during an in-flight pass re-runs rather than being dropped, paused state in UserDefaults. Verified live: launch pass ran, concurrent CLI sync coexisted, app survived and quit cleanly.
