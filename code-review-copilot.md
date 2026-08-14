# WorkSync Code Review (Copilot)

## Snapshot (Milestone 1)
- Reviewed commit: `35edd006bbde471b0de7b5d4eb973b6d3d1c2206` (`35edd00`)
- Commit message: `Apply swiftformat (fixes CI lint)`
- Commit author/date: Viktor Gamov, 2026-08-13 21:58:29 -0400
- Working tree at review time: clean
- Review date: 2026-08-13

## Scope
This review focused on the currently implemented M1 paths:
- config parsing and validation
- calendar resolution/listing
- dry-run planning pipeline (`sync --dry-run`)
- EventKit adapter safety and error handling
- unit test coverage and results

## Verification Run
- `swift test` passed
- Result: 41 tests, 0 failures

## Findings (ordered by severity)

### 1) High: `sync` does not reliably map backend failures to defined exit codes
**Why it matters**
The CLI promises stable exit-code semantics. Right now, certain runtime failures can bypass those mappings and surface as uncaught command errors.

**Evidence**
- `Sync.run()` only catches `ResolutionError`: `Sources/worksync/Sync.swift:27`
- But `Sync.plan()` can throw from backend calls:
  - `store.calendars()`: `Sources/worksync/Sync.swift:48`
  - `store.events(...)`: `Sources/worksync/Sync.swift:56`, `Sources/worksync/Sync.swift:67`
- Exit-code contract is explicitly defined in spec: `SPEC.md:215`

**Risk/impact**
- Non-deterministic user-facing behavior on EventKit/backend failures.
- Automation/scripts may mis-handle failures due to unexpected exit status and messaging.

**Recommendation**
Catch `CalendarStoreError` (and optionally a final fallback `Error`) in `Sync.run()` and map to the declared exit code contract (`2` for permission issues where applicable, `3` for runtime/partial backend failures).

---

### 2) Medium: Source `id` whitespace is validated inconsistently and may create hidden identity drift
**Why it matters**
`source.id` is a durable identity used in markers and operational commands. Leading/trailing whitespace should be normalized or rejected consistently.

**Evidence**
- Parsed ID is taken as-is: `Sources/WorkSyncCore/Config.swift:164`, `Sources/WorkSyncCore/Config.swift:173`
- Validation trims only for emptiness/dup detection, but does not persist normalized value: `Sources/WorkSyncCore/Config.swift:218`
- Marker identity embeds source ID directly: `Sources/WorkSyncCore/Marker.swift:35`

**Risk/impact**
- Two visually identical IDs (for example `personal` vs `personal `) can behave as different identities in markers.
- Can complicate source-scoped operations (for example purge-by-source) and future config editing flows.

**Recommendation**
Normalize IDs during parse (trim and assign) or reject any ID containing leading/trailing whitespace with a clear validation error.

---

### 3) Medium: Event identity fallback to empty `externalIdentifier` can cause key collisions in edge cases
**Why it matters**
Identity stability is core to idempotent reconciliation. Falling back to empty identifiers increases collision risk when provider metadata is missing.

**Evidence**
- Event mapping uses empty-string fallback: `Sources/WorkSyncKit/EventKitStore.swift:100`
- Marker key is derived from external ID + occurrence date: `Sources/WorkSyncCore/Marker.swift:45`

**Risk/impact**
- If backend returns nil/empty external identifiers for multiple events, those can collapse onto the same computed key and produce incorrect update/delete behavior.

**Recommendation**
Fail-safe on missing `calendarItemExternalIdentifier` for managed candidates (skip with warning), or incorporate an additional stable discriminator when external ID is absent.

## Milestone 1 Alignment Notes (not defects)
These gaps are documented and expected for M1, but worth making explicit in status communication:
- Cross-source dedup and conflict check are intentionally deferred to M3 (`Sources/worksync/Sync.swift:46`, `SPEC.md:336`).
- Non-dry-run write path is intentionally deferred to M2 (`Sources/worksync/Sync.swift:38`).

## Test Coverage Observations
Good coverage exists for pure core logic (interval math, marker parsing, reconciliation behavior, config parsing, resolver behavior).

Remaining high-value tests to add soon:
- CLI-level exit-code mapping tests for backend failures in `sync`.
- EventKit adapter edge tests around missing identifiers and chunk-boundary dedupe.

## Overall Assessment
The M1 foundation is strong: structure is clean, core planner logic is well tested, and spec intent is reflected in code comments.

The most important near-term improvement is robust runtime error-to-exit-code handling in `sync`, since that affects reliability for real users and automation.
