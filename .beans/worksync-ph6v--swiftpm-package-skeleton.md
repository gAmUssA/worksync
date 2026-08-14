---
# worksync-ph6v
title: SwiftPM package skeleton
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:34Z
updated_at: 2026-08-14T00:54:03Z
parent: worksync-zlvm
---

SPEC §3. Package.swift with targets:
- [ ] WorkSyncCore (pure logic — no EventKit/AppKit imports, enforced by review)
- [ ] WorkSyncKit (EventKit adapter behind CalendarStore protocol)
- [ ] worksync executable (CLI entry + menubar mode), swift-argument-parser command tree with all subcommand stubs (§8)
- [ ] Tests/WorkSyncCoreTests
- [ ] Dependencies: swift-argument-parser, TOMLKit
- [ ] `swift build` and `swift test` green locally


## Summary of Changes
Implemented and covered by the 41-test suite (all green). See Sources/WorkSyncCore, Sources/WorkSyncKit, Sources/worksync.
