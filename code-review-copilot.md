# WorkSync Code Review (Copilot)

## Findings (ordered by severity)

### 1) High: Saved source-ID renaming is effectively unusable in the settings editor
**Why it matters**
The settings form sends every `TextField` edit directly to `requestRename`. For a saved source, the first keystroke that differs from the old ID immediately presents the confirmation alert. The text field cannot accumulate a new name normally, because the alert interrupts editing while the model still holds the old ID.

**Evidence**
- The source ID field calls `requestRename` from its setter on every text change: [Sources/worksync/MenuBar/SettingsView.swift](Sources/worksync/MenuBar/SettingsView.swift#L193-L199)
- `requestRename` immediately creates `pendingRename` for any changed saved ID: [Sources/worksync/MenuBar/MenuBarModel.swift](Sources/worksync/MenuBar/MenuBarModel.swift#L335-L348)
- The alert is presented whenever `pendingRename` is non-nil: [Sources/worksync/MenuBar/SettingsView.swift](Sources/worksync/MenuBar/SettingsView.swift#L36-L57)
- There are no UI/model tests exercising the actual text-field editing flow; rename policy tests only cover the pure predicate: [Tests/WorkSyncCoreTests/SourceRenamePolicyTests.swift](Tests/WorkSyncCoreTests/SourceRenamePolicyTests.swift)

**Impact**
- A user cannot normally rename an existing source from the M6 settings screen.
- Depending on the first character and alert choice, the user either cancels back to the original value or confirms a one-character partial ID, which can orphan managed events under an unintended name.

**Recommendation**
Use a draft ID field independent of `editingConfig` while the user types. Validate/normalize it on commit, then show one confirmation alert for the completed old-to-new transition. Apply the rename only after confirmation; cancel should discard the draft without changing the working config.

---

### 2) Medium: No executable UI test protects the settings save/rename workflow
**Why it matters**
The highest-risk M6 behavior crosses SwiftUI bindings, alert presentation, working-copy state, and the comment-preserving writer, but only the pure writer and rename-policy layers are tested.

**Evidence**
- Writer coverage is extensive: [Tests/WorkSyncCoreTests/ConfigWriterTests.swift](Tests/WorkSyncCoreTests/ConfigWriterTests.swift)
- Rename coverage is policy-only: [Tests/WorkSyncCoreTests/SourceRenamePolicyTests.swift](Tests/WorkSyncCoreTests/SourceRenamePolicyTests.swift)
- The settings view has no dedicated UI/integration test target.

**Impact**
- Regressions in text editing, alert sequencing, save/cancel behavior, or source-list reorder handling can pass CI.

**Recommendation**
Add a focused model-level interaction test for draft rename lifecycle, or a macOS UI smoke test that edits a saved source ID, cancels, confirms, saves, reloads, and verifies the backup/config result.

## Residual Risks

### Medium: Config writer fallback can silently discard comments after a line-edit mismatch
The writer correctly self-checks and protects the existing file, but `verified` falls back to full serialization when line editing does not round-trip. That is permitted by the specification for unexpected line-edit failure, yet the UI reports only a successful save and does not tell the user that comments/layout were lost. Consider surfacing a warning when the fallback path is used, or make fallback an explicit result rather than an invisible behavior.

### Low: M6 review includes post-close-out platform/lifecycle changes
The current HEAD also contains `e78d6b3` (menu keyboard navigation and macOS 27 migration) and `553e7bc` (single-instance menu bar guard). These were reviewed only for scope awareness here, not as the primary M6 settings/writer implementation. They should receive a focused runtime check on the target macOS versions.

## Snapshot (Milestone 6 Delta)
- Review type: Delta review (M5 -> M6/current HEAD)
- Baseline commit: `8ff1525890feccd4e97b53b8e61dd1d3a59d2e11` (`8ff1525`)
- Current commit reviewed: `553e7bc83b9df57660ca4df6de92b6cdb8b8fa4a` (`553e7bc`)
- M6 implementation commits:
  - `ed4d412` - comment-preserving config writer
  - `a13dec5` - settings screen inside the panel
  - `6fe176b` - close M6
- Follow-up commits included in current HEAD:
  - `5f7a39c` - transparent menu bar panel fix
  - `e78d6b3` - keyboard navigation and macOS 27 migration record
  - `553e7bc` - single-instance guard
- Working tree at review time: clean
- Review date: 2026-08-14

## Scope Reviewed
- `ConfigWriter` and `TomlDocument` comment/layout preservation
- source add/remove/reorder and ID rename policy
- settings screen bindings, save/cancel, calendar pickers, and backup behavior
- panel integration and post-M6 lifecycle changes
- M6 tests and runtime-only validation gaps

## Verification Run
- `swift test`: **187 tests, 0 failures**

## Improvements Confirmed
- Config writes are self-checked, backed up, and comment-preserving on the normal path: [Sources/WorkSyncCore/ConfigWriter.swift](Sources/WorkSyncCore/ConfigWriter.swift)
- The TOML text model preserves trailing comments, section-leading comments, source block movement, and newline style: [Sources/WorkSyncCore/TomlDocument.swift](Sources/WorkSyncCore/TomlDocument.swift)
- M6 writer coverage includes no-op byte identity, scalar edits, trailing comments, source add/remove/reorder, serialization fallback, backup creation, and refused invalid writes: [Tests/WorkSyncCoreTests/ConfigWriterTests.swift](Tests/WorkSyncCoreTests/ConfigWriterTests.swift)
- Settings is integrated as an in-panel screen with calendar choices, source ordering, save/cancel, and rename warning surfaces: [Sources/worksync/MenuBar/SettingsView.swift](Sources/worksync/MenuBar/SettingsView.swift)

## Assessment
M6’s config writer and settings architecture are strong and well-tested at the core layer. The saved-source rename interaction is a release-blocking UX/data-integrity issue for the settings editor and should be fixed before calling the M6 UI complete.
