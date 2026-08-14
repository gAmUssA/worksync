---
# worksync-z356
title: 'build-app.sh: bundle assembly + codesign + DR check'
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:34:35Z
updated_at: 2026-08-14T01:44:37Z
parent: worksync-068j
blocked_by:
    - worksync-ph6v
---

SPEC §3.1 rule 1. scripts/build-app.sh, strict order:
- [ ] swift build -c release
- [ ] Assemble WorkSync.app/Contents/{MacOS,Resources}; binary -> Contents/MacOS/worksync
- [ ] Copy SwiftPM <Package>_<Target>.bundle resource bundles into Contents/Resources/ (Bundle.module traps without them)
- [ ] Copy Resources/Info.plist -> Contents/, AppIcon.icns -> Contents/Resources/
- [ ] codesign --force --sign "<identity>" --timestamp --options runtime --entitlements Resources/worksync.entitlements (identity as argument; ad-hoc fallback for CI). Never --deep
- [ ] Verify designated requirement via codesign -d -r- ; FAIL the build on bare cdhash when a real identity was requested
- [ ] lsregister -f WorkSync.app
- [ ] tar.gz artifact with version


## Progress notes
Script works end to end (assembly, codesign, DR verification, lsregister, tarball). Identity selection switched to SHA-1 hash — duplicate same-named certs make name-based selection ambiguous.

FINDING (2026-08-13): Apple Development certificates are NOT usable for this bundle: AMFI rejects them at exec with error -420 'The signature on the file is invalid' because there is no embedded provisioning profile (Xcode normally embeds one). Even get-task-allow does not help. The identity grep must prefer 'Developer ID Application' or the self-signed 'WorkSync Dev' cert and must NOT fall back to 'Apple Development'.


## Summary of Changes
scripts/build-app.sh complete: release build, bundle assembly, codesign (identity by SHA-1 hash; auto-selects only 'Developer ID Application' or 'WorkSync Dev' — Apple Development certs are AMFI-invalid without an embedded provisioning profile), bare-cdhash DR check, lsregister, tarball. Verified DR: identifier "io.gamov.worksync" and certificate leaf = H"800b705e..." (stable across rebuilds).
