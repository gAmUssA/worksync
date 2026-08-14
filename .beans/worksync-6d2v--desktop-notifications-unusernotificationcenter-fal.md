---
# worksync-6d2v
title: Desktop notifications (UNUserNotificationCenter + fallback)
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T17:06:13Z
parent: worksync-4p15
blocked_by:
    - worksync-fkyu
---

SPEC §11.2 / §3.1 rule 2. Desktop notifications:
- [ ] Notifier protocol in EventKit-free core; UNUserNotificationCenter implementation + osascript display-notification fallback (AppleScript escaping: backslashes first, then quotes)
- [ ] Lazy .alert authorization the first time notify != off; fall back + log path used when denied/NotSupported
- [ ] Body reuses the exact pass-summary string (single source of truth); error notifications carry the underlying error text
- [ ] Lock-skipped passes post nothing; default "errors" respected
