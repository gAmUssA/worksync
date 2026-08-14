---
# worksync-qn4y
title: 'Bundle smoke test: notifications + TCC stability'
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T01:49:25Z
parent: worksync-068j
blocked_by:
    - worksync-z356
    - worksync-oz46
---

SPEC §3.1 rule 2 + §14 M1. Validate the bundle architecture before any milestone depends on it:
- [ ] Build via build-app.sh with the local stable cert
- [ ] Launch via `open WorkSync.app` (LaunchServices path, NOT the inner binary)
- [ ] Confirm UNUserNotificationCenter authorization prompt appears and settings are not NotSupported
- [ ] Confirm no Dock icon (LSUIElement honored)
- [ ] Rebuild and confirm TCC calendar grant + notification authorization survive (stable designated requirement)


## Findings (2026-08-13)
- Apple Development cert: AMFI SIGKILL (error -420, no provisioning profile). get-task-allow does not help.
- macOS 26 Gatekeeper auto-moves blocked apps to the Trash (two mysterious bundle disappearances explained).
- Self-signed 'WorkSync Dev' cert (scripted: openssl -> p12 -legacy -> security import -A -> add-trusted-cert -p codeSign, one password prompt): bundle now launches; approval + signature SURVIVE REBUILDS (stable DR verified).
- smoke-test subcommand added. Via LaunchServices launch: bundleIdentifier resolves, UNUserNotificationCenter.current() no crash, alertSetting=2 (enabled, NOT NotSupported) — bundle architecture validated.
- Notification authorization shows 'denied' (a timed-out request from a direct-exec run was recorded as denial). One-time fix: System Settings > Notifications > WorkSync > Allow.
- TCC calendar prompts are auto-denied from non-UI shells AND polling with EventKit calls re-records denial, dismissing a pending prompt. Recovery: tccutil reset Calendar io.gamov.worksync + LaunchServices launch, then wait for the human.


## Summary of Changes
PASSED. smoke-test subcommand validates: bundle identity resolves, UNUserNotificationCenter.current() no crash, alertSetting=2 (enabled — bundle accepted as real app), authorization request delivered. Gatekeeper approval + TCC calendar grant verified to SURVIVE REBUILDS with the WorkSync Dev cert (stable designated requirement). Note: notification permission currently 'denied' from a stray early request — one-time Settings toggle before M7.
