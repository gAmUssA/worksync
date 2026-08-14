---
# worksync-vh5p
title: Log file + rotation
status: todo
type: task
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T00:35:51Z
parent: worksync-5lsv
---

SPEC §8. Logging:
- [ ] stdout/stderr always; unattended runs also append ~/Library/Logs/worksync/worksync.log
- [ ] Size-based rotation, keep 5 x 1 MB
- [ ] log_level filtering (error|warn|info|debug)
