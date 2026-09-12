---
# worksync-4t1b
title: Panel must survive the TCC dialog
status: todo
type: epic
created_at: 2026-08-17T19:28:13Z
updated_at: 2026-08-17T19:28:13Z
parent: worksync-n2bv
---

Verified risk, not speculation. `PanelDismissPolicy.shouldKeepOpen` keeps the
panel open only for the panel itself, the status button, and windows whose
class name contains "menu" or "popover". The global mouse-down monitor sees
clicks in OTHER processes with `event.window == nil`, so a click on
"Allow Full Access" in the TCC dialog falls through every branch and dismisses
the panel — mid-setup, at the exact moment the user is granting access.

This is the class of bug SPEC §3.1 rule 7 exists to catch.
