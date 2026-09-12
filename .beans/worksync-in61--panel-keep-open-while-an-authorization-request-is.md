---
# worksync-in61
title: 'panel: keep open while an authorization request is in flight'
status: todo
type: task
created_at: 2026-08-17T19:29:05Z
updated_at: 2026-08-17T19:29:05Z
parent: worksync-4t1b
---

[ ] Add an "authorization request in flight" input to `PanelDismissPolicy` —
the same shape as the existing attached-sheet and in-flight-resize rules, so
the decision stays a pure, tested function rather than a special case in the
monitor
[ ] Verify against the running app: open setup, trigger the prompt, click
Allow, and confirm the panel is still there
[ ] Test both edges: it must NOT keep the panel open forever if the dialog is
dismissed some other way (Escape, or granting in System Settings instead)
