---
# worksync-r4nx
title: 'SPEC prose contradicted by the implementation (audit residue)'
status: todo
type: chore
created_at: 2026-09-12T14:30:56Z
updated_at: 2026-09-12T14:30:56Z
---

The 2026-09-12 divergence audit found ~24 claims in SPEC.md that the code does
not honour. The substantive ones are filed separately as `worksync-b2ke`,
`worksync-m9qt`, `worksync-c5vd` and `worksync-k8fw`.

This bean tracks the remainder: places where the **code is right** and the
prose is simply wrong or stale. Under ADR-0001 SPEC is no longer the authority,
so these are not urgent — but they are traps for anyone who still reads it as
one, so they should be corrected or explicitly marked historical.

Documentation-only, from the audit:

- §4.1 / §7 — renaming a source does not strand every orphaned blocker:
  unmatched current-version markers **inside the fetched window, on a calendar
  still being reconciled** are deleted by a normal pass, so purge is not "the
  only way". Blockers outside that window, or on a calendar the config no
  longer targets, are never fetched and do still need purge. §6 is closer to
  the code.
- §6 — a changed `target_calendar` is not retargeted in place when the old
  target leaves the fetched set; the old event is simply never seen.
- §4.3 step 6 — full serialization has a **third** trigger: an existing file
  that cannot be parsed.
- §15 — "preserves all comments" is not unconditional; the fallback path says so
  itself via `ConfigWriteOutcome.reserialized`.
- §5 — cross-source dedup runs **before** padding/coalescing, not after.
- §7 — unknown marker versions are skipped but not warned about.
- §8 — the command is `worksync --version`, not `worksync version`; and no
  pause/resume subcommand exists despite "every capability is reachable".
- §16 — doctor is not literally read-only: it acquires `.menubar.lock`,
  creating the directory and file on a fresh setup.
- §9 — single-instance is not absolute: a filesystem failure deliberately allows
  launch with a warning. No disconnected-source warning exists at all.
- §3.1 — the osascript notification fallback does not fire on denial (denial is
  deliberately respected); the SDK restamp IS in `build-app.sh`, contrary to
  "deliberately not yet".
- §10 — login-item state is a cached enum refreshed on open/toggle, not read
  every render; no move-triggered re-registration exists.
- §11 — notification authorization is requested lazily on first actual
  notification, not when `notify` becomes non-off.

[ ] For each: correct the prose, or mark the section historical per ADR-0001
[ ] Where the divergence encodes a real decision, write the ADR instead
