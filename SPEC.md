# WorkSync — local calendar blocker sync for macOS

## 1. Purpose

A native macOS tool that mirrors busy time from one or more source calendars (personal, travel, etc.) onto a work calendar as sanitized blocker events, without any third-party service touching the work account. All reads and writes go through EventKit against accounts already configured in macOS, so corporate infrastructure only ever sees native Calendar.app sync traffic.

Replaces Reclaim.ai calendar sync for environments where connecting the work calendar to external SaaS is prohibited.

## 2. Non-goals

- **No two-way sync.** Work calendar content is never read except for reconciliation and conflict checks, and never copied anywhere.
- **No Reclaim.ai API integration.** Reclaim writes its output into the personal Google calendar, which is consumed here as a plain source calendar.
- **No cloud component, no network calls, no telemetry.** The tool is fully offline; calendar servers are reached only by macOS itself.
- **No UI is ever *required* to operate the sync, and no cloud- or network-backed configuration.** This is a constraint on dependence, not on ambition: the menu bar app should be a genuinely well-designed piece of software (§11), not a bare list of menu items. What it may never become is the only way in. Two rules make that concrete, and both are load-bearing rather than stylistic:
  1. **Every capability is reachable from the CLI** (§8), and a full sync runs headless with no UI process alive. This is what makes the tool scriptable, debuggable over SSH, and survivable when the UI breaks.
  2. **`config.toml` is the single source of truth**, hand-editable, and never replaced by a UI-owned store. Any UI that writes it round-trips through the comment-preserving writer (§4.3). A UI that owned the configuration would rebuild, locally, exactly the opaque SaaS this tool exists to avoid.
- **No main application window.** The only surface is the menu bar status item and its panel (§11), which contains the settings screen (§11.1). A document-style or dashboard-style main window is out of scope.
- **No Xcode project.** The repository must build, test, and package entirely from the command line with SwiftPM. Packaging includes assembling a real `WorkSync.app` bundle (§3.1) — done by a shell script, still no `.xcodeproj` and no `xcodebuild`.

## 3. Architecture

**Language/tooling:** Swift 5.10+, Swift Package Manager only — no `.xcodeproj`, no `xcodebuild`. Everything builds with `swift build`, tests with `swift test`, on any machine with the Xcode command-line toolchain. Dependencies: swift-argument-parser (CLI), TOMLKit (config), EventKit and AppKit (system frameworks).

**Repository layout:**

```
Package.swift
Sources/WorkSyncCore/       # pure logic: config, planner, markers (no EventKit/AppKit)
Sources/WorkSyncKit/        # EventKit adapter behind CalendarStore protocol
Sources/worksync/           # executable: CLI entry + menu bar mode
Tests/WorkSyncCoreTests/
Resources/Info.plist        # bundle plist, copied to WorkSync.app/Contents/ by build-app.sh
Resources/worksync.entitlements  # hardened-runtime entitlements (calendars)
Resources/AppIcon.icns      # app icon, generated from assets/icon-1024.png
assets/icon-1024.png        # icon master (designed asset)
scripts/build-app.sh        # release build + .app assembly + codesign + tarball (§3.1)
```

**Execution model:** one binary, two modes.

- `worksync sync` — stateless one-shot reconciliation pass, exits (usable manually, from CI smoke tests, or from cron-like schedulers).
- `worksync menubar` — long-running NSStatusItem app (§11) that owns the schedule: runs the same sync pass on a timer every `interval_minutes` and displays progress/status. An SMAppService login item (§10) launches this mode at login.

Both modes call the identical SyncEngine; no logic may live only in one mode. No local database — all reconciliation state is encoded in the managed events themselves (§7). The one exception is a small last-run record (timestamp, success, summary) persisted alongside the config for the menu bar header and `worksync status`; it is display state only and is never an input to reconciliation.

**Packaging:** SwiftPM produces a plain Mach-O executable; `scripts/build-app.sh` wraps it into a real `WorkSync.app` bundle (§3.1). This needs no `.xcodeproj` — the bundle is a directory layout plus a plist, assembled by ~30 lines of shell around `swift build`. The bundle is required, not cosmetic: `UNUserNotificationCenter`, `SMAppService.mainApp`, and `LSUIElement` all hard-require a genuine registered app bundle (§3.1, §10, §11.2).

`Info.plist` ships as a normal file at `WorkSync.app/Contents/Info.plist` with: `CFBundleIdentifier` `io.gamov.worksync`, `CFBundleExecutable` `worksync` (must exactly match the binary filename), `CFBundlePackageType` `APPL`, `CFBundleName` `WorkSync`, `CFBundleShortVersionString`/`CFBundleVersion`, `LSMinimumSystemVersion`, `CFBundleIconFile` `AppIcon`, `NSCalendarsFullAccessUsageDescription`, and `LSUIElement = true`. With a real bundle, `LSUIElement` alone gives accessory behavior (no Dock icon, no launch flash) — do NOT also call `NSApp.setActivationPolicy(.accessory)` unconditionally at startup. Nothing in v1 needs the runtime activation-policy API at all: the panel is a non-activating key-capable `NSPanel` and settings live inside it (§11.0, §11.1), so there is no window to front.

**Permissions:** requires Calendar full access (read sources + read/write work calendar): `requestFullAccessToEvents()` on macOS 14+ (the legacy `requestAccess(to:)` is not merely deprecated — on current OSes it no longer prompts and immediately completes with an error). The bundle must be code-signed with a stable identity so the TCC grant survives rebuilds. This matters more than it sounds: TCC keys grants on the signature's *designated requirement*, and an ad-hoc signature's designated requirement is a bare cdhash that changes on every build — so with ad-hoc signing, every rebuild is a new identity and the calendar grant (plus Gatekeeper approval) resets. A self-created code-signing certificate (Keychain Access → Certificate Assistant, trust set to Always Trust for Code Signing) yields an identifier-anchored requirement that survives rebuilds.

`scripts/build-app.sh` signs with it:

```
codesign --force --sign "<identity>" --timestamp --options runtime \
  --entitlements Resources/worksync.entitlements WorkSync.app
codesign -d -r- WorkSync.app   # designated requirement must NOT be a bare cdhash
```

A bare-cdhash designated requirement means the identity wasn't picked up and grants will not stick — the build script fails on it. Because the app signs with hardened runtime (`--options runtime`; required if it is ever notarized), the entitlements file must include `com.apple.security.personal-information.calendars` — hardened runtime denies protected-resource access without it. Never use `codesign --deep` (deprecated for signing since macOS 13; sign nested code inside-out if any ever exists). Keep the bundle's on-disk path and `CFBundleIdentifier` stable across versions — TCC and notification grants key on them too. Document in README that the first sync run must happen interactively (Terminal receives the TCC prompt) before enabling the login item.

### 3.1 App bundle from SwiftPM — assembly rules and known traps

The repository still contains no `.xcodeproj` (§2), but the shipped artifact is a genuine `WorkSync.app` bundle assembled by `scripts/build-app.sh`. This section is binding for that script and for the app-lifecycle code.

