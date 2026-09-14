---
# worksync-q7rb
title: 'Settings: the rename warning alert cannot be clicked'
status: completed
type: bug
created_at: 2026-09-14T14:50:00Z
updated_at: 2026-09-14T14:50:00Z
---

Reported by the owner: renaming a source raises the "Rename this source?"
warning — the one that explains `worksync purge` — and the alert does not
respond to clicks. Neither button works, so a rename cannot be completed or
cancelled from the UI.

## The mechanism, measured

A probe build logged the window topology while the alert was up:

```
panel attachedSheet=_NSAlertPanel sheets=1 isKey=false
window=MenuBarPanel   visible=true level=101 isSheet=false parent=nil
window=_NSAlertPanel  visible=true level=101 isSheet=true  parent=MenuBarPanel
```

SwiftUI presents `.alert` as an `_NSAlertPanel` **sheet attached to the
panel** — a separate `NSWindow`. The dismiss monitors
(`StatusItemController.installDismissMonitors`) fire on every mouse-down;
`PanelDismissPolicy.shouldKeepOpen` sees a window that is neither the panel
nor named `menu`/`popover`, calls it an outside click, and `hidePanel()`
orders the panel out — taking its sheet with it — before the button's
mouse-up arrives.

This is the failure the policy already documents for NSMenu and popovers:
"Treating them as outside clicks tears the panel down before a button's
mouse-up fires, so the button never triggers." Sheets were never added.

## Fix

Class-name matching is the wrong instrument for this. A sheet is
identifiable structurally: `event.window?.sheetParent === panel`. Pass that
to the policy as its own input.

[x] `PanelDismissPolicy.shouldKeepOpen` takes whether the event window is a
      sheet of the panel
[x] `handleOutsideClick` computes it from `sheetParent`
[x] Tests: a sheet of the panel keeps it open; an unrelated window still
      dismisses; the `_NSAlertPanel` class name alone does not decide it

## Related
- `worksync-v8xr` — the same alert's confirm-time revalidation
