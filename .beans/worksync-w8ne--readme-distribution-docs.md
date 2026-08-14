---
# worksync-w8ne
title: README + distribution docs
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T04:30:56Z
parent: worksync-rt48
---

SPEC §12/§13/§4.2. README + docs:
- [x] Install: curl|tar path as primary (no quarantine xattr); xattr -d fallback for browser downloads (macOS 15+ has no Control-click bypass); local re-sign for stable TCC; PATH symlink for CLI
- [x] First-run: interactive Terminal run for the TCC prompt before enabling login item
- [x] Coloring: target_calendar mapping + title prefixes; Exchange free/busy caveat for secondary calendars
- [x] Manual test checklist from SPEC §13 verbatim
- [x] Operational note: nothing syncs unless something is running


## Summary of Changes
README written. Leads with what the tool does and a three-line before/after, then the two genuinely surprising things (first run must be in a terminal for the permission prompt; nothing syncs unless something is running), the three config facts that are easy to get wrong (source order decides who wins, a source id is permanent, colours come from calendars), the signing rationale, and the manual checklist for behavior unit tests cannot reach.


## Post-review fix (v0.1.1)
The README told users to run 'worksync ...' without ever putting it on PATH — the download is an app bundle, so the command did not exist. Added an explicit symlink step; build-app.sh now prints it with the right absolute path. Verified by running the documented flow verbatim against the published release.
