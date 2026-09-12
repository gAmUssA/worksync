# t9r4 — `{title}` on the blocker: ship or decline?

Bean: `.beans/worksync-t9r4--title-placeholder-for-the-blocker-template.md`
Repo: `/Users/vikgamov/projects/ai/worksync` (read-only)

## Recommendation

**Ship option 3. Decline. Keep the invariant absolute.**

Do not add `{title}`. Do not add a `copy_title` flag. Do not add a dry-run warning that exists to bless a write the product was built not to make.

The motivating case (work-to-work, “which meeting is blocking me”) is real, and it is already served without punching a hole in the one promise the README leads with. Per-source opt-in plus a dry-run warning is not a safety mechanism. It is a waiver.

---

## What the code actually enforces today

This is not a convention. The source title cannot reach a blocker without a signature change.

`SyncPlanner.renderTitle` takes `(template, eventStart, calendar)` and substitutes only `{date}` and `{weekday}`. There is no event argument. `DesiredBlock.title` is that rendered string. `EventKitStore.write` does `event.title = block.title` and overwrites notes with the marker block — it never copies `StoredEvent.title`, location, attendees, or notes onto the work event.

All three construction sites (all-day, coalesced, timed) call `renderTitle(source.titleTemplate, eventStart:…)`. Coalesced blocks use `cluster.members[0].start` for the date placeholder, not a title. Marker keys hash `externalIdentifier + occurrenceDate` only.

README, first screen:

> The blocker carries no title, location, attendees, or notes from the source event. That is the entire point, and it is enforced in the code rather than by convention.

SPEC §4.1:

> `title_template` supports optional placeholders, all privacy-safe: `{date}`, `{weekday}`. Never expose source titles, locations, attendees, or notes. No other placeholders in v1.

(The bean cites SPEC §7 as the privacy invariant. §7 is the marker scheme. The “never copy titles” rule lives in README + §4.1. §7 matters here only because notes are the primary marker location — they must stay the fixed header + `worksync://…` line, never source notes.)

Adding `{title}` is not a template tweak. It is a decision to stop being able to say “enforced in the code.”

---

## What comparable tools do

Every serious calendar-sync product treats “copy the real title onto the other calendar” as the *dangerous* mode, not the default. The ones closest to WorkSync default to a generic hold.

| Tool | What lands on the destination | Default | Notes |
|---|---|---|---|
| **Reclaim Calendar Sync** | Policy: Busy / Personal Commitment / limited details / full details | Onboarding offers “Personal Commitment for all” or “Busy for all”, not full details | Full-details is an explicit escape. Reclaim’s own docs warn that “syncing with full details, even when marked private, can still result in workplace administrators and superusers being able to see them.” `#nosync` in title/description is the per-event off switch. |
| **Clockwise Personal Calendar Sync** | Historically `"Busy (via Clockwise)"` with no personal details | Busy | Feb 2026 added “share titles and selected details” as a *new setting*. The original product promise was the sanitized hold. |
| **Fantastical Calendar Mirroring** (Jun 2026) | One-way local copy; titles and locations each have a checkbox | **Titles off. Locations off.** | Closest analog: on-device, one-way, privacy-first. David Sparks’ walkthrough: “this is off by default, and I recommend you leave it off unless you're comfortable sharing the titles of your personal events with your work calendar.” WorkSync is trying to be this, without the checkbox. |
| **Google Calendar native sharing** | Does **not** copy events onto another account | “See only free/busy (hide details)” is the privacy permission | “Private” on an event still shows Busy to viewers, but **delegates / “Make changes” see full details**. Copying a title onto a work event is strictly more leaky than sharing the personal calendar as free/busy, because the title then lives on the corporate tenant. |
| **Outlook / Exchange** | Default org view is usually free/busy; many teams share “limited details” (subject + location) | Availability-only is the safe default | “Private” does **not** hide details from anyone with read permission on the calendar (Microsoft documents this). A title written onto the work calendar is visible to anyone whose permission is “limited details” or above, and to delegates even if marked private. |
| **OneCal** | Per-sync checkboxes for title / description / location / attendees | Unchecked = custom title, **“Busy” by default** | Copying titles is an opt-in on the sync rule. |
| **CalendarBridge** | “Subject” checkbox; unchecked → copies titled `"busy"` | Subject off unless checked | Separate “All Private” flag, because even a copied title is visible in Scheduling Assistant unless the copy is marked private — and even then, admins/delegates can see it. |
| **Calendrz / CalendarPipe-style “busy-only” tools** | Marker events, never a copy of the source | Busy | Their marketing pitch against OneCal/CalendarBridge is *privacy by architecture*: don’t strip titles after copying; never have them. That is WorkSync’s current design. |

