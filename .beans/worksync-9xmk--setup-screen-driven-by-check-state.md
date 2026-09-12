---
# worksync-9xmk
title: Setup screen driven by check state
status: todo
type: epic
created_at: 2026-08-17T19:28:13Z
updated_at: 2026-08-17T19:28:13Z
parent: worksync-n2bv
---

One scrolling screen of cards in the panel. Each card collapses to a checkmark
row when its check passes. The screen is replaced by the dashboard once every
prerequisite is green, and is re-entered automatically when one stops being.

Panel is 320pt wide (`PanelView.swift`), not 360 — four cards at that width is
tight but workable given the height morph. Check the calendar popups do not
truncate long account names.

## Card sequence

0. Launch: open the panel ONCE on first launch. An accessory app that starts
   and visibly does nothing reads as broken; Rectangle and Ice both force UI up.
1. What WorkSync does — 3 lines + the privacy line. One button: Continue.
2. Choose calendars — resolver-backed popups, writes the config.
3. Preview — dry-run plan, then Sync now.
4. Keep it running — launch at login, off by default.

## Make Health and Setup the same view, filtered

The risk in this epic is two renderings of one data set drifting apart. Render
both from one view with a different filter and ordering, not two views.