1. **Bundle assembly** (`build-app.sh`, in this order): `swift build -c release`; create `WorkSync.app/Contents/{MacOS,Resources}`; copy the binary to `Contents/MacOS/worksync`; copy any SwiftPM-emitted `<Package>_<Target>.bundle` resource bundles from `.build/release/` into `Contents/Resources/` (`Bundle.module` traps at runtime without them); copy `Resources/Info.plist` to `Contents/` and `Resources/AppIcon.icns` to `Contents/Resources/`; codesign as specified in §3 and verify the designated requirement; finally register with LaunchServices: `lsregister -f WorkSync.app` (path: `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`). The menubar app must be launched through LaunchServices (`open WorkSync.app`, or the login item) — launching `Contents/MacOS/worksync` directly does not give the process a bundle identity, and `UNUserNotificationCenter` either crashes (uncaught `NSInternalInconsistencyException`, "bundleProxyForCurrentProcess is nil") or reports every notification setting NotSupported. The plain CLI subcommands (`sync`, `calendars`, `purge`, …) may be invoked as `WorkSync.app/Contents/MacOS/worksync <cmd>` from a terminal; only notification posting and login-item registration require the LaunchServices launch path. Ship a small install step (or README instruction) that symlinks the inner binary onto PATH for CLI use.
2. **`UNUserNotificationCenter` is the notification mechanism** (§11.2) — the bundle exists largely to make it legal. Requirements: signed bundle, LaunchServices-registered, launched via the bundle. Authorization is keyed to `CFBundleIdentifier`; changing the identifier resets it to NotDetermined. Because "signed bundle accepted as a real app" has failure modes that only manifest at runtime (settings all NotSupported), M1 includes a smoke test: build the bundle, launch it, and confirm the notification authorization prompt actually appears before any milestone depends on it. Keep the osascript `display notification` fallback (escaped for AppleScript string literals, backslashes first then double quotes) available behind the same Notifier protocol, used only if UN authorization is denied or unavailable.
3. **App lifecycle:** `main.swift` explicitly creates the NSApplication, instantiates the AppDelegate, assigns `NSApp.delegate`, and then calls `NSApp.run()`. Do not use `@main`/`@NSApplicationMain` in the menubar target: with no nib/storyboard, `NSApplicationMain` reaches `[NSApplication run]` without ever instantiating the delegate, so setup code silently never executes — a failure that presents as "nothing in my app runs".
4. **Swift concurrency:** normal structured concurrency is fine in this process. `NSApplication.run()` spins the main CFRunLoop, and draining the main-actor executor (the main dispatch queue) is one of the run loop's jobs — a `Task { }` created from `@MainActor` context runs once the run loop is going. (An earlier revision of this spec claimed the main-actor executor is never drained in a SwiftPM-built process and mandated `Task.detached` + `RunLoop.main.perform` everywhere; that claim did not survive verification and the mandate is withdrawn.) The two real traps to avoid: (a) a Task created before `NSApp.run()` is reached sits pending until the run loop starts — don't misread "runs later" as "never runs"; (b) `Task { }` only inherits main-actor isolation when the enclosing context is actually isolated — in non-isolated contexts (e.g. a notification callback on an arbitrary queue) write `Task { @MainActor in ... }` explicitly. If a pass-in-flight flag ever latches (§11 pending-pass rule), suspect these two and the delegate trap in rule 3 before suspecting the framework.
5. **SwiftUI hosting:** all SwiftUI is hosted via `NSHostingController` inside AppKit windows this process owns — never a SwiftUI `App`, `Settings`, or `MenuBarExtra` scene, which conflict with the `NSApplication` + app-delegate lifecycle established in rule 3. In v1 there is exactly one such surface, the menu bar panel (§11.0), and settings live inside it as a screen rather than in a second window (§11.1). If a real `NSWindow` is ever added, its `styleMask` must include `.fullSizeContentView` — without it a `NavigationSplitView` sidebar cannot extend to full height and its toggle misbehaves, which is a window-configuration defect, not a hosting-mode one.
6. **SDK version stamp (required before the M4 UI, not before):** SwiftPM stamps the binary's `LC_BUILD_VERSION` `sdk` field with the *deployment target*, not the SDK it actually compiled against. macOS gates modern (Liquid Glass) control appearance on the linked SDK version, so a binary stamped `14.0` silently renders legacy Aqua controls no matter what the code does — there is no error and nothing to debug, the UI is just quietly wrong. The fix is a `vtool -set-build-version macos <deployment-target> <sdk-version> -replace` restamp of `Contents/MacOS/worksync` **before** the codesign step (restamping after signing invalidates the signature). This is deliberately not in `build-app.sh` yet: M1 has no UI, and the signing pipeline is verified working (§15), so the restamp lands with M4 and is re-verified against the TCC/Gatekeeper chain then.
7. **General principle:** when a framework feature "does nothing" or crashes for no apparent reason, verify the packaging first (signature, LaunchServices registration, launch path, SDK stamp) — most "broken framework" symptoms in this architecture are assembly mistakes. Prefer explicit, state-driven implementations over behaviors that depend on a scene lifecycle, and verify UI behavior against the actually running app rather than assuming a documented API works here.

## 4. Configuration

Config lives at `~/.config/worksync/config.toml`. Example:

```toml
[general]
window_days = 21            # rolling sync horizon from "now"
interval_minutes = 10       # menu bar sync timer (and --headless agent interval)
timezone = "system"         # reserved; v1 always uses system tz
log_level = "info"          # error | warn | info | debug
notify = "errors"           # off | errors | always — desktop notifications
                            # after a menu bar pass (§11.2)
change_driven = false       # opt-in EKEventStoreChanged fast path (§11.2)
change_debounce_seconds = 20 # coalescing window for change-driven triggers

[target]
account = "Confluent Exchange"    # EKSource title of the work account
calendar = "Calendar"             # calendar title within that account

# --- Source definitions. Order matters: first matching source wins
# --- when the same underlying event appears in multiple sources.

[[source]]
id = "personal"                    # stable slug, used in event markers
account = "iCloud"                 # or "Google" — EKSource title
calendar = "Personal"              # source calendar title
title_template = "Busy"            # what appears on the work calendar
target_calendar = ""               # empty = use [target].calendar
coalesce = true                    # merge overlapping/adjacent events
coalesce_gap_minutes = 15          # gaps <= this are merged
min_duration_minutes = 15          # ignore shorter source events
max_duration_minutes = 0           # 0 = unlimited; ignore longer source events
skip_weekdays = []                 # e.g. ["sat", "sun"] — days never mirrored
padding_before_minutes = 0
padding_after_minutes = 0
include_all_day = false
skip_if_work_busy = true           # don't create block if work calendar
                                   # already has a non-worksync event
                                   # overlapping >= 80% of the interval
availability = "busy"              # busy | free | tentative

[[source]]
id = "travel"
account = "Google"
calendar = "Travel"                # e.g. TripIt/Flighty-fed calendar
title_template = "✈️ Flight"
target_calendar = "Travel Blocks"  # separate work calendar => distinct
                                   # color in Calendar.app/Outlook
coalesce = false                   # each flight stays a discrete event
min_duration_minutes = 0
padding_before_minutes = 120       # airport buffer before departure
padding_after_minutes = 60
include_all_day = true             # multi-day trips as all-day blocks
skip_if_work_busy = false          # flights always get blocked
availability = "busy"
```

### 4.1 Config semantics

