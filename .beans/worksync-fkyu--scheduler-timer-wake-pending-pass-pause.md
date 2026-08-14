---
# worksync-fkyu
title: 'Scheduler: timer, wake, pending-pass, pause'
status: todo
type: feature
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T00:35:51Z
parent: worksync-kxg1
blocked_by:
    - worksync-m0b3
---

SPEC §11. Scheduler:
- [ ] Timer every interval_minutes; pass on launch; pass on NSWorkspace.didWakeNotification
- [ ] Single pass at a time via the shared flock; sync work off the main thread; menu stays responsive
- [ ] Pending-pass flag: a request during an in-flight/lock-skipped pass re-runs after it finishes — never lost
- [ ] Pause/Resume persisted in UserDefaults, survives restart
- [ ] Manual check: "Sync now" x10 runs a complete pass every time (latch-detection)
