---
# worksync-yacc
title: Config model + TOML parsing
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T00:54:03Z
parent: worksync-do7l
blocked_by:
    - worksync-ph6v
---

SPEC §4. Config model + TOMLKit parsing in WorkSyncCore:
- [ ] All [general], [target], [[source]] fields with defaults per the §4 example
- [ ] Source order preserved exactly (order is semantically load-bearing — §4.1)
- [ ] Loader is the single entry point (the M6 writer round-trip self-check reuses it)
- [ ] Unit tests: full example config parses; defaults; unknown-key tolerance decision documented


## Summary of Changes
Implemented and covered by the 41-test suite (all green). See Sources/WorkSyncCore, Sources/WorkSyncKit, Sources/worksync.
