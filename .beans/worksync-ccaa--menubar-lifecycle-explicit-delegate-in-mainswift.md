---
# worksync-ccaa
title: 'menubar lifecycle: explicit delegate in main.swift'
status: completed
type: task
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T03:30:45Z
parent: worksync-kxg1
blocked_by:
    - worksync-qn4y
---

SPEC §3.1 rules 3-4 / §11. App lifecycle + concurrency ground rules:
- [x] main.swift: create NSApplication, instantiate AppDelegate, assign NSApp.delegate, then NSApp.run() — never @main/@NSApplicationMain (delegate silently never instantiated)
- [x] No unconditional setActivationPolicy at startup (LSUIElement handles accessory)
- [x] Structured concurrency: Task per pass; explicit Task { @MainActor in } from notification callbacks (arbitrary queues)
- [x] worksync menubar subcommand entry


## Summary of Changes
main.swift builds NSApplication, instantiates the delegate, assigns it, then runs — never @main. Startup logs whether AppKit returned a status item button, which distinguishes 'delegate never ran' from 'menu bar manager hiding the icon'. LaunchServices launches (no args, no tty) default to menubar instead of printing CLI help.
