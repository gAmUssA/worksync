---
# worksync-8je2
title: flock concurrency lock
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T02:36:10Z
parent: worksync-ud6v
---

SPEC §9. Concurrency lock:
- [x] Exclusive flock on ~/.config/worksync/.lock
- [x] If held: exit 0 quietly (another run in progress)
- [x] Shared by CLI and menubar passes (cross-process safety)


## Summary of Changes
RunLock: non-blocking exclusive flock on ~/.config/worksync/.lock, explicit unlock() (holding it in an unread variable both warns and invites early release), creates the parent directory for first runs. Verified live: two concurrent passes, one ran and one exited 0 quietly.