- Every `[[source]]` is fully independent: its own filters, templates, padding, coalescing, and target calendar. Adding a new source must require config changes only, no code changes.
- `title_template` supports optional placeholders, all privacy-safe: `{date}` (source event start date, yyyy-MM-dd), `{weekday}`. Never expose source titles, locations, attendees, or notes. No other placeholders in v1.
- Calendar/account resolution: match `EKSource.title` then `EKCalendar.title`, case-insensitive. If ambiguous or not found, fail the run with a clear error listing available sources/calendars (`worksync calendars` prints this list).
- Config validation runs before any calendar mutation. Invalid config = non-zero exit, no writes.
- **Source order is semantically load-bearing, not cosmetic.** The first-listed source wins cross-source dedup (§5 step 5), so reordering `[[source]]` blocks silently changes which source's title/target calendar/padding a shared event gets — with no error and no warning anywhere in the pipeline. Any tool that writes this file must preserve source order exactly, and any editing UI must support reordering (§11.1), not just add and remove.
- A source's `id` is embedded verbatim in every managed event's marker (§7). Renaming an id orphans every event created under the old id: the new id will never match them, so they are never updated and never deleted by a normal sync — they are reachable only via `worksync purge --source <old-id>`. This is a data-integrity concern, not a UI nicety: any tool that writes config.toml must warn before committing an id rename on an existing source, and must tell the user the purge command that recovers the orphans. Ids of brand-new sources need no warning, since nothing exists under them yet.
- `max_duration_minutes` (0 = unlimited) drops absurdly long timed events — usually informational entries from subscribed calendars — that would otherwise paint one enormous block hiding the real meetings underneath. Three rules: it applies to **timed events only** (all-day is already gated by `include_all_day`, and every all-day event exceeds any sane maximum); it is measured on the **raw event, before padding**, so unrelated config cannot decide eligibility; and it does **not** apply to coalesced clusters, because a long block built from back-to-back real meetings is honest busy time. Because it is per-source, a travel source that must keep 12-hour flights (§9) simply leaves it at 0. Validation rejects a maximum below the minimum, which would silently mirror nothing.
- `skip_weekdays` (e.g. `["sat", "sun"]`) never mirrors events falling on those days. The motivation is privacy, not tidiness: even a sanitized `Busy` block reveals that the user has weekend commitments, and a run of them reveals a pattern — exactly the signal the rest of this design avoids leaking. **The rule is whole-interval: an event is dropped only when every minute of it falls on a skipped day.** Testing the start day instead would drop a Saturday 23:00 → Monday 02:00 event that covers Monday morning, which under-blocks and risks a double-booking; over-blocking is merely untidy, so the filter fails in the safe direction (the same principle as treating indeterminate availability as busy). Weekdays are evaluated in the system timezone, consistent with `{date}`/`{weekday}` rendering. Skipping all seven days is a config error.
- Both filters run in the step-3 eligibility pass, which puts them before padding, before coalescing, and before cross-source dedup — so a filtered-out event never claims an identity and never blocks a later source from mirroring it (§5 step 5).
- `notify`, `change_driven`, and `change_debounce_seconds` affect the menu bar mode only; the one-shot CLI ignores them.

### 4.2 Event coloring — constraint and approach

