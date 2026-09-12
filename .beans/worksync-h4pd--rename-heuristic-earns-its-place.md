---
# worksync-h4pd
title: 'ConfigWriter: does the rename-inference heuristic earn its place?'
status: todo
type: chore
created_at: 2026-09-12T01:01:36Z
updated_at: 2026-09-12T01:01:36Z
---

Raised in the independent review of PR #8 (merged as `f1343f0`). Not a defect in
what shipped — a design call worth making deliberately rather than by default.

`updateSources` takes explicit `sourceOrigins` and ALSO keeps a fallback
heuristic for when it is nil: an unknown id adopts a unique prior source with
identical non-id fields whose old id is gone.

## Why it may not earn its place

- **`MenuBarModel` is the only caller and always passes origins**, seeded with an
  identity mapping for every source. The heuristic serves no current caller.
- **`delete a + add an identical c` and `rename a -> c` are the same input.** On
  the nil path the heuristic picks "rename", so a new source inherits the deleted
  one's documentation. A comment describing a source the user deleted, now
  sitting above a different one, is arguably worse than the missing comment
  `main` used to produce. Both failure modes are invisible.
- It silently does not fire when a field changed alongside the rename.

Dropping it would make `sourceOrigins` the single source of truth. The cost is
that a future non-UI caller gets no inference — which is arguably correct, since
inference is what produces the wrong-comment case above.

## Also from that review

- **A partial origins map silently loses comments.** The "include unchanged
  sources too, absence means new" contract is documented on `save` but nothing
  enforces it. Cheap guard: when `sourceOrigins` is non-nil, assert in debug
  builds that every `new` id is either a key in the map or absent from
  `previousByID`. Catches "I only listed the renames" without changing shipping
  behaviour.
- `sourceOrigins` has no test at the model layer — only through `ConfigWriter`.
- `testMatchingOtherSourcesFieldsDoesNotMoveComments` is a control, not a
  defect-catching test; worth labelling as such so nobody reads it as coverage.

[ ] Decide: keep the heuristic, or make `sourceOrigins` mandatory
[ ] Either way, add the debug-only partial-map guard
[ ] Add model-layer coverage for origins tracking

## Related
- PR #8, PR #6 (the review that found the original rename defect)
