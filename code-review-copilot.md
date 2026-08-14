# WorkSync Code Review (Copilot)

## Findings (ordered by severity)

### 1) High: The menu bar UI does not expose the required “Launch at login” control
**Why it matters**
M4 includes the login-item UX, not only the CLI commands. Users cannot enable, inspect, or disable the SMAppService login item from the menu bar panel, so the primary persistent-operation workflow is incomplete.

**Evidence**
- M4 requires the panel overflow to include “Launch at login”: [SPEC.md](SPEC.md#L288)
- The panel overflow only contains Open config, Open log, and Quit: [Sources/worksync/MenuBar/PanelView.swift](Sources/worksync/MenuBar/PanelView.swift#L135-L140)
- The context menu likewise omits login-item status/actions: [Sources/worksync/MenuBar/StatusItemController.swift](Sources/worksync/MenuBar/StatusItemController.swift#L111-L121)
- Login-item functionality exists only in the CLI command implementation: [Sources/worksync/LoginItem.swift](Sources/worksync/LoginItem.swift#L39-L69)

**Impact**
- The documented menu bar workflow cannot configure launch at login.
- Users must discover and use `worksync install-agent` manually, despite M4 presenting this as a menu-bar setting.

**Recommendation**
Expose the live `SMAppService.mainApp.status` in the panel and add register/unregister actions. Handle `.requiresApproval` by opening Login Items settings, and re-read status whenever the menu/panel is rendered.

---

### 2) High: The status icon can remain stuck in the “syncing” state after an async pass completes
**Why it matters**
The icon is required to reflect idle, syncing, error, and paused state without opening the panel. The async completion path updates `MenuBarModel.state`, but does not trigger a corresponding icon render.

**Evidence**
- `finish(_:)` changes `isSyncing` and calls `refreshState()`: [Sources/worksync/MenuBar/MenuBarModel.swift](Sources/worksync/MenuBar/MenuBarModel.swift#L112-L126)
- `StatusItemController` renders initially and schedules refreshes around timer/action starts, but does not observe model changes: [Sources/worksync/MenuBar/StatusItemController.swift](Sources/worksync/MenuBar/StatusItemController.swift#L35-L44), [Sources/worksync/MenuBar/StatusItemController.swift](Sources/worksync/MenuBar/StatusItemController.swift#L278-L311)
- The declared observation property is unused and no `withObservationTracking` re-arm is present: [Sources/worksync/MenuBar/StatusItemController.swift](Sources/worksync/MenuBar/StatusItemController.swift#L30-L34)
- The spec explicitly requires observation-driven re-rendering: [SPEC.md](SPEC.md#L304)

**Impact**
- After the first pass starts, the icon can stay on `calendar.badge.clock` indefinitely until another scheduled refresh, button action, or wake event.
- A completed failure or pause transition may not be visible in the status item promptly.

**Recommendation**
Use `withObservationTracking` around the model properties read by `renderIcon()`, re-arm the observation after every change, and retain the existing ~50 ms debounce. At minimum, schedule an icon refresh from `MenuBarModel.finish`, but observation is the contractually correct fix.

## Residual Risks

### Medium: M4 UI behavior is not covered by an actual bundle-launched smoke test
Core and policy tests pass, but the menu bar lifecycle, status-item rendering, Login Items registration, wake behavior, panel dismissal, and async state transitions still require execution from the assembled `WorkSync.app`. The current unit suite cannot prove those AppKit/LaunchServices behaviors.

### Low: Last-run and log paths ignore a custom config path
`MenuBarModel` and `Status` accept a config path, but read/write last-run data and logs through global default paths. This is acceptable for the default installation, but surprising for `--config` users and worth documenting or fixing before broader CLI use.

## Snapshot (Milestone 4 Delta)
- Review type: Delta review (M3 -> current M4-ready HEAD)
- Baseline commit: `074bbc18a993c3d812bded15291e4f4926381645` (`074bbc1`)
- Current commit reviewed: `7d287e85706f960038006c28bdc587a807b0eafb` (`7d287e8`)
- Main M4 landing commits:
  - `090a717` - SDK restamp, log rotation, last-run record, status command
  - `f778e5e` - menu bar lifecycle, NSPanel, scheduler
  - `f213ac7` - SMAppService login item and headless launchd alternative
  - `9ba825f` - close M4
- Later non-M4 changes included in HEAD: M8 doctor specification work and related planning metadata; not treated as M4 implementation scope.
- Working tree at review time: contained the existing review-file change and untracked `Sources/worksync/Init.swift` / `config.example.toml`; these were not part of the M4 findings
- Review date: 2026-08-13

## Scope Reviewed
- menu bar lifecycle and explicit delegate setup
- status item, panel, context menu, and dismissal behavior
- scheduler, wake handling, and pending-pass behavior
- logger rotation and last-run persistence
- `status`, `install-agent`, and `uninstall-agent`
- headless launchd plist generation
- M4 tests and remaining runtime-only validation gaps

## Verification Run
- Command: `swift test`
- Result: **151 tests, 0 failures**

## M4 Improvements Confirmed
- Shared `PassRunner` keeps CLI/menu-bar sync behavior aligned: [Sources/WorkSyncCore/PassRunner.swift](Sources/WorkSyncCore/PassRunner.swift)
- M4 pipeline diagnostics and last-run state are persisted without becoming reconciliation input: [Sources/WorkSyncCore/SyncPipeline.swift](Sources/WorkSyncCore/SyncPipeline.swift), [Sources/WorkSyncCore/LastRun.swift](Sources/WorkSyncCore/LastRun.swift)
- Log rotation is bounded and synchronized: [Sources/WorkSyncCore/Logger.swift](Sources/WorkSyncCore/Logger.swift)
- Lock setup failures are now distinguished from normal contention: [Sources/WorkSyncCore/RunLock.swift](Sources/WorkSyncCore/RunLock.swift)
- Panel dismissal policy and pipeline behavior have focused tests.

## Assessment
The M4 core scheduling and persistence work is solid and the test suite is healthy. The milestone is not fully complete from a user-facing perspective until the login-item control is exposed in the menu bar and status-icon rendering is made reactive to async model changes.
