---
# worksync-z029
title: Adopt NSStatusItemExpandedInterfaceDelegate (macOS 27 SDK)
status: draft
type: task
created_at: 2026-08-14T04:47:59Z
updated_at: 2026-08-14T04:47:59Z
---

Blocked on toolchain, not on design.

macOS 27 introduces NSStatusItemExpandedInterfaceDelegate. A status item that shows custom UI is supposed to tell AppKit when that UI is active so keyboard focus and menu tracking behave; the Axiom macOS skill lists 'toggling a status-item window manually from target/action' as a red flag, which is exactly what StatusItemController does today.

Verified NOT adoptable yet: the symbol is absent from the macOS 26.5 SDK this builds against, and the deployment target is macOS 14.

## When the build moves to the 27 SDK
- [ ] statusItem.expandedInterfaceDelegate = self at creation
- [ ] Move showPanel() into statusItem(_:didBegin:) and hidePanel() into statusItemDidEndExpandedInterfaceSession(_:animated:)
- [ ] Dismiss via expandedInterfaceSession?.cancel() rather than ordering the window out
- [ ] Conformance needs @MainActor explicitly — the protocol is not actor-annotated, so a main-actor delegate needs it to satisfy the requirements under Swift 6
- [ ] Gate with BOTH #if compiler(>=X) and #available(macOS 27, *), for the same reason the Liquid Glass helpers need both: #available is a runtime check but the symbol must exist at compile time

## Already applied (available today)
- Status button has target+action, so Return activates it during keyboard navigation
- panel.autorecalculatesKeyViewLoop = true, which matters because the settings screen adds and removes controls as the selection changes
