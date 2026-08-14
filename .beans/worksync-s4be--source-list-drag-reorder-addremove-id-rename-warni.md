---
# worksync-s4be
title: 'Source list: drag-reorder, add/remove, id-rename warning'
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T04:39:43Z
parent: worksync-o7n2
blocked_by:
    - worksync-kss0
---

SPEC §11.1. Source list management:
- [x] Drag-reorder (order decides dedup — must round-trip into config.toml block order)
- [x] Visible add/remove toolbar buttons (remove disabled when nothing selected)
- [x] id-rename confirmation alert: explains marker orphaning + purge --source <old-id> recovery; new sources exempt


## Summary of Changes
Drag-reorder via List onMove, visible add/remove pair, and an id-rename confirmation naming the exact purge command. The warning decision lives in WorkSyncCore.SourceRenamePolicy with its own tests — it must fire for a saved id and must NOT fire for a never-saved one, or it trains users to dismiss the dialog that matters.
