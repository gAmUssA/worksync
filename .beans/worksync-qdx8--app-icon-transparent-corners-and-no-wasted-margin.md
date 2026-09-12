---
# worksync-qdx8
title: 'App icon: transparent corners and no wasted margin'
status: todo
type: bug
created_at: 2026-08-17T19:29:05Z
updated_at: 2026-08-17T19:29:05Z
---

`assets/icon-1024.png` reports `hasAlpha: no` — the white background is baked
in — and the artwork occupies only x=177..846 of 1024, wasting 17% margin on
every side. So macOS renders the whole white canvas: on a dark Dock or in dark
mode it is a white square with a small icon floating inside it.

A mechanical fix is prepared and reviewed: crop to the artwork, resize to the
macOS icon grid (~80% of canvas), mask to a squircle at 22.37% corner radius,
transparent outside. Verified corners become (0,0,0,0) and the halo from the
original drop shadow is cut by insetting the crop 14px.

Open question for the owner: ship the mechanical fix, or redesign. The
underlying art is AI-generated raster and busy at 16pt, where the two
overlapping calendars and the arrows will not read.

[ ] Whichever route: regenerate `Resources/AppIcon.icns` from the fixed master
[ ] Check legibility at 16pt and 32pt, not just 1024
[ ] Verify against both light and dark menu bars
