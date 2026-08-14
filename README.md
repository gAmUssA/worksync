# WorkSync

Mirrors busy time from your personal calendars onto your work calendar as
sanitized blocker events, so colleagues see when you are unavailable without
seeing why.

Everything happens on your Mac through EventKit, against accounts macOS has
already set up. There is no server, no account to create, and no network call
of any kind — your work calendar is only ever touched by macOS's own sync. It
exists for workplaces where connecting the work calendar to an external service
is not allowed.

```
Personal calendar          Work calendar
─────────────────          ─────────────
09:00 Dentist         →    09:00 Busy
14:00 School pickup   →    14:00 Busy
```

The blocker carries no title, location, attendees, or notes from the source
event. That is the entire point, and it is enforced in the code rather than by
convention: titles come from a template with two allowed placeholders (`{date}`
and `{weekday}`), and nothing else is ever copied.

## Requirements

macOS 14 or later, and the Xcode command line tools to build.

## Install

WorkSync is not notarized, so how you download it matters more than usual.

**Recommended — build it yourself.** This is the path that gives you a stable
code signature, which is what keeps macOS from revoking calendar access every
time you update (see [Signing](#signing) for why).

```bash
git clone https://github.com/gAmUssA/worksync
cd worksync
swift test                    # optional, ~1s
scripts/build-app.sh          # assembles and signs WorkSync.app
```

**Or download a release.** Use `curl`, not your browser: files downloaded by a
browser get macOS's quarantine attribute, and an app that is not notarized will
be blocked. `curl` does not set it.

```bash
curl -L -o worksync.tar.gz \
  https://github.com/gAmUssA/worksync/releases/latest/download/WorkSync-arm64.tar.gz
tar xzf worksync.tar.gz
```

Every release publishes two identical tarballs: `WorkSync-arm64.tar.gz`, whose
name never changes so the `latest` URL above keeps working, and
`WorkSync-<tag>-arm64.tar.gz` for pinning a specific version.

### Put the CLI on your PATH

The download is an app bundle, so the `worksync` command does not exist until
you link the executable inside it. Both install paths need this step:

```bash
mkdir -p ~/.local/bin
ln -sf "$PWD/WorkSync.app/Contents/MacOS/worksync" ~/.local/bin/worksync
```

If `~/.local/bin` is not already on your `PATH`, add it:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh
```

`scripts/build-app.sh` prints this command with the right absolute path when it
finishes. You can skip the link entirely and run
`WorkSync.app/Contents/MacOS/worksync <command>` instead — every example below
assumes the link exists.

If you did download through a browser, clear the flag before opening it:

```bash
xattr -d com.apple.quarantine WorkSync.app
```

On macOS 15 and later there is no Control-click "Open anyway" shortcut any
more; a blocked app has to be approved in System Settings → Privacy & Security.

Release builds are ad-hoc signed, because the CI runner has no signing
identity. They work, but macOS will forget your calendar permission on every
update. To fix that permanently, re-sign once with your own certificate:

```bash
scripts/build-app.sh --identity "WorkSync Dev"
```

## First run

```bash
worksync init          # writes a fully commented ~/.config/worksync/config.toml
worksync calendars     # lists your accounts and calendars by exact name
```

Edit the config with the names `worksync calendars` printed, then preview
before anything is written:

```bash
worksync sync --dry-run
```

`--dry-run` prints the full plan and changes nothing. When it looks right:

```bash
worksync sync
```

**The first real run must happen in a terminal**, because macOS shows the
calendar permission prompt to the foreground process. Once granted, the login
item and background agent work unattended.

To keep it running:

```bash
worksync install-agent             # menu bar app at login
worksync install-agent --headless  # background agent, no menu bar icon
```

Nothing syncs unless something is running. A one-shot `worksync sync` exits
immediately, so unattended operation needs one of the above. When a change
does not appear, "no worksync process was alive" is a far more common cause
than any sync bug — `worksync status` tells you when the last pass ran.

## Configuring

`~/.config/worksync/config.toml` is the single source of truth, and it stays
hand-editable. `worksync init` writes a copy of
[`config.example.toml`](config.example.toml), which documents every option
inline with its default. A minimal config is one `[target]` and one
`[[source]]`:

```toml
[target]
account = "Work Exchange"
calendar = "Calendar"

[[source]]
id = "personal"
account = "iCloud"
calendar = "Personal"
```

Three things are worth knowing before you edit it, because each is easy to get
wrong and hard to notice afterwards:

**Source order decides who wins.** When the same event appears in two sources,
the first one listed provides the title, padding, and target calendar.
Reordering the blocks changes that silently.

**A source `id` is permanent.** It is embedded in every event WorkSync creates,
which is how it recognizes its own work later. Renaming one orphans every event
already created under the old name — they will never be updated or cleaned up
by a normal sync. `worksync purge --source <old-id>` is the only way to reach
them afterwards.

**Colors come from calendars, not events.** EventKit cannot set a per-event
color, so pointing different sources at different `target_calendar`s is the
only way to make flights look different from appointments. You set the colors
once in Calendar.app.

## Commands

| Command | What it does |
| --- | --- |
| `worksync init` | Write a commented starter config |
| `worksync calendars` | List accounts and calendars with identifiers |
| `worksync sync [--dry-run]` | Run one pass; `--dry-run` previews without writing |
| `worksync status` | Last run, staleness, and managed events per source |
| `worksync doctor [--json]` | Check everything that can quietly break; `--strict` fails on warnings too |
| `worksync menubar` | Run the menu bar app in the foreground |
| `worksync purge [--source ID]` | Remove WorkSync's events; needs `--yes` to delete |
| `worksync install-agent` | Launch at login (`--headless` for no icon) |
| `worksync uninstall-agent` | Stop launching at login |

Exit codes: `0` success, `1` config or validation error, `2` permission error,
`3` something failed but is safe to re-run.

## When something isn't working

`worksync doctor` is the first stop. It checks the nine things that actually go
wrong — calendar permission, the config, whether every account and calendar
still resolves, whether the target is writable, whether anything is running at
all, plus warnings for a signature that will lose its permission on the next
update, a stale last run, notification permission, and a log that stopped
rotating.

```
✓ Calendar access
✓ Config
✗ Accounts and calendars resolve
    • Calendar "Personl" not found in account "iCloud". Available: Personal, Family.
    → Run `worksync calendars` for the exact account and calendar titles.
✓ Target calendars are writable
...
9 checks: 1 error.
```

Every failing check comes with something you can run or click; warnings never
change the exit code unless you pass `--strict`. The menu bar panel shows the
same findings with buttons that open the right settings pane — it renders what
`doctor` computes, so the two can never disagree.

Doctor is strictly read-only: it never prompts for permission, never writes,
never runs a sync, and prints calendar and account titles only — never event
titles or attendees — so its output is safe to paste into a bug report.

## The menu bar app

The icon shows state at a glance: idle, syncing, an error badge that persists
until a pass succeeds, or paused. Clicking opens a panel with the last run,
per-source counts, and Sync now / Pause. Right-clicking gives the same actions
as a plain menu, which also works with VoiceOver.

Passes run on a timer (`interval_minutes`), on launch, and on wake from sleep.
A manual `worksync sync` in a terminal and the menu bar app share a lock, so
they never collide.

### Reacting to calendar edits

`change_driven = true` adds a fast path: when a source calendar changes, a pass
runs after `change_debounce_seconds` (default 20) instead of waiting for the
next tick. The debounce collapses a burst of edits into one pass, and WorkSync
ignores the echo of its own writes so a syncing pass cannot trigger another.

This is deliberately additive. macOS can defer the notification for a
background app and delivers nothing at all while the machine is asleep, so the
timer and the wake-from-sleep pass remain the guarantee — if the notification
never arrives, syncing quietly carries on at its normal interval.

### Notifications

`notify` controls banners after a pass: `errors` (the default) only when
something failed, `always` for every pass, `off` for none. A pass skipped
because another one already held the lock never notifies — nothing happened.
The banner text is the same summary line the log and the panel show.

Notifications are menu bar only. The headless agent has no session to post
into, and `worksync sync` in a terminal already prints its summary. WorkSync
asks for notification permission the first time it actually has something to
show, not at launch; `worksync doctor` reports the state if you decline and
later change your mind.

## Signing

macOS ties calendar permission to a signature's *designated requirement*. An
ad-hoc signature's requirement is a hash of the binary itself, so every rebuild
looks like a different app and the permission is revoked. A stable certificate
produces a requirement anchored to your identity instead, and the grant
survives.

Create one once, in Keychain Access → Certificate Assistant → Create a
Certificate: name it `WorkSync Dev`, type *Self-Signed Root*, Certificate Type
*Code Signing*. Then find it in Keychain Access, open it, and set Trust → Code
Signing to *Always Trust*.

`scripts/build-app.sh` picks it up automatically and refuses to finish if the
resulting designated requirement is still a bare hash — a silent failure here
would surface weeks later as "permissions randomly broke again".

## Building and testing

```bash
swift build          # debug
swift test           # unit tests, no calendar access needed
swiftformat --lint . # style, as CI runs it
scripts/build-app.sh # release build + signed WorkSync.app
```

The core is deliberately free of EventKit so the logic can be tested without
calendar accounts or permission grants, which is what lets CI run the whole
suite. Calendar behavior is covered through an in-memory fake implementing the
same protocol as the real adapter.

There is no Xcode project and there will not be one; everything builds from the
command line with SwiftPM, including the `.app` bundle.

## Things unit tests cannot catch

Some behavior only exists in the assembled, LaunchServices-launched app. Before
calling a change done, verify by hand:

- A recurring event moved — both a single detached occurrence and the whole
  series
- A source event deleted, and one toggled busy → free and back (its blocker
  must disappear and reappear)
- A flight with padding that crosses midnight
- A coalesced block gaining and losing a constituent
- An event spanning a skipped weekday into a working day (it must survive)
- `Sync now` clicked repeatedly — a complete pass every time, not just the first
- Quitting and relaunching the menu bar app
- Denying calendar permission, and the message you get

## Limitations

- **One way only.** Work calendar content is read for reconciliation and
  conflict checks, and never copied anywhere.
- **Not notarized.** See [Install](#install).
- **The change-driven fast path is best-effort.** `EKEventStoreChanged` may not
  fire at all on some macOS versions, and nothing is delivered while the machine
  sleeps. The timer is the guarantee; the fast path only ever makes it sooner.
- **Google and CalDAV sources lag.** EventKit only sees what that account has
  already pulled down on its own schedule, often every ~15 minutes.
- **Secondary Exchange calendars may not count toward free/busy** for
  colleagues' scheduling assistants. If that matters, make the main work
  calendar the target.

## Design

[`SPEC.md`](SPEC.md) is the full specification, including the reasoning behind
the parts that look arbitrary: why identity is keyed on
`(externalIdentifier, occurrenceDate)`, why the sync window filters rather than
truncates, why the marker lives in event notes rather than the URL field, and
why the app is a bundle rather than a bare binary.

## License

MIT.
