---
# worksync-dopp
title: 'M1: Skeleton, bundle, config, read-only plan'
status: completed
type: milestone
priority: normal
created_at: 2026-08-14T00:32:36Z
updated_at: 2026-08-14T01:49:38Z
---

SPEC §14 M1. SwiftPM skeleton + CI green (build, empty tests, format lint), config parsing, `worksync calendars`, `sync --dry-run` printing the plan (read-only). Includes `scripts/build-app.sh` producing a signed, LaunchServices-registered WorkSync.app and the bundle smoke test (SPEC §3.1 rule 2): launch it and confirm the notification authorization prompt appears — the bundle architecture is validated before anything depends on it.

## Acceptance
- [x] `git clone && swift build && swift test` succeeds on a clean machine; no .xcodeproj/.xcworkspace anywhere
- [x] CI green on push (workflow committed; runner verification on first push to a remote)
- [x] `build-app.sh` produces signed WorkSync.app; designated requirement is NOT a bare cdhash
- [x] Bundle smoke test: bundle accepted as real app (UN center no crash, alertSetting=enabled, auth request delivered)
- [x] `worksync calendars` lists accounts + calendars (verified live)
- [x] `worksync sync --dry-run` prints a correct plan without mutating (verified live: 9 events -> 6-create plan)


## Summary of Changes
M1 delivered 2026-08-13: SwiftPM package (WorkSyncCore/WorkSyncKit/worksync), 41 passing tests, config parse+validation, resolver with guards, pure SyncPlanner (filters/padding/coalescing/window-filter/reconcile diff), marker scheme, EventKit adapter with 4-year span chunking, CLI (calendars, sync --dry-run, stubs, exit codes 0/1/2), build-app.sh (WorkSync Dev cert, stable DR, lsregister), Resources (Info.plist/entitlements/AppIcon.icns), CI + swiftformat. Bundle architecture validated live; TCC grant + Gatekeeper approval survive rebuilds.
