---
# worksync-vh5p
title: Log file + rotation
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T03:22:25Z
parent: worksync-5lsv
---

SPEC §8. Logging:
- [ ] stdout/stderr always; unattended runs also append ~/Library/Logs/worksync/worksync.log
- [ ] Size-based rotation, keep 5 x 1 MB
- [ ] log_level filtering (error|warn|info|debug)


## Summary of Changes
Logger with size-based rotation (1MB x 5), level filtering, NSLock-guarded for the menu bar's concurrent writers. Rotation drops the oldest archive rather than accumulating.
