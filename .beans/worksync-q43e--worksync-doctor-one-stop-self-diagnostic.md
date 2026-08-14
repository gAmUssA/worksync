---
# worksync-q43e
title: worksync doctor — one-stop self diagnostic
status: todo
type: epic
priority: normal
created_at: 2026-08-14T03:10:50Z
updated_at: 2026-08-14T03:40:03Z
parent: worksync-ikky
---

One command that checks everything that can quietly go wrong, so "why didn't my change sync?" has a first stop that is not guesswork.

Design settled after studying brew/flutter/gh/npm/mise doctor commands (all run locally, exit codes observed rather than assumed).

## Structural decision, make this first
Define the check result as a value type in WorkSyncCore with `severity`, `title`, `detail`, `remediation`. Every check returns one. Homebrew had to retrofit exactly this (PR #23044) before `--json` was possible, and it is what keeps checks unit-testable against the in-memory fake with no TCC grant in CI.

## Severity and exit codes — reuse the existing four, add none
- 0: no errors (warnings may print)
- 2: calendar access not fullAccess. HIGHEST PRECEDENCE — without it every calendar check is unknowable rather than failing
- 1: config missing/unparseable/invalid, or a calendar that does not resolve
- 3: a check itself blew up
Warnings NEVER change the exit code. `--strict` promotes them to 1 for CI — deliberate opt-in, unlike brew doctor which exits 1 on anything at all (verified: 4 cosmetic warnings -> exit 1). flutter doctor exits 0 even with a hard [x] (verified) because ExitStatus never reaches the process exit code.
Borrow flutter's `notAvailable`: when access is denied, downstream checks are "skipped (needs calendar access)", not failed — one root cause instead of five symptoms.

## Output
Two levels: one headline line per check with a leading glyph, then indented detail lines with their own glyphs. Glyph carries severity; colour is redundant decoration (pipe-safe). Findings on STDOUT — brew doctor writes everything to stderr, so `brew doctor | grep` returns nothing. Default prints passing checks too: with ~10 checks green lines are the difference between "everything else is fine" and "everything else was skipped". `-v` adds detail; `--json` from day one.

## Hard rules
- No check without a remediation the user can execute (npm's own TODO says this and they still shipped checks without one)
- No check that can be wrong on a healthy machine. npm doctor scored 100% false positives here (2 of 2)
- Fast and local: no network, no full calendar scan
