---
# worksync-ikky
title: 'M8: worksync doctor + health surfacing'
status: completed
type: milestone
priority: normal
created_at: 2026-08-14T03:40:03Z
updated_at: 2026-08-14T05:18:57Z
blocked_by:
    - worksync-5lsv
---

Self-diagnosis, surfaced in both places a user might look: `worksync doctor` in the terminal, and a health indicator in the menu bar.

## Why one milestone rather than two features
The checks are the product; the two surfaces are renderings of the same result. If the UI computed health separately it would drift from the CLI, and the first time they disagreed the user would trust neither. Everything runs through one set of checks in WorkSyncCore returning one value type (see the epic), and both surfaces format it.

This also inverts the SPEC §2 CLI-parity rule in a useful way: parity usually means "the CLI can do anything the UI can". Here the CLI computes and the UI displays, so parity is free by construction.

## Sequencing
Depends on M4 (the menu bar) for the UI half, and on nothing at all for the core + CLI half. Can be pulled ahead of M5-M7 if the diagnostics are worth more than the release polish — most of the checks came from failures hit while building M1-M4, so they pay for themselves the next time something breaks.

## Acceptance
- [ ] `worksync doctor` prints every check with a severity glyph, detail, and an executable remediation; exits 0/1/2/3 per the existing contract, warnings never changing the exit code
- [ ] `worksync doctor --json` emits the same findings machine-readably
- [ ] The menu bar icon reflects health, not just sync outcome: a user with calendar access revoked sees a problem without opening anything
- [ ] The panel lists failing checks with their remediation, and offers a button for the ones that have a destination (System Settings, config file)
- [ ] Both surfaces are driven by the same checks — no second implementation, no separate thresholds
- [ ] Doctor remains provably read-only: no prompts, no writes, no sync pass