The industry split is clean:

- **Availability mirrors** (Clockwise’s original hold, Fantastical’s default, OneCal/CalendarBridge with subject off, Calendrz, WorkSync) never put the source title on the work calendar.
- **General sync** (Reclaim full-details, Fantastical with the checkbox on, OneCal with titles checked) will copy titles, and they all make you ask.

Nobody who sells “colleagues see that you are busy, not why” ships `{title}` on by accident. WorkSync’s README is in the first camp. Putting `{title}` in the template vocabulary moves it into the second camp while keeping the first camp’s slogan. That is a documentation lie waiting to happen.

---

## Blast radius if someone enables this on the wrong source

Concrete, not hypothetical. Default `window_days = 21`, 1 hour of lookback. One `worksync sync` (or the next menubar timer tick, default 10 minutes) rewrites every managed blocker in that window.

**What gets written.** For every eligible source event: `EKEvent.title` becomes the real personal title. Location, attendees, and notes still do not copy — so this is “only” the title. Titles are the payload. “Therapy — Dr. Klein”, “Divorce mediation”, “Interview @ Competitor”, “AA meeting”, “Prenatal 20-week”, a child’s school name, a recruiter’s live screen-share title. Google/Outlook titles routinely contain the whole agenda.

**Who sees it.**

- Anyone in the org whose calendar permission is **limited details** or **full details** sees the subject in Outlook/Google/Teams. Many engineering teams share “titles and locations”. Free/busy-only viewers still only see Busy — but the user cannot know which colleagues have which permission, and they cannot know what the admin default is.
- **Delegates, EAs, and “Make changes” users** see titles even if the event were marked Private. WorkSync does not set EventKit privacy/sensitivity today, and even if it did, Exchange Private is a display hint, not an ACL (Microsoft documents this; third-party clients ignore it).
- **Lock-screen / banner notifications** on the work phone and laptop show the event title. A “Busy” hold is boring. “Colonoscopy prep” is not.
- **Scheduling Assistant / Find a time** shows the subject under limited-details sharing.
- **eDiscovery, legal hold, Purview, Vault, HR export.** The title is now a record on the corporate tenant. Turning the feature off later rewrites the live event back to “Busy”; it does not un-index what already synced, screenshotted, or got pulled into a hold. Calendar change history on the server is not under WorkSync’s control.
- **Dry-run, logs, notifications, the panel.** `worksync sync --dry-run` prints `CREATE [personal] "<block.title>"`. Error strings in `SyncEngine` interpolate `block.title`. A paste of a dry-run into Slack or a GitHub issue is a leak. SPEC already forbids doctor from printing event titles *because* that output gets pasted into bug reports. `{title}` would put those strings on the default CLI path.

**How much, how fast.** One pass. Not a gradual rollout. Coalesce-on (the personal source default in the example config) makes it worse: a cluster currently becomes one “Busy” spanning several personal events. With `{title}`, you either stamp the first member’s title across the whole span (mislabeling 14:00 school pickup as 09:00 dentist) or you concatenate titles (now the work calendar lists every private event in the cluster). Both are leaks; the first is also a lie.

