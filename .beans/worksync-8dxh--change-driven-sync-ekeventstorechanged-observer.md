---
# worksync-8dxh
title: Change-driven sync (EKEventStoreChanged observer)
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T17:06:13Z
parent: worksync-4p15
blocked_by:
    - worksync-fkyu
---

SPEC §11.2. Change-driven fast path (change_driven, default false):
- [ ] Observer object owns a long-lived EKEventStore (notifications filter on the store instance and die with it); behind a core protocol, fakeable in CI
- [ ] Treat notification as payload-free ("something changed, re-query"); start observing only after first successful pass
- [ ] Hop to main actor explicitly; if using for-await loop, continue (never return) on transient conditions — return permanently kills observation
- [ ] Prefer macOS 26 typed EKEventStore.EventStoreChanged when deployment target allows
- [ ] Debounce: single coalescing timer of change_debounce_seconds re-armed per notification; 5s own-write echo suppression
- [ ] Best-effort only: timer + wake pass remain the guarantee; no feature may assume delivery
