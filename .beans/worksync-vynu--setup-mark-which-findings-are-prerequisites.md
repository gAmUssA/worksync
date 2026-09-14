---
# worksync-vynu
title: 'setup: mark which findings are prerequisites'
status: completed
type: task
created_at: 2026-08-17T19:28:43Z
updated_at: 2026-08-17T19:28:43Z
parent: worksync-9xmk
---

Do this first — it is what lets the setup screen and the Health section be one
view with two filters.

Only 5 of 9 checks are prerequisites: calendar-access, config,
calendars-resolve, target-writable, scheduling. Signature stability, log size,
notifications and staleness are noise to someone who has not synced once, and
must never gate setup — consistent with warnings never changing the exit code.

[x] `isPrerequisite` on DoctorFinding (or a prerequisite id list in core, not
in the view — the UI must not own the definition)
[x] Prerequisite ORDER, which is not severity order: doctor sorts by severity
and its checks are independent; setup is dependency-ordered
[x] Reuse `.skipped(because:)` verbatim — "needs calendar access" is already
the right sentence
[x] Tests: the prerequisite set is exactly those five; a warning never gates
