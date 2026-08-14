---
# worksync-pg25
title: Config validation + resolution guards
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T00:54:03Z
parent: worksync-do7l
blocked_by:
    - worksync-yacc
---

SPEC §4.1/§9. Validation before any calendar mutation; invalid config = exit 1, no writes:
- [ ] Range/enum checks (log_level, notify, availability, minute knobs)
- [ ] Unique source ids; non-empty id slug rules (embedded in markers)
- [ ] Resolution-stage errors listing available accounts/calendars (worksync calendars text reused)
- [ ] Duplicate account/calendar titles -> hard error asking to disambiguate
- [ ] Source == target guard (feedback-loop prevention)
- [ ] Unit tests for every error path


## Summary of Changes
Implemented and covered by the 41-test suite (all green). See Sources/WorkSyncCore, Sources/WorkSyncKit, Sources/worksync.
