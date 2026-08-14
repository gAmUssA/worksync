---
# worksync-rt48
title: 'M5: Release workflow + docs'
status: todo
type: milestone
priority: normal
created_at: 2026-08-14T00:33:15Z
updated_at: 2026-08-14T00:33:43Z
blocked_by:
    - worksync-5lsv
---

SPEC §14 M5. Release workflow, build-app.sh signing + designated-requirement verification in CI, docs.

## Acceptance
- [ ] Tagging v* produces a downloadable GitHub Release artifact (WorkSync-<version>-arm64.tar.gz containing the .app)
- [ ] README documents: curl install path (no quarantine), xattr fallback, local re-sign for stable TCC, first interactive run, manual test checklist
- [ ] Calendar TCC grant survives a rebuild when signed with the local stable certificate
