---
# worksync-v8xr
title: 'Settings: a pending rename is not revalidated at confirm time'
status: todo
type: bug
created_at: 2026-09-12T01:31:24Z
updated_at: 2026-09-12T01:31:24Z
---

Found by an independent reviewer during PR #7. **Pre-existing on `main`** —
`PendingRename(index:from:to:)` predates that branch — so it is filed rather
than bundled into the settings-UI PR.

## The defect

As filed: `pendingRename` captured the source's **index** when the rename
warning was raised, so a concurrent add, remove or reorder could land the
rename on a **different source**.

**That half is fixed.** `PendingRename` now holds a `SourceHandle`
(`MenuBarModel.swift:1153`), and `applyRename` resolves the handle to the id
the config currently holds, so the rename cannot reach the wrong source however
the list moves underneath it.

What is still open is the revalidation at confirm time:

- `confirmPendingRename` does not re-check that the source still carries
  `rename.from`. The handle guarantees the right *source*; it does not
  guarantee the user is still answering the question that was asked.
- The destination-collision check runs when the warning is raised and is **not
  repeated** at confirmation, so a rename can still complete into an id another
  source has taken meanwhile. This one is silent: valid config, two sources
  racing for a name.

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

[x] Retain the source's identity (not index) in `PendingRename` — shipped as
      `SourceHandle`; see ADR-0005
[ ] Verify at confirmation that the live source still carries `from`
[ ] Repeat the destination-collision check against current sources at confirm
[x] Consider the stable editor-session token for sources generally — that is
      what `SourceHandle` became
[ ] Tests: confirm-into-taken-id; confirm after the source's id changed by
      another path

## Related
- PR #7 (settings UI) — fixed the same class for the title-filter paths
- `worksync-h4pd` — `sourceOrigins` identity questions from PR #8
