---
# worksync-w2k7
title: 'Settings UI: list editor for title_matches / title_excludes'
status: completed
type: feature
created_at: 2026-09-11T21:15:16Z
updated_at: 2026-09-11T23:05:00Z
---

`title_matches` and `title_excludes` shipped in PR #1 as config-file-only.
`SettingsView.sourceDetail` has no controls for either, so the settings screen
silently omits two source options.

Every other per-source field is a row: a text field, a toggle, a stepper. These
two are list-valued, which is why they were left out rather than bolted on — a
comma-joined text field would be the wrong answer, since a title can contain a
comma.

SPEC §11.1 previously claimed the per-source form covers every source field.
That claim was already false for four other fields, so this work corrected the
line to say what the form really covers rather than restoring the blanket
wording. See worksync-t4qp for the missing editors.

[x] List editor (add / remove / edit rows), one per field
[x] Reject blank entries in the UI before save — `ConfigLoader.validate` already
    throws on them, so the UI should not let the user reach that error
[x] Round-trip through `ConfigWriter` with comments preserved
[x] Correct SPEC §11.1: the per-source form does NOT cover every source field,
    so the line now lists what it covers and names the four that are
    config-file-only (`target_calendar`, `coalesce_gap_minutes`,
    `max_duration_minutes`, `skip_weekdays`). The blanket "every source field"
    claim was inaccurate before this branch too; restoring it would have
    re-asserted that. The editors themselves are worksync-t4qp

## Landed
`TitleFilterEntry` (WorkSyncCore) judges one entry — empty, blank, duplicate
under the planner's case- and diacritic-insensitive matching, or valid — and is
where the tests live, since the app target has no test harness. The form adds
through it, disables the add button on anything else, flags a row emptied in
place, and disables Save while either list is unusable. Duplicates are refused
too: two entries differing only in case are one filter written twice.

Based on the wrapped-array writer fix (PR #4) — without it, saving a config
whose filter list was wrapped by hand falls back to reserialization and the
user loses every comment in the file.

## Related
- worksync-30i2 — the filters themselves
