---
# worksync-oz46
title: Info.plist, entitlements, AppIcon.icns
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T01:44:37Z
parent: worksync-068j
---

SPEC §3. Bundle resources:
- [ ] Resources/Info.plist: CFBundleIdentifier io.gamov.worksync, CFBundleExecutable worksync, CFBundlePackageType APPL, CFBundleName WorkSync, version keys, LSMinimumSystemVersion, CFBundleIconFile AppIcon, NSCalendarsFullAccessUsageDescription, LSUIElement=true
- [ ] Resources/worksync.entitlements with com.apple.security.personal-information.calendars (required under hardened runtime)
- [ ] Resources/AppIcon.icns generated from assets/icon-1024.png (iconutil pipeline; commit both)
- [ ] README note: create local signing cert (Certificate Assistant, Always Trust for Code Signing)


## Summary of Changes
Info.plist (all keys incl. LSUIElement, NSCalendarsFullAccessUsageDescription), worksync.entitlements (calendars, required under hardened runtime), AppIcon.icns generated from assets/icon-1024.png via sips+iconutil.
