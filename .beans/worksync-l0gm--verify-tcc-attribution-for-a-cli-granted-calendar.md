---
# worksync-l0gm
title: Verify TCC attribution for a CLI-granted calendar permission
status: todo
type: bug
created_at: 2026-08-17T19:29:05Z
updated_at: 2026-08-17T19:29:05Z
parent: worksync-n2bv
---

The README claims the first real run must happen in a terminal because macOS
shows the prompt to the foreground process. If the grant is attributed to the
RESPONSIBLE process (Terminal) rather than to WorkSync.app's own designated
requirement, then the menu bar app's first launch is still notDetermined and
prompts again — and the README is telling users to do something that does not
achieve what it claims.

Does not change the M9 design; it makes the in-app grant step non-optional
rather than merely nicer. It does change what the README should say.

[ ] Test: grant via Terminal on a clean TCC state, then launch WorkSync.app
fresh and read `EKEventStore.authorizationStatus(for:.event)`
[ ] Correct the README either way
