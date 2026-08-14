// Generated from config.example.toml by scripts/generate-example-config.sh.
// Do not edit by hand — ExampleConfigTests asserts this matches the file.
//
// Embedded rather than loaded as a bundle resource so `worksync init` cannot
// fail at runtime on a missing resource bundle: first-run UX is the worst
// possible place for a "file not found".

public enum ExampleConfig {
    public static let contents = """
    # WorkSync configuration
    #
    # Copy to ~/.config/worksync/config.toml (or run `worksync init`), then edit.
    # Run `worksync calendars` to see the exact account and calendar names to use,
    # and `worksync sync --dry-run` to preview what would change before anything
    # is written.
    #
    # Every option is listed here with its default. Options you delete fall back to
    # the default shown, so a minimal config is just [target] plus one [[source]].

    [general]

    # How far ahead to sync, in days, measured from now. The window is rolling:
    # both ends move forward on every run.
    window_days = 21

    # How often the menu bar app runs a pass. Also the interval used by
    # `worksync install-agent --headless`. Ignored by a one-shot `worksync sync`.
    interval_minutes = 10

    # Reserved. v1 always uses the system timezone; this key exists so a future
    # version can add one without a config migration.
    timezone = "system"

    # error | warn | info | debug
    # Written to ~/Library/Logs/worksync/worksync.log (rotated at 1 MB, 5 files).
    log_level = "info"

    # off | errors | always — desktop notifications after a menu bar pass.
    # Default is "errors" because a healthy sync running every few minutes must not
    # produce a banner every time. Menu bar only; the CLI ignores this.
    notify = "errors"

    # Opt-in fast path: react to calendar changes instead of waiting for the timer.
    # Best-effort only — it may never fire at all, and Google/CalDAV sources benefit
    # far less because EventKit only sees what that account has already pulled down
    # on its own schedule (often ~15 minutes). The timer remains the guarantee.
    change_driven = false

    # How long to wait after a change before syncing, so a burst of edits collapses
    # into one pass. Only used when change_driven = true.
    change_debounce_seconds = 20


    # --- Where blockers are written -----------------------------------------------

    [target]

    # The account and calendar names exactly as `worksync calendars` prints them.
    # Matching is case-insensitive. If two calendars in one account share a name,
    # WorkSync refuses to run rather than guess — rename one in Calendar.app.
    #
    # WorkSync never creates calendars: creating one on a corporate account is
    # often restricted, and silently making a calendar is a surprising thing for a
    # sync tool to do. If the calendar below does not exist, you get an error.
    account = "Work Exchange"
    calendar = "Calendar"


    # --- What gets mirrored -------------------------------------------------------
    #
    # Each [[source]] is fully independent: its own filters, padding, title, and
    # target calendar. Add as many as you like — no code changes needed.
    #
    # ORDER MATTERS. When the same underlying event appears in two sources, the
    # FIRST one listed wins, and its title, padding, and target calendar are the
    # ones used. Reordering these blocks silently changes that outcome, so keep the
    # order deliberate.

    [[source]]

    # A short, stable slug. It is embedded verbatim in every event WorkSync creates,
    # which is how it recognizes its own events later.
    #
    # RENAMING THIS ORPHANS EVERY EVENT ALREADY CREATED UNDER THE OLD NAME: they
    # will never be updated and never cleaned up by a normal sync. The only way to
    # reach them afterwards is `worksync purge --source <old-id>`. Choose it once.
    #
    # Cannot contain "/" or line breaks — both would corrupt the marker.
    id = "personal"

    # The calendar to read from.
    account = "iCloud"
    calendar = "Personal"

    # What appears on the work calendar. Your source event's real title, location,
    # attendees, and notes are NEVER copied — that is the entire point of the tool.
    #
    # Two optional placeholders, both privacy-safe:
    #   {date}    the source event's start date, as 2026-08-14
    #   {weekday} the source event's weekday, as Thursday
    title_template = "Busy"

    # Which calendar this source writes to. Empty means [target].calendar above.
    # Point different sources at different calendars to colour-code them: EventKit
    # cannot set per-event colours, so a separate calendar is the only way to make
    # flights look different from appointments. You set the colours once in
    # Calendar.app or Outlook.
    target_calendar = ""

    # Merge nearby events into one longer blocker, so a busy morning becomes a
    # single block rather than a wall of fragments. Never merges across sources.
    coalesce = true

    # Gaps of this many minutes or less are merged when coalesce = true.
    coalesce_gap_minutes = 15

    # Ignore events shorter than this. Useful for filtering out reminders and
    # five-minute holds. 0 means no minimum.
    min_duration_minutes = 15

    # Ignore events LONGER than this. 0 means no maximum.
    #
    # Useful for sources carrying informational multi-hour entries that would
    # otherwise paint one enormous block hiding the real meetings underneath. Leave
    # at 0 for anything where long events are real busy time — a travel source with
    # long-haul flights, for example. Measured on the event itself, before padding.
    max_duration_minutes = 0

    # Block extra time around each event, for travel or preparation.
    padding_before_minutes = 0
    padding_after_minutes = 0

    # Days that are never mirrored, e.g. ["sat", "sun"]. Full names also work.
    # An event is only dropped when ALL of it falls on skipped days, so something
    # running Saturday night into Monday morning still gets blocked.
    skip_weekdays = []

    # Mirror all-day events as all-day blockers. Off by default because all-day
    # entries are frequently informational ("School closed") rather than busy time.
    include_all_day = false

    # Skip creating a blocker when your work calendar is already ~80% booked for
    # that time by a real (non-WorkSync) event. Avoids stacking a blocker on top of
    # a meeting you are already in.
    skip_if_work_busy = true

    # busy | free | tentative — how the blocker appears to colleagues checking your
    # availability. "busy" is almost always what you want; "free" creates a visible
    # event that does not actually block scheduling.
    availability = "busy"


    # A second source, showing a different shape: flights, on their own calendar,
    # with airport buffers, and never suppressed by existing work events.
    [[source]]
    id = "travel"
    account = "Google"
    calendar = "Travel"
    title_template = "✈️ Flight"

    # A separate work calendar, so flights are visually distinct.
    target_calendar = "Travel Blocks"

    # Each flight stays its own block rather than merging with the next one.
    coalesce = false

    # No minimum: a short hop is still time you cannot take a meeting in.
    min_duration_minutes = 0

    # Airport buffers.
    padding_before_minutes = 120
    padding_after_minutes = 60

    # Multi-day trips arrive as all-day entries and are worth blocking.
    include_all_day = true

    # Travel wins over anything already on the work calendar.
    skip_if_work_busy = false

    # Colleagues checking your availability see this time as unavailable.
    availability = "busy"

    """
}
