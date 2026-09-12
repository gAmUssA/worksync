# ADR-0008 — Validate move callbacks against captured rendered source order

Status: accepted
Date: 2026-09-12

## Context

Source order is load-bearing (ADR-0009). SwiftUI `onMove` hands back
`IndexSet` offsets into the list the gesture was computed against. That is
the one settings callback that cannot carry a `SourceHandle`: the framework
does not say which rows moved, only where.

An in-range check is not enough. Drag B at offset 1 of `[A, B, C, D]` toward
offset 3, lose A before the drop, and offsets `(1, 3)` still fit `[B, C, D]`
while naming C, which the user never touched. Applying that silently changes
who wins dedup.

## Decision

`SettingsView` captures `let rows = model.sourceRows` when the list is
rendered and passes `rows.map(\.id)` into `onMove`.
`MenuBarModel.moveSources` calls `SourceOrder.canMove` (`Sources/WorkSyncCore/SourceOrder.swift`)
with that snapshot as `rendered` and `sourceRows.map(\.id)` at drop as
`current`. If the identity sequences differ, the drop is ignored. If they
match, the offsets are still bounds-checked, then `Array.move` runs — the
framework's move, not a reimplementation.

## Consequences

- A callback whose captured identity sequence differs from the current list
  is rejected, even when its offsets remain in range. Matching sequences still
  require valid offsets. This is the guarantee exercised by the pure guard
  and stale-callback checks.
- The snapshot is taken at **render**, not at drag start. There is no explicit
  drag-start snapshot. Native SwiftUI behavior during an intervening render
  was not exercised: it is not established whether the framework retains the
  old callback, replaces it, rebases offsets, or cancels the drag. If it delivers
  old offsets through a new callback whose snapshot matches the current list,
  the identity guard cannot detect that mismatch. This is a conditional risk,
  not a reproduced native drag defect or a guarantee that every changed-list
  gesture is rejected.
- Ignoring a drop is safer than guessing. It can surprise a user whose
  list changed under them; they can drag again.