**Undo is not undo.** Removing `{title}` from the template causes reconcile to UPDATE titles back to “Busy” inside the window. Outside the window, stale titled blockers sit until the window reaches them. Anyone who already saw them has seen them. The Exchange dump is not rewritten.

The bean’s “colleagues on B cannot see A, so nothing leaks to a party who did not already have it” is true of *calendar A*. It is false of *the copy on B*. The copy is a new disclosure to every viewer of B, including people who never had access to A: coworkers, the EA, the tenant admin, the compliance pipeline.

---

## Is per-source opt-in actually safe, or does it just move blame?

It moves blame.

Option 1 (“opt-in per source, dry-run warning”) fails every place WorkSync actually runs:

1. **The template is a free-text field.** Settings already has “Shown as” as a `TextField`. Typing `{title}` is the same gesture as typing `Busy` or `✈️ Flight`. There is no confirm alert, unlike source-id rename (which *does* warn, because SPEC treats that as data-integrity). A placeholder in a string is the opposite of a loud name.
2. **Dry-run is not on the write path.** The menubar login item and `worksync sync` without `--dry-run` write. Nobody is forced to preview. A warning in dry-run output is a warning for the people who were already being careful.
3. **The source is not a privacy classification.** `id = "personal"` vs `id = "work-a"` is a slug the user typed. The tool cannot know whether that calendar is therapy or standup. Option 2 in the bean admits this (“the tool cannot actually determine”), then option 1 pretends the source boundary is the determination. It isn’t. It is the user remembering, every time they edit `title_template`, which calendar is which.
4. **Config is hand-editable.** SPEC §2. A copied snippet, an LLM-edited toml, a well-meaning `title_template = "{title}"` on the default personal source, and the next timer tick publishes three weeks of private titles. There is no second factor.
5. **WorkSync’s users are exactly the people who cannot use Reclaim.** The README exists because connecting the work calendar to SaaS is prohibited. Those same workplaces have EAs, shared-calendar norms, and eDiscovery. “The user opted in” is not a defence that survives an HR conversation.

Fantastical can ship a checkbox that defaults off because Fantastical is a general calendar app. Its users did not download it *because* titles never copy. WorkSync’s entire first paragraph is that they never copy. An opt-in that lives in the same string as `{date}` is how you stop being able to say that.

Two-key consent (`allow_title_copy = true` AND `{title}` in the template, scary Settings toggle, refuse to save without a typed “COPY TITLES”) would be *less* reckless than option 1, and would still be a waiver. I would not ship that either. Once the write exists, the invariant is a default, not a guarantee. The README would have to stop saying “enforced in the code rather than by convention.”

---

## What README and SPEC would have to change if you shipped it anyway

Not a footnote. The privacy claim is unconditional; it has to be rewritten, not amended.

**README (lead + the enforcement paragraph).** Today:

```
sanitized blocker events, so colleagues see when you are unavailable without
seeing why.
…
The blocker carries no title, location, attendees, or notes from the source
event. That is the entire point, and it is enforced in the code rather than by
convention: titles come from a template with two allowed placeholders (`{date}`
and `{weekday}`), and nothing else is ever copied.
```

Would become something like: blockers are sanitized *by default*; `{title}` copies the source title onto the work calendar; you are responsible for never putting that on a personal source; colleagues, delegates, and tenant admins may see it; turning it off does not erase server-side history. The phrase “enforced in the code rather than by convention” has to go. The dentist → Busy diagram becomes a lie for any source that opted in.

**SPEC §4.1.** Delete “all privacy-safe” and “Never expose source titles… No other placeholders in v1.” Replace with a `{title}` definition, a statement that it is a deliberate privacy hole, coalescing behaviour (first member? refuse `{title}` when `coalesce = true`?), and a length/newline sanitizer. Add a validation rule if you go two-key.

**SPEC §5 step 4 / `renderTitle`.** Signature becomes `(template, eventStart, calendar, sourceTitle)`. The “deliberately has no access to the event” comment is the current enforcement; it goes.

