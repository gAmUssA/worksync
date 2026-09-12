---
# worksync-kq8e
title: 'setup: keep-it-running card'
status: todo
type: task
created_at: 2026-08-17T19:28:43Z
updated_at: 2026-08-17T19:28:43Z
parent: worksync-9xmk
---

[ ] Launch-at-login toggle, defaulting OFF (§10 — auto-enabling it is a spec
violation)
[ ] One sentence: nothing syncs unless something is running. This is the #1
misdiagnosis in both SPEC §11 and the README.
[ ] Handle `.requiresApproval` via `SMAppService.openSystemSettingsLoginItems()`
— registration succeeds, so every other signal looks like success while
nothing runs
