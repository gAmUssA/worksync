---
# worksync-n2bv
title: 'M9: First-run setup'
status: todo
type: milestone
created_at: 2026-08-17T19:27:58Z
updated_at: 2026-08-17T19:27:58Z
---

A new user launches an accessory app with no Dock icon, no window, and no
calendar permission, and nothing happens. Setup is what turns that into a
working sync.

## The shape, and why

NOT a paged wizard, and NOT a `hasCompletedOnboarding` flag. One scrolling
`.setup` screen in the existing panel whose visibility derives from the SAME
doctor check state the Health section already computes.

That single decision is the milestone. A completion flag cannot reappear when
calendar access is revoked six months later, so it forces a second code path
that answers "is this set up?" differently from doctor — two truths, drifting.
Deriving from check state means revocation re-enters setup for free, which
SPEC §15 already demands of the icon.

Researched against six menu bar apps verified from current source (Rectangle,
Ice, Stats, MonitorControl, Maccy, Hidden Bar). The repeating pattern is a
state-driven permission gate, not a tour. Ice gates on `permissionsState`
rather than a first-launch flag — that is the model. Rectangle polls
`AXIsProcessTrusted()` every 0.3s and auto-dismisses the moment it flips,
which also covers the user who grants in System Settings instead; steal that.
The only true paged wizard in the set (Stats) belongs to the only app with no
permission to gate on.

## What doctor gives us, and the three things it cannot

Reuse: the checks, `DoctorDestination` buttons, `.skipped(because:)` phrasing
("target writable: skipped, needs calendar access" is already the right
onboarding sentence), the resolver-backed calendar popups, the
comment-preserving writer, the panel height morph.

Doctor structurally cannot provide:
1. **A prompt.** Doctor is provably non-prompting by spec (§16) and must stay
   that way. The authorization request is a UI-layer action rendered beside
   the `calendar-access` finding — the seam must not leak back into the core.
2. **An explanation of what the app IS.** Doctor's register is diagnostic:
   it tells someone who already knows what WorkSync is what is broken. A
   first-time user needs "busy time only; titles never leave your Mac."
3. **Proof it is safe.** The felt milestone is not "all checks green" — it is
   seeing the plan: "12 blockers would be created on Work / Calendar." Doctor
   never runs a pass, by design.

## Acceptance

[ ] Setup visibility derives from check state, never from a stored flag;
revoking calendar access re-enters setup with no extra code path
[ ] Status item shows a distinct "needs setup" state — NOT the red error
state; error means broken, setup means never configured
[ ] The priming card has exactly ONE button, titled Continue, that opens the
system prompt (HIG Privacy: an Allow/Skip/Cancel button there is manipulation)
[ ] Authorization is polled so granting in System Settings also advances
[ ] A dry-run preview is shown, and the first real write is never automatic
[ ] Launch at login is offered, defaulting OFF (§10)
[ ] Only prerequisites gate; warnings (signature, log size, notifications,
staleness) never do
[ ] Every config write goes through the comment-preserving writer (§4.3)
[ ] The panel survives the TCC dialog appearing over it
