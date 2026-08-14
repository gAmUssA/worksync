---
# worksync-ko6i
title: worksync status command
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T03:22:25Z
parent: worksync-5lsv
---

SPEC §8. `worksync status`: managed-event count per source + last-run info (timestamp, success, summary) from the display-state record.
- [ ] Implemented against CalendarStore + last-run record


## Summary of Changes
worksync status leads with last-run + staleness (2x interval), then per-source managed counts via the purge sweep, flagging orphaned ids with the purge command that recovers them. LastRun degrades to nil on missing/corrupt files so display state can never break a sync.
