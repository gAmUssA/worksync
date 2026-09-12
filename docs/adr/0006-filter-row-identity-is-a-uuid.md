# ADR-0006 — Filter row identity is a UUID minted when the form opens

Status: accepted
Date: 2026-09-12

## Context

Title-filter lists are `[String]` in config, which is the right file shape.
The settings form used `ForEach(entries.indices, id: \.self)` and committed
edits by that index. Removing row 0 of `[A, B, C]` shifted every later row;
a text field still live for the old row 1 then wrote index 1, which was now
C. The range check succeeded, so nothing trapped and nothing was logged.

The string itself cannot be the identity either: two rows may hold the same
text while one of them is being typed.

## Decision

`TitleFilterRowIDs` (`Sources/WorkSyncCore/TitleFilterRows.swift`) mints a
UUID per row when the form opens (`seed`), and on append (`appended`).
`ForEach` keys on `TitleFilterRow.id`. A commit resolves through
`position(of:in:count:)`. A row that moved is found where it moved; a row
that was removed resolves to nil and the commit is dropped.

A list nobody seeded, or whose UUID count no longer matches the entries,
falls back to `TitleFilterRowID.position` — the old behaviour, kept so
`ForEach` still has stable-across-render keys.

## Consequences

- `[String]` stays the config shape. The UUIDs live only in the editing
  session and die with `closeSettings`.
- The positional fallback *is* the original bug for any list that has
  entries and was not seeded. Today `openSettings` seeds every list
  (including empty ones) and `addTitleFilter` calls `appended`, so that
  path is not reached. A future writer of filter arrays that skips
  `seed` / `appended` reintroduces a silent wrong-row write. The fallback
  is a `ForEach` safety net, not a degrade with a warning.
- `seed` with a changed count remints every UUID. Live fields holding the
  old ids then resolve to nil (dropped keystrokes), not the wrong row.
  `seed` is only called from `openSettings`.
