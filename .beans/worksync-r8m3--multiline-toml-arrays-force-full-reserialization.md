---
# worksync-r8m3
title: Multiline TOML arrays force full reserialization on edit
status: done
type: bug
created_at: 2026-09-11T21:15:16Z
updated_at: 2026-09-12T03:37:22Z
---

`TomlDocument.setValue` replaces only the line carrying the key. When a user
hand-formats an array across several lines:

    title_matches = [
      "Personal Commitment",
      "Focus Time",
    ]

editing that key rewrites the header line and leaves the continuation lines
behind. The result does not parse, `ConfigWriter`'s round-trip guard catches it,
and the save falls back to full serialization — which preserves every value but
drops the user's comments and layout, reporting only the generic reserialization
warning.

Found independently by both reviewers on PR #1. Not data loss, and the guard
does its job, so it did not gate that PR. It predates the title filters:
`skip_weekdays` has the same shape. The filters make it easier to hit, because a
list of title substrings is the kind of thing a user naturally wraps.

[ ] Replace the whole multiline value, or handle arrays structurally in
    `TomlDocument.setValue` rather than line-wise
[ ] Test: hand-wrap `skip_weekdays` and `title_matches` across lines, edit one,
    assert comments survive and no fallback warning is emitted

## Closed — 2026-09-12

Fixed and shipped in v0.4.0 (PR #4, merged 5d68529). `TomlDocument.setValue` now
replaces the whole span of a wrapped array and preserves every comment in it —
opening-line, interior, inline and after the closing bracket — keeping the array
wrapped when interior comments exist rather than collapsing at their expense.

The same PR fixed two adjacent defects the work surfaced: the bracket/comment
scanner did not recognise TOML literal strings (`title_matches = ['[']` could
swallow a later key), and `splitValueAndComment` truncated `'Busy #1'` at the `#`.
