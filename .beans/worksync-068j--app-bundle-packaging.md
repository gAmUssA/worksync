---
# worksync-068j
title: App bundle packaging
status: completed
type: epic
priority: normal
created_at: 2026-08-14T00:34:34Z
updated_at: 2026-08-14T01:49:25Z
parent: worksync-dopp
---

Script-built WorkSync.app per SPEC §3/§3.1. The bundle is a hard requirement for UNUserNotificationCenter, SMAppService, LSUIElement, and stable TCC — validate it before anything depends on it.
