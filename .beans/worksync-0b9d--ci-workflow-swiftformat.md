---
# worksync-0b9d
title: CI workflow + swiftformat
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:34Z
updated_at: 2026-08-14T01:17:17Z
parent: worksync-zlvm
blocked_by:
    - worksync-ph6v
---

SPEC §12. .github/workflows/ci.yml on macos-15:
- [x] swift --version; cache .build keyed on Package.resolved
- [x] swift build -c debug
- [x] swift test (WorkSyncCore stays EventKit-free — CI has no TCC; in-memory fake covers integration)
- [x] swiftformat --lint . with config committed to repo
- [x] Green on a clean runner, zero manual steps (workflow written; verification on first push)


## Summary of Changes
.github/workflows/ci.yml (build-test on macos-15 + release job on v* tags, ad-hoc signed) and .swiftformat committed. Runner verification happens on first push.
