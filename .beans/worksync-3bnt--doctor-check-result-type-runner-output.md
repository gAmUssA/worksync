---
# worksync-3bnt
title: 'doctor: check result type + runner + output'
status: completed
type: task
priority: normal
created_at: 2026-08-14T03:37:43Z
updated_at: 2026-08-14T05:18:57Z
parent: worksync-q43e
blocking:
    - worksync-vxlt
---

Do this first — it is what makes everything else testable and --json possible.
- [ ] DoctorFinding value type in WorkSyncCore: severity (ok/warning/error/skipped), title, detail, remediation
- [ ] Runner collects findings, maps worst severity through the EXISTING ExitCodes.code(for:) — no parallel mapping, so ExitCodesTests keeps covering it
- [ ] Two-level output: headline glyph per check, indented detail lines. Glyph carries severity, colour is decoration only
- [ ] Findings to STDOUT (brew doctor's everything-to-stderr makes it ungreppable)
- [ ] Default shows passing checks; -v adds detail; --json
- [ ] --strict promotes warnings to exit 1 (opt-in, for CI)
- [ ] Unit tests drive every severity via the in-memory fake
