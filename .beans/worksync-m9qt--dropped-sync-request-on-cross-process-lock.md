---
# worksync-m9qt
title: 'A sync request lost to another process is silently dropped'
status: todo
type: bug
created_at: 2026-09-12T14:30:33Z
updated_at: 2026-09-12T14:30:33Z
---

Found by the SPEC divergence audit (2026-09-12).

SPEC §11 says cross-process lock contention must "set a pending flag and re-run
once the current pass finishes."

`MenuBarModel.finish` handles `.skippedLocked` with `break`. `pendingRequest`
is set only by an **in-process** call arriving while `isSyncing`. A request that
loses the `flock` to the CLI or the background agent gets no retry when that
other process finishes — it is simply dropped.

`PassRunner.run` returns `.skippedLocked` immediately, so the menu bar's
"Sync now" can appear to do nothing when the agent happens to hold the lock.

[ ] Queue a retry on `.skippedLocked`, or tell the user the pass was skipped
      and why — silently doing nothing is the worst of the three options
[ ] Test: a request that loses the lock results in either a retry or a visible
      explanation
