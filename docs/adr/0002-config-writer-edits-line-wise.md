# ADR-0002 — The config writer edits text line-wise instead of reserializing

Status: accepted
Date: 2026-09-12

## Context

`config.toml` is hand-editable (SPEC §2). The example file is comment-dense on
purpose. TOMLKit wraps toml++, which discards comments at parse and, on
serialize, alphabetizes keys and drops blank-line structure. A
load-parse-write round trip would return a file the user no longer recognizes.
SPEC §4.3 recorded this before the writer existed; the implementation had to
choose how to write without doing that.

## Decision

`ConfigWriter` (`Sources/WorkSyncCore/ConfigWriter.swift`) diffs the intended
`Config` against the previous parse and rewrites only the changed lines in the
original text, via `TomlDocument.setValue`. Trailing `#` comments on those
lines are kept.

`verified(_:matches:fallback:)` then parses the produced text and compares it
to the intended value. If the line edit does not round-trip, the writer falls
back to `serialize` — a full rewrite that loses comments and layout — and
checks that too. Either way it refuses to overwrite the file if the result
would not load back as written (`ConfigWriteError.roundTripFailed`). A `.bak`
copy is taken first.

The outcome is reported (`ConfigWriteOutcome.preserved` vs `.reserialized`) so
a silent full rewrite cannot pass as a comment-preserving save.

## Consequences

- Hand-written comments survive a settings save on the happy path.
- The line editor is a second TOML implementation sitting next to TOMLKit. It
  has to understand arrays, quotes, and section layout well enough not to
  corrupt the file; when it does not, `verified` is the only backstop, and the
  cost of that backstop is losing every comment.
- Wrapped / multiline arrays, exotic quoting, and any construct the line
  walker does not understand force the fallback. That is acceptable data loss
  only because it is reported.
- A writer that skipped the self-check could hand the next sync an unparseable
  file. That must not happen.
