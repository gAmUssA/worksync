---
# worksync-bj4l
title: purge command (bounded span, --source, --yes)
status: todo
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T00:36:15Z
parent: worksync-ud6v
blocked_by:
    - worksync-h8ng
    - worksync-6ubu
---

SPEC §8. `worksync purge [--source ID] [--yes]`:
- [ ] Scans EVERY calendar on every account (not just configured targets) — catches strays from renamed ids / retargeted calendars
- [ ] Bounded span: now ± 365 days (predicateForEvents silently truncates >4-year spans; chunk if ever widened)
- [ ] Without --yes: count only, no deletes; with --source: that source only (id-rename recovery path)
- [ ] Deletes only valid-marker events; tests incl. stranded-calendar case
