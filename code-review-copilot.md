# WorkSync Code Review (Copilot)

## Snapshot (Milestone 2 Delta)
- Review type: delta review (M1 -> M2)
- Baseline commit (M1 anchor): 35edd006bbde471b0de7b5d4eb973b6d3d1c2206 (35edd00)
- Current commit reviewed: c68fc68301677fa1b136929717309ce92cc8f2ca (c68fc68)
- Milestone landing commit in range: 4f6d581 (M2: reconciliation writes, purge, and cross-process run lock)
- Working tree at review time: clean
- Review date: 2026-08-13

## Scope
This review covers changes introduced after M1, with focus on M2 deliverables:
- reconciliation writes and apply pipeline
- marker persistence and parsing behavior
- purge command and bounded scan behavior
- cross-process lock behavior
- exit-code mapping behavior
- tests added/updated for M2 paths

## Verification Run
- swift test passed
- Result: 79 tests, 0 failures

## Findings (ordered by severity)

### 1) High: purge can return success after an incomplete scan
Why it matters:
- The command can tell users no managed events were found even when one or more calendars failed to scan.

Evidence:
- Scan failures are warned and skipped: Sources/worksync/Purge.swift:39-46
- Empty managed set returns success immediately: Sources/worksync/Purge.swift:53-57

Risk/impact:
- False confidence that purge completed successfully.
- Operational cleanup can remain incomplete without a failure signal to automation.

Recommendation:
- Track scan failures during discovery and exit with code 3 when any scan failed, even if zero deletions were attempted.

---

### 2) High: lock acquisition errors are conflated with normal lock contention
Why it matters:
- The lock API currently returns nil for two different conditions: expected contention and unexpected I/O/setup failure.

Evidence:
- RunLock returns nil when open fails and when flock fails: Sources/WorkSyncCore/RunLock.swift:23-29
- Sync treats nil as normal "already running" and exits quietly: Sources/worksync/Sync.swift:29-35
- Purge treats nil similarly: Sources/worksync/Purge.swift:71-74

Risk/impact:
- Real environmental failures (permissions/filesystem issues) can be silently reported as success.

Recommendation:
- Change RunLock to return typed outcomes (held vs setup failure), or throw explicit errors.
- Map setup failures to exit code 3 (retryable runtime failure), while preserving exit-0 behavior for true contention.

---

### 3) Medium: purge lock-contention behavior is likely too weak for operator intent
Why it matters:
- Purge is an explicit operator action. Returning success when nothing ran may be surprising in scripts.

Evidence:
- On lock contention, purge prints a message and returns success: Sources/worksync/Purge.swift:71-74

Risk/impact:
- Automation may interpret lock contention as completed cleanup.

Recommendation:
- Consider returning exit 3 on purge lock contention so callers can retry explicitly.
- If current behavior is intentional, document it clearly in SPEC and command help.

## M2 Improvements Confirmed
These are positive deltas and appear correctly implemented:
- Reconciliation write/apply path with batch commit and partial-failure reporting:
  - Sources/WorkSyncCore/SyncEngine.swift
  - Sources/WorkSyncKit/EventKitStore.swift
- Source id normalization and validation hardening:
  - Sources/WorkSyncCore/Config.swift
- Marker extraction improved for notes-tail edits:
  - Sources/WorkSyncCore/Marker.swift
- Purge bounded scan span aligns with EventKit four-year predicate constraint:
  - Sources/WorkSyncCore/PurgeScan.swift
- Exit-code mapping centralized and unit-tested:
  - Sources/WorkSyncCore/ExitCodes.swift
  - Tests/WorkSyncCoreTests/ExitCodesTests.swift

## Test Coverage Notes
M2 added solid coverage for new core behavior:
- apply path and convergence behavior: Tests/WorkSyncCoreTests/SyncEngineTests.swift
- lock behavior: Tests/WorkSyncCoreTests/RunLockTests.swift
- purge claim/span rules: Tests/WorkSyncCoreTests/PurgeScanTests.swift
- exit-code mapping: Tests/WorkSyncCoreTests/ExitCodesTests.swift

Suggested additions for remaining risk:
- purge command-level tests that assert non-zero exit on partial scan failure
- lock error path tests that distinguish contention from lock setup failure

## Overall Assessment
M2 landed substantial and high-quality progress: write path, purge mechanics, locking, and stronger invariants are all in place, and test depth increased significantly.

The key remaining reliability issue is error signaling around purge/locking edge cases. Addressing those will make operational behavior match user expectations and automation needs.
