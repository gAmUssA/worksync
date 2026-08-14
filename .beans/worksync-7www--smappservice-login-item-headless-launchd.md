---
# worksync-7www
title: SMAppService login item + --headless launchd
status: todo
type: feature
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T00:35:51Z
parent: worksync-5lsv
blocked_by:
    - worksync-ccaa
---

SPEC §10. Launch at login:
- [ ] install-agent -> SMAppService.mainApp.register(); uninstall-agent -> unregister(); idempotent
- [ ] Menu toggle OFF by default; state always read from SMAppService.mainApp.status (never cached); re-register if app moved
- [ ] .requiresApproval handled: explain + SMAppService.openSystemSettingsLoginItems()
- [ ] install-agent --headless: launchd plist running the one-shot CLI on StartInterval; bootstrap/bootout; idempotent