EventKit does not support per-event colors; in Calendar.app an event's color is its calendar's color, and Exchange category colors are not writable via EventKit (the `CATEGORIES` iCalendar property is not surfaced by EventKit in any form — this is a platform-level gap, and Apple's own Calendar app has the same limitation). Therefore per-source visual distinction is achieved by:

1. **`target_calendar` mapping** (primary mechanism): each source may write into a different calendar under the work account (e.g. main calendar for Busy, a secondary "Travel Blocks" calendar for flights). The user sets calendar colors once in Calendar.app/Outlook. The tool must NOT create calendars automatically; if the configured target calendar doesn't exist, error out and instruct the user to create it (creating calendars on a corporate Exchange account may be restricted).
2. **`title_template` prefixes** (fallback): emoji/text prefixes distinguish sources even when they share one target calendar.

Document both in README, including the caveat that secondary Exchange calendars may not count toward free/busy for coworkers scheduling against the user — recommend `availability = "busy"` and note that if colleagues' scheduling assistants must see the time as busy, the main calendar is the safe target.

### 4.3 Writing config.toml back to disk — required design

config.toml is hand-editable by definition (§2), which means anything that writes it programmatically (the editor window in §11.1, or any future tool) must return a file the user still recognizes. TOML libraries in this ecosystem — TOMLKit specifically, which wraps toml++ — discard comments at parse time and expose no comment API; worse, toml++ serialization also reorders keys alphabetically and drops blank-line structure. So the obvious load-parse-reserialize round trip doesn't merely strip every comment — it rewrites the file's entire visual organization. No Swift TOML library preserves comments (the format-preserving implementations live in Python's `tomlkit` and Rust's `toml_edit`; the TOML spec itself declined to standardize round-trip fidelity). The example config above is comment-dense by design; losing those comments is unacceptable data loss.

The required approach is line-level text editing of the original file, not re-serialization:

1. Diff the previously-loaded config against the new config field by field.
2. For each changed scalar field, locate its existing line in the original text and rewrite only that line's value, preserving any trailing `#` comment on the same line.
3. Treat each `[[source]]` block as a movable, insertable, deletable chunk of text: existing sources are matched by id and edited in place, new sources get a synthesized block appended, removed sources have their whole block dropped, and final block order follows the new config's source order (this is what makes drag-reordering in a UI actually change dedup behavior, per §4.1).
4. Run a full round-trip self-check before committing: re-parse the produced text through the normal config loader and refuse to write anything that doesn't come back clean. This guarantees a writer can never hand the next sync pass a file that fails to load.
5. Copy the existing file to `config.toml.bak` before overwriting.
6. Fall back to a plain full serialization (accepting comment loss) only when there is no previous config to diff against — a brand-new file — or when the line-level edit unexpectedly fails its own round-trip check. The fallback output is subject to the same self-check and backup.

## 5. Sync pipeline (per run)

1. Load + validate config. Resolve all source and target calendars.
2. Compute window: `[now - 1h, now + window_days]`. The 1h lookback catches events that just started.
3. Fetch source events per source via `EKEventStore.predicateForEvents`. Recurring events must be expanded to concrete instances (EventKit does this natively via the predicate). Apply per-source filters:
   - drop events where the user's own attendee status is declined
   - drop events whose own EventKit availability is free. This is a spec'd behavior, not an incidental filter: an event the user explicitly marked "Free" in Calendar.app (informational/transparent entries like "School half day" or "No school") is not busy time and must never become a blocker on the work calendar. The check is on the source event's own availability value, not the source's configured availability output.
   - drop all-day events unless `include_all_day = true`
   - drop events shorter than `min_duration_minutes`
4. Transform to desired intervals: apply padding, then (if `coalesce = true`) merge intervals within the same source whose gap ≤ `coalesce_gap_minutes`. Coalescing never crosses source boundaries. Finally, restrict to the window by FILTERING: keep an interval if it overlaps the window at all, drop it otherwise, and never truncate or clamp its start/end to the window's edges. This is a hard rule. The window is rolling — both bounds are pinned to now and drift forward on every run — so truncating an interval to a window edge makes the stored value for any event straddling that edge change on every single pass, producing an endless stream of spurious updates and permanently breaking the "sync twice with no source changes performs zero writes" invariant (§15). A blocker whose real bounds extend slightly past the nominal window is harmless; non-convergent reconciliation is not.
5. Cross-source dedup: if two sources produce intervals from the same underlying event, the earlier-listed source wins. The identity key is the tuple `(calendarItemExternalIdentifier, occurrenceDate)` — never the identifier alone, and `occurrenceDate` rather than the occurrence's current start time. In EventKit, every occurrence of a recurring event shares one `calendarItemExternalIdentifier`, so keying on the identifier by itself makes a single source's own 2nd, 3rd, … occurrences look like duplicates of its first and silently drops them, which then deletes already-synced blockers on the work calendar. `occurrenceDate` (Apple: "the original occurrence date… remains the same even when the event has been detached and its start date has changed") is used instead of `startDate` so that a user dragging one occurrence of a recurring series to a new time keeps the same identity — an in-place update, not a delete+create (§6). For non-recurring events `occurrenceDate` equals the start date, so the tuple still implements genuine cross-source dedup correctly: a truly duplicated occurrence appearing in two sources matches on both fields. Two EventKit caveats to encode, not assume away: `calendarItems(withExternalIdentifier:)` returns an *array* (external identifiers are not guaranteed unique — handle multiple matches), and on Exchange the external identifier differs between devices, so markers written by this Mac are machine-local (fine for v1, which always runs on one machine; do not build cross-device features on these identifiers). Only an event that passes its own source's eligibility filters (step 3) claims its identity: an event a source filters out must never block a later source from producing that event.
6. Fetch existing managed events on all target calendars in the window: any event carrying a worksync marker in either of its two locations (§7). Everything else fetched here is a real work event and feeds step 7.
7. Conflict check: for sources with `skip_if_work_busy = true`, drop desired intervals overlapped ≥ 80% by real (non-managed) events on that block's own target calendar. The non-managed intervals come from the step-6 fetch already made — no second round trip to the calendar store. Overlap must be computed as the UNION of the busy intervals covering the block, not as a sum of each busy event's duration: work calendars routinely contain double-booked or nested meetings, and naive summing double-counts that time and can push a barely-covered block over the threshold. Concretely: clip each busy interval to the block's bounds, merge the clipped intervals (zero-gap coalescing), sum the merged spans, and divide by the block's duration. Skipped blocks are simply excluded from the desired set handed to reconciliation, so a block that becomes newly conflicted on a later run is deleted through the normal delete path with no special-casing.
8. Reconcile (§6).
9. Report: log summary line `created=N updated=N deleted=N skipped=N unchanged=N`; with `--dry-run`, print the full plan and exit without mutating.

## 6. Reconciliation

Desired state = set of (target calendar, interval, title, availability, marker key). Existing state = managed events found in step 6.

- Match existing→desired by marker key.
- Create desired entries with no existing match.
- Update in place when the matched event's interval, title, availability, all-day flag, or target calendar differs from desired — typically because config changed (padding, title template, target calendar) or the source event's duration changed while keeping its start. Prefer update over delete+create to avoid notification noise on Exchange.
- Delete managed events whose key is no longer desired (source event deleted, moved out of window, or now filtered). Never delete anything lacking a valid worksync marker — this is a hard safety invariant. Enforce it structurally: the existing-state set handed to the diff must already be restricted to events carrying a valid v1 marker, so a delete for an unmarked event is unrepresentable rather than merely unlikely.
- Everything that removes an event from the desired set converges through this one delete path — no feature needs its own deletion logic. A source event the user re-marks "Free" in Calendar.app is dropped by the step-3 filter, falls out of the desired set, and its blocker is deleted on the next pass. The same holds for a newly conflicted block (step 7), a source removed from config, and a source event deleted outright.
- Matching key note: the marker key incorporates `occurrenceDate`, not the occurrence's current start time (§5 step 5, §7). Consequences: dragging one occurrence of a recurring series to a new time keeps its key (`occurrenceDate` is stable across detachment), so it reconciles as one in-place update; moving a non-recurring event changes its `occurrenceDate`, so its old key disappears and a new one appears — one delete plus one create rather than one update. Both are correct and idempotent — the next pass converges to unchanged.
- Events outside the window are left untouched (they'll be reconciled when the window reaches them; stale past blockers are harmless and must not be purged automatically).

## 7. Marker scheme (idempotency & state)

Each managed event carries a marker:

```
worksync://v1/<source_id>/<key>
```

- For non-coalesced events: `<key>` = SHA-256 (first 16 hex chars) of the source event's `calendarItemExternalIdentifier` + `occurrenceDate` timestamp (stable across detached-occurrence moves; disambiguates recurring instances — §5 step 5).
- For coalesced blocks: `<key>` = hash of the sorted list of constituent identifiers+occurrenceDates. Any change in constituents produces a new key → clean update path via delete+create of the block.
- Set event notes to a fixed human-readable line: `Managed by worksync — do not edit; changes will be overwritten.`
- Parsing tolerates unknown future versions (skip, warn) but only v1 markers are ever deleted/updated.
- **The notes line is the PRIMARY marker location; the url field is supplementary.** This ordering is forced by the backends, not a style choice: Google's CalDAV explicitly does not support user-settable URL properties, and Exchange drops the field too — the whole url field, regardless of scheme, so on this tool's own target (Exchange) and its typical sources (Google) a url-only marker would simply not round-trip. Every managed event is therefore written with the marker as the last line of its notes (under the fixed human-readable line above) AND in its url field; the url copy costs nothing and survives on backends that keep it (iCloud). Parsing checks the notes last-line first and falls back to url, accepting either — both locations must be checked, since an event written on one backend may be read back with only one intact. Because notes are user-visible and user-editable, parse the marker line defensively (exact-prefix match, tolerate surrounding whitespace/edits elsewhere in notes). An event with a marker in neither location is not ours and must never be touched (§6).
- The source id is embedded in the marker verbatim, which is what makes renaming a source id in config an orphaning operation (§4.1). A purge filtered by source id (§8) is the only way to reach the stranded events afterwards.

## 8. CLI

```
worksync sync [--dry-run] [--config PATH] [--verbose]
worksync menubar              # run as menu bar app (scheduler + status UI, §11)
worksync calendars            # list accounts + calendars with identifiers
worksync status               # count of managed events per source, last-run info
worksync purge [--source ID] [--yes]   # delete ALL managed events (or one source's)
worksync install-agent        # register login item (SMAppService); --headless for launchd
worksync uninstall-agent
worksync version
```

- `purge` is deliberately not bound to the rolling sync window: it scans every calendar on every account, not just the currently configured targets, so it can also collect events stranded by a since-changed config (a renamed source id, a retargeted calendar). Without `--yes` it only prints the count it would delete. With `--source ID` it deletes only that source's events, which is the documented recovery path for an id rename (§4.1).
- **Scan span limit — mandatory:** `EKEventStore.predicateForEvents` is documented by Apple to match only a four-year span — a wider range "is shortened to the first four years", silently, with no error and no truncation flag. This is arguably worse than returning nothing: a naive "all of time" purge query returns a plausible-looking result set that quietly ends four years after its start date, so purge reports success while leaving newer managed events in place. purge must query a bounded span; 365 days each direction from now (730 days total) is the specified value — comfortably under the limit while covering any realistic backlog. The same constraint binds any other broad EventKit query added later: any query that could exceed 4 years must be chunked into ≤4-year segments and unioned, and an apparently complete result must never be assumed to cover the requested range. (Apple's own guidance: use the shortest range possible.)
- **Purge exit semantics — a complete sweep is part of the contract.** `purge` exits 0 only when it could scan every calendar *and* did everything asked of it. It exits 3 when any calendar could not be scanned, when a deletion failed, or when another worksync process held the run lock. This matters because purge's answer is a negative claim: "no managed events found" after a sweep that could not look everywhere is a false statement, and automation that trusts a 0 would conclude cleanup was complete. A non-zero exit always means "managed events may remain; safe to re-run". Note the asymmetry with `sync`: a sync that loses the lock exits 0 because the process holding it is doing that same work, whereas the process holding it against a purge is running a *sync* — nobody is doing the purge, so reporting success would be a lie.
- Because purge intends to delete, it takes the run lock **before** scanning, so the sweep cannot observe a calendar that a sync pass is midway through writing. A count-only run (no `--yes`) mutates nothing and therefore takes no lock.
- Exit codes: 0 success, 1 config/validation error, 2 permission error (with remediation text), 3 partial failure (some writes failed, a backend call failed, a sweep was incomplete, or the run lock was unavailable; safe to re-run). The mapping is a pure function in the core (`ExitCodes.code(for:)`) so it stays unit-testable and no error path can silently bypass it — an uncaught error reaching the argument parser would collapse every failure onto one status. Anything unrecognized maps to 3, never to 1: reporting a runtime failure as a config error sends the user to edit a file that is not the problem.
- **CLI parity is a standing requirement, not a v1 convenience.** Every capability the menu bar app exposes must also be reachable from the CLI (§2). When §11 or a later milestone adds a UI affordance, the corresponding subcommand ships with it — the UI may present something more nicely, but it may never be the only way to do it.
- All output to stdout/stderr; when run unattended (login item or launchd), logs also append to `~/Library/Logs/worksync/worksync.log` with size-based rotation (keep 5 × 1 MB).

## 9. Edge cases & rules

- Timezones: operate in absolute time (Date); intervals compare in UTC. Titles with `{date}` render in system timezone.
- All-day events: when included, create the blocker as all-day on the same date span with availability per config.
- Multi-day timed events (e.g. long-haul flights crossing midnight): keep as a single timed event; do not split.
- Duplicate calendars/accounts with same title: hard error, ask user to disambiguate (v1 keeps config simple; identifiers-based selection can come later).
- Source == target guard: refuse to run if any source calendar resolves to a target calendar (prevents feedback loops).
- **Exactly one menu bar instance.** The app takes a second, separate flock on `~/.config/worksync/.menubar.lock` and holds it for its whole lifetime; a second instance finds it held, says so, and terminates. Two instances mean two status items, which reads as a bug in the app rather than in how it was started — and it is easy to reach, since `open WorkSync.app` and running the inner binary from a terminal are both normal things to do. Two details are load-bearing: it must be a **kernel flock rather than a LaunchServices/`NSRunningApplication` check**, because that snapshot can still list an instance midway through exiting and deferring to a corpse leaves *zero* instances running; and the code **must `return` immediately after `NSApp.terminate(_:)`**, which unwinds asynchronously and can be cancelled, so execution otherwise continues and creates the very duplicate the guard exists to prevent. The lock is separate from the pass lock below on purpose — sharing one would mean a running menu bar app blocks every CLI sync.
- Concurrent runs: acquire an exclusive non-blocking flock on `~/.config/worksync/.lock`; for a sync, if held, exit 0 quietly (another run in progress). **Contention and failure must be distinguishable at the API.** Returning "no lock" for both a busy lock and a lock file that cannot be opened would make a permissions or filesystem problem indistinguishable from a healthy race: every sync would exit 0 having done nothing, forever, with logs that look fine. Only `EWOULDBLOCK` is contention; anything else throws and maps to exit 3.
- Offline/sync lag: EventKit writes commit locally and macOS syncs to Exchange when online — no special handling, but log a warning if the event store reports the target source as disconnected.
- Rate/batching: commit via a single `EKEventStore.commit()` batch where possible; on partial failure, continue and exit 3.

## 10. Launch at login (SMAppService)

The menubar app registers itself as a login item via `SMAppService.mainApp` (macOS 13+) — the modern replacement for hand-written launchd agent plists, and a second hard reason the `.app` bundle exists (§3.1): `SMAppService.mainApp` only works for a real app bundle. Rules:

- `worksync install-agent` calls `try SMAppService.mainApp.register()`; `uninstall-agent` calls `.unregister()`. Both idempotent. The menu bar also exposes this as a "Launch at login" toggle, OFF by default — auto-launching without explicit consent is both bad manners and against Apple's guidelines.
- Never cache the enabled state as a bool: the user can remove the item in System Settings > General > Login Items at any time. Read `SMAppService.mainApp.status` every time the toggle is rendered and on every launch; if the app was moved on disk since registration, re-register (registration records the bundle location and does not follow moves).
- First `register()` may return `.requiresApproval` — that is normal first-run behavior, not an error. Surface it with a short explanation and call `SMAppService.openSystemSettingsLoginItems()` to deep-link the user to the approval UI.
- Crash resilience: login items are not supervised like KeepAlive launchd jobs — a crashed menubar app stays down until next login. Acceptable for v1; the interval timer makes a missed pass harmless, and `worksync status` / the missing icon make it visible.
- Support `install-agent --headless` as the alternative for users who don't want the icon: writes `~/Library/LaunchAgents/io.gamov.worksync.plist` with `ProgramArguments` `[<bundle>/Contents/MacOS/worksync, sync]`, `StartInterval = interval_minutes * 60`, `StandardOutPath`/`StandardErrorPath` pointing at the log file (§8), then `launchctl bootstrap gui/$(id -u)`. `uninstall-agent` reverses via `launchctl bootout` and removes the plist. This headless path runs the one-shot CLI, so it needs no LaunchServices identity and posts no notifications (§4.1: notify is menu bar-only).

## 11. Menu bar app (`worksync menubar`)

`NSStatusItem` in the system menu bar, whose click opens a key-capable non-activating `NSPanel` hosting one SwiftUI view via `NSHostingController` (§11.0). Accessory behavior (no Dock icon) comes from `LSUIElement = true` in the bundle's Info.plist (§3) — no unconditional `setActivationPolicy` call at startup.

### 11.0 Presentation: a custom NSPanel, not MenuBarExtra and not NSPopover

The prior art here is [OpenUsage](https://github.com/robinebers/openusage) (MIT, Robin Ebers), a menu bar app with an almost identical build shape to this one — SwiftPM with no `.xcodeproj`, a shell script that assembles the `.app`, a library plus thin executables, and a CLI that works with the GUI not running. Its documented reasons for rejecting both obvious presentations apply here unchanged, and are worth stating so nobody re-litigates them:

- **Not `MenuBarExtra`.** It is a `Scene`, and this process already owns the `NSApplication` + app-delegate lifecycle a SwiftUI `App` would otherwise own (§3.1 rules 3 and 5). Independently of that conflict: its `.window` panel never becomes a proper key window for text input, and there is no public API to present it programmatically. macOS 26's `NSHostingSceneRepresentation` would sidestep the lifecycle half, but the deployment target is macOS 14 (§3).
- **Not `NSPopover`.** A popover's window is key only while the whole app is active, and activating an `LSUIElement` accessory app is asynchronous — it can land several runloop ticks later or be denied outright. The result is a panel that is on screen but not key: keystrokes go to the status item button and the user needs a second click.

The presentation is therefore an `NSPanel` subclass overriding `canBecomeKey` to `true` and `canBecomeMain` to `false`, with style mask `[.borderless, .nonactivatingPanel, .fullSizeContentView]`, `level = .popUpMenu`, `hidesOnDeactivate = false`, clear background, and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. A non-activating panel that can still become key takes focus the moment it is ordered front *without* activating the app, so keyboard navigation works on the first click. Call `layoutSubtreeIfNeeded()` on the hosting view before `makeKeyAndOrderFront` to avoid a first-frame size flash.

Dismissal is a local + global `NSEvent` mouse-down monitor, with the keep-open decision factored into a **pure, unit-tested policy function** rather than living inline in the monitor. Three cases in that policy are non-obvious and are bugs if missed:

1. Events whose window class name contains "menu" or "popover" must NOT dismiss: `NSMenu` and hover popovers are separate windows that otherwise read as outside clicks and tear the panel down before a button's mouse-up fires.
2. The status-button hit zone must extend from the button's top edge to the top of the screen, inclusive: a cursor slammed against the menu bar reports exactly the screen's `maxY` and would otherwise dismiss-then-immediately-retoggle.
3. Attached sheets and in-flight resizes keep it open.

The panel is a designed surface, not a list of menu items: the point is that a glance answers "is my calendar covered right now, and did the last pass work". Two consequences bind the implementation:

- **The status item icon carries state on its own** (below), because the common case is not opening the panel at all.
- **A right-click (or control-click) opens a plain `NSMenu`** with the same actions in text form — assign it to `statusItem.menu`, `performClick`, then clear `statusItem.menu` immediately so left-click still toggles the panel. A custom panel cannot be driven by VoiceOver or the keyboard as reliably as a real menu, and this is also the escape hatch when the panel itself misbehaves.

**Known limitation — the status item toggles the panel directly.** macOS 27 introduces `NSStatusItemExpandedInterfaceDelegate`, and with it the rule that a status item showing custom UI must tell AppKit when that UI is active so keyboard focus and menu tracking behave; toggling the window straight from the button's target/action is explicitly the wrong pattern there. That API does not exist in the macOS 26 SDK and the deployment target is macOS 14, so it cannot be adopted yet. What is available today is applied: the status button has a target and action (so Return activates it during keyboard navigation) and the panel sets `autorecalculatesKeyViewLoop = true`, which matters because the settings screen adds and removes controls as the selection changes. When the build moves to the 27 SDK, move show/hide into the delegate callbacks and dismiss via `expandedInterfaceSession?.cancel()` rather than ordering the window out.

**The panel must paint its own background.** The window is transparent so its rounded corners are not drawn over, which makes the SwiftUI content the only thing painting a ground — without one the panel is literally see-through to the desktop. Its appearance must also be pinned to the system's and follow Light/Dark switches: an unset panel appearance resolves to Aqua regardless of the system setting, so in Dark Mode the content renders light-mode colours on a dark backdrop.

**Closing the panel must reset transient state.** The SwiftUI tree survives `orderOut`, so on hide: dismiss orphaned hover tooltips (a closed panel fires no hover-exit), clear stray first-responder focus rings without stealing focus from a live text field, and reset scroll position and any pending confirmation.

Icon states (template images so they adapt to light/dark menu bar):

- idle/ok — calendar glyph
- syncing — animated or badged variant while a pass is running
- error — exclamation badge (last run failed; persists until a successful run)
- paused — dimmed/slashed variant

Panel content — one pinned header, a scrolling body, a pinned footer:

- Header: last-run line — `Synced 4m ago · created 1, deleted 2`, or the error text when the last pass failed.
- Body: one row per source — source name, the count of managed blocks currently on its target calendar, and its target calendar. A row's detail line is the place to surface per-source trouble (calendar not found, events skipped for want of an identifier, §7).
- Footer (chrome): **Sync now** (disabled while a pass runs), **Pause / Resume**, and an overflow for **Settings**, **Open config**, **Open log**, **Launch at login**, **Quit**.

**Open config** opens config.toml in the default editor and then validates it, surfacing any error immediately rather than letting a bad edit fail invisibly at the next scheduled pass. Config is re-read at the start of every pass, so edits apply on the next sync without a restart. This raw-file path always remains available alongside the settings screen.

Visual system (adapted from OpenUsage, whose conventions are worth taking wholesale rather than re-deriving):

- Fixed panel width ~320pt, ~14pt outer padding, 12pt card corner radius, 44pt top bar on secondary screens.
- Cards use `NSColor.textBackgroundColor` with `.fill.quaternary` composited on top — the macOS System Settings grouped-box look. No hand-tuned hex colors; status colors come from the system palette (`.systemBlue`/`.systemYellow`/`.systemRed`) so they track light/dark and accessibility settings automatically.
- **Liquid Glass is confined to chrome, never content** (Apple's own guidance): glass on the footer/navigation layer, standard materials in the content layer.
- **Every `#available(macOS 26, *)` check lives in exactly one file** of paired helpers (`glassButtonStyle()`, `barGlass()`, `pinnedFooter {}`), so no view ever contains an availability branch. This is the single highest-value pattern to copy.
- **Those helpers need a compile-time guard as well as the runtime one.** `#available` is a runtime check; the symbol must still exist when the code is compiled, and `glassEffect` is absent from the macOS 15 SDK — so a toolchain older than the 26 SDK fails to build at all, not gracefully. Each helper is therefore gated by `#if compiler(>=6.2)` (Swift 6.2 ships with the macOS 26 SDK) around the `#available` check. CI runs an older toolchain than a current developer machine, so this is load-bearing rather than theoretical: it is exactly how the first menu bar commit broke the build.
- Screen transitions use a pure `.offset`, never a `.transition` carrying `.opacity`: compositing into a transparency layer leaves `.quaternary` material with no vibrant backdrop to sample, so it resolves to its opaque near-white base and flashes white across the cards. There is no clean SwiftUI fix.
- Dark mode is set as an app-level `NSApp.appearance` override and pinned separately on the panel — the panel ignores SwiftUI's `preferredColorScheme`, and the menu bar's own appearance otherwise wins.
- Time-sensitive text (a "synced 4m ago" line) wraps in `TimelineView(.periodic(...))` so it ticks without waiting for a data refresh, and only while the panel is visible.
- Motion constants live in one place with a reduce-motion environment key; under reduce-motion, screen changes snap as one structural update.

**Status item rendering.** The icon must reflect state without opening the panel. When the status item's image is generated (rather than a static template symbol), drive it through `withObservationTracking` and **re-arm on every render** (`onChange` is one-shot), with a ~50ms debounce so a burst of state writes collapses into one render — undebounced, the repeated work can make the status item visibly disappear during a busy pass.

Behavior rules: the timer fires every `interval_minutes`; a pass also runs immediately on launch and on wake-from-sleep (`NSWorkspace.didWakeNotification`). Only one pass may run at a time (same flock as CLI, so a manual `worksync sync` in a terminal and the menubar app never collide). All sync work happens off the main thread; the menu stays responsive.

Concurrency model — read §3.1 rules 3–4 before writing any async code here. Standard structured concurrency is fine: run the pass in a Task, await it, update UI state on the main actor afterwards. The specific traps: instantiate the app delegate explicitly in `main.swift` (never `@main`/`@NSApplicationMain` — §3.1 rule 3), and write `Task { @MainActor in ... }` explicitly from non-isolated contexts such as NSWorkspace/EventKit notification callbacks, which arrive on arbitrary queues. The failure mode being defended against does not fail loudly: if the in-flight flag latches (a pass "starts" but its continuation never runs), every later pass — timer, wake, and "Sync now" — silently does nothing for the life of the process. The manual test checklist (§13) exercises repeated "Sync now" clicks precisely to catch this.

A pass request must never be lost: when a pass is requested while one is already in flight (in-process, or cross-process when another holder of the flock causes the pass to be skipped), set a pending flag and re-run once the current pass finishes.

### 11.1 Settings screen

Settings is **a screen inside the panel**, not a separate window: a `screen` enum (`.dashboard` / `.settings` / `.source(id)`) on a layout store, with a pinned 44pt back bar. This is less code than a window, reads better for a menu bar utility, and deletes a whole class of accessory-app problems — no `NSApp.activate(ignoringOtherApps:)` dance to bring a window forward, no activation-policy flipping, and no `NavigationSplitView`-in-a-plain-`NSWindow` sidebar-toggle defect (previously §3.1 rule 5, now moot for this surface).

It edits config.toml through the same on-disk file the CLI reads — config.toml stays the single source of truth and is never replaced by a UI-owned store.

**Where each setting lives — a hard rule, since two stores are now in play.** Anything that affects sync behavior lives in config.toml and nowhere else, because headless operation (§2) depends on it: calendar selection, window, intervals, per-source knobs, notify, change_driven. `UserDefaults` is reserved strictly for view state with no headless meaning: last panel height, which screen was open, density/appearance override, paused state. **No setting may exist in both places.**
- The real value of this screen is that account and calendar are resolver-backed popups populated from the same account/calendar enumeration `worksync calendars` uses — for `[target]` and for each source. A free-text typo in an account or calendar title hard-errors the entire sync (§4.1); a popup cannot be wrong.
- General/target form covers `window_days`, `interval_minutes`, `log_level`, `notify`, `change_driven`, and the target account/calendar. `timezone` is not exposed (reserved, §4).
- Per-source form covers every source field: `id`, `account`, `calendar`, `title_template`, `target_calendar`, `availability`, the `coalesce` / `include_all_day` / `skip_if_work_busy` toggles, and the minute knobs (`coalesce_gap_minutes`, `min_duration_minutes`, `padding_before_minutes`, `padding_after_minutes`).
- Source list must support drag-reorder in addition to add and remove, because order decides cross-source dedup (§4.1, §5 step 5). Removal needs a visible control — a paired add/remove pair of toolbar buttons, with remove disabled when nothing is selected — since swipe-to-delete alone is not a discoverable macOS interaction.
- Renaming an existing source's id must raise a confirmation alert explaining that every managed event's marker embeds the source id, that the rename orphans those events, and that `worksync purge --source <old-id>` is the only way to clean them up (§4.1, §7). New sources are exempt.
- Saving goes through the same config writer the rest of the system uses (§4.3) — comment-preserving line edit, round-trip self-check, .bak backup — never a separate UI-only write path.
- If config.toml does not currently parse, the settings screen refuses to render the forms and points the user at "Open config" instead, rather than presenting a form full of defaults that would overwrite the broken file with garbage on save.
- The panel auto-fits its content height with an animated morph between screens (publish each screen's intrinsic height through a SwiftUI preference, sum it with the measured chrome, and drive the panel's frame from a `@State` height so one spring animates both the window and the content). This is the single most expensive item in §11 and the one that most distinguishes a designed panel from a generic one — a simplified version that measures content and sets the frame anchored to a stored top-left captures most of the benefit and is the acceptable v1.

### 11.2 Change-driven sync and notifications

Both are menu bar-only behaviors, config-gated, and additive to the timer.

- **Change-driven fast path** (`change_driven`, default false): observe `EKEventStoreChanged` and use it to trigger a pass sooner than the next timer tick. Treat the notification as carrying no payload — Apple documents "individual changes are not described", and while a userInfo dictionary with undocumented keys does exist in practice, nothing in it is contractual; the correct design is "something changed, re-query" via the ordinary filtered fetch. It requires a long-lived, retained `EKEventStore`: notifications are filtered on the specific store instance being observed and stop the moment the posting store deallocates, so the per-pass calendar store is unsuitable and a dedicated observer object must own its own store (Apple also advises apps keep a single event store). Keep that observer behind a small protocol declared in the EventKit-free core so it stays fakeable in CI (§13). Start observing only after the first successful pass, so access is known-granted. Notifications arrive on an arbitrary queue — hop to the main actor explicitly (`Task { @MainActor in ... }`, §3.1 rule 4). If the observer uses a `for await` notification loop, never `return` out of it on a transient condition (e.g. a momentary authorization check) — that permanently ends observation for the process lifetime; use `continue`. macOS 26 adds a typed, main-actor-isolated `EKEventStore.EventStoreChanged` message (`NotificationCenter.default.addObserver(of:for:)`) — prefer it when the deployment target allows. Debounce with a single coalescing timer of `change_debounce_seconds` (default 20) that each notification re-arms, so a burst collapses into one pass before any lock contention. Suppress the echo of worksync's own commits with a short ignore window (5s) after any pass that actually wrote, otherwise every writing pass triggers one extra no-op pass behind it.
- **Known limitation — the fast path is best-effort, never a guarantee.** During development on macOS 26.5.2, `EKEventStoreChanged` was never observed firing under any observer configuration (store-object or nil filtering, access granted, warm-up fetch on the observer's own store, waits past 40 seconds, changes from Calendar.app and worksync's own verified writes alike). External corroboration for a platform-level defect was not found, so treat this as a local observation, not established platform fact — the registration pitfalls above are the more likely explanation in general. Either way the design conclusion stands: App Nap can defer delivery to an accessory app, nothing is delivered while the machine sleeps, and the interval timer plus the wake-from-sleep pass are therefore not optional — they are the safety net that makes shipping this fast path acceptable. When the notification never fires, behavior degrades silently to timer-only polling, which is the correct and expected fallback. Do not build any feature that assumes the notification will arrive.
- User-facing caveat to state plainly in any description of this feature: Google/CalDAV-backed sources benefit far less, because EventKit only ever reflects what that account has already pulled down locally on its own refresh cadence (often ~15 minutes).
- **Desktop notifications** (`notify`: off | errors | always, default errors): after each completed pass, post a native notification via `UNUserNotificationCenter` — legal now that the process runs from a registered, signed app bundle (§3.1 rule 2). Request authorization (`.alert`) lazily, the first time `notify` is not `off`; if authorization is denied or notification settings report NotSupported (a mis-assembled or mis-launched bundle, §3.1), fall back to the osascript `display notification` path behind the same Notifier protocol and log which path was used. The body must reuse the exact same pass-summary string already shown in the menu header and written to the log, so there is one source of truth for "what happened this pass". Error notifications carry the underlying config/calendar-resolution error text. Passes that were skipped because another process held the lock post nothing — "another sync is already running" is not news. The default is errors because a healthy idempotent sync running every few minutes must not produce a banner every time.
- Nothing here adds persisted sync state: the sync engine stays stateless and reconciliation state stays in the managed events themselves (§3). The only thing persisted outside calendar data is last-run info for the header line and `worksync status`.

Operational note: nothing syncs unless something is running. A one-shot `worksync sync` exits immediately, so unattended operation requires either the menu bar app running continuously (login item, §10) or the headless launchd agent installed. "Why didn't my change sync?" is far more often "no worksync process was alive" than a reconciliation bug — check for a running process and an enabled login item before investigating the pipeline.

## 12. Build & CI (GitHub Actions)

Local commands (the only interface anyone — human or agent — uses):

```
swift build                       # debug
swift test                        # unit tests, no TCC needed
swift build -c release --arch arm64
scripts/build-app.sh              # release build + WorkSync.app assembly + codesign
                                  # + designated-requirement check + tar.gz with version
```

CI workflow `.github/workflows/ci.yml`, runner macos-15:

1. `swift --version`, cache `.build` keyed on Package.resolved
2. `swift build -c debug`
3. `swift test` — this is why WorkSyncCore must be EventKit-free: CI has no calendar accounts and no TCC grants. Any test requiring a real EKEventStore must not exist; the in-memory CalendarStore fake covers integration-level tests.
4. `swiftformat --lint .` (config committed to repo)
5. On tag `v*`: release job runs `scripts/build-app.sh` with ad-hoc signing (CI has no signing identity — acceptable, since users re-sign locally with their own stable certificate, which build-app.sh supports via an identity argument), packages `WorkSync-<version>-arm64.tar.gz` containing the `.app`, attaches to a GitHub Release.

Distribution/Gatekeeper notes for README:

- Notarization is out of scope for v1 (requires a paid Apple Developer membership; ad-hoc/self-signed code cannot be notarized).
- On macOS 15+, the old Control-click → Open Gatekeeper bypass is gone; unnotarized quarantined apps must be approved via System Settings > Privacy & Security.
- The quarantine xattr is applied by the *downloading* app: browser downloads get it, but `curl -L | tar xz`, `git clone`, and Homebrew do not. Document the curl install path as the primary one — it sidesteps Gatekeeper's first-launch block entirely. Keep `xattr -d com.apple.quarantine` documented as the fallback for browser downloads (verified working through macOS 15.x; not yet verified on macOS 26).
- Users should re-sign with a local stable certificate (§3) before granting calendar access, or the TCC grant resets on every update of the ad-hoc-signed release build.

Definition of done for CI: green build + tests on a clean runner with zero manual steps, no Xcode project files in the repository.

## 13. Testing

- Unit tests (no EventKit): interval math (padding, coalescing, window filtering, 80% overlap-by-union rule including a double-booked case that naive summing would get wrong), marker generation/parsing, cross-source dedup including the within-source recurring-series regression (multiple occurrences sharing one external identifier must all survive) and the detached-occurrence case (moved occurrence keeps its `occurrenceDate` key), config parsing + validation errors, reconciliation diff (pure function: desired + existing → create/update/delete plan). Structure the core as a pure SyncPlanner so all logic is testable without a calendar store.
- Config writer tests must use a comment-dense fixture — the §4 example config verbatim is the right one — and cover: a single-field edit preserving every comment, the edited file reloading to the new value, editing one source leaving another source's fields and comments untouched, adding a source, removing a source, reordering two sources (proving the dedup-order-sensitive case survives a round trip), and a no-op edit producing byte-identical output.
- Integration harness: thin CalendarStore protocol wrapping EventKit, with an in-memory fake for end-to-end plan+apply tests. These run in CI.
- Unit tests cannot catch the packaging and lifecycle failure modes in §3.1 — a never-instantiated app delegate, notification settings all NotSupported from a mis-assembled bundle, a dead sidebar toggle from a missing styleMask flag — all look fine in code review and in CI. UI, menu bar, and notification behavior must be exercised against the actually running, bundle-launched app before being called done.
- **Filter edge cases need a real store, not just unit tests.** The weekday and duration filters are unit-tested against a fixed UTC calendar, which cannot catch what a real backend does with timezone-carrying events. Exercise these against live calendars before calling the filters done: a weekend-spanning event that crosses into Monday (must survive — the whole-interval rule), an all-day event on a skipped weekday (must drop), `max_duration_minutes` on a source with large padding (the raw duration decides, not the padded one), and an event created in a non-local timezone while `skip_weekdays` is set.
- Manual test checklist in README: recurring source event moved (both a detached single occurrence and the whole series), source event deleted, source event toggled busy → free (blocker must disappear) and back, flight with padding crossing midnight, coalesced block gaining/losing a constituent, purge, TCC denial path, notification authorization prompt appears on first enable and a banner is delivered, launch-at-login toggle round-trips through System Settings, menubar pause/resume, wake-from-sleep sync, Sync now clicked repeatedly (must run a full pass every time, not just the first), the settings screen round-tripping an edit into config.toml with all comments intact.

## 14. Milestones

1. **M1:** SwiftPM skeleton + CI green (build, empty tests, format lint), config parsing, `calendars`, `sync --dry-run` printing the plan (read-only). Includes `scripts/build-app.sh` producing a signed, LaunchServices-registered `WorkSync.app` and the bundle smoke test (§3.1 rule 2): launch it and confirm the notification authorization prompt appears — the bundle architecture is validated before anything depends on it.
2. **M2:** full reconciliation writes, marker scheme, purge, single-source.
3. **M3:** multi-source with per-source target calendars, cross-source dedup, conflict check.
4. **M4:** menubar mode (icon states, menu, timer, pause), SMAppService login item + `--headless` launchd alternative (§10), logging/rotation, `status`.
5. **M5:** release workflow, build-app.sh signing + designated-requirement verification, docs.
6. **M6:** settings screen inside the panel (§11.1) — validate-and-surface on Open config, the config writer with backup and round-trip self-check (§4.3), the comment-preserving line editor, the general/target forms, and the source list with add/remove/drag-reorder and the id-rename warning.
7. **M7:** change-driven sync and desktop notifications (§11.2).
8. **M8:** `worksync doctor` and health surfacing (§16) — one set of checks in the core, rendered as terminal output by the CLI and as a menu bar indicator by the app. Depends on M4 for the UI half and on nothing for the core half, so it can be pulled ahead of M5–M7 if diagnostics are worth more than release polish.

## 16. Self-diagnosis (`worksync doctor`)

Most of what goes wrong is environmental rather than logical: a permission tier that silently returns zero events, a signature that resets the calendar grant on every update, a login item that was never approved, a process that simply is not running. Each of those cost real debugging time during M1–M4, and each is mechanically detectable — which is the argument for the command.

**The checks live in the core and return a value type** (`severity`, `title`, `detail`, `remediation`), because that single decision buys three things at once: `--json` output, unit tests against the in-memory fake with no TCC grant in CI, and a menu bar indicator that cannot drift from the CLI. Homebrew had to retrofit exactly this shape before its own `--json` was possible; doing it first is free.

**Severity maps onto the existing exit codes (§8); no new codes.** Access failures take precedence and exit 2, because without access every calendar-dependent check is *unknowable* rather than failing — reporting the symptoms first sends the user somewhere useless. Config and resolution problems exit 1, a check that itself blew up exits 3. **Warnings never change the exit code**, with `--strict` as an opt-in for CI. This is deliberate: `brew doctor` exits non-zero on anything at all, including purely cosmetic findings, and the result is a command whose own help text tells users to ignore it.

Two rules keep it worth running:

- **No check without a remediation the user can execute.** A finding whose fix is "file a bug" belongs in a debug dump, not here.
- **No check that can be wrong on a healthy machine.** One false positive teaches the user to ignore the whole command, and they do not come back to re-evaluate.

**Doctor is provably read-only.** It never prompts (it reads `authorizationStatus` rather than calling the requesting API, which would both show a dialog to someone running a diagnostic *and* let it report success for a permission granted to the diagnostic itself), never reads the TCC database, never runs a sync pass, and never fixes anything. It prints calendar and account titles — needed to diagnose a typo — and never event titles or attendees, because doctor output is exactly what users paste into bug reports.

**The menu bar renders the same findings** (§11): the icon answers "is WorkSync OK?", so doctor errors and a failed last pass share the error treatment, warnings get a distinct non-red treatment, and paused outranks both. Checks are fast and local, so they can run on launch, after each pass, and on panel open without a timer.

## 15. Acceptance criteria

- `git clone && swift build && swift test` succeeds on a clean macOS machine with only command-line tools; repository contains no `.xcodeproj`/`.xcworkspace`.
- `scripts/build-app.sh` produces a signed `WorkSync.app` whose designated requirement is not a bare cdhash; the calendar TCC grant survives a rebuild.
- CI is green on every push; tagging `v*` produces a downloadable release artifact.
- Two configured sources (generic busy + travel) produce correctly titled blockers on two different work calendars; recoloring in Calendar.app persists across syncs.
- Deleting or moving a personal event is reflected on the work calendar within one sync interval; moving a single detached occurrence of a recurring event reconciles as one update, not a delete+create.
- Running sync twice in a row with no source changes performs zero writes.
- Menu bar icon reflects syncing/ok/error/paused states; Sync now and Pause work; quitting the menubar app and re-launching it (or logging in with the login item enabled) restores it.
- With `notify = "always"`, a completed pass posts a native notification banner; with `notify = "errors"`, only failures do.
- Marking a source event "Free" in Calendar.app removes its blocker from the work calendar on the next pass; marking it busy again restores it.
- Every menu bar action works on the tenth invocation exactly as on the first — "Sync now" in particular runs a complete pass every time it is clicked.
- Editing a value in the settings screen and saving updates exactly that value in config.toml, leaves every other line byte-identical, and preserves all comments; a save with no edits leaves the file byte-identical.
- Reordering sources in the settings screen changes their order in config.toml, and renaming an existing source's id prompts a warning first.
- `purge` removes every worksync-managed event and nothing else, including events stranded on calendars the current config no longer targets.
- Tool makes no network connections of its own (verifiable with Little Snitch/nettop).