**SPEC §6.** Already diffs title, so a source title *edit* correctly becomes an UPDATE. Document that. Also document that enabling `{title}` on an existing source rewrites every in-window blocker on the next pass — a mass update, not a no-op.

**SPEC §7.** Notes stay marker-only (do not copy source notes). Say that explicitly so `{title}` does not grow into `{notes}` / `{location}` by analogy.

**SPEC §11.1.** The “Shown as” field needs a confirm path if `{title}` is present, analogous to source-id rename. Otherwise Settings is a one-click leak.

**SPEC §13 / doctor.** Doctor must still never print source titles. Dry-run *would* print them (that is the point of the warning). Those two outputs would then disagree about what is safe to paste.

**Example config / `worksync init`.** Bean is right that init must not suggest `{title}`. The current comment block (“real title, location, attendees, and notes are NEVER copied — that is the entire point”) would have to be replaced with a warning, or it would be false.

**Tests.** `testMatchedTitleIsNeverCopiedToTheBlocker` (title-filter work) and the README claim would need a carve-out. A privacy test that is true “unless the user typed `{title}`” is not a privacy test.

If you are not willing to do that rewrite, you are not willing to ship the feature. That is the point of option 3.

---

## Options the bean missed

1. **Keep the invariant on the work calendar; show source titles only locally.** The menubar panel / a “why am I blocked?” inspector can display the source title on-device, because EventKit already has it on the Mac. Colleagues never see it. This actually solves “I want to know which meeting on A is blocking B” for the operator, which is the honest motivation. It does not require `{title}` on `EKEvent`.

2. **`target_calendar` + colour + template prefix**, which the bean already lists under option 3, plus **`title_matches`** (shipped). Work-to-work “only copy the standups” is an eligibility problem, not a title-copy problem. Pull those events onto a dedicated “Work-A Blocks” calendar, colour it, title them `Busy` or `A · {weekday}`. The user looking at B sees *which source* and *when*, which is what scheduling needs. They still have calendar A for the real title.

3. **Two-key consent** (`allow_title_copy = true` plus `{title}`), Settings confirm, refuse `{title}` when `coalesce = true`. Strictly better than option 1, still a waiver. Do not ship.

4. **Allow `{title}` only when source account == target account.** Catches personal iCloud → work Exchange. Fails the bean’s actual motivating case (two employers, two accounts). Heuristic theatre.

5. **Share or overlay calendar A on the work account as free/busy**, or use Fantastical mirroring with titles off. For the work-to-work user who *does* want titles, Fantastical’s checkbox is the right product. WorkSync should not become a worse Reclaim in order to avoid recommending a general calendar app.

6. **Per-event opt-in via a token in the source title** (`#synctitle`), Reclaim’s `#nosync` inverted. Still copies titles onto the tenant; still a leak; now the leak is load-bearing on people remembering a tag.

None of these except (1) and (2) preserve the README sentence. (1) and (2) are the features I would actually build if the work-to-work itch stays.

---

## The three options, scored

**Option 2 — trust the user.** No. The tool exists because the work calendar is a hostile privacy environment. Trusting the user to never put `{title}` on the wrong `[[source]]` is how therapy titles end up in eDiscovery. Rejected.

**Option 1 — opt-in per source, dry-run warning.** This is what Fantastical/Reclaim/OneCal do, and it is the correct design *for a general sync tool*. WorkSync is not one. Dry-run is optional. The template field is a text box. The first write is a 21-day rewrite. Opt-in moves the invariant from the type system (`renderTitle` has no event) into a string the user can type. That is the whole ballgame. Rejected.

**Option 3 — decline.** The status quo, and the only option that leaves “enforced in the code rather than by convention” true. The work-to-work user gets `target_calendar`, colour, `{weekday}` / prefix, `title_matches`, and — if we ever build it — a local inspector. They do not get to publish source titles onto Exchange.

---

## Ship this

**Option 3.** Close t9r4 as declined. If the work-to-work pain is still loud after that, open a bean for a local “why this block exists” inspector (missed option 1), not for `{title}`.
