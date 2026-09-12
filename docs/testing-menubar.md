# Testing the menu bar app

The menu bar model is tested against the real thing. Everything below the model
— SwiftUI views, the status item, the native service adapters — is not, and this
is the record of which is which.

## How to run it

```sh
swift test                      # both targets
swift test --filter WorkSyncAppTests
```

The suite must be safe on a fresh machine: **no test may prompt for calendar
access or touch `~/.config/worksync`.** `IsolationTests` asserts that rather than
assuming it, including a check that no menu bar file outside the live-services
file reaches `EventKitStore`, `DoctorFacts`, `UserDefaults.standard` or
`PassRunner` directly.

## The seam

`MenuBarModel` has one designated initializer and it is inert:

```swift
init(initialState: MenuBarInitialState, services: MenuBarServices)
```

It assigns what it is given and computes what is pure. It calls no service —
`MenuBarConstructionTests.testConstructingTheModelCallsNoService` builds one with
services that fail the test if called.

`MenuBarServices` is every effect the model has on the world outside itself:
config load/save, last-run and paused persistence, logging, the login item,
health, calendar choices, running a pass, notifications, change observation, the
clock, the debounce, and opening URLs. No operation has a live default. A service
that defaulted to the real one would make the unsafe composition the easy one to
get by accident.

`MenuBarModel.live(configPath:)` is the one production composition. It reads the
initial state, builds the real adapters, and calls `startInitialRefreshes()` —
which is what the initializer used to do at the end of itself, at the same point
in the lifecycle. `AppDelegate` calls `live`; tests call `startInitialRefreshes`
on an inert model with fakes, so startup is exercised rather than skipped.

The services value carries no decisions. Nothing in it says whether a rename is
allowed, which source owns a draft, or whether a save proceeds — those stay in
the model under test. A fake that answered them would be the hand-written mirror
this target exists to delete.

## What is covered

`Tests/WorkSyncAppTests/` drives the shipping model: opening and blocking on a
broken config, selection and its per-source drafts and row identities, the name
field's ownership, refusals and confirmations, title-filter rows and add fields,
saving (spy **and** the real `ConfigWriter` on a temporary file), reordering
through the real `moveSources`, and the effect boundaries.

## What is not, and why

SwiftUI and AppKit. A model test verifies the callback sequences it is given; it
cannot verify that SwiftUI supplies them, binds a control to the right method, or
renders an inline message.

Platform-bound, unhostable on a CI runner, and therefore manual:

| Layer | Why | How it is checked |
|---|---|---|
| `SettingsView` | SwiftUI bindings, `.disabled`, captions, focus | read the diff; AX dump below |
| `StatusItemController` | NSStatusItem, panel window behaviour | manual |
| `LiveMenuBarServices`, `UserNotifier`, `EventKitStore`, `DoctorFacts`, `LoginItem` | EventKit, UNUserNotificationCenter, SMAppService, launchctl, codesign | manual, and `scripts/check-doctor.sh` for the CLI's own output |

## Driving the real panel by hand

The technique that works, recorded because the obvious one does not:

1. Build and run against an isolated config:
   ```sh
   ./scripts/build-app.sh --adhoc --no-tar
   ./build/WorkSync.app/Contents/MacOS/worksync menubar --config /tmp/check/config.toml
   ```
2. Click the status item, then **More → Settings…**, through System Events.
3. The source list is an **`AXOutline`**. Its rows are `AXRow` children.
4. **Select a row by setting `AXSelected` on the row** (or `AXSelectedRows` on
   the outline). **`AXPress` on the row fails** with `kAXErrorCannotComplete`,
   and pressing the row's text label is not a substitute.
5. Read state back with `entire contents of scroll area 1 of group 1 of window 1`:
   static texts and pop-up button values come through. SwiftUI
   `.accessibilityLabel` on a `.toggleStyle(.button)` Toggle does **not** surface
   through System Events, so those labels can only be read in the diff.

This is a manual procedure, not an automated test. Running it against the
production bootstrap is not isolation either: `AppDelegate` takes a default
instance lock and the live services use real log and lock paths, so a temporary
`--config` alone does not make it safe to write from. An automated AX harness
needs its own bootstrap with fake services and temporary paths; that is separate
work and is not claimed here.

## Outstanding

- Native drag delivery: a captured row array does not establish which `onMove`
  closure SwiftUI retains across a re-render.
- First-click keyboard focus, menu dismissal, the selection bounce on a refused
  name.
- TCC attribution, notification banners, LaunchServices identity.
