---
# worksync-c69a
title: worksync calendars command
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T01:49:25Z
parent: worksync-1838
blocked_by:
    - worksync-6ubu
    - worksync-rfln
---

SPEC §8. `worksync calendars`: list accounts (EKSource titles) + calendars with identifiers, marking write access. Output reused by config validation errors and M6 resolver popups.
- [ ] Command implemented against CalendarStore
- [ ] Human-readable + stable formatting


## Summary of Changes
Implemented + verified live: lists all 5 accounts / 20+ calendars grouped by account with read-write markers and identifiers. --output option added (open(1) swallows stdout for GUI launches).
