---
# worksync-x7nc
title: 'A test target for the menu bar app'
status: completed
type: chore
created_at: 2026-09-12T03:37:41Z
updated_at: 2026-09-12T12:00:00Z
---

The settings UI (PR #7, v0.4.0) took **eleven fix rounds**. Every defect was
real and most silently lost user input. None were found by a test — all of them
were found by reading code, because nothing in this package can exercise the
menu bar target.

That is the root cause worth fixing, not any individual bug.

## What the gap actually is

`Package.swift` declares one test target, `WorkSyncCoreTests`, on
`WorkSyncCore`. `MenuBarModel` and `SettingsView` live in the `worksync`
executable target, which has none. So:

- no test can import the model;
- round 7 had to drive a hand-written `Editor` mirror of the model's
  composition, which passes even if the real model drifts from it;
- `MenuBarModel.init` calls `refreshLoginItemStatus()` and `refreshHealth()`,
  so constructing one in a test reads UserDefaults, loads config and last-run
  files, creates the real log directory, reads `SMAppService`, and starts health
  gathering. Unsuitable for an isolated unit test.

## What eleven rounds cost, concretely

Defects that a driven UI would have caught immediately, each found by reading:

- a draft typed for source A saved onto source B
- an emptied row disabling Save with no visible reason
- a stale save error masking the live validation message
- an index trap while a text field resigned focus
- a late row commit silently overwriting a **different** row
- a late setter from a live-but-unselected source erasing the current draft
- a refused rename silently swallowed, discarding the user's typed name
- a drag reordering the wrong source after the list changed

Four separate attempts by two agents failed to drive the panel at all. The fifth
succeeded only after discovering the list is an `AXOutline` with `AXRow`
children — every earlier attempt had been clicking the label inside a row.

## Shape of the work

[x] Extract the model's construction so it can be built without `SMAppService`
      or EventKit — inject those, or split an inert init for tests
[x] Add a test target covering the `worksync` target, and delete round 7's
      `Editor` mirror in favour of testing the real model
[x] Decide whether XCUITest for the panel is worth it, or whether model-level
      coverage plus the AX technique below is enough
[x] Record the AX technique that works, so nobody rediscovers it:
      the settings list is an `AXOutline`; `AXPress` on a row fails
      (`kAXErrorCannotComplete`), but setting `AXSelected` on the row, or
      `AXSelectedRows` on the outline, works

## Related
- `worksync-p3wk`, `worksync-v8xr`, `worksync-h4pd`, `worksync-t4qp` —
  all of them are settings-editor work that this would make testable

## Correction (2026-09-12, from the design round)

Two claims above were wrong, and the design round disproved both by experiment
rather than argument:

- **It does not fire a calendar prompt at construction.** `DoctorFacts.gather`
  calls `authorizationStatus()`, not `requestAccess()`. The prompt-capable paths
  are *after* construction — `openSettings` → `loadCalendarChoices` and
  `syncNow` → `PassRunner` both request access. So injecting only health and
  login providers would leave tests unsafe the moment they exercise the very
  behaviour this bean exists to cover.
- **An executable target is not an absolute SwiftPM testing barrier.** Two
  scratch experiments (logs: `/tmp/x7nc-executable-probe.log`,
  `/tmp/x7nc-target-probe.log`) showed a test target importing an executable,
  including this repository's own sources via `@testable import worksync`,
  without running `main`. The blanket advice predates SwiftPM work on this.

  Caveat kept deliberately: those ran on Apple Swift 6.3.3. The first
  implementation gate is reproducing the import test on the macos-15 CI
  toolchain before anything is built on the assumption.

## Landed
`WorkSyncAppTests` imports the `worksync` executable target directly — the gate
the design called for, confirmed on CI (macos-15, Swift 6.1.2, run 34700234885)
and locally, with `main` not running. The `WorkSyncUI` fallback was not needed,
and no production file moved.

`MenuBarModel` gained an inert designated initializer plus `MenuBarServices`,
and `MenuBarModel.live(configPath:)` is the one production composition.
`AppDelegate` is the only call-site change. Construction now calls no service,
and the paths that can prompt — `openSettings` → calendar choices, `syncNow` →
the pass — are injected too, which is what makes the suite safe rather than
merely quiet at init.

The hand-written `Editor` in `Tests/WorkSyncCoreTests/SettingsSelectionTests.swift`
is deleted; its whole inventory now runs against the real model.

Mutation evidence, reverting each production decision in turn and recording
which app tests fail: per-handle drafts (2), the name field's ownership check
(2), row identity (4), the drag snapshot (3), the pending-confirmation check
(1), and consulting the commit outcome (14).

Not closed by this: SwiftUI bindings and rendering, native drag delivery, and
anything needing a GUI session. `docs/testing-menubar.md` records the carve-out
and the `AXOutline` selection technique that works, since `AXPress` on a row
does not.
