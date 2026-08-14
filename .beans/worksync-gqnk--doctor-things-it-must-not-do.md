---
# worksync-gqnk
title: 'doctor: things it must NOT do'
status: completed
type: task
priority: normal
created_at: 2026-08-14T03:37:43Z
updated_at: 2026-08-14T05:18:57Z
parent: worksync-q43e
---

Enforce these in review; each is a real failure mode observed in a shipped tool.
- [ ] Never prompt for permission (read authorizationStatus only)
- [ ] Never read the TCC database — SIP-protected, needs Full Disk Access, undocumented schema. Asking for FDA to diagnose a Calendar permission is a worse privacy posture than the problem
- [ ] Never run a sync pass, not even dry — that is sync --dry-run's job. Doctor answers 'is the plumbing connected'
- [ ] Never print event titles or attendees. Doctor output is what users paste into bug reports, and the tool's whole premise is that personal details must not leak. Calendar/account TITLES only
- [ ] Never fix anything. npm doctor garbage-collects the cache during what the user was told is a checkup (reclaimed 5.1 GB here). For a tool whose delete path is guarded specifically because it is irreversible, a mutating diagnostic is unacceptable
- [ ] No network checks, no version/update check

## Cut from the original candidate list
- Stale run lock: NOT REACHABLE. RunLock uses flock(2), which the kernel releases when the descriptor closes — including crash, kill -9, reboot. The lock file persisting is normal and carries no information, so the check would fire on every healthy machine. Check that ~/.config/worksync is writable instead, if anything
- Managed-event count per calendar: duplicates worksync status (SPEC §8) and costs the slowest thing doctor could do. Footer pointer instead
- source==target guard: already part of resolution, do not resolve twice
