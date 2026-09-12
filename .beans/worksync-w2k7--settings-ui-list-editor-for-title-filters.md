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

SPEC §11.1 previously claimed the per-source form covers every source field;
that line now names these two as file-only, and should be reverted to the
stronger claim once this lands.

[x] List editor (add / remove / edit rows), one per field
[x] Reject blank entries in the UI before save — `ConfigLoader.validate` already
    throws on them, so the UI should not let the user reach that error
[x] Round-trip through `ConfigWriter` with comments preserved
[x] Restore the SPEC §11.1 "every source field" wording

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
