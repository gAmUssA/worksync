---
# worksync-ywyz
title: Release workflow (tag v* -> GitHub Release)
status: todo
type: task
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T00:36:15Z
parent: worksync-rt48
blocked_by:
    - worksync-z356
---

SPEC §12. Release job on tag v*:
- [ ] Runs build-app.sh with ad-hoc signing (CI has no identity — acceptable; users re-sign locally)
- [ ] Packages WorkSync-<version>-arm64.tar.gz containing the .app; attaches to GitHub Release
- [ ] worksync version reports the tagged version
