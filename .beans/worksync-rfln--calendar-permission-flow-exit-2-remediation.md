---
# worksync-rfln
title: Calendar permission flow (exit 2 + remediation)
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T01:49:25Z
parent: worksync-1838
blocked_by:
    - worksync-6ubu
---

SPEC §3/§8. Permission flow:
- [ ] requestFullAccessToEvents() (macOS 14+; never the legacy requestAccess(to:) — it fails without prompting)
- [ ] Denied/restricted -> exit 2 with remediation text (System Settings path, first-run-in-Terminal note)
- [ ] Warning when target source reports disconnected (§9)


## Summary of Changes
requestAccess() in EventKitStore handles fullAccess/restricted/denied/writeOnly (writeOnly treated as denied — queries return no results under it); CLI maps CalendarStoreError to exit 2 with remediation text.


## Post-completion fix
.writeOnly must NOT be treated as denied: requestFullAccessToEvents() prompts to UPGRADE write-only to full. Treating it as denied dead-ends users who first landed on the add-only tier — this exact bug blocked the live test until fixed.
