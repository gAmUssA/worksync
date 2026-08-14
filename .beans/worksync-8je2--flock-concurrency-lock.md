---
# worksync-8je2
title: flock concurrency lock
status: todo
type: task
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T00:35:02Z
parent: worksync-ud6v
---

SPEC §9. Concurrency lock:
- [ ] Exclusive flock on ~/.config/worksync/.lock
- [ ] If held: exit 0 quietly (another run in progress)
- [ ] Shared by CLI and menubar passes (cross-process safety)
