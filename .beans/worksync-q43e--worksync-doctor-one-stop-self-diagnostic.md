---
# worksync-q43e
title: worksync doctor — one-stop self diagnostic
status: draft
type: epic
created_at: 2026-08-14T03:10:50Z
updated_at: 2026-08-14T03:10:50Z
---

One command that checks everything that can quietly go wrong, so "why didn't my change sync?" has a first stop that is not guesswork.

Most of the candidate checks below come from failures actually hit while building M1-M3, which is the argument for the feature: each one cost real debugging time and each is mechanically detectable.

## Candidate checks (to be ranked by the research pass)
- [ ] Calendar TCC authorization: fullAccess vs writeOnly vs denied vs notDetermined. The writeOnly tier silently returns zero events from every query — this one blocked M1 for an hour.
- [ ] config.toml exists, parses, validates
- [ ] Every configured account + calendar resolves (catches typos), and each target calendar is writable
- [ ] source == target feedback-loop guard holds
- [ ] Login item / launchd agent registered and enabled
- [ ] A worksync process is actually alive (SPEC §11.2 operational note: nothing syncs unless something is running, and this is more often the cause than any reconciliation bug)
- [ ] Last successful sync timestamp, and whether it is stale relative to interval_minutes
- [ ] Log file present, written, rotating, not enormous
- [ ] Bundle signature: designated requirement is NOT a bare cdhash. An ad-hoc signature resets the calendar grant on every rebuild, which presents as "permissions randomly broke again".
- [ ] Notification authorization status
- [ ] Stale run lock
- [ ] Managed-event count per target calendar

## Open questions for the research pass
- [ ] Severity model: which failures are fatal vs advisory, and does the command exit non-zero on advisory findings? (brew doctor and flutter doctor differ here.)
- [ ] Default verbosity: show every check, or only problems?
- [ ] --json for scripting?
- [ ] Remediation text: every failure must print the fix, not just the symptom.

Research agent dispatched to study brew/flutter/gh/npm doctor conventions before this is broken into tasks.
