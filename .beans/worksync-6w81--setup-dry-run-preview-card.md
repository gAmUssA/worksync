---
# worksync-6w81
title: 'setup: dry-run preview card'
status: todo
type: task
created_at: 2026-08-17T19:28:43Z
updated_at: 2026-08-17T19:28:43Z
parent: worksync-9xmk
---

The highest-value step in the milestone and the only one that earns trust.

The felt first-run milestone is not "all checks green" — it is seeing the plan:
"12 blockers would be created on Work / Calendar over 21 days". Doctor never
runs a pass by design, so this cannot come from it. HIG's "teach through
interactivity" points straight here, and `sync --dry-run` already exists.

[ ] Run the dry-run, show the plan summary and the target calendar BY NAME
[ ] Button: Sync now — the first real write is never automatic
[ ] Names the fact that it writes to a real work calendar, and that purge is
the only undo
