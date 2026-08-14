---
# worksync-m0b3
title: Status item + SwiftUI panel (NSPanel)
status: in-progress
type: feature
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T03:22:25Z
parent: worksync-kxg1
blocked_by:
    - worksync-ccaa
    - worksync-9kh2
---

SPEC §11. Status item + menu:
- [ ] Template-image icon states: idle/ok, syncing (animated/badged), error (persists until success), paused (dimmed)
- [ ] Menu: last-sync header (shared pass-summary string), per-source counts, Sync now (disabled while running), Pause/Resume, Launch at login, Preferences… (stub until M6), Open config (validate + NSAlert on error), Open log, Quit
- [ ] Config re-read at start of every pass (edits apply without restart)


## Design change (2026-08-14) — supersedes the plain-NSMenu plan
SPEC §11.0 now specifies a key-capable non-activating NSPanel hosting SwiftUI via NSHostingController, NOT a plain NSMenu and NOT NSPopover (a popover is key only while the app is active; activating an LSUIElement accessory is async, so it lands on screen but not key).
- [ ] MenuBarPanel: NSPanel subclass, canBecomeKey=true / canBecomeMain=false
- [ ] styleMask [.borderless, .nonactivatingPanel, .fullSizeContentView], level .popUpMenu, hidesOnDeactivate=false, clear background, collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary]
- [ ] layoutSubtreeIfNeeded() before makeKeyAndOrderFront (avoids first-frame size flash)
- [ ] Outside-click dismissal: local+global NSEvent monitors, decision in a PURE unit-tested policy function
- [ ] Policy case: windows whose class name contains menu/popover must NOT dismiss (they are sibling windows; otherwise the panel tears down before a button's mouse-up)
- [ ] Policy case: status-button hit zone extends to screen maxY inclusive (a cursor against the menu bar reports exactly maxY -> dismiss-then-retoggle)
- [ ] Right/control-click builds an NSMenu, assigns statusItem.menu, performClick, then clears it (accessibility + escape hatch)
- [ ] hidePanel resets transient state: orphaned tooltips, stray focus rings (skip live text fields), scroll position, pending confirmations
- [ ] Status item image via withObservationTracking, re-armed each render, ~50ms debounce (undebounced bursts can make the item vanish)
Prior art: robinebers/openusage (MIT) — attribute if code is copied rather than re-derived.
