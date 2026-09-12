---
# worksync-ubcn
title: 'setup: priming card and the in-app authorization request'
status: todo
type: task
created_at: 2026-08-17T19:28:43Z
updated_at: 2026-08-17T19:28:43Z
parent: worksync-9xmk
---

The one card doctor structurally cannot provide, because doctor is provably
non-prompting by spec (§16) and must stay that way. The request is a UI-layer
action rendered beside the calendar-access finding; the seam must not leak
back into the core.

HIG Privacy rules are hard requirements here, not suggestions — an App Store
rejection list:
[ ] EXACTLY one button, titled "Continue" (not "Allow" — HIG calls that
manipulation)
[ ] No Cancel, Skip or Close inside the card; Quit lives in the footer
[ ] No screenshot or mockup of the system dialog, no dimming or annotating
the screen behind it
[ ] Three lines on what it does + the privacy line: busy time only, titles
never leave the Mac

[ ] Poll authorizationStatus after prompting and advance the instant it flips,
like Rectangle does — this also covers granting via System Settings
[ ] On denial, fall through to the existing calendar-access finding and its
DoctorDestination button; doctor already owns that remediation
