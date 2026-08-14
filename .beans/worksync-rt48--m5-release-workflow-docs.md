---
# worksync-rt48
title: 'M5: Release workflow + docs'
status: completed
type: milestone
priority: normal
created_at: 2026-08-14T00:33:15Z
updated_at: 2026-08-14T04:08:33Z
blocked_by:
    - worksync-5lsv
---

SPEC §14 M5. Release workflow, build-app.sh signing + designated-requirement verification in CI, docs.

## Acceptance
- [ ] Tagging v* produces a downloadable GitHub Release artifact (WorkSync-<version>-arm64.tar.gz containing the .app)
- [ ] README documents: curl install path (no quarantine), xattr fallback, local re-sign for stable TCC, first interactive run, manual test checklist
- [ ] Calendar TCC grant survives a rebuild when signed with the local stable certificate


## Summary of Changes
M5 complete. Release pipeline exercised for real: v0.1.0 tagged, built on macos-26, published, downloaded, and every README claim verified against the actual artifact.
