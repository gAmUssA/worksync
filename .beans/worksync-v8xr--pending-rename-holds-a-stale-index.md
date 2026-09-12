---
# worksync-v8xr
title: 'Settings: a pending rename confirms against a stale index'
status: todo
type: bug
created_at: 2026-09-12T01:31:24Z
updated_at: 2026-09-12T01:31:24Z
---

Found by an independent reviewer during PR #7. **Pre-existing on `main`** —
`PendingRename(index:from:to:)` predates that branch — so it is filed rather
than bundled into the settings-UI PR.

## The defect

`pendingRename` captures the source's **index** when the rename warning is
raised. Confirmation then acts on that index. Between raising and confirming,
the user can add, remove or reorder sources.

The bounds check prevents a trap, so this does not crash. Instead:

- Confirmation never verifies the live source at that index still has
  `rename.from`. If the list changed, the rename can land on a **different
  source**.
- The destination-collision check is performed when the warning is raised and
  **not repeated** at confirmation, so a rename can complete into an id another
  source has taken meanwhile.

Both failure modes are silent: valid config, wrong source renamed.

## The deeper point the reviewer made

A source id is **editable data, not lifetime identity**. It can be renamed, and a
deleted source's id can be reused by a new one. So resolving by id — the fix
applied to the title-filter paths in PR #7 — is correct as far as it goes but is
not a general identity solution for the editor session.

The suggested shape: a stable editor-session token per source, minted when the
editing config is loaded, surviving rename and reorder, invalidated on deletion.
Scalar, row and draft callbacks capture and resolve **that**, while the config id
stays ordinary editable data.

That is a refactor of the settings editor's identity model, not a patch, which is
why it wants its own change.

[ ] Retain the source's identity (not index) in `PendingRename`
[ ] Resolve again at confirmation; verify the live source still has `from`
[ ] Repeat the destination-collision check against current sources at confirm
[ ] Consider the stable editor-session token for sources generally
[ ] Tests: rename-in-flight with a concurrent add/remove/reorder; delete and
      recreate under the same id; confirm-into-taken-id

## Related
- PR #7 (settings UI) — fixed the same class for the title-filter paths
- `worksync-h4pd` — `sourceOrigins` identity questions from PR #8
