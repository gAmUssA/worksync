# ADR-0005 — A source id is editable data; identity is a `SourceHandle`

Status: accepted
Date: 2026-09-12

## Context

`[[source]]` blocks have an `id` that is also embedded in every marker
(ADR-0010). The settings form lets the user rename that id, and a removed id
can be reused by a new source. Callbacks that carried only the string
therefore named "whatever is called that *now*".

That was not obvious up front. Several rounds of settings bugs were the same
defect in new clothes: a late edit from one source landed on another after a
rename, a removal, or a reuse of the old id. Index-based addressing failed
the same way when the list shifted.

## Decision

While the settings form is open, each source has a `SourceHandle`
(`Sources/WorkSyncCore/SourceHandles.swift`) — a UUID minted at load (or at
add). Controls capture the handle. `SourceHandles.resolve` returns the id it
currently names, or nil if the source is gone.

Rename moves the id under the same handle (`rename(_:to:)`). Removal retires
the handle. A callback still holding a retired handle resolves to nothing and
is ignored, never retargeted.

## Consequences

- Nothing in the editor may key long-lived callback state on the config id or
  on array index. New controls have to take a `SourceHandle`.
- Handles do not survive closing the form. `seed` on `openSettings` mints a
  new set; a stale handle from a previous session must not resolve.
- The config file still speaks ids. The writer, the marker, and purge keep
  using the string. Handles exist only for the editing session.
- This was learned the expensive way. Treating "the id is identity" as
  obvious will recreate the same class of bug.
