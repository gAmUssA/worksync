---
# worksync-bj4l
title: purge command (bounded span, --source, --yes)
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:02Z
updated_at: 2026-08-14T02:36:10Z
parent: worksync-ud6v
blocked_by:
    - worksync-h8ng
    - worksync-6ubu
---

SPEC §8. `worksync purge [--source ID] [--yes]`:
- [x] Scans EVERY calendar on every account (not just configured targets) — catches strays from renamed ids / retargeted calendars
- [x] Bounded span: now ± 365 days (predicateForEvents silently truncates >4-year spans; chunk if ever widened)
- [x] Without --yes: count only, no deletes; with --source: that source only (id-rename recovery path)
- [x] Deletes only valid-marker events; tests incl. stranded-calendar case


## Summary of Changes
purge scans all calendars on all accounts, ±365d bounded span (PurgeScan.span, unit-tested to stay under the 4-year predicate truncation limit), --source filter, count-only without --yes, takes the run lock before deleting. Verified live: found 6 by marker through iCloud, --source with a wrong id matched nothing, --yes deleted 6, re-scan clean.
