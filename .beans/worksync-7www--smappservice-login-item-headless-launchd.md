---
# worksync-7www
title: SMAppService login item + --headless launchd
status: completed
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T03:57:39Z
parent: worksync-5lsv
blocked_by:
    - worksync-ccaa
---

SPEC §10. Launch at login:
- [x] install-agent -> SMAppService.mainApp.register(); uninstall-agent -> unregister(); idempotent
- [x] Menu toggle OFF by default; state always read from SMAppService.mainApp.status (never cached); re-register if app moved
- [x] .requiresApproval handled: explain + SMAppService.openSystemSettingsLoginItems()
- [x] install-agent --headless: launchd plist running the one-shot CLI on StartInterval; bootstrap/bootout; idempotent


## Summary of Changes
SMAppService.mainApp login item with status always re-read (never cached) and .requiresApproval deep-linked to System Settings; --headless launchd plist for the icon-free path; uninstall-agent reverses both. Headless verified live end to end. Login-item registration needs the app in /Applications to confirm — README step for M5.


## Correction (2026-08-14)
The earlier note that login-item registration needs /Applications was WRONG. Verified from build/: install-agent reported 'Launch at login: enabled' and uninstall-agent cleared it. SMAppService resolves the bundle fine from any location.
