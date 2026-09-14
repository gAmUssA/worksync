---
# worksync-w3fn
title: 'Settings keeps showing a stale config after the file changes'
status: completed
type: bug
created_at: 2026-09-14T14:50:00Z
updated_at: 2026-09-14T14:50:00Z
---

Reported by the owner: editing `title_excludes` in the config file does not
show up in the settings UI.

## The mechanism

`StatusItemController.hidePanel` orders the panel out but never calls
`closeSettings()`. `screen` stays `.settings` and `editingConfig` keeps the
copy loaded when settings were first opened.

`openSettings()` is the only thing that reads the file, and it is reached
only from the "Settings…" button — which the user does not press, because
the panel already reopens onto the settings screen. So the form can show a
config that no longer matches the disk indefinitely.

Worse than stale display: a save from that form writes the in-memory copy
over whatever the file now holds.

## Fix

Re-read on panel show while the settings screen is active, comparing against
the config as loaded:

- No unsaved edits (`editingConfig == baseline`) and the file changed: adopt
  the file. Reseed handles and origins so identity follows the new content.
- Unsaved edits present: keep them — silently discarding typing is worse than
  showing it — and record that the file changed underneath.
- File unchanged: do nothing, so selection and drafts do not churn on every
  panel open.

[x] Keep the loaded config as a baseline at `openSettings`
[x] Reload on show when clean and the file differs
[x] Preserve edits when dirty, and surface the external change
[x] Tests: clean reload; dirty preserved; unchanged file leaves selection and
      drafts alone

## Related
- `worksync-k8fw` — config edits that need a restart (interval, logger)
