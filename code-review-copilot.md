# WorkSync Code Review (Copilot)

## Findings (ordered by severity)

### 1) Medium: Doctor remediation names the wrong config file for `--config` users
**Why it matters**
The doctor command accepts an explicit config path, but the target-writability remediation always tells the user to edit `ConfigLoader.defaultPath`. A user diagnosing a custom config receives an actionable-looking instruction for a file that is not being used.

**Evidence**
- `DoctorInputs` carries the requested config path: [Sources/WorkSyncCore/DoctorChecks.swift](Sources/WorkSyncCore/DoctorChecks.swift#L77-L108)
- The writability remediation ignores it and uses the default path: [Sources/WorkSyncCore/DoctorChecks.swift](Sources/WorkSyncCore/DoctorChecks.swift#L275-L282)
- The CLI passes the caller's `--config` path into fact gathering: [Sources/worksync/Doctor.swift](Sources/worksync/Doctor.swift#L53-L75)
- Existing doctor tests use `/tmp/config.toml` but do not assert the remediation path: [Tests/WorkSyncCoreTests/DoctorTests.swift](Tests/WorkSyncCoreTests/DoctorTests.swift#L24-L48), [Tests/WorkSyncCoreTests/DoctorTests.swift](Tests/WorkSyncCoreTests/DoctorTests.swift#L230-L241)

**Impact**
- The diagnostic can send users to edit the wrong configuration file.
- Fixing the suggested default file will not change the failing custom-config run.

**Recommendation**
Pass `inputs.configPath` into `writabilityCheck` and use it in the remediation, with a regression test using a non-default path.

---

### 2) Medium: Doctor treats an unreadable instance lock as proof that the menu bar is running
**Why it matters**
When the doctor cannot acquire the menu-bar instance lock because of a filesystem or permission error, it returns `menubarRunning = true`. That suppresses the “nothing is scheduled” error and can make the overall scheduling check look healthy even though no running instance was established.

**Evidence**
- Lock contention and lock setup failure are distinct outcomes: [Sources/WorkSyncCore/RunLock.swift](Sources/WorkSyncCore/RunLock.swift#L50-L72)
- Doctor maps every lock exception to `menubarRunning = true`: [Sources/worksync/Doctor.swift](Sources/worksync/Doctor.swift#L101-L115)
- `SchedulingFacts.somethingWillRun` treats that boolean as a real running mechanism: [Sources/WorkSyncCore/DoctorChecks.swift](Sources/WorkSyncCore/DoctorChecks.swift#L10-L31)
- Existing tests cover synthetic `menubarRunning` values but not the fact-gathering lock-error path: [Tests/WorkSyncCoreTests/DoctorTests.swift](Tests/WorkSyncCoreTests/DoctorTests.swift#L245-L270)

**Impact**
- A broken lock directory can produce a false healthy scheduling diagnosis.
- The user may not discover that the menu bar app cannot establish its single-instance guard or that the diagnostic could not verify it.

**Recommendation**
Represent “unknown” separately from `menubarRunning = true`, and emit a skipped/error finding with the lock failure detail. At minimum, add a diagnostic detail or dedicated check so lock setup failure cannot satisfy the scheduling check silently.

## Residual Risks

### Medium: Doctor’s environment-facing path is not covered by integration tests
The pure `DoctorChecks` judgment is extensively tested, but `DoctorFacts.gather` still shells out to `launchctl`/`codesign` and queries EventKit/UserNotifications. Bundle-launched runtime checks are needed to verify that real macOS states map to the intended findings and do not prompt.

### Low: Health refresh runs during menu-bar startup before the instance lock is claimed
`MenuBarModel` refreshes health during initialization, while `AppDelegate` claims the single-instance lock immediately before creating the model. The initial scheduling finding can therefore report that the menu bar is absent before the app has claimed its lock; later pass/refresh activity corrects it, but the first displayed health state can be transiently misleading.

## Snapshot (M7 Delta)
- Review type: Delta review from the prior M6 anchor
- Baseline commit: `553e7bc83b9df57660ca4df6de92b6cdb8b8fa4a` (`553e7bc`)
- Current commit reviewed: `e50a66afe4476e69fe1c22fc003953c6d6d238b4` (`e50a66a`)
- Main feature commit in this delta: `a5a1660` - `worksync doctor` and health surfacing
- Related fixes included in the delta:
  - `cf1c294` - source-ID rename draft flow and comment-loss reporting
  - `9a172f4` - locale-independent log timestamps
  - `e50a66a` - Gregorian `{date}` rendering with localized `{weekday}`
- Working tree at review time: clean
- Review date: 2026-08-14

## Scope Reviewed
- doctor report model, severity/exit-code rules, text/JSON rendering
- read-only environmental fact gathering
- calendar access and resolution diagnostics
- scheduling, signing, notification, staleness, and log checks
- menu-bar health display and destinations
- M6 rename-flow fix and config-writer warning integration
- locale/date correctness updates

## Verification Run
- `swift test`: **187 tests, 0 failures**

## Improvements Confirmed
- Doctor shares the existing exit-code mapping and remains read-only: [Sources/WorkSyncCore/Doctor.swift](Sources/WorkSyncCore/Doctor.swift), [Sources/WorkSyncCore/DoctorChecks.swift](Sources/WorkSyncCore/DoctorChecks.swift)
- Permission states, write-only access, downstream skipped checks, resolution aggregation, notification states, JSON output, and strict mode have focused tests: [Tests/WorkSyncCoreTests/DoctorTests.swift](Tests/WorkSyncCoreTests/DoctorTests.swift)
- The M6 saved-source rename defect is addressed with a draft/commit model: [Sources/WorkSyncCore/SourceIDDraft.swift](Sources/WorkSyncCore/SourceIDDraft.swift), [Sources/worksync/MenuBar/MenuBarModel.swift](Sources/worksync/MenuBar/MenuBarModel.swift)
- Config writer comment-loss is now surfaced as a save warning rather than silently hidden: [Sources/WorkSyncCore/ConfigWriter.swift](Sources/WorkSyncCore/ConfigWriter.swift)
- Log timestamps are pinned to POSIX/Gregorian formatting while user-facing doctor dates remain localized: [Sources/WorkSyncCore/Logger.swift](Sources/WorkSyncCore/Logger.swift), [Sources/WorkSyncCore/DoctorChecks.swift](Sources/WorkSyncCore/DoctorChecks.swift)

## Assessment
The M7 doctor core is well-designed and unusually well-tested for its pure decision layer. The two medium findings are diagnostic correctness issues: custom-config remediation can point at the wrong file, and lock inspection failure can be mistaken for a healthy running menu-bar instance. Fix those before treating health reporting as fully trustworthy.
