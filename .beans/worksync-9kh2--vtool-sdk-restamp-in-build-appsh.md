---
# worksync-9kh2
title: vtool SDK restamp in build-app.sh
status: completed
type: task
priority: normal
created_at: 2026-08-14T02:25:53Z
updated_at: 2026-08-14T03:22:25Z
parent: worksync-5lsv
---

SPEC §3.1 rule 6. SwiftPM stamps LC_BUILD_VERSION's sdk field with the DEPLOYMENT TARGET, not the SDK compiled against. macOS gates modern (Liquid Glass) control appearance on the linked SDK, so the UI silently renders legacy Aqua with no error to debug.
- [ ] vtool -set-build-version macos <target> <sdk> -replace on Contents/MacOS/worksync BEFORE codesign (restamping after signing invalidates it)
- [ ] Re-verify the TCC/Gatekeeper chain after the change (M1 acceptance: grant survives rebuild)
Deliberately deferred from M1: no UI yet, and the signing pipeline is verified working.


## Summary of Changes
vtool -set-build-version runs before codesign in build-app.sh; SDK version read from xcrun, deployment target from Info.plist. Verified: minos 14.0 / sdk 26.5, calendar permission survived the restamp + re-sign. Falls back with a warning if vtool or the SDK version is unavailable.
