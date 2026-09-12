# ADR-0007 — Draft state is stored per (field, source handle), not as a single owner

Status: accepted
Date: 2026-09-12

## Context

The add-field draft started as one `owner` plus a dictionary of field text.
A guard could only ask whether that source still existed. Two live sources
defeated it: the user selected B and typed; a late setter from still-alive A
took ownership and wiped B's text. Existence checks cannot distinguish "the
source I left" from "the source I am looking at" when both are in the config.

## Decision

`TitleFilterDrafts` (`Sources/WorkSyncCore/TitleFilterDrafts.swift`) is
`[SourceHandle: [String: String]]`. `setText` writes only that handle's slot.
A late setter from A writes A's slot, which the selected card is not reading.

Drafts still do not outlive attention: `select` calls `removeAll` (except on
rename, which keeps the same handle). `closeSettings` drops everything. A
retired handle is refused by `setText(_:field:of:in:)` so a field built
before a removal cannot store text against a dead source.

## Consequences

- Typing into B no longer wipes A's slot. That wiping *was* the bug, even
  though it looked like "the user moved on." The form still *shows* empty
  add fields on the unselected card; a selection change still clears every
  slot, so half-typed text does not reappear when the user comes back.
- `remove(_:)` exists for a deleted source but the model currently relies on
  `select` → `removeAll`. That is enough today because delete always
  reselects. A later change that stops calling `removeAll` on delete would
  leave a dead-handle slot until the form closed — harmless while handles
  are UUIDs, but the dedicated `remove` is the one that matches the comment.
- Save commits the *selected* handle's drafts, not every slot. Unselected
  leftover text is discarded with the next `select` / close, not written.
