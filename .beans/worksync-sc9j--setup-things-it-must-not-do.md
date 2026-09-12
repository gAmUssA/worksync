---
# worksync-sc9j
title: 'setup: things it must NOT do'
status: todo
type: task
created_at: 2026-08-17T19:28:43Z
updated_at: 2026-08-17T19:28:43Z
parent: worksync-9xmk
---

Enforce in review. Each is a real failure mode observed in a shipped app or an
explicit HIG prohibition.

[ ] No `hasCompletedOnboarding` boolean as the gate — visibility derives from
check state. This is THE bug this milestone exists to avoid.
[ ] No Allow/Skip/Not now/Cancel in the priming card; no mockup of the system
dialog
[ ] No explaining macOS itself beyond the deep-link buttons doctor provides
[ ] No blocking on warnings
[ ] No auto-enabling launch at login, no automatic first real sync
[ ] No marketing slides — every card contains the control that satisfies its
own check
[ ] No config write bypassing the comment-preserving writer, and setup must
never become the ONLY way to configure something (§2)
[ ] No `tccutil reset` tricks. Bartender ships this; it silently discards
grants the user set deliberately.

## Deliberately NOT taught in the tour

Source order deciding dedup, source ids being permanent, and colors coming
from calendars are all bite-worthy — and all already explained in the README's
Configuring section. A first-run user has one source and cannot yet be bitten
by ordering. Teaching it now is exactly the "teach too much" failure HIG warns
about; those belong as contextual tips (TipKit, macOS 14+) next to the source
list, not in setup.
