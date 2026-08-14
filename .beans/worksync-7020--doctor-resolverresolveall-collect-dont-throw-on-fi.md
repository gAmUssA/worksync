---
# worksync-7020
title: 'doctor: Resolver.resolveAll (collect, don''t throw on first)'
status: todo
type: task
created_at: 2026-08-14T03:37:43Z
updated_at: 2026-08-14T03:37:43Z
parent: worksync-q43e
---

Resolver.resolve throws on the FIRST failure, so a config with three typos reports one. Right for sync, wrong for a diagnostic — the point is the complete list so the user edits the file once.

Note this is a papercut in the CURRENT code too, not only for doctor.
- [ ] resolveAll(config:calendars:) collecting per-source results
- [ ] Existing resolve() becomes the throwing wrapper over it
- [ ] Covers four candidate checks at once: typo'd account, typo'd calendar, ambiguous duplicate titles, and the source==target feedback-loop guard
- [ ] Reuse ResolutionError.errorDescription — it already lists available accounts and points at 'worksync calendars'
