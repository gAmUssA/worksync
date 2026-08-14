---
# worksync-ywyz
title: Release workflow (tag v* -> GitHub Release)
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T04:08:33Z
parent: worksync-rt48
blocked_by:
    - worksync-z356
---

SPEC §12. Release job on tag v*:
- [x] Runs build-app.sh with ad-hoc signing (CI has no identity — acceptable; users re-sign locally)
- [x] Packages WorkSync-<version>-arm64.tar.gz containing the .app; attaches to GitHub Release
- [x] worksync version reports the tagged version


## Summary of Changes
Release job moved to macos-26 after probing it (Swift 6.3.3, same as a dev machine) — releasing from macos-15 would have shipped legacy Aqua controls because build-app.sh stamps the SDK it compiled against. build-test stays on macos-15 deliberately as the older toolchain that catches SDK-gated code. Added a tag/Info.plist version guard and release notes covering ad-hoc signing and the curl-not-browser download.

Verified by actually tagging v0.1.0 and downloading the artifact: no quarantine, sdk 26.5, ad-hoc cdhash signature as documented, binary runs and 'init' works from the download.
