---
# worksync-ccaa
title: 'menubar lifecycle: explicit delegate in main.swift'
status: in-progress
type: task
priority: normal
created_at: 2026-08-14T00:35:51Z
updated_at: 2026-08-14T03:22:25Z
parent: worksync-kxg1
blocked_by:
    - worksync-qn4y
---

SPEC §3.1 rules 3-4 / §11. App lifecycle + concurrency ground rules:
- [ ] main.swift: create NSApplication, instantiate AppDelegate, assign NSApp.delegate, then NSApp.run() — never @main/@NSApplicationMain (delegate silently never instantiated)
- [ ] No unconditional setActivationPolicy at startup (LSUIElement handles accessory)
- [ ] Structured concurrency: Task per pass; explicit Task { @MainActor in } from notification callbacks (arbitrary queues)
- [ ] worksync menubar subcommand entry
