# UX decisions log

Owner: **ux**. Answers to design questions from the team. Newest at the bottom. Each entry: question
→ decision → why. These override the canvas where they conflict; design-language.md and
information-architecture.md are updated to match.

## 2026-11-08

### U1 · URL scheme (fe-setup plan)
**Decision:** `O = /console/:orgId`, `M = O/:missionId`. Org pages are `O/org/<page>`. Account and
notifications are not org-scoped: `/console/account`, `/console/notifications`.
**Why:** a deep link must survive an org switch in a multi-tenant app. Lead owns the router; if the
scaffold differs, lead's scheme wins and ux updates the IA.

### U2 · Setup without a mission-wide revision (fe-setup Q1, option B)
**Decision:** while there is no mission change set, **drop `CONFIG rN` from the top bar** (Setup
clock cluster = `UTC` only) and **hide the staged-changes bar**. Each entity shows its own version
in its page header (`EARENDIL BLOCK 1 · v4`, `Catalog revision 14`, spacecraft config `active v3 ·
draft pending review`). Readiness R2 becomes **Recent changes** (who, when, what, from a unified
event feed) if api can provide one; otherwise R2 is omitted.
**Why:** truth before calm. A fake `rN` would lie about atomic applies.
**Update (DECISIONS #1):** change sets will be built. This entry is the v1 behavior behind the seam;
the target design is `screens/Changes.md`.

### U3 · Finding severities (fe-setup Q2)
**Decision:** blockers get their own shape. Order and grammar:
| Severity | Mark | Word | Meaning |
| --- | --- | --- | --- |
| blocker | crit diamond | `Blocker` | stops commanding or contacts |
| caution | triangle | `Caution` | degraded, act soon |
| stale | hatched square | `Stale` | a source or station is late |
| not set up | dashed square | `Not set up` | install / configure to enable |
| optional | 10×2 gray dash | `Optional ·` prefix in the title | a suggestion, never a warning |
The verdict headline counts blockers only ("Ready for operations · 0 blockers" / "2 blockers").

### U4 · Providers and transports in the Setup rail (fe-setup Q3)
**Decision:** **Transports** = a tab in 05 Comms & routing (`Routing rules · Transports`).
**Ground-network providers** (mission) = a tab in 06 Ground stations (`Stations · Providers`),
because providers supply the stations, antennas and pass opportunities. **Provider accounts**
(org credentials) = Organization group.

### U5 · Takeover vs in-shell (fe-setup Q4)
**Decision:** a **multi-step creation wizard with a step bar** is a full-page takeover without the
rail: Add spacecraft, New mission, and the catalog **upload** if it grows beyond one step. The
takeover header has `×` close (returns to where you came from, keeps the draft) plus the step bar.
**Catalog import review (the diff) stays in-shell**, as on the board, since it's a reading view
inside the Catalog section and links into the rest of Setup.

### U6 · Spacecraft detail in Setup (fe-setup Q5)
**Decision:** yes, reuse the Profile layout: entity title + readiness tag, then local section nav
with panels `Identity · Profile & version · Configuration (active vs draft, review) · Routing ·
Overrides`. Header link `Open in Ops →` goes to `M/fleet/:scId`. Ops › spacecraft › Configuration
tab is read-only and links back here to edit.

### U7 · MET (fe-ops Q-ux-1)
**Decision:** **omit MET** wherever there is no mission epoch: top bar, time picker summary, time
picker zone switch (UTC│LOCAL only). Never derive it from mission creation time. Backlog for api:
optional `mission.epoch_at` (launch or ops start); when set, MET appears.

### U8 · Fleet matrix shape (fe-ops Q-ux-2)
**Decision:** rows = planes **when plane metadata exists**. Columns = the largest slot count across
planes (20 × 25 in the demo is fine; header meta `ROW = PLANE · 25 SLOTS`). A cell is placed by
slot when known, else by ordinal; unused slots draw as `cell-empty`. Spacecraft without a plane go
in a final row group labelled `—` (meta `NO PLANE`). A fleet with **no** plane metadata is a flat
grid ordered by SCID, wrapping at 50 per row, row labels are SCID ranges in mono (`001–050`), meta
`ORDERED BY SCID`. Minimum cell 8px; below that the matrix scrolls inside its panel. Never-heard
spacecraft use the dashed `off` cell, not stale.

### U9 · Stale threshold (fe-ops Q-ux-3)
**Decision:** product default **15 min without fresh TLM**, overridable later per profile (expected
telemetry cadence). **The server decides staleness** and returns the threshold it used
(`stale_after_s`); the client never hardcodes 15. The Stale tile caption states the rule it used
("no TLM over 15 min"). A spacecraft never heard since creation is `off` ("Awaiting first AOS"),
not stale.

### U10 · Panels whose data doesn't exist yet (fe-ops Q-ux-4)
**Decision:**
- **Structural console regions** (A1 Constellation, A4 Passes, B1 trend chart) **stay in the
  layout** with ApEmptyState: `off` mark, a fact headline and the reason ("Orbit data not available ·
  the constellation needs orbital elements per spacecraft"). The console holds still; nothing
  reflows when the data arrives.
- **Panels or controls that recommend or act** (B3 Recommended procedure, Acknowledge, Assign)
  are **hidden** until real. Never show an empty recommendation or a dead button.
- **Single facts** in a fact strip (Next eclipse, Last LOS): omit the fact. Don't show a row of
  dashes.
- **Fleet summary tiles** (Stale, In contact): keep the tile, value `—`, caption "not tracked yet".
- Overlays that need missing data (umbra bands on a plot) are simply not drawn, and the legend
  leaves them out.

### U11 · Action-queue ranking (fe-ops Q-ux-5)
**Decision:**
- **P1 · act now:** critical alarm; a critical flight event (safe mode); a verify failure; a missed
  pass when the spacecraft's next contact is beyond its allowed gap (or unknown).
- **P2 · needs you soon:** caution alarm; a GO / approval waiting on **you** (not on anyone);
  no-ACK retries; stale groups; a degraded station with upcoming passes.
- **P3 · when you can:** not set up (missing app or source); setup suggestions.
- Within a priority: soonest time-to-consequence first (next AOS, umbra entry, release time), then
  oldest first. Group identical causes into one row ("4 in plane 2 stale", likely cause in the
  secondary line). Priority label mono 11 in the underlying state's text tint, next to that state's
  mark. Only the top P1 row's action is primary. The queue scrolls; nothing is truncated without a
  count.

### U12 · Breakpoints (shell review)
**Decision:** ≥ 1100px full console (rail 200/220px). 768–1099px: rail collapses to the index
column only (56px; labels as `aria-label` + tooltip); console screens may page-scroll and stack
panes as each spec's "below 1100px" note says. < 768px: Mobile layout (`screens/Mobile.md`), no
rail, one 56px top row, bottom tab bar. The shell carries these breakpoints from now on, so feature
screens are built against them.

### U13 · Health counts we can't know (Now review)
**Decision:** a count is only a number when it could have been non-zero. When no spacecraft is
fresh, Caution / Critical / Stale tiles show `—` + `no fresh telemetry` (`no telemetry yet` only if
nothing was ever heard). When ground limits aren't configured, Caution / Critical show `—` +
`limits not configured`, and that caption wins over the telemetry one (flight-event criticals, if that
source exists, still count). Same rule for any summary tile elsewhere (Fleet, Alarms, Readiness).

### U14 · Fleet matrix wraps planes into columns (Now third look)
**Decision:** when the plane rows overflow the matrix panel's height but the width has room, the
matrix lays the planes out in 2+ columns (each with its own plane labels, 24px gutter), choosing
the column count that gives the largest cell within 8–16px. It scrolls inside the panel only when
no column count fits at 8px. The goal is the whole fleet visible at a glance (J1).

### U15 · "Ever heard" is durable (qa #7)
**Decision:** `last_received_at` is the true last receipt and must survive node restarts and
redeploys (persisted, not only in a node-local cache). A spacecraft that has ever been heard can only
be fresh or stale, never "awaiting first contact" again. After a restart, before the live store
warms, the console shows the persisted time (stale if it's past the threshold), not unknown.
**Why:** a restart was turning heard spacecraft back into "awaiting first AOS", which hid silence
as newness. Truth before calm.

### U16 · Alarm source and evaluation time (applies DECISIONS #17)
**Decision:** every alarm row and the Investigate B1 header carry a **source tag**: `LIVE`
(catalog monitoring; readout outline tag) or `GROUND LIMITS` (batch; `text-3` outline tag),
followed for ground limits by mono `EVALUATED 22:41Z · T+3m`. That's the one time format (§4)
carrying #17's "evaluated 3m ago" intent. Ground-limit values never pulse or update as if live, and
the Now tile caption for ground-limit-only states says `evaluated T+3m`. When an escalation clears
an ack (ISA-18.2), the row shows the owner chip struck through plus `ACK CLEARED · ESCALATED TO
CRITICAL` in caution text until someone acks again. Assign lists all mission members.

### U17 · Revision numbers keep their case (fe-setup question)
**Decision:** `r6` is an identifier, so it's never uppercased. Inside display-type headings, buttons
and tags, wrap it in a mono `normal-case` span: `APPLY r6 · 2 CHANGES`, `REVIEW & APPLY AS r6`,
`REVISIONS · r5 LIVE`. Same for other literal ids inside display text (`SCID 312`, `HK.battery_voltage`).
Words like `rev 14` (catalog revision) are words and may uppercase.

### U18 · Touch targets under 768 (pass 1)
**Decision:** below 768px every interactive element (links in breadcrumbs and panel metas, table
name links, segmented options, chips) has at least 44px of hit area (padding, min-height or a
`::before` hit box), keeping its visual size. Primary/commit actions stay at 48px and full width
(Mobile.md). Desktop keeps the canvas densities.

### U19 · Takeover routes replace the shell top bar (lead question)
**Decision:** as on the boards, a takeover (Add spacecraft, New mission, Compose, Command a group,
Approve, Uplink & verify, Plan, Re-plan) **swaps the 52px shell top bar for its takeover header**.
The header context line carries org and mission (qa contract): mono `REFLECT ORBITAL / EARENDIL ·
APPROVALS · SIGNED IN AS MIRA K.` over the title. `×`/back sits left, the step/station bar in the
middle, clocks (UTC + the flow's own countdown) right. No mode switch, query or account menu inside a
takeover: `×` is the way out, and Esc does nothing destructive. Under 768 the header is one 56px row
(`×`, title, UTC) with the station bar scrolling horizontally below it.
**Why:** commanding screens hold still and need the height; a second header row says the same
thing twice.

### U20 · Failure copy states the outcome only when it's known (fe-setup correction)
**Decision:** after any write (stage, apply, approve, release, ack), failure copy says what
happened to the data, and only claims what is certain:
- **Rejected** (the server answered with an error): "Nothing was staged." + `Retry`.
- **Outcome unknown** (timeout, unreadable reply, a lost connection after the request was sent): "It
  isn't clear whether anything was staged." + a link to where the truth lives (Staged changes, the
  request page) instead of `Retry`, because a retry could duplicate the write.
- **Partial** (only where the model allows it): name what changed and what didn't.
**Why:** a 201 may already have staged it. "Nothing changed" is a promise; make it only when true.

### U21 · Acknowledged items keep their priority (api-ops question)
**Decision:** keep api-ops' current behavior: an item whose episodes are all acknowledged **keeps its
priority and sorts last within it** (P1 acked stays P1, below unacked P1s). Don't demote. The row
also changes: owner chip `ACK MIRA K.` (+ `→ TOMÁS R.` when assigned), the action becomes `Open`
instead of `Engage`, and it's never the primary. An escalation clears the ack (U16) and the item
returns to the top of its new priority.
**Why:** ISA-18.2: acknowledging doesn't make a critical alarm less critical. Demotion would mix
an acked critical in with fresh cautions and hide severity. Sorting last keeps unhandled work on top.

### U22 · Scheduling answers (lead's plan, Q1–Q9)
1. **Day** = 00–24Z UTC. Shift-aligned windows can come later as a preset.
2. **Rule source:** show the rule text (`≥ 3 CONTACTS A DAY · AT LEAST 2h00 APART`; corrected: `minimum_separation_seconds` is a minimum spacing, not a max gap) with its true source,
   `FROM REQUIREMENT TEMPLATE "BLOCK 1 DAILY" ↗` (link to the existing page) until profile demand
   exists. No IA home is added for templates.
3. **Budgets:** confirmed. No denominators and no budget caution until a budget setting exists.
   Totals (minutes, cost) only when providers report prices.
4. **Freeze clock:** omit until a provider reports a cutoff.
5. **K2 v1:** yes, ship **"Re-plan after provider changes"** entered from a plan or a rejected/changed
   reservation, same layout. A Impact lists the rejected/changed reservations instead of a station
   outage (title `Re-plan · 3 reservations rejected`). The outage entry joins when S7 lands.
6. **K3:** agreed, hold it until S9. Hide the `Review` tab until then (no dead tab).
7. **Window source naming:** `<SOURCE> · <KIND>` mono, with the source's display name (`NORTHLIGHT ·
   PROVIDER WINDOW`). The simulator always says so: `SIMULATOR · SYNTHETIC WINDOW`, and the plan
   shows a stale-tone callout "Opportunities come from the simulator, not a provider" whenever any
   window is synthetic.
8. **Gantt rows** = stations; antenna sub-rows only when the provider reports antennas. Confirmed.
9. **Plan approval** follows the server's policy, like commanding (DECISIONS #7 pattern). Default:
   one planner submits. When a plan comes back `pending_approval`, show ApDecision to people who
   can approve, with the reviewer ≠ the author. The UI never invents the requirement.

### U23 · Every count names its unit; plans count spacecraft first (qa question)
**Decision:** no bare counts. Every number on a plan screen says what it counts: `10 SPACECRAFT NOT
COVERED`, `40 CONTACTS SHORT`. The **headline unit for coverage is spacecraft** (ScheduleFlow R01: "who
isn't covered"). Contact shortfall is the secondary figure, beside it. So: header line `R41 DRAFT · 10
SPACECRAFT NOT COVERED`; A Demand meta `10 SPACECRAFT · 40 CONTACTS SHORT`; footer `RULE MET 490 / 500
SPACECRAFT`; a **gap** = one unmet requirement, so the primary reads `Accept 10 gaps and submit` and
the sheet title adds the shortfall: `Accept 10 gaps · 40 contacts short`. Same rule everywhere: a
count beside a label that doesn't name the unit is a bug.
**U23 amendment (lead question, K1):** in the UI a **gap = one uncovered spacecraft**, not one
requirement, because operators reason per spacecraft and it matches the headline unit. `Accept 10 gaps ·
40 contacts short`; one sheet row per spacecraft listing its unmet requirements inside (mono, `1 DOWNLINK
≥ 5 MIN · 11 NOV 00–24Z`); one reason per spacecraft, which the client sends as the acknowledgement for
each of its requirements (the audit stays per requirement server-side). A `Different reason per
requirement` disclosure in the row allows splitting when needed. The approver sees the same grouping.

### U24 · Schema units are formatted by the client (Contact planning policy)
**Decision:** generated forms never ask people to type storage units. The client formats by the schema's
`unit`, with no extra server hints needed:
- `s` (duration): display `48h 00m` / `9m 12s` (design-language §4); input accepts `48h`, `2d`, `90m`,
  `1h30m`, `5400s`; show the canonical seconds in `Technical details`.
- `micros` (money): display and enter in the currency's units (`1,200.00 USD`); convert ×1e6 on save.
  The currency field is a select of ISO 4217 codes (the provider's currency first when known), not free
  text.
- booleans with a server default: a Yes / No `choice` segmented showing the default (`No · default`),
  not `Choose…`; null = default, stated.
- raw keys (`resources.capacities`) and JSON never appear in help text; they go to Technical details.
  JSON editing is Advanced-only, org admins only, and is labelled as such.

### U25 · Never invent identifiers (station code fallback)
**Decision:** when an entity lacks an identifier (a station with no `code`, a spacecraft with no SCID),
the console shows the absence (`—` in the code column, with the name carrying identity) and, where the
user can fix it, a `Not set · Add code` affordance. It never derives a stand-in (`HAR` from
"Hartebeesthoek"): a derived code looks real, can collide, and differs from the one that gets set later,
so one station ends up with two codes across screens. Applies to reads too: the server returns `null`, not a derived value (correction: the HAR/PUN/SAN on Ground stations were **stored** by the profile-routing migration backfill, domain 99fc1dc7; the read and the console only displayed them). **Final (domain):** stored codes are only confirmed codes. A migration (after #44) NULLs every code that
still equals the backfill formula. The stations read returns `suggested_code` (computed from the name,
de-duplicated against confirmed codes in the mission) **only when `code` is null**. UI: code cell shows
the suggestion dimmed (`text-4`, mono) + `Suggested · Confirm` for editors (confirming stages a normal
ground_station change writing `code`); viewers see `—` with the suggestion in the title attribute
only. Readiness: "3 stations have no confirmed code" (counts `code IS NULL`), fix → Ground stations. A
suggestion is never shown where a code is used as an identity (routing rules, the Gantt rows, the
palette): those fall back to the station name.
**Editing a code-less station (lead, qa's live check, 11-16):** the Stations editor must not require a code to save
other metadata, or operators invent one just to get past the form. While the stored code is null, `Code` is optional,
with the 2–8 letter check only when something is typed. Help: "Leave empty to keep showing the station's name." With a
`suggested_code`: "Suggested: INU" + `Use INU` (fills the field; it still saves only as part of the staged edit). Once a
code is set it can be changed but not emptied, because pass titles and filters already use it. The form marks
it required then; the server's refusal (domain) on the `code` field reads "INU is already used in pass titles and
filters, so it can be changed but not removed." (the stored code).

**A spacecraft with no name (#190, #237; dashboards, 11-18):** where a craft's name is null the console shows
`Unknown spacecraft` ("on an unknown spacecraft" in a sentence), never its id; `Deleted spacecraft` only where the
server says it's gone. A link stays a link when it opens the row's own page (the requirements table). On a GO target
list a caution line sits next to GO: "This console can't show the name of 1 target spacecraft. Check its id in
Technical details before you give GO.", with the id in that row's Technical details. GO isn't disabled for it (lead,
11-18): the target is still exact.

### U26 · Passes inside station unavailability (K1, lead question)
**Decision:** K1 flags it in place; it isn't left to K2.
- **Outage or maintenance** (the station won't serve): the pass is a **conflict**. The bar is drawn
  caution-dashed over the band, it counts in `CONFLICTS`, and D lists it ("SVA is down 04:00–08:00Z
  (outage) · 1 drafted pass falls in it") with `Move` (to the focused spacecraft's alternatives) / `Remove`.
  Submit stays blocked with the reason (#28). A draft that predates the window says so: "The outage was
  reported after this draft (05:10Z)".
- **Degraded** (may still work): a **warning**, not a block. A caution marker on the bar, a line in D
  ("KIR degraded 14:00–18:00Z · passes may lose data"), counted in the footer as `1 at risk`.
- After submit (booked passes), the same windows feed K2 "Re-plan after provider changes".
The planner's conflict check must include availability windows (api) so the server agrees with the UI.

### U27 · Dim marks, not text (qa axe finding on the superseded draft)
**Decision:** see design-language §6. Inactive / superseded / historical states dim marks and chrome
only, and text keeps its tier (≥ 4.5:1). The state is named in words. Also: **a draft is superseded when
its inputs change, not when the next draft starts.** A plan read must compare the draft's rule/template
versions with the current ones and report `superseded` immediately (api), so a stale draft can never be
shown as current or submitted.

### U28 · Repair proposals live in K2; K1 shows the day's plan (fe-setup / qa)
**Decision:** K1 always opens the **day's own plan** (the latest non-repair plan: draft, pending or booked),
never a repair proposal. When a repair proposal exists for that day (`repair_of` set, api), K1 shows an
info callout under the header: "A re-plan proposal is open for this day: 4 passes move off HBK · proposed
10:32Z by Mira K. · `Open in Re-plan →`". K2 owns the proposal: its header names both sides, `RE-PLAN ·
R1 → PROPOSAL · 4 MOVES`, with a mono context line `REPAIR OF R1 (<base plan state>)`, and its primary
applies the repair (`Apply proposal · send 4 requests`). No invented revision number for the proposal (U25):
it gets one only if the server assigns it. Counts on any screen come from one plan only: never a
header from one plan and a footer from another.

### U29 · Who and when must refer to the same event (K1 drafter line)
**Decision:** an actor and a time on one line describe one event. "Drafted 10:52Z by Mira K." needs the
**creation** time, not `updated_at`, which may be someone else's later edit. Without `created_at`, write
`Drafted by Mira K. · updated 10:52Z`; with it, `Drafted 10:40Z by Mira K. · updated 10:52Z` (drop
`updated` when the times match). System authors read `by Cadence (automatic draft)` /
`(automatic repair)` per the kind of run.

### U30 · Unconfirmed bookings (DECISIONS #52) (fe-setup / lead / domain)
**Decision:** `unconfirmed` means we sent the request and the provider didn't answer within the
confirmation window. Cadence **doesn't know** whether the pass is booked, so the copy says exactly that
(U20): neither "failed" nor "booked". Tone is **caution** (it needs a person and blocks Execute). The
passes themselves are stale-hatched, because their truth is unknown. Header tail
`R41 · 36 BOOKED · 4 UNCONFIRMED`. Callout: "Northlight hasn't confirmed 4 bookings after 10 min. They
may or may not be booked, so Cadence won't send them again. Check them with Northlight." The passes are
listed with the soonest first and a `T−` to it. **The list is capped** (qa's U30 live check): show the 5 soonest, then
`and 35 more · Show all 40`, which opens a sheet listing all of them (with the U32 actions). The callout
never grows past that, so the console layout holds still. **No re-plan for unconfirmed passes** in K2 or K1:
re-planning a pass that may already be booked risks double-booking and double billing. They resolve first,
as booked or as not booked. Not-booked ones then become Demand rows and re-plan normally. Until domain
offers a resolution action (`Mark booked` / `Mark not booked` with a note, audited), the screen offers none,
and no dead buttons. When it lands, it sits per pass in that list.

### U31 · Where mission "needs acknowledgment" items appear (DECISIONS #53/#54) (domain / api / fe-ops / lead)
**Decision:** they use the console's existing "needs you" surface, **Now's action queue (A2)**, with no new
rail item and no inbox page. Each open item from domain's attention read becomes a queue row of kind
`attention` (subkind = source), ranked by U11 like everything else. The pass's own pages hold the detail
and the actions.
- **Ranking:**
  - **P1** when the affected pass starts within 2 h, or is in progress.
  - **P2** otherwise (`cancel_failed`, `late_confirmation`, `contradicts_attestation`).
  - Within a priority, the soonest AOS comes first.
  - Acknowledged items keep their priority and sort last within it (U21). Resolved items leave the queue
    with "Resolved by Mira K." for 5 s.
- **Rows** (title = `<SPACECRAFT NAME> · <what>`, secondary = evidence, meta = `SVB-1 · AOS T−01:12`):
  - `contradicts_attestation`: "EARENDIL-001 · Northlight says a pass marked booked isn't." /
    "Marked booked by Mira K. 10:52Z with ref NL-48213. Don't count on this contact."
  - `late_confirmation`: "EARENDIL-001 · Northlight confirmed a pass marked not booked." / "Marked not
    booked by Mira K. 10:52Z. It may be booked and billed."
  - `cancel_failed`: "EARENDIL-001 · Northlight didn't accept the cancel." / "<provider's message>. The
    pass may still be booked and billed."
  - Action `Review`, which goes to the contact (`M/contacts/:contactId`, drawer). It's the primary only
    when the row is the top P1 (U11).
- **Contact drawer (D2)** for that pass: a caution block at the top with the open conflict in words, the
  resolution record (who, when, note, provider reference, the provider's last answer), and the actions
  domain offers (`Acknowledge`, `Resolve`). The `operator_attested` evidence reads
  `BOOKED · ATTESTED BY MIRA K.` (not the provider's word), plus `UPLINK UNCONFIRMED` while #46 D1 holds.
- **K1 for that day:** a caution callout under the header, "2 pass resolutions need you", which lists
  them and links to each contact. No separate count anywhere else.
- **Counts:** the `/counts` entry adds to Now's queue header (`6 OPEN`) and to the mobile Now badge. The
  rail doesn't get a second number on Contacts (that count stays `7 AOS`).
- **Future sources** (provider changes, …) join as new subkinds with the same row grammar. Each source
  needs: subject (spacecraft and/or station), target route, evidence sentence, consequence time,
  raised_at, actor of the originating action.
**Data asked of domain's attention read:** `{id, source, conflict, state: open|acknowledged|resolved,
acknowledged_by?, spacecraft_id, contact_id, station, provider, starts_at, raised_at, resolution:
{action, actor, at, note, provider_reference?}, provider_message?}`.

### U32 · Resolving unconfirmed bookings and attention items: copy (DECISIONS #53/#54, domain e3849f74)
**Unconfirmed passes (K1/K2 U30 list, admins only):** each pass row gets two secondary buttons, `Mark booked` and
`Mark not booked`. Members see the list without them, plus "Org admins resolve unconfirmed bookings."
- **Mark booked sheet:**
  - Title `Mark EARENDIL-001 · KIR · 03:00Z as booked`.
  - First line: "Cadence asks Northlight once more first. If Northlight answers, its answer is used and nothing is marked."
  - Fields: `Northlight booking reference` (mono, required) and `Note` (required, placeholder "How did you confirm it?").
  - Consequence: "The pass counts as booked on your word. Uplink stays unconfirmed until Northlight confirms it."
  - Primary: `Mark booked`.
- **Mark not booked sheet:**
  - Same first line.
  - Then: "Then Cadence sends Northlight a cancel. The pass becomes a gap that Re-plan can fill."
  - `Note` (required, placeholder "How do you know it isn't booked?").
  - Primary: `Cancel at Northlight and mark not booked`.
- **Outcomes** (callout in the sheet's place, then the list refreshes):
  - `provider_answered`: info, "Northlight answered: booked. Nothing was marked." (or "…: not booked.").
  - `attested`: "Marked booked by you · ref NL-48213."
  - `not_booked`: "Marked not booked. The cancel went to Northlight." Don't claim it was accepted: a failed cancel
    arrives in the Now queue (U31).
- **Errors (U20):**
  - `booking_not_unconfirmed`: "This booking isn't unconfirmed any more. Northlight may have answered." + refresh.
  - `{booking_already_resolved, actor}`: "Mira K. already resolved this." (domain 8a1e9721), or "Someone
    already resolved this." when the actor is nil. Then refresh.
  - `invalid`: inline under the field.
  - `forbidden`: "Org admins resolve unconfirmed bookings."
- **Evidence afterwards:**
  - Contact and pass rows read `BOOKED · ATTESTED BY MIRA K.` for `booking_evidence: operator_attested`.
  - Its uplink reads `UPLINK UNCONFIRMED` (caution text) until the provider confirms the leg.
  - When the provider confirms the uplink before AOS (#55, revision reason `uplink_confirmed`), the warning clears
    and the contact's history reads "Northlight confirmed the uplink · 11-14 02:10Z".
  - After AOS the confirmation is only recorded in the history, and the pass doesn't change.

**Attention items (contact drawer D2 block, members with operate):**
- **Caution block:**
  - The U31 title sentence.
  - The resolution record: "Marked booked by Mira K. 10:52Z · ref NL-48213 · 'Called the Northlight ops desk.'"
  - The provider's message, quoted, in mono.
  - One "what to do" line per conflict:
    - `cancel_failed`: "Check with Northlight that the pass is canceled. If it can't be, keep it and record what you did."
    - `late_confirmation`: "Northlight booked it after it was marked not booked. Cancel it with Northlight or use the pass, then record what you did."
    - `contradicts_attestation`: "Don't count on this contact. Re-plan the spacecraft if it needs this contact." (link `Open the day's plan`)
- **Actions:**
  - `Acknowledge` (secondary): the row gets `ACK <you>` (U21).
  - `Resolve…` (primary in the block): a sheet with `What did you do?` (required, placeholder "Called Northlight; the cancel is confirmed, ticket 4471."), then `Resolve`.
  - Cadence can't act at the provider here, so the copy never implies it did.
  - Errors `attention_item_not_found` / `not_open`: "This was already resolved." + refresh.
- **Names:** spacecraft, station and provider names are resolved client-side from their ids. A provider closure in
  `resolved[]` reads "Resolved: Northlight confirmed" / "…canceled".

### U33 · Uplink readiness per pass (DECISIONS #58) (domain / api-ops / fe-ops)
**Decision:** readiness is shown where commanding happens: on the pass, on each command group queued for it,
and in Now's queue when it blocks queued commands. It's quiet when ready.
- **Pass (contact drawer D2, Gantt bar inspector, K1/Contacts pass rows):**
  - `ready`: no tag on bars and rows. The drawer reads `UPLINK READY` (nominal text).
  - `qualifying` / `recovering`: neutral `UPLINK QUALIFYING…` / `UPLINK RECOVERING…`, with the start time
    when known (`since 00:41Z`).
  - `blocked`: a tag `CAN'T COMMAND` plus the reason in words: "Can't command: the session needs its protocol
    state restored." It's **crit** when command groups are queued for that pass, and caution when none are.
  - Reasons map from domain's keys to sentences. Unknown keys fall back to sentence case, never the token (pass-2 #4).
- **Command group (Commands list row, request page `…/uplink`):**
  - When its pass is blocked, the row's secondary line reads "Can't command on the SVB-1 pass (AOS 00:54Z):
    <reason>. Nothing will be sent on this pass until the uplink recovers. Otherwise it goes on the next ready
    pass (FBK 02:31Z) unless it expires at 03:00Z."
  - The group stays queued for the spacecraft and releases on the next ready pass (domain).
  - Name that pass only when the read carries it; otherwise "on the next ready pass".
  - Add the expiry clause only when `not_after` is set.
  - The request page shows the same line as a callout above the uplink trail, with `Recover uplink`.
- **`Recover uplink`:** a secondary button in the drawer and on the request page, for `operate_mission` only.
  - Members without it see "Operators with mission access can recover the uplink."
  - No confirm sheet: it re-runs the automatic recovery, is audited, and is safe to repeat.
  - While it runs, the state reads `UPLINK RECOVERING…` and the button is disabled with the reason "Recovering now".
  - Outcomes are in words: "Uplink recovered · ready at 00:43Z", or "Recovery refused: <reason>". Failure copy per U20.
- **Now queue (U31 attention, subkind `uplink_blocked`):**
  - Title: "EARENDIL-001 · Can't command on the SVB-1 pass."
  - Secondary: "<reason>. 2 command groups are queued for it."
  - Meta: `SVB-1 · AOS T−01:12:00`.
  - Ranking: P1 when AOS is within 2 h or the pass is in progress, P2 otherwise.
  - Action `Review` → the contact drawer, where Recover lives. It resolves by itself when readiness returns to
    `ready` or no groups are queued; the fade reads "Resolved: uplink recovered".
**Amendment (DECISIONS #59, domain):** `Recover uplink` re-runs qualification only, getting fresh provider
attestations. Show it only for reasons it can fix (expired or missing evidence). For each reason:
- `protocol_state_restore_required` (mid-pass restart):
  - Tag `CAN'T COMMAND`: "Can't command: the link restarted mid-pass and can't resume before LOS 01:06Z.
    The next pass isn't affected."
  - No Recover button. In its place: "Recovery isn't possible on this pass."
  - The group line drops "until the uplink recovers": "Nothing will be sent on this pass. It goes on the next
    ready pass (FBK 02:31Z) unless it expires at 03:00Z."
  - The queue row keeps U31 ranking and resolves at LOS ("Resolved: pass ended").
- `cop1_awaiting_clcw`: not blocked. It shows as `UPLINK QUALIFYING… · waiting for the spacecraft's first link
  report`, with no queue row.
- Evidence reasons: the words come with domain's key list. Recover is offered.
**Amendment 2, the reason words (domain e683b3e2).**
- States are `ready | qualifying | blocked`; there's no `recovering`. While Recover runs, the pass reads
  `UPLINK QUALIFYING…`.
- Provider names are resolved client-side. The raw key sits in the drawer's Technical details, never in the copy.

| Key | State | Words after "Can't command:" / "Uplink qualifying ·" | Recover |
| --- | --- | --- | --- |
| `cop1_awaiting_clcw` | qualifying | waiting for the spacecraft's first link report | – |
| `cop1_clcw_stale` (a5004aa8) | qualifying | the spacecraft's link reports stopped; waiting for them to resume | – |
| `cop1_no_clcw_report` (a5004aa8) | blocked | the spacecraft didn't send a link report within 15 s of the uplink connecting. It clears when the spacecraft reports or the link reconnects. | no ("Recovery won't help: it clears when the spacecraft reports."; the server refuses it, c7c79063) |
| `uplink_state_unavailable` | qualifying (always) | Cadence can't read the uplink's state right now | – |
| `session_not_attached` | qualifying | waiting for Northlight's uplink connection | – |
| `protocol_state_restore_required` | blocked | the uplink restarted after this pass had sent commands, and it can't resume before LOS 01:06Z. The next pass isn't affected. | no ("Recovery isn't possible on this pass.") |
| `attestation_*` (signature, challenge, peer, contact, validity, purpose) | blocked | Northlight's proof for this session didn't check out | yes |
| `unverified_peer_connected` (#67) | blocked | an unverified connection took the uplink, so Cadence dropped it and is waiting for Northlight's verified one | yes |
| `uplink_farm_locked_out` | blocked | the spacecraft's receiver reports a lockout | yes |
| `provider_cannot_attest_uplink_sessions` | blocked | Northlight can't vouch for uplink sessions, so Cadence won't command through it. Choose a provider that can in Setup › Ground stations. | no (structural; domain f57e5fff refuses it) |
| `provider_attestation_required` | blocked | Northlight didn't vouch for this session | yes |
| `malformed_provider_attestation` | blocked | Northlight's proof for this session couldn't be read | yes |
| `provider_credential_unavailable` | blocked | Cadence couldn't read the credential for Northlight (link: Org › Provider accounts) | yes |
| `transport_runtime_unavailable` | blocked | the uplink transport isn't running | yes |
| any other key | blocked | Northlight returned an error (<key in sentence case>) | yes |

- **Next pass** (domain: it's booked, not guaranteed ready): the group line reads "…Otherwise it goes on the next pass
  (KIR 02:31Z)…".
  - Use the station code: `next_contact.ground_station_ref` is resolved through the stations index (domain f57e5fff). Fall back to "the next pass at 02:31Z" only if it can't be resolved.
  - With no `next_contact`: "…until the uplink recovers. No later pass is booked for it yet."

### U34 · Money is hidden, not "not reported" (DECISIONS #63)
**Decision:** with billing out of scope, no screen shows a money panel, tile, column, budget or dispute.
"Not reported" would imply that Cadence tracks money and is missing a number; hiding says it isn't part of
the product. Layouts reflow, with no empty slots. Time facts stay. Wording that only made sense with billing
goes too ("22 inside 2 h are billed", "to dispute"). Contact planning hides its money policy fields; they
keep their server values. When billing returns, the specs' money items come back as written.

### U35 · Queue ranking without a modelled max gap (api-ops, amends U11)
**Context:** U11's "next contact beyond its allowed gap" assumed a max gap. None is modelled.
`minimum_separation_seconds` is the minimum spacing between contacts, and my earlier specs misread it as a
max gap (corrected in ContactPlanning and U22).
**Decision (interim, until contact requirements carry a max gap):**
- **Missed pass:**
  - **P1** when the spacecraft has no booked contact in the next **6 h**, or its next contact is unknown.
  - **P2** otherwise.
  - The evidence line says which: "Next contact SVB-1 in 1h 12m", or "No contact booked in the next 6 h".
  - Keep 6 h as one named constant, so it can become the requirement's max gap later.
- **Station outage, maintenance or degraded windows over booked passes:**
  - Horizon **24 h**, **P2**.
  - **P1** when an affected pass starts within **2 h** or is in progress (the same clock as U31/U33).

### U36 · Resubmitting a sent-back plan (qa #40) (lead / api / domain)
**Decision:** lead's recommendation. A sent-back draft can be submitted again **unchanged**: on submit, the server
creates a new version (vN+1, same selection). The rejection stays on vN for the audit trail. A reviewer may only
want better gap reasons (acknowledgements are per submit), so a forced, meaningless edit would be worse.
- **Author callout:** "Sent back by Mira K. at 10:52Z: <reason>. Change the plan or its gap reasons, then submit
  it again."
- **Primary:** `Submit again` (admins: `Submit again and book N passes`). The accept-gaps sheet reopens with the
  previous reasons prefilled and editable.
- **Optional note** in the sheet: `What changed for the reviewer` (one line). The reviewer sees it as
  "Resubmitted by Tomás R. · 11:20Z: <note>", or "Resubmitted unchanged" when it's empty.
- **Reviewer view:** the header context includes `v2 · RESUBMITTED`, and a text-3 line shows the earlier round:
  "v1 sent back by Mira K. at 10:52Z: <reason>".
- **The sheet's title names the act** (lead's finding approving the 11-18 plan, 11-17; it read "Submit the plan" for
  every case). With unmet gaps the title stays `Accept 2 gaps · …`. Otherwise, matching the commit button without
  its count:
  - draft, not an admin: `Request approval`; sent back: `Submit the plan again`
  - draft or sent back, admin (submitting approves and books): `Approve and book the plan`
  - awaiting approval, admin: `Approve and book the plan`
  - Re-plan's proposal: not an admin `Request approval for the proposal`; admin `Approve and apply the proposal`
- `contact_plan_version_already_decided` should then only occur in a race (someone else decided first): "This
  version was already decided by <actor>. Reload to see it."


### U37 · Telemetry not yet stored after a pass (DECISIONS #71, domain shape) (domain / api-ops / fe-ops)
A U31 attention source, `contact_settlement`. It's raised 6 h after LOS (`deadline_at`) while the pass's telemetry
is still on disk and not in telemetry history. It's always **P2**: the journal is never pruned before it's stored
(`expires_at` null), so nothing is lost by waiting. No person action and no Acknowledge. Cadence retries by itself
(`retry: "automatic"`), and the system closes the item.
- **Row** (title / evidence / meta):
  - Title: `EARENDIL-001 · Telemetry from the SVA 18:49Z pass isn't stored yet.` The time is the AOS (`starts_at`),
    with the §4 date prefix when it isn't today. Drop the station when it's null.
  - Evidence, by `failure_kind`:
    - `telemetry_storage_unavailable`: "1,204 entries (3.4 MB) are on disk. Telemetry storage is unavailable;
      Cadence stores them when it's back."
    - `settle_failed`: "1,204 entries (3.4 MB) are on disk. Cadence couldn't store them: <failure_message>."
    - null (deadline passed with no failure): "1,204 entries (3.4 MB) are on disk, past the 00:57Z deadline for
      storing them."
      Domain confirms: a slow drain, not a failure, and `failure_message` is null too. Null items fold together;
      the folded line is "… are on disk, past the deadline for storing them."
  - Meta: `SVA · Northlight · 18:49Z–18:57Z`. Drop any part that's null (U20).
  - Action: `Review` goes to the contact drawer (`contact_id`).
  - The UI never shows "TSDB", "journal", "settlement" or the journals count. `failure_message` is shown only for
    `settle_failed`; for storage outages it goes in Technical details.
  - Bytes use the console's decimal formatter (`formatBytes`, add a GB tier at ≥ 1e9).
- **Folding:** two or more open items with the same `failure_kind` fold into one row:
  `Telemetry from 37 passes isn't stored yet.` / "48,210 entries (4.1 GB) are on disk. Telemetry storage is
  unavailable; Cadence stores them when it's back." The meta is the earliest and latest pass (`11-11 06:01Z … 18:49Z`).
  `Show all 37` opens the U30-style sheet, which lists the passes soonest-first and links each to its drawer.
- **Resolved:** the row fades for 5 s with `Resolved: telemetry stored` (a system closure states the action only, U31).
  A folded row counts down as items resolve, then fades the same way.
- **Contact drawer:** a caution block reads "Telemetry from this pass isn't stored yet." plus the evidence line.
  It has no actions.
- **Retries (domain #71 replay delta, director: stop after 6 failed replays):**
  - **Automatic, backing off** (`retry: "automatic"`, `next_attempt_at` set): the evidence line ends with
    "Next try at 23:40Z." in place of "Cadence stores them when it's back". When `attempts` > 0 it adds
    "<n> of 6 tries failed." With `next_attempt_at` ≤ now: "Trying now."
  - **Manual** (`retry: "manual"`): the row needs a person. It stays P2 (nothing is lost) but sorts above the
    automatic items in P2. Evidence: "1,204 entries (3.4 MB) are on disk. Cadence stopped after 6 failed
    tries: <failure_message>." With storage unavailable, the reason reads "telemetry storage was unavailable
    at the last try, 23:10Z". The action is `Retry storing` (POST …/retry). While it's in flight the row
    reads `Retrying…`, then it returns to the automatic form ("Trying now."). An error is shown in the row
    with the server's sentence (U20).
  - Without the capability, there's no button and the row reads "Operators can retry storing."
  - **Folding:** the fold key is `failure_kind` + `retry`, so manual items never hide inside an automatic
    fold. A folded manual row: "Cadence stopped retrying for 37 passes." with `Retry all 37`. The result reads
    "Retried 37." or "Retried 35 of 37. 2 failed: <reason>."
  - **Drawer block:** adds "Tried 6 times, last at 23:10Z." and, when manual, the same `Retry storing`.
  - **Server answers** (domain): Retry needs `operate_mission` (403 otherwise). There's no bulk endpoint: `Retry
    all` sends one POST per item, and each one stands alone. A 409 `retry_not_manual` means someone else already
    restarted it. That isn't a failure: the row takes `details.item`, and in a fold it counts as retried. A 404
    means it was resolved meanwhile and the item drops out. `failure_*` and `last_attempt_at` describe the latest
    attempt. `first_failure_kind` goes in Technical details only.
  - **After a retry** (fe-ops c10265fd): a 200 updates the row from the returned item at once. If every item in a
    fold was retried, the emptied fold stays for 5 s with "Retried 37." and fades like a resolved row. On a
    partial result, the remaining fold keeps "Retried 35 of 37. 2 failed: …" in its evidence. Without
    `operate_mission`, rows keep `Review` / `Show all N` and add "Operators can retry storing."
- **Journal off, telemetry lost** (`journal: "disabled"`, `lost: true`; director-approved): there's no on-disk copy,
  so the UI never says "on disk" or offers Retry.
  - Row title: `EARENDIL-001 · Telemetry from the SVA 18:49Z pass was lost.`
  - Evidence: "412 telemetry batches were in memory when the runtime stopped and weren't stored. This mission
    doesn't keep a disk copy, so they can't be recovered."
  - The drawer shows the same text in a caution block. Caution, not crit: the loss is past and final, and
    there's nothing to do now.
  - The fold key adds `lost`: "Telemetry from 37 passes was lost." / "1,912 batches weren't stored and can't be
    recovered." A lost item never folds with on-disk items.
  - **Closing (domain: acknowledge closes it, unless the director vetoes):** a person closes it with `Mark as
    seen` (POST …/acknowledge, allowed only when lost, needs `operate_mission`). The resolution is {action:
    "acknowledged", actor: user}, and the row fades with "Resolved by Mira K.". Until then it stays P2.
    Without the capability: "Operators mark lost telemetry as seen." This acknowledge closes the item,
    unlike U31's, which only sorts it last; the label `Mark as seen` keeps the two apart.
  - If the mission has a setting that turns the disk copy on, the drawer links to it ("Keep a disk copy of
    incoming telemetry"). It isn't shown unless the setting exists.
- **Later, not in this step:** contacts showing "settling" after LOS (realized-contact `metadata.settlement`). It
  gets wording when a read carries it.

### U38 · The runtime hasn't applied the active configuration (domain proposal, director: 2026-11-12 outage) (domain / fe-ops / lead)
A U31 attention source, `mission_runtime` (`generation_not_applied`). It opens after 60 s of mismatch and is
system-closed. Mission-wide, so it has no spacecraft. **P1**, and it sorts first. No Acknowledge.
- **Row:**
  - Title: `EARENDIL · Telemetry isn't being processed.` (the mission name is the subject).
  - Evidence: "The runtime hasn't applied the active configuration; it's still running the earlier one."
    (when `applied_generation` is null: "…; no configuration is running."). `since` (domain: when applying
    the current configuration first failed) appears only in the meta and the banner. Then the reason, by key:
    - `spec_mismatch`: "What's running doesn't match it."
    - `runtime_not_running`: "The runtime isn't running."
    - `apply_failed`: "Applying it failed: <failure_message>."
    - `reconcile_crashed`: "Cadence's apply process hit an error: <failure_message>."
    - null: no clause. (These are the keys in domain 292c8e6b, `Control.MissionRuntimeStatus.reasons/0`.)
  - **Retry sentence by group** (domain: every 30 s poll retries the apply, for all reasons):
    - `runtime_not_running`, `apply_failed` (these can clear on their own): "Cadence keeps trying every 30 s."
    - `spec_mismatch`, `reconcile_crashed` (they come from the stored configuration, so retrying won't fix
      them): "Retrying won't fix this. The configuration needs a fix, or a new one needs activating."
      `Review` is the primary on this row.
    - null: no retry sentence.
    - The banner adds " It needs a configuration fix." only for the second group, and stays reason-free
      otherwise.
    - Any other key: no reason clause; the key goes in Technical details.
  - Meta: `GENERATION 8 · RUNNING 7 · SINCE 23:10Z` (mono; `RUNNING —` when null).
  - Words never used: "generation" in sentences, "reconciler", "spec".
- **Banner (lead's proposal, domain's ask: yes):** a crit strip under the top bar on every mission page, Ops and
  Setup, while the item is open. Every live value is stale, not only Now's. Organization and account pages don't
  show it.
  - Text: "Telemetry isn't being processed for EARENDIL since 23:10Z. The runtime hasn't applied the active
    configuration." (with `activated_at`: "…the configuration activated at 23:00Z"). `since 23:10Z` is shown
    only when the server sends `since`. followed by the link `Details`, which goes to the queue row on Now. The banner reads
    `/counts.runtime` (api-ops), which shares its source and its 60 s debounce with the attention item.
  - One line; truncated at 390 with `Details` kept visible. It can't be dismissed.
  - When the item resolves, the strip turns nominal for 5 s ("Telemetry processing resumed at 23:26Z."), then
    goes.
  - Now shows the banner and the P1 row. Its h1 stays computed, so there's no third copy.
- **Meta:** the age replaces the AOS countdown: `GENERATION 8 · RUNNING 7 · SINCE 23:10Z · T+00:14:02`.
- **Review:** goes to Setup › Changes, opened on the change set that activated it when the item carries
  `change_set_id`, otherwise the Changes list. Readiness can't show it (domain).
- **Resolved:** the row fades for 5 s with `Resolved: configuration applied`.
- **Optional fields** (a clause is added only when the server says so, U20):
  - `activated_by` together with `activated_at`: the evidence adds "Mira K. activated it at 23:00Z." (U29: the
    actor and the time of the same event, never `since`). With no `activated_at`, the actor isn't shown.
  - Commanding also stopped: the evidence adds "Commands can't be sent."
- Domain states that no spacecraft's telemetry is processed while the item is open, for every reason. The title
  relies on that.

### U39 · Staged changes left waiting (api BACKLOG 8d, Now queue kind `change_set_stale`) (api / fe-ops)
P3, `off` mark, at most one per mission. Shown when the active change set holds staged changes and the oldest is
more than 24 h old.
- **Open:**
  - Title: `3 staged changes aren't applied`.
  - Evidence: "Staged on r6 by Mira K. and Ana P. The oldest has waited since 11-11 02:10Z." The time belongs to
    "the oldest", not to the authors (U29). With 3 or more authors: "Mira K., Ana P. and 2 others".
- **In review:**
  - Title: `3 staged changes are waiting for review`.
  - Evidence: "Sent for review at 11-12 09:00Z. Staged on r6 by Mira K. and Ana P." Name a submitter only if the
    server sends one.
- **Meta:** `SINCE 11-11 02:10Z · T+1d 21:44` (oldest_staged_at, as U38's age).
- **Action:** `Review` → Setup › Changes.
- **Singular:** `1 staged change isn't applied` / `is waiting for review`.
- **Timeline `config_revision`:** `Applied r6 · 2 changes`, plus the actor when the event has one. It links to
  Setup › Revisions r6.

### U40 · Per-spacecraft Commanding and Telemetry switches; handled APIDs (§11 L22) (domain / api / fe-setup / fe-ops)
- **Spacecraft page** (Setup › Spacecraft › EARENDIL-312) gets an `Operation` panel with two switch rows. Each has
  a label, a state sentence and the switch:
  - `Commanding`. On: "Operators can request and release commands to EARENDIL-312." Off: "No new requests or
    releases for EARENDIL-312."
  - `Telemetry`. On: "Cadence decodes telemetry from EARENDIL-312." Off: "Cadence doesn't decode telemetry from
    EARENDIL-312: no live values, alarms or new history." What happens to incoming frames (kept raw or dropped) is
    for domain to confirm; add it to the sentence when known.
  - **Not set** (api: `null` when the mission has no active configuration for the spacecraft): the state sentence
    is "No active configuration covers EARENDIL-312 yet, so this isn't set." with the off tag `NOT SET`. It
    doesn't claim on or off (U20). Staging a value from here works like any other switch change.
- **Changing a switch stages it** (L17 spacecraft kind). The switch shows the staged target with a caution tag
  `STAGED · APPLIES WITH r7` until it's applied. Changes line: `EARENDIL-312 · turn commanding off` / `turn
  commanding on` / `turn telemetry off` / `turn telemetry on`.
- **No typed confirm.** It's reversible, and the change-set review is the confirmation. Staging off opens a short
  sheet that states the consequence from the dry run: "Turning commanding off stops new requests and releases for
  EARENDIL-312. 3 queued commands won't be released." (only if the dry run counts them), or for telemetry "No
  live values, alarms or new history from EARENDIL-312 until it's turned on again." Actions `Stage` and `Cancel`.
- **While commanding is off:**
  - The spacecraft header (Investigate, Fleet row) shows the off tag `COMMANDING OFF`. `Command` is disabled with
    "Commanding is off for EARENDIL-312."
  - In Compose, the target is excluded with that reason.
  - The refusal `spacecraft_commanding_not_active` reads "Commanding is off for EARENDIL-312." plus "Turn it on in
    Setup › Spacecraft." with a link for people with `config.stage`.
  - On release: "Not released: commanding is off for EARENDIL-312."
- **Telemetry off:** the header tag `TELEMETRY OFF`. Its live values read "Telemetry is off for this spacecraft." in
  place of stale hatching, so it doesn't look like a fault.
- **Change-set HOLDs for these switches** (domain puts them in the HOLD's sentence field):
  - (a) Hard: "Commanding can't be turned off for EARENDIL-312 while “Low power safe” is being sent to it. Abort
    that request or wait for it to finish." Use the request's title as the server gives it, and the same
    sentence for releasing and radiating.
  - (b) Acknowledgeable: "Turning commanding off cancels 3 commands waiting to be sent to EARENDIL-312 when this is
    applied." (singular: "1 command … waiting"). The ack placeholder: "Why it's safe to cancel them".
  - (c) Acknowledgeable: "After this is applied, telemetry from EARENDIL-312 isn't decoded: no live values, alarms
    or new history until it's turned on again."
  - (d) Hard: "EARENDIL-312 handles APIDs 0x101 and 0x1A0, which rev 15 doesn't define. Change its handled APIDs
    first." Several spacecraft: "12 spacecraft handle APIDs that rev 15 doesn't define (0x101, 0x1A0). Change
    their handled APIDs first." List at most 5 APIDs, then "and 3 more".
  - (e) Acknowledgeable `handled_apids_change` (domain: null = all, expanded at apply; any apply that changes what
    a spacecraft decodes is shown). The sentence states the change, not the full list, and always says "after this
    is applied":
    - Wider: "EARENDIL-312 will also decode APIDs 0x2B, 0x30 and 3 more after this is applied (today only 0x2A)."
    - Narrower: "EARENDIL-312 will stop decoding APIDs 0x2B and 0x30 after this is applied."
    - Both: "EARENDIL-312 will start decoding 0x31 and stop decoding 0x2B after this is applied."
    - Several spacecraft: "12 spacecraft will decode different APIDs after this is applied." The list is in the
      HOLD's detail (spacecraft, with added and removed APIDs).
    - Ack placeholder: "Why this change is intended". At most 5 APIDs per list, then "and N more".
    - Effects tag on the change row: `DECODED APIDS CHANGE` (caution), beside any `RUNTIME` tag.
- **Handled APIDs** (profile field next to the catalog revision, overridable like P3): label `Handled APIDs`, with
  the default value `All of the catalog's APIDs`. An override is a mono chip list in the catalog's notation:
  `Only 0x101, 0x102, 0x1A0`. Help: "Packets with other APIDs aren't decoded." (domain to confirm the effect).
- **Switch help text** (api's L17 schema `help`, lead's ask 11-13; state-independent, shown under each label):
  - Commanding: "Lets operators request and release commands to this spacecraft. Turning it off cancels commands
    still waiting to be sent when the change is applied."
  - Telemetry: "Cadence decodes this spacecraft's telemetry into live values, alarms and history. Turning it off
    means no new live values, alarms or history until it's turned on again."
- **HOLD acknowledgements** (the sentences are already in `SwitchCompatibility` and match (b) and (c)). They're
  acknowledged on Changes with the "I've read the N holds" checkbox, plus a reason where a placeholder is given:
  - `commanding_disabled_cancels_commands`: placeholder "Why it's safe to cancel them".
  - `telemetry_disabled`: placeholder "Why decoding can stop for EARENDIL-312".
- **Archive** (deleting a spacecraft archives it, #49/#50):
  - Staging it opens a short sheet titled `Archive EARENDIL-312?`: "It leaves the mission's lists, fleet and
    planning when the change is applied. Its history stays." Actions `Stage archive` and `Cancel`.
  - HOLD `spacecraft_has_traffic` sentence: "EARENDIL-312 has had passes booked or commands requested. Archiving
    it takes it out of the mission's lists, fleet and planning when this is applied. Its history stays."
    Placeholder: "Why EARENDIL-312 is being archived". Say "passes booked" (reservations), not "contacts".
  - **Pending traffic** (lead's ruling, 11-13). The counts and the earliest pass time are in the HOLD's detail:
    - **Waiting command requests block** (hard HOLD): "EARENDIL-312 has 1 command request waiting. Release or
      cancel it first." Plural: "…has 2 command requests waiting. Release or cancel them first." The row links
      `Open in Uplink` (this spacecraft, waiting).
    - **Future booked passes are acknowledged:** "3 booked passes from 11-15 03:00Z stay booked after EARENDIL-312
      is archived. Release them in Contacts if they're not needed." Singular: "1 booked pass on 11-15 03:00Z stays
      booked after EARENDIL-312 is archived. Release it in Contacts if it isn't needed." The time is §4 short time;
      drop "from …" / "on …" when the server doesn't give it. Ack placeholder: "Why the passes stay booked". The row
      links `Open in Contacts` (this spacecraft, booked, from now).
  - **The archive sheet** shows the same check from the dry run, under its "It leaves…" line. Waiting requests
    show a crit callout with the blocking sentence and its link, and `Stage archive` is disabled with "Release or
    cancel the waiting requests first." Booked passes show a caution callout with the passes sentence and its
    link, and Stage stays enabled. When the dry run can't tell, the sheet keeps the plain line, and the HOLD
    catches it on Changes.
  - **Already staged** (fe-setup 674a65a1b, qa's duplicate find): the sheet shows an info callout, not nominal
    (it isn't an outcome): "Archiving EARENDIL-009 is already staged. It happens when the change set is applied."
    with `Open Changes`. `Stage archive` is disabled with "Already staged." The two don't repeat each other.
  - **Refusal `spacecraft_archived`** (releasing or uplinking a command for an archived spacecraft): "EARENDIL-312
    is archived, so commands can't be released or sent to it." On a release it reads as the release outcome:
    "Not released: EARENDIL-312 is archived." In Compose, an archived target isn't offered.

### U41 · An approved activation that didn't apply: sentences, Retry, Now row, audit (§11 L10, domain 9b8456132) (domain / api / fe-setup / fe-ops)
- **Error sentences** (domain's `error` field; standalone, so Now and the review page use them as they are; the
  code goes in Technical details):
  - `apply_stalled`: "Applying didn't finish, and nothing is working on it now." It's true both when it stopped
    partway and when it never started.
  - `activation_execution_interrupted`: "Applying was cut off: Cadence lost its database connection partway."
  - `spacecraft_configuration_review_stale`: "EARENDIL-312's configuration changed after it was reviewed, so the
    reviewed version can't be applied." Several or unknown: "A spacecraft's configuration changed after it was
    reviewed, so the reviewed version can't be applied."
  - `approved_activation_content_mismatch`: "What would be applied now differs from what was approved, so it
    wasn't applied."
  - Any other code: "Applying failed." Never the raw reason (U20).
- **Next step, by cause:**
  - Stalled, interrupted or another code: `Retry apply` (people who may approve). Domain says every step is
    safe to repeat, so the button needs no warning. Without the permission: "Someone who can approve activations
    can retry it."
  - Review stale or content mismatch: no `Retry apply`, because re-running checks the same thing and fails again.
    The next step: "Request activation again so the current version can be approved." Domain confirms a resume can
    never succeed for these two (8f30aac21).
  - **The console reads `retryable`** (domain's field on the item and row) and doesn't keep its own list of codes:
    true shows `Retry apply`, false shows the request-again sentence.
  - **Refusals from `Retry apply`:**
    - `409 not_resumable {error_code}`: "This can't be retried: <the code's sentence>" followed by the
      request-again sentence. The row then switches to the false state.
    - `409 nothing_to_resume {state}`: succeeded reads "It already applied." in_progress reads "It's applying now."
      Any other state: "There's nothing to retry." Refetch either way.
- **Review page line** (fe-setup): caution "Approved, but it didn't apply. <sentence> Since 02:14Z." Then the next
  step as above.
- **Now row** (`activation_apply`, fe-ops):
  - Title `Decom composition for 3 spacecraft · approved, not applied` (the server's summary; spacecraft batch-named).
  - Meta: `Approved by Mira K. at 02:10Z · since 02:14Z`. Body: the sentence. Action: `Retry apply` or `Review`, as
    above.
  - Priority: P1 when `runtime_not_applied` (add the line "Telemetry isn't being processed until this applies."),
    else P2. This is domain's suggestion, accepted.
  - Resolved: applied reads "Applied at 02:20Z."; superseded reads "Replaced by a newer request." (the review page's words, lead, fe-setup 1de70ac18) The
    row fades as other resolved items do.
- **Audit `activation_resumed`** (mission event log): "Mira K. retried applying “Decom composition for 3
  spacecraft”." Without a summary: "Mira K. retried applying an approved activation." The binding set and its
  version go in Technical details.
- **Withdraw** (requester, once domain ships it; fe-setup 1de70ac18): `Withdraw request`, with the reason inline on
  the review page (required, placeholder "Why you're withdrawing it"). There's no sheet, so the label has no `…`.
  After it: the decision line "Withdrawn by Mira K. at 02:20Z: <reason>." Superseded: "Replaced by a newer
  request.", where `newer request` links to it.

### U42 · HOLD `derived_point_in_use` (derived telemetry kind; domain proposal 11-13) (domain / api / fe-setup)
A blocking HOLD: retiring a point that another derived point's expression uses. It names the point first, then why,
then the fix:
- One dependent: "BATT_SOC_PCT can't be retired: BATT_HEALTH's expression uses it. Change or retire BATT_HEALTH
  in this change set too."
- Several: "BATT_SOC_PCT can't be retired: 3 derived points use it in their expressions (BATT_HEALTH, PWR_MARGIN,
  EPS_FLAG). Change or retire them in this change set too." List at most 5 names, then "and 2 more".
- Names are the points' names as the server gives them, in mono. On Changes each dependent links to its
  definition in the Derived telemetry app: `M/setup/apps/derived_telemetry/manage?definition=<derived_definition_id>`
  (AppSurfaces.md › Deep links; the app's own query key, lead 11-13). That needs the definition id per dependent in
  `used_by` (domain). Without it, there's no link and the name still shows in mono. The plain sentence is fine
  until the kind ships.
- It doesn't fire when every dependent is retired or changed in the same change set. If domain makes it
  acknowledgeable instead, the first clause becomes "Retiring BATT_SOC_PCT breaks BATT_HEALTH, whose expression
  uses it." and ux adds a placeholder.

### U43 · Limits as a change-set kind `limit_definition` (#77 stage 2; domain proposal 11-13) (domain / api / fe-setup)
- **Summaries:** the set is named only when it isn't DEFAULT. "Add limits for BATT_V" / "Edit limits for BATT_V" /
  "Retire limits for BATT_V"; with a named set: "Add ECLIPSE limits for BATT_V". Point ids are in mono.
- **Retire** is the verb for delete. Its effect line on Changes: "BATT_V stops being checked against these limits
  when this is applied. Its alarm history stays." Re-adding the same point and set continues that history.
- **HOLD `limit_alarm_active`** (acknowledgeable). Severity words follow the Alarms page: red, yellow, or "limit"
  when unknown.
  - Edit: "BATT_V has a red-limit alarm raised now. When this is applied, it's checked against the new limits
    and may clear or change." Placeholder: "Why it's safe to change them while it's raised".
  - Retire: "BATT_V has a red-limit alarm raised now. Retiring these limits clears it when this is applied."
    Placeholder: "Why it's safe to clear it".
  - With a named set: "BATT_V's ECLIPSE limits have a red-limit alarm raised now. …"
  - One HOLD per point and set. The row links `Open in Alarms` (Alarms filtered by `?point=<point_id>`). There's
    no per-episode page, and limits are mission-wide, so every spacecraft raised on that point shows (fe-setup).
- **Kind word** on Changes: `Limits`.
- **Hold placeholders in Apply's one `Why` field** (also for U40's holds): with exactly one acknowledgeable hold,
  the field uses that hold's placeholder. With several, it uses "Why it's safe to apply despite these holds".
- **Field errors** keep today's direct-save messages. Two new ones: "Limits for BATT_V already exist. Edit them
  instead." (a point_id field error at staging, domain 63206b13d; link to them only through a query key the Limits
  app declares, AppSurfaces.md › Deep links, otherwise no link) and "The point and limit set can't change after the limits are added."

### U44 · Provider changes to booked passes (§11 L14, api 30b3f60b9) (fe-ops / api)
The U31/U32 grammar applies: one item per change, approval P2 due at the deadline, acknowledgement and
configuration failure P3. The amendments to fe-ops' drafts:
- **Titles** (the pass identified as in Contacts, §4 time with the date when it isn't today):
  - approval_required: `EARENDIL-312 · Northlight wants to change the SVA 03:10Z pass`
  - acknowledgment_required: `EARENDIL-312 · Northlight changed the SVA 03:10Z pass`
  - configuration_failure: `EARENDIL-312 · Cadence couldn't apply Northlight's change to the SVA 03:10Z pass`.
    Cadence is named because it's Cadence's side that failed. The body adds nothing that isn't known; the action
    is `Review`.
- **Evidence:** the changed fields, as in `Start 03:10Z → 03:12Z · Antenna 2 → 4`.
  - At most 3, then "and 2 more".
  - Labels are the server's `label` (see Field labels below; no console map is needed). Never show raw JSON
    quoting.
  - Times use the §4 format. A value that's absent or null reads `none`.
  - Approval adds "Decide by 02:40Z. After that, Northlight decides." At the deadline Cadence does nothing by
    itself (api 84f58b73d).
  - Acknowledgement adds "Northlight already made this change."
- **Drawer block:** a Before → After table with the same labels and formats. Every action needs a reason, and
  'Say why.' stays the validation message. Placeholders:
  - Approve (primary): "Why the pass can take this change".
  - Reject: "Why the pass can't take this change".
  - **After the deadline**, both Approve and Reject are refused, so both go. The block reads "The deadline passed
    at 02:40Z. This change stays until Northlight's next update replaces it." (fe-ops' words). The Now row
    swaps "Decide by …" for "The deadline passed at 02:40Z." and drops to P3, because there's nothing left to do
    here.
  - Acknowledge: "What you checked".
  - Members see the block without buttons and the line "Org admins decide provider changes."
- **Refusals:**
  - 409 stale with an item: "Northlight changed it again. Here's the current change." The block reloads.
  - 409 stale with a null item: "This change was already decided or replaced." The row resolves.
  - 409 deadline passed (a decision racing the deadline): the block switches to its after-deadline state and line.
  - 403: "Org admins decide provider changes."
- **Resolved** (U29, actor and time): "Approved by Mira K. at 02:31Z: <reason>." / "Rejected by …" /
  "Acknowledged by …" / "Replaced by a newer change." The last matches U41's "Replaced by a newer request."
- **Field labels** (server-side, api 84f58b73d): `AOS` · `LOS` · `Station` · `Antenna` · `Service profile` ·
  `Delivery profile` · `Spacecraft` · `Pass phase` · `Status`. AOS and LOS match how Contacts names pass times.
  A field the server can't label (null) isn't hidden, because hiding it would understate the change (U20). In
  Now it counts toward "and N more". In the drawer it's a row labelled `Other`, with its key and raw values in
  Technical details.
- **After the pass has flown** (lead 11-13: these leave Now).
  - **An unapproved change expires.** On the pass detail its block keeps the Before → After table, read-only,
    with the off tag `EXPIRED` and the line "Northlight's change wasn't decided before the pass ended, so it
    expired." It doesn't say whether Northlight applied it (U20); the pass's own times show what flew. There are
    no buttons.
    - 409 when a decision races the pass: "The pass has ended, so this change can't be decided any more." The
      block then shows the expired state.
    - Pass history line: "Not decided: the pass ended first." (domain's words, lead 11-13)
  - **An unacknowledged change stays acknowledgeable** in the pass history. Its entry shows the caution tag
    `NOT ACKNOWLEDGED` and "Northlight changed this pass: AOS 03:10Z → 03:12Z · Antenna 2 → 4." (the same
    evidence rules), plus `Acknowledge` with a required reason (placeholder "What you checked"). After that:
    "Acknowledged by Mira K. at 11-14 09:10Z: <reason>." It's not in Now, so nothing else nags. The pass detail
    header shows the count `1 CHANGE NOT ACKNOWLEDGED` (caution text), linking to the entry.
  - **Pass history = `provider_changes`, every change** (api: newest first, at most 50, each with `resolution`).
    Every entry leads with the evidence, "Northlight changed this pass: AOS 03:10Z → 03:12Z.", then its outcome:
    - approved / rejected / acknowledged: "Approved by Mira K. at 02:31Z: <reason>." With `by` null: "by an
      operator" (U29).
    - policy_accepted (`by` null): "Accepted by the mission's policy at 02:31Z."
    - superseded: "Replaced by a newer change."
    - expired: "Not decided: the pass ended first."
    - configuration_failure / apply_failed: "Cadence couldn't apply it." (crit mark).
    - observed: no outcome line and no tag; the evidence alone. It's shown, not hidden, because the pass did
      change, and history should say so (U20).
    - Open states keep their block (approve, acknowledge). An unknown state shows the evidence alone.
    - At 50: "Showing the latest 50 changes."
  - **A booking's own confirmation isn't a provider change** (qa's find, api 11-13). When a status-only pending →
    confirmed transition is the provider confirming the booking, it isn't listed as "…changed this pass". Domain
    stops classifying it as a provider change at the source; api doesn't filter on field shape. When the pass
    history shows the confirmation, it's the booking's own line: "Confirmed by Earendil Demo Ground Network at
    02:12Z." Any other status change by the provider (for example confirmed → cancelled) is a real change and
    stays.

### U45 · Now source `contact_start`: a pass that didn't start (domain, with the eaddrinuse fix) (domain / api / fe-ops)
- **not_started** (in the window, Cadence retrying), **P1**, due at LOS:
  - Title `EARENDIL-312 · SVA 03:10Z pass hasn't started`.
  - Meta `Cadence is retrying · 3 tries · LOS T−00:06:12`. Give the try count only if the server sends it.
  - Body: the reason sentence (below).
  - Action: `Open pass` (Contacts). There's no "Start now" unless domain offers a real action.
  - It resolves when the pass starts: "Started at 03:12Z." The row fades.
- **missed** (the window ended unstarted), **P2**:
  - Title `EARENDIL-312 · SVA 03:10Z pass was missed`.
  - Body: "The pass ended before Cadence could start it." then the reason sentence.
  - Action `Mark as seen` (as in U37: no reason, needs `operate_mission`). Without the capability: "Operators
    mark missed passes as seen."
  - Resolved: "Marked as seen by Mira K. at 03:40Z."
- **Reason sentences** (domain's list, 11-13; the key and `failure_message` in Technical details):

| Key | Sentence | Link |
| --- | --- | --- |
| listener_in_use | "Cadence couldn't open the station connection because the EARENDIL-047 · SVA 02:55Z pass was still holding it." Without a holder: "…because another pass was still holding it." | the holder pass |
| listener_unavailable | "Cadence couldn't open the station connection on its side." | — |
| connect_failed | "Cadence couldn't reach Northlight's endpoint for this pass." | `Check provider` (Setup › Ground stations › Providers) |
| ingress_pipeline_failed | "Cadence couldn't start storing telemetry for this pass." | — |
| uplink_session_failed | "Cadence couldn't start the uplink session for this pass." | — |
| no_runtime_spec | By `reason_detail` (U91). `no_configuration` and null: "No configuration has been activated on this mission yet, so passes can't start. EARENDIL-004's configuration has to be reviewed and activated first." (no spacecraft: "…Each spacecraft's configuration has to be reviewed and activated first."). It says where the fix is, not that the console does it: today review and activate exist only in the legacy host's spacecraft page (domain 11-17), a gap taken to lead.. A change set can't start a mission (U93, domain 11-17), so never `Open Changes`. `configuration_unverifiable`: U91's words. | `Open spacecraft` (Setup › Spacecraft › EARENDIL-004; without a spacecraft, the list). `configuration_unverifiable`: `Open pass` |
| transport_archived | "This pass's transport, INU S-band, was archived after the pass was booked, so it can't start, and every try fails the same way. Book another pass for this spacecraft." Without `transport_name`: "This pass's transport was archived after…". Only this pass: later bookings take a live route (domain 11-17: the template is taken at booking, and the in-use check keeps routes and booked passes off an archived transport), so nothing is said about later passes. (api 11-17; U82) **Building (api):** this refusal comes before the pass exists, so today it raises no item; api is recording every realization refusal on the booked pass (lead 11-17), and the item anchors there. Other realization refusals read the `unknown` line. | `Book a pass` (Contacts, for this spacecraft) |
| unknown | "Starting failed." | — |
| (missing) | "No reason was recorded." | — |

- **Failed before the pass was set up** (api, lead's (A), 11-17: `realized_contact_id` null, the item anchored on the
  booked pass): titles, meta, retries and Mark as seen as above. `unknown` reads "Cadence couldn't set up this
  pass." instead of "Starting failed." (it's known the failure came before the start; `failure_message` in Technical
  details). Other keys use their row. Resolved (`started` at setup): "Set up at 03:12Z." (not "Started": the start
  itself can still fail, and then the usual item appears). The resolved entry's `realized_contact_id` is what the
  item was while open (api 11-17): null reads "Set up at…", a value "Started at…".

  There's no "Start now": Cadence already retries as soon as it can (domain), so `Open pass` is the only action.
  Domain sends any new key before it's used.
- **In Contacts** (there are no pass rows: the schedule is an ApGantt; fe-ops 11-13):
  - **Bar:** a status mark at its leading edge, ApStatusMark ▲ caution while not started and ◆ crit once
    missed. It's shape and colour, never colour alone, and not a bar fill. This needs an ApGantt bar prop
    `attention: caution | crit | null` (fe-setup, ui package). It shows the top item by U45's order.
    The mark sits on a small dark backing so ▲ stays visible on caution-filled bars. The Gantt legend lists the
    marks only while one is on screen, as with U30's Unconfirmed: `▲ Needs attention` · `◆ Missed` (revised,
    fe-ops 11-13). ▲ marks any pass whose top item is open and caution-level (not started, a decision with a
    deadline, a resolution), so actionable passes show on the chart. ◆ marks a missed pass. The description and the
    panel tag say which.
  - **Bar description** (screen readers): ", hasn't started" / ", was missed", plus ", and 2 more items" when
    there are more.
  - **Selected pass panel:** the tag `▲ NOT STARTED` / `◆ MISSED` beside the state tag, then `+2`, which lists
    the others. The reason, links and Technical details go in its block.
- **A pass (bar, panel) with several open items** (api's question) shows one tag, chosen by Now's own order: priority first
  (P1 > P2 > P3), then the soonest due, then contact_start. So a not_started (P1) wins. A missed pass (P2, nothing
  due) yields to an approval or provider change that has a deadline, because that's the one still actionable. The
  other items show as a count beside it, `+2`, and all of them appear in the pass detail.

### U46 · Release gate: command window closed, and uplink dropped by the provider (domain's gate; lead's questions) (domain / api / fe-ops)
- **(a) Fix the read.** The console never shows commanding as possible when it isn't (U20). When the provider
  drops a pass's uplink leg, the pass and contact show it straight away, not after the next snapshot:
  - Tag `UPLINK DROPPED`: crit when command groups are queued for that pass, else caution (as U33's blocked).
  - Sentence in place of the command-window line: "Northlight dropped the uplink from this pass at 02:40Z, so
    commands can't be sent on it." Without a time, drop "at 02:40Z". Without the provider's name: "The provider
    dropped…".
  - Compose and Uplink don't offer the pass as a command window.
  - **Outside the pass** (director approved the read fix, 11-13): the command-window line reads from the pass
    times, not the snapshot. Before AOS: "Command window opens at AOS 03:10Z." After LOS: "Command window closed at
    LOS 03:19Z." While it's open: "Command window open until LOS 03:19Z."
- **(b) Refusal `command_window_closed`** (a named release), in the release outcome form:
  - outside_pass, before AOS: "Not released: the pass hasn't started (AOS 03:10Z)."
  - outside_pass, after LOS: "Not released: the pass has ended (LOS 03:19Z)."
  - uplink_leg_dropped: "Not released: Northlight dropped the uplink from this pass."
  - Unknown or missing reason: "Not released: the command window is closed."
  - Where the screen doesn't already name the pass, it follows "pass" as "the EARENDIL-312 · SVA 03:10Z pass".
    Times are §4.
- **Hand-started contacts** (director's decision, 11-13): armed groups never release into a contact that wasn't
  booked as a pass. An operator can release into one only by naming it.
  - Command-window line on such a contact: tag `NOT A BOOKED PASS` (caution) and "Armed commands don't go to this
    contact on their own. Release them here only if you mean to."
  - The named release confirms first (sheet, danger):
    - Title `Release into a contact that isn't a booked pass?`
    - Body: "EARENDIL-001's contact at SVA, started by Mira K. at 00:12Z, wasn't booked as a pass. Release 3
      command groups to it anyway?"
    - Actions `Release to this contact` (danger) and `Cancel` (the default focus).
    - Without the starter or time, drop that clause. Count the groups that would go.
  - Audit and the request log read "Released by Mira K. at 00:14Z into a contact that wasn't a booked pass."
  - Placement (lead): the line and the named release sit on Contacts' selected-pass panel and Uplink's contact
    view. fe-ops builds it after domain's gate, on an api endpoint. Domain: nothing live relies on releasing into
    unscheduled contacts, and there's no start-time confirmation or request opt-in.
- **Named release words** (fe-ops' drafts for a77cd4d40, ruled 11-13). The noun is **request**, as in the request
  log and CommandFlow; "command group" is the model's word. On Contacts, plain `Release` already cancels a booking,
  so these buttons name what they release.
  - The callout button is `Release commands…` (secondary; the sheet is the danger step). The sheet's body ends
    "Release 3 requests to it anyway?", and its action is `Release 3 requests` (danger), counted.
  - A hand-started contact reads "contact", not "pass", and has no AOS or LOS: "Not released: the contact ended at
    03:19Z." (without a time, "the contact has ended"), and "the contact hasn't started" if ever needed. A booked
    pass keeps (b)'s AOS/LOS forms.
  - Clauses after "Not released: " or "then stopped: ". Name the spacecraft where the screen has it (U25):
    - not_found: "the request wasn't found"
    - not_armed: "the request isn't queued for a contact"
    - not_target_spacecraft: "it has no uplinks for EARENDIL-001"
    - nothing_to_release: "its uplinks to EARENDIL-001 have already gone or ended"
    - not_next: "an earlier queued uplink to EARENDIL-001 has to go first" (no "lane")
    - earlier_command_failed: "an earlier uplink in it failed"
    - command_release_refused: "the uplink transport refused it"
    - release_basis_changed: "the configuration it was approved against has changed"
    - unknown: the server's message, without its final stop.
  - Outcome after the sheet: "Released 3 requests." when all go. Otherwise one line per request: "This request:
    Released 1 uplink, then stopped: an earlier uplink in it failed. 2 uplinks still queued." Other requests are
    named the way the request list names them. They read "Another request:" only when the console has no name.
  - Request log (its column has the time): "Mira K. released 2 uplinks into a contact that wasn't a booked pass ·
    then stopped: <clause> · 1 uplink still queued". For a booked pass: "Mira K. released 2 uplinks into the SVA
    03:10Z pass" (without a label, "into a booked pass"), not "by name". Audit keeps the sentence above, with the
    time.
  - Uplink C3: "SVA pass · Command window opens at AOS 03:10Z." sits above the pipeline, and a member's refusal sits
    under its target row.
  - Whole-request refusals: "Not released: the contact has ended." No access: "Operators with mission access can
    release commands."

### U47 · Now source `ingress_backpressure` (DECISIONS #83 follow-up; api-ops proposal) (api-ops / fe-ops)
Titles lead with the spacecraft and pass, as in U45. Say "buffer", not "journal", in visible text; the journal,
stream and error go in Technical details. The pass label is `SVB 03:10Z pass`; without one, `SVB contact`; without
a station, the spacecraft alone.
- **journal_near_full** (P1 at ≥ 95% or rising during a live pass, else P2):
  - Title `EARENDIL-008 · SVB 03:10Z pass · telemetry is backing up`.
  - Meta `BUFFER 87% · RISING · 412 MB WAITING`. Show RISING only while it is.
  - Body: "Cadence is storing this pass's telemetry more slowly than it arrives. At 100% Cadence stops reading, and
    new telemetry arrives late." At ≥ 95%, "The buffer is almost full." comes first, and the cause sentence stays.
  - Action `Open pass`. There's nothing to acknowledge.
  - Resolves itself: "Caught up at 03:22Z." The row fades.
- **frames_dropped** (P1 while live with a drop in the last 5 min, else P2):
  - Title `EARENDIL-008 · SVB 03:10Z pass · 12 telemetry frames lost` (singular: "1 telemetry frame lost").
  - Meta `12 FRAMES · 48 KB · 03:14Z–03:15Z`.
  - Body: "Cadence's buffer was full, so these frames from Northlight were dropped. Cadence can't recover them."
  - Actions `Acknowledge` (operate_mission, no reason, as U37's Mark as seen) and `Open pass`. Without the
    capability: "Operators acknowledge lost telemetry."
  - After that: "Acknowledged by Mira K. at 03:20Z." It resolves when the pass has also ended.
  - Acknowledged rows keep their place with `ACK MIRA K.` in the meta until the pass ends (U21).
- **Contacts:** the selected-pass panel gets a block for either conflict, with the same sentences, the buffer or
  drop figures, and Technical details (journal, stream, raw error), as U45's block. Now has no Technical details.
  - **Who to tell:** nobody is named. Cadence doesn't know a mission's escalation path, and the Now row itself is
    the notice (U20). If missions get an on-call setting, the body names it then.

### U48 · A template edit leaves decided days alone (domain's template-version fix; director confirmed 11-13) (domain / api / fe-setup)
A day an operator closed or canceled stays that way across a template edit. A day already planned or started keeps
its requirement, and no second one is added. Reopening a day is its own explicit action, never a side effect of an
edit. This replaces ContactPlanning's "an edit generates every remaining day afresh".
- **Edit preview count line** (api: `GET …/templates/:id/supersedes` gains `decided` {planned_or_started, closed,
  canceled}, each a list of `{occurrence_at, date, spacecraft_ids}`). A group's days are its distinct `date`s, and
  its requirements are the sum of its `spacecraft_ids` lengths. It's a
  neutral info line above the caution "supersedes N drafts" callout, which stays as it is:
  - "v3 applies to every day that's still open. 3 days already planned or started keep their requirement: 11-14,
    11-15, 11-16. 2 closed days stay closed: 11-12, 11-13. 1 canceled day stays canceled: 11-11." Each group is its
    own sentence (fe-setup).
  - "Keep their requirement", not "keep v2's": kept days can come from older versions, so no single version
    describes them (U20). `current_version` isn't needed for this line.
  - Not "from the next open day": planned and open days can alternate, so there's no single day it starts from.
  - Drop any group whose count is 0, and use singulars ("1 day … keeps its requirement"). When every group is 0,
    the first sentence stands alone. A new template has no dry run, so it shows no line.
  - **Dates:** with 3 days or fewer, list them after a colon (§4, `11-14`). Above 3, put the span right after the
    noun, using the first and last date, because the days needn't be consecutive: "5 days between 11-14 and 11-20,
    already planned or started, keep their requirement." / "4 closed days between 11-12 and 11-18 stay closed."
    Never at the end, where it reads as the requirement's window.
  - **Days or requirements:** when requirements equal days (one spacecraft), the noun is "days". Otherwise
    lead with requirements: "1,500 requirements on 3 days already planned or started keep their requirement…"
    becomes "1,500 requirements on 3 days, already planned or started, stay as they are: 11-14, 11-15, 11-16." The
    closed and canceled groups follow the same rule: "2 closed requirements on 1 day stay closed: 11-15." Above 3
    days: "1,500 requirements on 5 days between 11-14 and 11-20, already planned or started, stay as they are."
  - **Definitions** (domain 11-13):
    - **Planned:** a plan in pending_approval, approved, executing, partially_reserved or reserved holds the
      requirement. Booked passes come from those plans, so they're covered. A day with only a draft isn't
      planned: it's regenerated under the new version, and the drafts callout says so.
    - **Started:** the requirement's window has begun.
    - **Closed / canceled:** done by an operator. Requirements canceled by supersession, or by a spacecraft leaving
      the target, are regenerated and not counted.
- **Template-generated occurrence, Close/Cancel sheet ending:** "This is final for this day: the template won't
  bring it back, even when the template is edited. To plan 11-15 again, add a one-off requirement for it." Once a
  reopen action exists: "To plan it again, reopen it." **Timing** (fe-setup): today's sentence ("unless the
  template is edited") stays until domain's template-version fix is live, and switches in that fix's slot, because
  until then it's the true one.
- **Requirement rows:** template-generated rows show the version in Source (`Block 1 daily · v2`), from api's
  `template_version`. Without it, show the template name alone.

### U49 · Now source `archive_quarantine` (DECISIONS #88; domain's shape) (domain / api / fe-ops)
Some records from a pass couldn't be added to the archive. Their telemetry was still stored, so this is not lost
telemetry, and the words must not suggest it is. **P2, caution:** confirmed, never P1. Say "archive" and "raw
records", not "quarantine", "writer", "entries" or "index"; those go in Technical details. The pass label is
U47's (`SVB 03:10Z pass`, `SVB contact`, or the spacecraft alone).
- **Title:** `EARENDIL-008 · SVB 03:10Z pass · 12 frames and 40 packets couldn't be archived`. Drop a zero count,
  and use singulars ("1 frame couldn't be archived"). Without a contact or a spacecraft (id `none:…`), the count
  stands alone.
- **Meta:** `12 FRAMES · 40 PACKETS · 03:14Z–03:15Z`, from first_received_at–last_received_at (when the records
  arrived, §4; one time when they're equal). Add `STILL ARRIVING` while the pass is live and last_seen_at is within
  the last 5 minutes. As with U47's RISING, show it only while it's true.
- **Body:** the cause sentence, then what was stored, then the choice.
  - identity_conflict: "The archive already holds different records with the same identity, so these
    weren't added."
  - data_rejected: "The archive rejected their data, so these weren't added."
  - unknown (or a code the console doesn't know): "The archive couldn't take them."
  - Stored: "Their telemetry was still stored: 12 frames and 40 packets, without an archived copy of the raw
    records." With both stored counts 0: "None of their telemetry was stored."
  - Choice: "Retry once the cause is fixed, or discard them if they can't be archived."
  - The server's `error` is free text and goes in Technical details only, as do error_code and the item id. There's
    no entry count: operators read frames and packets.
- **Actions:** `Retry` (secondary) and `Discard…` (danger, sheet). Operators only; without the capability: "Operators
  retry or discard records that couldn't be archived."
  - Retry has no confirm, and it's synchronous (domain's final shape). When everything is archived, the row
    resolves. If some still fail, the row stays with the new counts, and the line comes from last_retry: "Retried
    by Mira K. at 03:20Z; the rest still couldn't be archived." If none were archived: "Retried by Mira K. at
    03:20Z; none could be archived yet."
  - Discard sheet: title `Discard 12 frames and 40 packets that couldn't be archived?`, body "They won't be
    archived, and Retry won't be offered for them again. Their stored telemetry stays." A reason is required. The
    action is `Discard` (danger). Put "The raw bytes may still be in the buffer or the ingest archive." in the
    sheet's Technical details: it's a "may", so it isn't promised in the body (U20).
- **Resolutions:** retried: "Archived on retry at 03:21Z." The row fades. discarded: "Discarded by Mira K. at 03:22Z:
  <reason>."
- **Contacts:** the selected-pass panel gets a block per item, with the same title, sentences, actions and Technical
  details, as for U45 and U47.
- **Build calls** (fe-ops f7d5f6384, accepted):
  - The Now row has `Retry` and `Discard…` side by side; the title link opens the pass. Row rule: at most two
    buttons, and `Open pass` takes a slot only when one is free (U47 keeps it next to Acknowledge).
  - The last-retry line goes last in the body, and `STILL ARRIVING` goes last in the meta.
  - The Contacts block drops the spacecraft and pass label from its title, because the panel is the pass:
    `12 frames and 40 packets couldn't be archived`.
  - With both counts 0, the title is `Raw records couldn't be archived`, and the sheet asks "Discard the raw records
    that couldn't be archived?". A blank reason shows "Give a reason first.".
- **Shape** (domain's final, 11-14): `last_retry {by, at}` and `resolution {kind, by, at, reason}` are both sent.
  The pass block needs `contact_id` / `provider_reservation_id`; with both null, the item is Now-only. There's no
  acknowledge.

### U50 · Now source `listener_refusal` (DECISIONS #87; domain's shape) (domain / api / fe-ops)
Cadence refused one or more connections on a listener that this pass shares with others, because it couldn't match
them to exactly one pass. **Never say "someone else's frames"** (U20): a refused connection may be this pass's own
data with an SCID or address Cadence didn't expect, and that's the case that matters most. Say "connection", not
"peer", "socket" or "acceptor"; those go in Technical details. The pass label is U47's.
- **Priority:** P2 caution while the pass is connected (`connected: true`). **P1** while it isn't and the window
  is open: then a refused connection may be this pass's own telemetry being turned away. due_at is LOS (api), so it
  sorts among due items by LOS.
- **Title:** `EARENDIL-008 · SVB 03:10Z pass · 3 connections refused` (singular: "1 connection refused").
- **Meta:** `FIRST 03:12Z · LAST 03:14Z` (raised_at, last_refused_at; one time when they're equal). Add `STILL
  REFUSING` last while last_refused_at is within 5 minutes, shown only while true (as U49's STILL ARRIVING). The connection's
  address isn't in visible text (api): it goes in Technical details.
- **Body:** first the context, then the last refusal's reason, then the pass's state.
  - Context, from `shared_with` (the other open passes on the profile): "This pass shares Northlight's listener with
    2 other open passes, and Cadence refuses any connection it can't match to exactly one of them." With none:
    "Cadence refuses any connection on Northlight's listener that it can't match to this pass." Without the
    provider's name: "the listener". It's never worded as this pass's fault: every open pass on the listener gets
    its own row for the same refusal (domain), and each row's priority follows its own pass's `connected`.
  - Reason, from last_refusal:
    - unregistered_scid: "The last one sent frames for SCID 42, which no pass on this listener expects." Without
      the scid: "…sent frames for a spacecraft no pass on this listener expects."
    - ambiguous_scid: "The last one sent frames for SCID 42, which more than one pass on this listener expects."
    - unexpected_peer: "The last one came from an address Northlight's profile doesn't expect."
    - unidentified: "Cadence couldn't tell from its first frames which spacecraft the last one was for."
    - read_failed: "Cadence couldn't read the last one's first frames."
    - unknown, or a code the console doesn't know: "Cadence couldn't match the last one to a pass."
  - Pass state: connected: "This pass has its own connection." Not connected: "This pass isn't connected yet. If a
    refused connection was meant for it, its telemetry isn't arriving." (Under that, for unregistered_scid or
    unexpected_peer only: "Check EARENDIL-008's SCID and Northlight's profile in Setup.")
- **Actions:** none from the server; `Open pass` takes the free slot (U49's row rule). There's nothing to
  acknowledge.
- **Resolutions:** accepted: "Connected at 03:16Z." ended: "The pass ended at LOS 03:19Z." (hand-started: "The
  contact ended at 03:19Z.", as U46). Both fade.
- **Technical details:** reason key, peer address, scid, the listen profile (provider_profile_name, then its id),
  ground_station_ref, refused_count and the id, plus "Counted live: a Cadence restart starts the count again." (in-memory counts, U20).
- **Contacts:** the selected-pass panel gets a block, as for U45, U47 and U49, with the title minus the spacecraft and
  pass label.
- **Second connection while connected** (api-ops' review, lead's call, 11-14). When the pass's own connection is
  up and receiving, a refused second connection to the same profile stays out of the item. It's counted only, and
  the count shows in the selected pass's own Technical details (the pass facts, from the pass row), as "Second
  connections refused: 2", whether or not a refusal block exists (fe-ops). It doesn't open a
  window, change the title or raise priority. **Exception:** if the pass's own connection has gone quiet (no frames
  for domain's threshold) when the second one is refused, it counts as a normal refusal and opens the item. A
  half-open old connection can block the provider's real reconnect, and that's telemetry being turned away.
  - **Quiet** (domain, 11-14): no ingested read for 30 s (a profile can override it) since the later of connect
    and the last read. Silence during our own backpressure (#83) doesn't count. An uplink-only connection has no
    reads to judge, so quiet doesn't apply to it, and a second connection there is counted only (domain may
    propose a write-side signal later).
  - A quiet own connection ranks the item **P1**, as not connected does (api): telemetry may be turned away while
    `connected` still reads true. The tone stays caution.
  - Reason second_connection: "The last one was a second connection for this pass, and Cadence keeps the first."
  - Pass-state sentence when quiet (in place of "This pass has its own connection."): "This pass's own connection
    has sent nothing since 03:14Z. If the refused connection was the provider reconnecting, its telemetry isn't
    arriving." It needs `own_quiet_since` (timestamp | null) on the item.
- **Build calls** (fe-ops a9dbf9813):
  - **Tone stays caution in both states** (changed). Priority isn't status: not connected raises it to P1, but
    nothing is known to be lost, so it's not crit (U20; as U45's not_started is P1 and still ▲). The
    not-connected sentence carries the weight.
  - The Setup line ends the body as plain text (accepted).
  - Without a provider, unexpected_peer reads "…an address the listen profile doesn't expect". Without an scid,
    ambiguous_scid reads "…for a spacecraft more than one pass on this listener expects." (accepted)
  - **ended without a booked flag:** "Ended at 03:19Z.", which is true for both kinds (changed; "LOS" is wrong for
    a hand-started contact, U46). With api's `booked` on the resolved entry, use "The pass ended at LOS 03:19Z." /
    "The contact ended at 03:19Z.".
  - Technical details order: reason, peer, scid, listen profile (name · id), station ref, count, id, then the
    "Counted live…" line (accepted).

### U51 · Per-target catalog revision and verifiers in Compose (director's backlog via lead, 11-14) (api / fe-ops)
On 11-14, 001 and 003 ran the same SET_MODE with different verifiers, and nothing showed it. Spec:
CommandFlow.md, C1 B "When targets differ".
- Group by the verifiers themselves; the revision explains the difference but isn't the test, because two
  revisions can share a verifier.
- The same verifiers everywhere means no change apart from the meta `rev 14 · 15`. Differing verifiers get a caution
  `VERIFIERS DIFFER` in the form header and on the stack chip, plus a grouped block of the verifier line, targets
  and revision. The same block appears in Approve, and U2 plots one panel per verifier point.
- Words: "Not every target checks this command the same way." The label is `rev 14`, as Compose's `Catalog rev`
  already reads.
- **Row text** (with api's shape, 11-14): when verifiers differ, each row lists its whole verifier set by name in
  order, then the longest wait: "Uplink started · Accepted on board · Mode applied · within 60 s". The single
  completion line would hide differences in other phases; tonight's two groups differ only by "Mode applied". So
  for 11-14: `Uplink started · Accepted on board · within 30 s` · `499 targets · rev 3` and `Uplink started ·
  Accepted on board · Mode applied · within 60 s` · `EARENDIL-001 · rev 4`. The single line stays when there's
  one group. Targets with a NO-GO for the command aren't in any group (api); their `revision unknown` shows with
  the NO-GO.
- **Data ask (api):** per stacked command, `verifier_groups: [{verifiers: [{name, phase, timeout_ms, …as today}],
  catalog_revisions: [{number, label}], spacecraft_ids}]`, grouped server-side by identical verifier definitions.
  Also per target, `catalog_revision {number, label}` for D's line. Preferably on the preflight response, so it
  re-runs with C1 and C2.
- Informational, not a GO/HOLD check. **No HOLD** (lead, 11-14): seeing it where targets are reviewed is enough,
  and a HOLD on every mixed-fleet request would become noise.

### U52 · Fleet start after the lookback fix: per-run cap and the 50,000 bound (domain / api / fe-setup)
Domain's fix generates a template's whole future horizon, so preview counts rise. The counts need no new words.
Two things must not stay silent (U20), because the preview has to say what Start will actually create.
- **Per-template cap: flag it**, as a caution line above Start that doesn't disable it, because the operator asked
  for more than this start generates. Start drafts one UTC day (there's no horizon control), so the cap stops at a
  time: "Block 1 daily stops at 12:00Z: it reached its limit of 8 occurrences per run, so its later occurrences on
  11-20 aren't generated by this start."
  - "Occurrences" is ContactPlanning's word for a template's generated days and slots.
  - Never "later runs generate the rest". The cap takes a template's earliest occurrences, and a repeat start
    regenerates the same ones (domain).
  - The cap stays as it is: it counts existing occurrences too, so a repeated start generates the same ones.
    Counting only new ones would make each repeat reach further, which surprises people.
  - Data (api, 11-14): on the setup read, `template_requirements_estimate.capped: [{template {id, name}, limit,
    last_at}]` (`[]` when none). It needs the timestamp `last_at` (domain's estimate has it), not just a date.
- **Over the 50,000 bound** (api's `422 fleet_planning_occurrence_limit_exceeded`, details `{count, limit}`). The
  count is gross fan-out: days that already exist count too, so it can read higher than what Start would create
  (domain). Say "counts toward the limit", never "would create".
  - With the count: "This start counts 62,400 template requirements toward the limit of 50,000, including days
    that already exist. Include fewer templates, or narrow their targets."
  - Without it: "This start goes over the limit of 50,000 template requirements. Include fewer templates, or narrow
    their targets."
  - There's no horizon control (api), so the advice never says "shorten the horizon".
  - **Beforehand** (domain: the estimate is cheap, one query per active template): the setup read carries
    `template_requirements_estimate {count, limit}` for the chosen day (`?day=`). Over the limit, Start is disabled, and
    the sentence above shows as a caution callout above it as the reason. At or under the limit, nothing shows:
    the number alone means nothing to an operator.
  - The 422 stays as the backstop and shows the same sentence in the same place (crit, since it was refused), never
    as a toast.

### U53 · Switching a platform-wide data-source binding (DECISIONS #90) (fe-setup / api-ops)
Only platform admins in admin mode can switch one. Elsewhere the row has no action, and a caption reads "Only
platform admins in admin mode can switch platform bindings." The binding name is mono throughout
(`default_flight_telemetry`).
- **Confirm sheet** (ApSheet, danger):
  - Title: `Switch default_flight_telemetry for 12 missions?`
  - Blast radius first: "This changes telemetry for all 12 missions that use it. They'll read from Northlight
    archive instead of Cadence managed store." (from and to are the targets' names; without them, drop the second
    sentence).
  - Live passes, when any: a crit line, "3 passes are live right now, and their telemetry switches mid-pass:
    EARENDIL-312 · SVA 03:10Z, EARENDIL-008 · SVB 03:12Z, EARENDIL-401 · KSAT 03:14Z." Up to 3, then "and 4 more".
    With none, the line is left out.
  - `Reason` (required, server-checked): help "Recorded with your name and the time." Blank: "Give a reason
    first."
  - `Type default_flight_telemetry to confirm` (mono input, exact match, case-sensitive; paste allowed).
  - Actions: `Switch for 12 missions` (danger), enabled once the reason and name are filled. `Cancel` takes the
    default focus.
  - **Counts unavailable:** if api-ops can't count missions or live passes, the sheet says "Cadence couldn't count
    the missions and live passes this affects, so it can't be switched now. Try again in a moment." and there's no
    Switch. The blast radius is never unknown at the moment of confirming.
  - Counts are re-read when the sheet opens. If they change while it's open (a pass goes live), the line updates
    and the typed name is cleared, so the operator confirms what they now see.
  - **At switch time** (api-ops' shape): the PUT sends the counts the operator saw. If the server's recount differs,
    the answer is `409 blast_radius_changed` with the new counts. The sheet then shows the caution line "This
    changed while you were confirming: it now affects 12 missions and 4 live passes." above the updated lines,
    and clears the typed name. Nothing is switched.
  - The outcome sentence uses the counts the server recorded, from the PUT's answer.
- **Outcome:** "Switched default_flight_telemetry to Northlight archive. 12 missions read from it now."
- **Build calls** (fe-setup, 11-14):
  - The list is the `Bindings` panel on Data sources, under Sources.
  - `History` is its own row button, opening a wide sheet (When · Who · What) with the audit line for switches and
    short lines for other kinds.
  - The blast line's noun is the logical source in words ("telemetry", "events").
  - One mission reads "the one mission that uses it" / "One mission reads from it now." (title: "…for 1 mission?").
  - The disabled Switch names the first missing field **in the sheet's own order**.
  - While the sheet is open, the blast radius is re-read on `data_sources` or `contacts` invalidations. The typed
    name is cleared only when a number actually changes.
- **Audit line** (actor and time in their columns): "Switched platform binding default_flight_telemetry from
  Cadence managed store to Northlight archive · 12 missions, 3 live passes: “<reason>”". It's recorded in two
  places: on the binding's own events (api-ops: `data_source_binding_events` with the reason, counts and names in
  its payload), shown in that binding's history; and in **Admin › Audit** (`GET /admin/audit`), the platform
  actions log, which api-ops adds binding switches to (lead, 11-14). The same line is used in both.
- **Mission binding list toggle:** a switch, `Show platform bindings (2)` with the count, off by default. Off: a
  `text-3` caption "Platform-wide bindings are hidden. They apply to every mission without its own binding." On:
  those rows show with a neutral mono tag `PLATFORM`.

### U54 · Now source `job_outcome_unknown` (api-ops; director and lead approved the behaviour) (api-ops / fe-ops)
Cadence stopped while a job that isn't safe to rerun was running, so nobody knows whether it finished. Say "outcome
unknown", never "failed" or "interrupted", which claim more than is known (U20). An operator checks, then retries
it or closes the item.
- **Per-type words** (api-ops' table): each type needs a **noun** for the title, a **place to check** and a
  **double-run consequence**. Examples:

  | type | noun | check | running it twice could… |
  | --- | --- | --- | --- |
  | booking | Booking at Northlight | with Northlight | book the pass twice |
  | provider cancel | Cancel at Northlight | with Northlight | send a second cancel |
  | TSDB write | Telemetry write to <store> | in <store> | write the same samples twice |
  | catalog import | Catalog import r15 | in Setup › Catalog | create a second revision |
  | evaluation | <evaluation name> | in its results | record the result twice |
  | backfill | Backfill 11-13 02:00Z–04:00Z | in the telemetry for that span | write the span twice |

  An unknown type uses the noun "A Cadence job", the place "where it acts" and the consequence "repeat what it
  did". **The real table is api-ops' (11-14), accepted with two edits:** limit evaluation is "<definition> limit
  check", like "<definition> evaluation"; spans are §4 ("Backfill 11-13 02:00Z–04:00Z"). The item carries
  `words {noun, check_place, consequence}`, and the console slots them in as-is.
  - **Names** (api-ops, 11-14): the run-based jobs don't carry names, so the nouns are bare for now: "Derived
    telemetry evaluation", "Limit check", "Backfill" / "Telemetry import", "Replay". The run id is in
    Technical details. **Follow-up, wanted:** the enqueue sites store the facts in the job args: the definition
    name when there's one, else the count, and the span's start and end. The words table then forms "Battery
    margin evaluation", "Derived telemetry evaluation of 3 definitions", "Battery voltage limit check", and
    "Backfill 11-13 02:00Z–04:00Z" (a stored span always has its date; across midnight, "11-13 23:00Z–11-14
    01:00Z"). Older jobs keep the bare noun. **Built** (api-ops 83f6f05b7): limit definitions have only a point
    id, so it's "EPS.batt_voltage limit check". The workflow kinds are backfill and import (not correction or
    replacement); an import reads "Telemetry import 11-13 02:00Z–04:00Z", because a bare "Import" doesn't say
    of what.
- **Title:** context, then the noun: "outcome unknown". For example `EARENDIL-312 · SVA 03:10Z pass · Booking at
  Northlight: outcome unknown`. With no pass, the noun alone: `Catalog import r15: outcome unknown`. U47's pass
  label.
- **Meta:** `STARTED 03:01Z · FOUND AT RESTART 03:09Z` (§4). Cadence doesn't record when it stopped, only the
  job's start and the restart that found it (api-ops); the real stop is somewhere between the two (U20).
- **Body:** "Cadence stopped while this was running, so it doesn't know whether it finished. It won't run it again
  by itself: running it twice could book the pass twice. Check with Northlight, then retry it or close this."
- **Priority:** P2 caution. P1 when the job's pass starts within 2 hours or is live, because an unknown booking near
  AOS can lose the pass.
- **Actions:** `Retry…` and `Close without retry…`. Operators only; otherwise "Operators decide what happens to
  jobs whose outcome is unknown." Both are audited with the actor, time, job and note.
  - **Retry sheet** (danger): title `Retry this job?` (fe-ops' option c: the noun is a title and can't take
    "the"), body first the noun as its own line ("Booking at Northlight"), then "Retry only if you've checked <place>
    that it didn't happen. If it did, retrying could <consequence>." A required checkbox: "I've checked <place>:
    it didn't happen." Note optional. `Retry` (danger) is enabled once the box is ticked;
    `Cancel` takes the default focus.
  - **Close sheet:** title `Close without retrying?`, body "Use this when you've checked that it finished, or when
    it shouldn't run again. Cadence leaves the job as it is." A required note, "What did you find?", for the audit.
    The action is `Close`.
- **Resolved lines:** "Retried by Mira K. at 03:20Z; it's queued." (the job's own new outcome shows where the job
  shows) /
  "Closed without retry by Mira K. at 03:22Z: “Northlight shows it booked.”"
- **Technical details:** job id, type key, worker, attempt, node, and the run or operation id.
- **Contacts:** a job tied to a pass gets a block on the selected pass, as U45–U50 do.

### U55 · Cancel or end a scheduled contact from Contacts (BACKLOG parity gap; after domain's window-truth fix) (api / fe-ops / domain)
The console gains 8g's two lifecycle actions on Contacts' selected pass. Both stop Cadence's side of the contact.
**Neither changes the provider's booking**: that's `Release` (Contacts D2), a separate act for org admins.
- **Which applies** (one action at a time, never both):
  - **Before AOS** (scheduled, not started): `Cancel contact…`. Domain's cancel: the contact won't open, so
    there's no listener and no runtime.
  - **While live:** `End contact now…`. Domain's close (end_realized_early): the runtime stops now, and the
    scheduled contact is marked done. "Close" is the model's word; operators end a contact.
  - After LOS, or already canceled or ended: neither. Hand-started contacts aren't pass rows, so they're out of
    this step (api's routes are per pass). Their `End contact now…`, in "contact" words (U46), waits for a BACKLOG
    item or Uplink's contact view, lead's call.
- **Sheet** (danger). The dismiss button is `Keep contact`, never `Cancel`, which would read as the action.
  - Cancel: title `Cancel EARENDIL-007's PUQ 13:04Z contact?` Consequence lines:
    - "Cadence won't open this contact: nothing is received or sent on it."
    - Booked: "Northlight's booking isn't changed. If you don't want the pass either, release it after this." (with
      a link to `Release` when the viewer may release; otherwise the sentence ends at "changed.")
    - Commands, when any are queued for it: "2 queued command requests wait for EARENDIL-007's next contact (KSAT
      15:40Z)." Without a next contact: "…wait for EARENDIL-007's next contact; none is scheduled yet."
  - End now: title `End EARENDIL-007's PUQ 13:04Z contact now?` Consequence lines:
    - "Cadence stops receiving and sending now. Telemetry from the rest of this pass won't be received."
    - Booked: "Northlight's booking isn't changed: the provider may keep flying the pass until LOS 13:12Z."
    - Commands: "Uplinks already sent stay sent. 2 queued requests wait for the next contact (KSAT 15:40Z)."
  - `Reason` (required): help "Recorded with your name and the time." Placeholder "e.g. Its booking failed, so
    there's nothing to listen to." Blank: "Give a reason first."
  - Actions: `Cancel contact` / `End contact now` (danger). `Keep contact` takes the default focus.
- **Outcome / history line** (Contacts' selected pass, and its Timeline event): "Canceled by Mira K. at 12:58Z:
  “Its booking failed.”" / "Ended early by Mira K. at 13:07Z: “…”". The Timeline reads "EARENDIL-007 · PUQ
  13:04Z contact canceled by Mira K.: “…”" (U29: actor and time together). The pass row's state tag becomes
  `CANCELED` (off) / `ENDED EARLY` (off).
- **Access:** operators (`operate_mission`). Otherwise there's no button, and the caption reads "Operators can
  cancel or end contacts."
- **Refusals** (api's codes, 11-14). Each also re-reads the pass, so the right button shows:
  - `contact_not_cancelable` with state active: "Not canceled: the contact started meanwhile. End it now instead."
  - `contact_not_cancelable` when ended or canceled: "Not canceled: the contact has already ended."
  - `contact_not_live` before AOS: "Not ended: the contact hasn't started. Cancel it instead."
  - `contact_not_live` after LOS: "Not ended: the contact has already ended."
  - `contact_not_live` with state canceled: "Not ended: the contact was canceled."
  - `no_scheduled_contact`: "Not canceled: this pass has no contact in Cadence."
  - `pass_not_found`: "Not canceled: the pass wasn't found."
  - Others: the server's message.
- **No record** (contacts ended before these actions were recorded: `cause` and `by` are null). The line says what's
  missing rather than guessing:
  - "Canceled at 12:58Z; who and why weren't recorded." / "Ended early at 13:07Z; who and why weren't recorded."
  - Without `at`: "Canceled; when, who and why weren't recorded."
  - The tags stay `CANCELED` / `ENDED EARLY`. The Timeline has no event for it.
- **History from the read:** `contact_ended {kind, by, at, reason, reason_code}`; Cadence's cancel is `by.kind:
  system` with `reason_code: provider_failed` (lead's change), and it uses U56's
  "Canceled by Cadence … Northlight couldn't book this pass (“…”)", and an operator's cancel uses the lines above.
  The org audit row reads "Canceled the PUQ 13:04Z contact for EARENDIL-007: “…”" (typographic quotes).
- **Confirmed (domain, 11-14):** neither action cancels queued command requests. The queue is per spacecraft, so
  they wait for the next releasable contact, armed groups stay armed, and a named release (U46) keeps what it
  already sent. One addition: when some will expire before that next contact, the commands line adds "1 of them
  expires at 14:00Z, before then." (one queued: "It expires at 14:00Z, before then."; several expiring: "2 of
  them expire before then, the first at 14:00Z.", fe-ops). Data (api): per pass, the queued
  count, how many expire before the next contact with the earliest expiry, and the next contact's station and
  AOS.

### U56 · Contact events `window_moved` and the `provider_failed` cancel reason (domain's window-truth fix) (domain / api / fe-ops)
- **window_moved** `{before, after, provider_change}`: an accepted provider timing shift moved the contact.
  - **Times:** a shift is often seconds, so these lines give HH:MM:SSZ (§4's minutes form would hide a 30 s move).
    The date is added when it isn't today.
  - **What moved**, from start_delta_s and end_delta_s. Durations: under a minute in s; above, min, or "1 min
    30 s". The direction is "later" or "earlier", never "+30 s".
    | change | history (pass panel) | timeline (api's mission-event sentence) |
    | --- | --- | --- |
    | both ends, same | "Northlight moved this pass 30 s later: now 12:11:27–12:19:27Z (was 12:10:57–12:18:57Z)." | "EARENDIL-003 · BRS 12:11Z pass moved 30 s later by Northlight: 12:11:27–12:19:27Z" |
    | start only | "Northlight moved this pass's AOS 30 s later: now 12:11:27–12:18:57Z (was …)." | "… pass AOS moved 30 s later by Northlight: 12:11:27–12:18:57Z" |
    | end only | "Northlight moved this pass's LOS 1 min later: now 13:04:30–13:13:30Z (was …)." | "EARENDIL-007 · PUQ 13:04Z pass LOS moved 1 min later by Northlight: 13:04:30–13:13:30Z" |
    | both, differently | "Northlight changed this pass's window: now … (was …)." | "… pass window changed by Northlight: …" |
  - The history line links `Open the change` to the provider change (U44, from provider_reservation_change_id),
    which says who accepted it. The timeline row links to the pass. Its label uses the new AOS. Stored sentences
    give the date when it differs from the event's own day (§4). The date appears once when both ends share it
    ("11-15 00:00:00–00:08:00Z"), and on both ends only across midnight ("11-14 23:58:00–11-15 00:06:00Z").
    Exactly 60 s reads "1 min" (fe-ops).
  - While live: the history line adds "Cadence now listens until 12:19:27Z." when the end moved.
  - Without the provider's name: "The provider moved…". A hand-started contact can't be moved by a provider, so
    there's no "contact" form.
- **provider_failed** (Cadence cancels a contact whose booking the provider couldn't make; the phantom fix):
  - History: "Canceled by Cadence at 12:58Z: Northlight couldn't book this pass (“no antenna available”)." The
    provider's reason is free text and goes in quotes; when it's a code, it's worded or left out, never raw.
    Without a reason: "…couldn't book this pass."
  - Timeline: "EARENDIL-007 · PUQ 13:04Z pass canceled by Cadence: Northlight couldn't book it". The tag is
    `CANCELED` (off), as for an operator's cancel (U55).
- **provider_canceled** (api's final shape: the reservation was canceled at the provider): history "Canceled by
  Cadence at 12:58Z: Northlight canceled this pass (“…”)."; timeline "…pass canceled by Cadence: Northlight
  canceled it". An unknown cause reads "Canceled by Cadence at 12:58Z." with nothing invented (U20).
- **provider_rejected** (domain 82104c735: the provider rejected the booking on attestation): history "Canceled by
  Cadence at 12:58Z: Northlight rejected the booking for this pass."; timeline "…pass canceled by Cadence:
  Northlight rejected its booking".
- **The provider's reason:** text and code come apart, never guessed from the string's shape. `provider_reason`
  is the provider's own text (quoted), and `provider_reason_code` is a code (worded or left out). Known codes:
  - delivery_descriptor_conflicts_with_transport → "(its delivery settings don't match the transport set up in
    Cadence)".
  - Unknown codes are left out, with the raw code in Technical details.
- A **running** contact whose booking is lost keeps running to LOS (director). That needs no new line; its pass shows
  the reservation's state as today.

### U57 · Now item: a booking the provider holds but Cadence's checks rejected (director; domain sends the fields) (domain / api / fe-ops)
The provider still holds the booking and will probably fly it, and Cadence keeps the contact and listens. But
Cadence's own validation found the booking inconsistent with its setup. Never say the pass is canceled or lost
(U20). Say "doesn't match", and name what was checked. The pass label is U47's.
- **Title:** `EARENDIL-007 · PUQ 13:04Z pass · Northlight's booking doesn't match Cadence's setup`.
- **Meta:** `FLAGGED 12:58Z` (§4).
- **Body:** "Northlight still holds this booking, but Cadence found a problem with it: <code words>. The pass is
  still on and Cadence will listen, but telemetry may not arrive as expected. Check EARENDIL-007's transport and
  data source in Setup, or the delivery settings with Northlight."
  - With the provider's own text too: "…: <code words> (Northlight: “…”)."
- **Code → words** (the same map as U56's reasons):
  - delivery_descriptor_conflicts_with_transport → "its delivery settings don't match the transport set up in
    Cadence"
  - unknown → "it doesn't pass Cadence's checks", with the raw code in Technical details.
- **Priority:** P2 caution. P1 when the pass starts within 2 hours or is live (U54's rule), because that's when
  telemetry is at stake.
- **Actions:** none from the server yet. `Open pass` takes the free slot (U49's row rule). There's nothing to
  acknowledge.
- **Resolutions** (domain names the triggers): the check passes again → "Matches Cadence's setup again at 13:01Z.";
  the pass ends → "The pass ended at LOS 13:12Z."; the provider drops the booking → U56's cancel line takes over.
- **Contacts:** a block on the selected pass, as U45–U50, with the title minus the spacecraft and pass label.
- **Technical details:** code, the provider's reason, provider_reservation_id, and the item id.
- **Data (domain, confirmed 11-14):** U47's pass fields; `code`; `source`; `provider_reason` (always null here: a
  Cadence-side check has no provider words, so the "(Northlight: …)" variant doesn't occur); `flagged_at`; and the
  resolution `{action: revalidated | ended | lost, at}`. All three triggers exist once window truth is live:
  revalidated by the next passing poll (b0efad061), ended at LOS, lost on the provider's own failure. `source`
  goes in Technical details. Built with the director's "delivery unverified" decision; if that changes what's
  claimed, the words change with it.

### U58 · Single-connection listener: refusals on an own listener, and the booking-time overlap flag (domain's proposal; lead) (domain / api / fe-ops)
Some station listeners take one connection at a time. When two passes overlap on one, the later pass is refused
until the earlier one lets go (11-14: 001 was refused for 26 s while 006 held Santiago :42105, and 30 frames were
lost). Say "takes one connection at a time" and name the pass that holds it. Keep "port", "acceptor" and "socket" in
Technical details.
- **(a) listener_refusal on an own listener** (`shared_with: []`, cause: another contact holds it). This is U50's
  item; only the context, state and resolution sentences change:
  - Title as U50: `EARENDIL-001 · SNTG 00:13Z pass · 3 connections refused`.
  - Meta: `FIRST 00:13:54Z · LAST 00:14:12Z · HELD BY EARENDIL-006` (+ STILL REFUSING while true).
  - Context: "Santiago's listener takes one connection at a time, and EARENDIL-006's SNTG 00:05Z pass held it, so
    Cadence refused this pass's connection."
  - Not connected (P1, U50): "This pass isn't connected yet, so its telemetry isn't arriving. It can connect when
    EARENDIL-006's pass lets go of the listener, at its LOS 00:14:15Z." Without the holder's LOS: "…when
    EARENDIL-006's pass lets go of the listener."
  - Loss, only when counted (U20): "30 telemetry frames were lost before it connected." Not counted: "Telemetry
    sent before it connected wasn't received."
  - Resolutions: accepted: "Connected at 00:14:20Z, 26 s after AOS. Telemetry from before that wasn't received."
    (or "…30 telemetry frames were lost before that." when counted). ended: "The pass ended at LOS 00:21:15Z
    without connecting."
  - Contacts block as U50, titled `3 connections refused`, with the same sentences.
  - Technical details: listener (station · port), the holder's realized_contact_id, reason key, count, item id.
  - **One item, not two** (domain, provisional): a pass that couldn't START because its listener was held is
    U45's contact_start `listener_in_use` ("…because the EARENDIL-006 · SNTG 00:05Z pass was still holding it."),
    and listener_refusal raises nothing for it. A RUNNING pass whose connection was refused is this item. Domain
    confirms after tracing 001's 00:05Z case, which showed nothing in Now.
- **(b) Booking-time overlap flag** (on the plan's passes, Book a pass offers, and the booked pass on Contacts):
  - Tag `LISTENER OVERLAP` (caution ▲) on the **later** pass, the one that loses time.
  - Sentence on the later pass: "Overlaps EARENDIL-006's SNTG 00:05Z pass by 26 s. Santiago's listener takes one
    connection at a time, so this pass loses its first 26 s."
  - On the earlier pass, no tag, only a `text-3` note: "EARENDIL-001's SNTG 00:13Z pass overlaps this one by 26 s
    and loses its start."
  - A Book a pass offer carries the sentence before booking, and booking is still allowed. On the plan's Gantt,
    the later pass gets U45's ▲ ("Needs attention" in the legend).
  - **Refuse variant (uplink), only if the director picks it:** the offer can't be booked. Disabled reason: "Can't
    book: it overlaps EARENDIL-006's uplink on Santiago by 26 s, and Santiago's uplink takes one connection at a
    time." The plan doesn't draft it; its unplanned-row cause reads "Santiago's uplink is taken by EARENDIL-006
    then." A booking refusal reads "Not booked: it overlaps EARENDIL-006's uplink on Santiago by 26 s."
- **Data asks (domain → api):**
  - (a): `holder {realized_contact_id, spacecraft name, station code, starts_at, ends_at}`, plus
    `frames_lost` (int | null) only when it's really counted.
  - (b): per pass `listener_overlap {with {spacecraft name, station code, starts_at}, seconds, loses: this |
    other, direction}`.

### U59 · Command groups in the organization audit (api's proposal; lead and director decide scope) (api / fe-setup)
One entry per decision, not per member. The verbs match the request log (groups/words.ts) and U46, so the audit and
the log say the same thing. `<label>` is "SET_MODE and 2 more for 12 spacecraft" (the first command, "and N more",
then the target count). The reason column takes the note or reason.
- submitted: "Submitted <label>". It adds " · needs a second GO" and " · 3 spacecraft have their own values" when
  they apply. Resent: "Resent <label> (sent back at 13:02Z: “Safe mode recovery”)". The parenthesis gives the
  original's send-back time, plus its title when the operator gave one. There are no request numbers in the
  product, so never "REQ-…" (U25).
- approved: "Gave GO on <label>"; with exclusions: "Gave GO on <label>, excluding 2 spacecraft".
- rejected: "Gave NO-GO on <label>"; sent_back: "Sent back <label>".
- aborted: "Aborted <label>: 40 uplinks canceled, 8 already sent". Its member cancels fold into this entry.
- released_on_contact (U46): "Released 2 uplinks of <label> into the SVL 14:05Z pass"; unbooked: "…into a contact
  that wasn't a booked pass (SVL 14:05Z)". If it stopped: "· then stopped, 1 uplink still queued".
- hold_acknowledged: "Acknowledged the <check label> HOLD on <label>" (checkLabel words, never the key).
- Single requests: keep Requested / Approved / Rejected, and add "Canceled <request>" from metadata.cancellation.
- **Notes aren't audit entries.** They're comments, and they stay in the request log and Timeline. The audit
  records decisions.
- **System cancels** (director: in, folded per group, actor Cadence with the SERVICE tag, reason given):
  - Standalone request: "Canceled SET_MODE on EARENDIL-004: it expired before release".
  - Group, folded per reason: "Canceled 12 uplinks of <label>: they expired before release" / "…: what they were
    approved against changed" / "…: the catalog changed" / "…: EARENDIL-004 was archived" (several: "…: 3 of its
    spacecraft were archived").
  - commanding_disabled (L22: a change set turned commanding off): group "…: commanding was turned off for
    EARENDIL-004" (several: "…for 3 of its spacecraft"); single request "Canceled SET_MODE on EARENDIL-004:
    commanding was turned off for it".
  - An unknown reason: "Canceled 12 uplinks of <label>." with nothing invented.
- **An operator cancels one member** (member_canceled, reason beside it): "Canceled SET_MODE on EARENDIL-004 from
  <label>".
  - Mixed reasons in one fold make one entry per reason, never one line that blurs them.
- The target kind `command_group` links to the group's page. Per-target values aren't separate rows; the
  submitted line's count points there.

### U60 · What the Timeline says about sources catching up (domain's storage-growth part 2, item 3) (domain / api)
An advance on every storage write isn't news, and "Data sources caught up" once a second is noise. The Timeline
shows **changes of state**. Every advance stays in the watermark table (part 3) as evidence, and the operational
event is emitted only for these:
- **Once per contact, at settle:** "EARENDIL-008 · SVB 03:10Z pass: telemetry stored through 03:19:40Z (LOS
  03:19:57Z)". It tells the operator the pass's data reached the store, and how close to LOS. It's emitted only
  when the contact had any advance.
- **Caught up after falling behind** (the source was ≥ 60 s behind, domain's threshold): "Telemetry from
  EARENDIL-008 caught up at 03:22Z after falling 2 min behind." This matches U47's "Caught up at 03:22Z."
- **Moved back** (a retreat: replay or correction): "EARENDIL-008's stored telemetry moved back to 03:12Z." With
  a replay run: "…moved back to 03:12Z for a replay."
- Not per N minutes: a heartbeat on the Timeline is still noise.
- Falling behind itself is U47's Now item (ingress backpressure), not a Timeline line.
- Fold labels: `Telemetry stored` (settled), `Telemetry caught up` (caught_up), `Telemetry moved back` (retreated,
  which has no label of its own today). Old `advanced` rows keep "Data sources caught up".
- **Kinds and placement** (api, 11-15): each case gets its own kind (source_watermark_settled /
  source_watermark_caught_up / the existing source_watermark_retreated). Old `advanced` rows keep their sentence
  until they age out. All three stay in the Timeline's **data** category (opt-in): one settle line per pass for
  every spacecraft would swamp the default view. The settle line also shows **always on the pass itself**
  (Contacts' selected-pass history), where it answers "did this pass's data get stored?". The EventBus fact keeps
  firing on every advance (live charts depend on it); only the operational_events row is coalesced.

### U61 · Now item: a day whose first contact window approaches without an approved plan (lead; 11-16 had no bookings) (api / domain / fe-ops)
11-16's plan sat in pending_approval from 11-11, and nothing was booked. Say plainly that **nothing is booked**,
name who it waits on, and let the countdown raise the priority. One item per UTC day.
- **Titles, by the day's plan state** (the newest plan for that day):
  - pending approval: `Plan for 11-16 is awaiting approval`
  - sent back: `Plan for 11-16 was sent back`
  - only a draft: `Plan for 11-16 is still a draft`
  - none: `11-16 has no plan yet`
- **Meta:** `FIRST WINDOW 00:00Z · T−6h · 1,512 REQUIREMENTS` (§4, with the date when it isn't today; the T− is
  live).
- **Body:** the state sentence, then the consequence, then whatever's waiting:
  - pending: "R41 has waited for approval since 11-11 22:10Z. Nothing is booked for 11-16's 1,512 requirements until
    it's approved. Waiting on an org admin: Ana R. or Owen P." (approvers named when the policy lists them; never
    the author, U-rule reviewer ≠ author).
  - sent back: "Ana R. sent R41 back at 11-12 09:40Z: “Too many KSAT passes.” Nothing is booked for 11-16's 1,512
    requirements until a new plan is approved."
  - draft: "R43 (Mira K.) hasn't been submitted. Nothing is booked for 11-16's 1,512 requirements until a plan is
    approved."
  - none: "Nothing is planned or booked for 11-16's 1,512 requirements."
- **Action**, one:
  - pending, for an approver who isn't the author: `Review`, to the plan's decision.
  - pending, for anyone else: `Open plan`. The author also gets "You can't approve your own plan."
  - sent back or draft: `Open plan`.
  - none: `Plan 11-16` (Contacts › Plan for that day).
  - There's nothing to acknowledge: the only way the item goes is by the day getting a plan.
- **Priority and status** (due_at = the first window):
  - Raised at T−24h as P2, caution.
  - P1 from T−6h.
  - Once the first window opens with no approved plan, the title becomes `11-16 started with no approved plan` with
    crit ◆: windows are passing unbooked. It stays P1 until the day ends or a plan is approved.
  - N (24h and 6h) is policy-tunable later. Domain proposes defaults if they differ.
- **Resolutions:**
  - "Approved by Ana R. at 18:02Z." The row fades; booking then shows on Contacts.
  - "Nothing is left to plan for 11-16." (every requirement closed or canceled).
  - The day ended: "11-16 ended with no approved plan." (crit, kept in recently resolved). When it ended stalled:
    "11-16 ended with R41 approved but not booked." or "11-16 ended with 12 of 41 passes booked."
  - `booking_started` (domain; no actor, since nobody did it): "Booking started at 22:11Z." From an interrupted
    item: "Booking continued at 22:20Z." 
- **Data:** day, first_window_at, requirements_count, `plan {id, revision, state, author, submitted_at,
  sent_back {by, at, comment}} | null`, `approvers [{name}]`, `viewer_can_approve`. Domain's source is
  `plan_coverage` (47aabe3ba), one per day from today to +2.
- **At crit** (domain: a pending plan lapses at its first selected pass, and mid-day only a new plan for the rest of
  the day can book). The action is `Plan the rest of 11-16`, never `Review`. Body: "11-16's first window opened at
  00:00Z and nothing is booked. R41 can't be approved now; a new plan for the rest of the day can still book its
  1,104 open requirements."
- **Lifecycle words** (domain's proposal, director's ruling):
  - A superseded plan's state line: "Superseded by R44 (Mira K.) at 10:05Z."
  - Refusal `contact_plan_day_already_planned`: "Not approved: R39 (approved) already covers 212 of these
    requirements for 11-16. Open R39, or send this plan back." The state word is approved / booking / booked.
  - Approving a superseded plan: "Not approved: R44 replaced this plan at 10:05Z." with `Open R44`.
  - All expired: "Not approved: the booking window has closed for all 36 of its passes, so nothing could be booked."
    with `Plan the rest of 11-16`. (#273: the rule is the provider's booking window, which can close before AOS, so
    never "already started", U20; U97 has the rest.)
  - Partial approval: "Approved. Booking 1,476 passes; 36 weren't booked because their booking window had closed."
    The left-out passes are listed under `Show 36`, with spacecraft, station and AOS.
  - **A new draft on a day whose plan is pending** (domain's supersede-on-draft):
    - K1's action is `Draft a new plan…` before the day starts, and `Plan the rest of 11-16…` once it has started.
      It's secondary; for approvers, the primary stays `Review`.
    - The confirm sheet is caution, because the pending plan can't be approved afterwards. Title `Draft a new plan
      for 11-16?`. Body "R41 (Mira K., sent for approval 11-11 22:10Z) is waiting for approval. A new draft
      replaces it: R41 can't be approved after this." Once the day has started, it adds "The new plan covers the
      rest of 11-16, from 13:40Z."
    - Actions `Draft a new plan` / `Plan the rest of 11-16`, with `Keep R41` as the default focus.
    - With only a draft (nothing pending): no confirm, because drafts are already superseded by a new one, as
      today.
  - Under "Needs a second person's approval" (governance `independent`):
    - An admin's Submit answers "Sent for approval. This mission needs a second person's approval, so another org
      admin approves it: Ana R. or Owen P." The plan then reads `AWAITING APPROVAL` (no auto-approve).
    - Refusal `contact_plan_self_approval_forbidden`: "Not approved: you submitted this plan, so another org admin
      has to approve it." There's no Approve button for the submitter in the first place. This is the backstop.

- **Approved but not booking** (domain 11-16: nothing runs or watches booking after approval). A day counts as
  covered only when its newest plan's **derived** state is `executing` or later. `approved` and `interrupted`
  don't cover, so a stalled run reopens the item.
  - **Approved, not started**, shown only after a 2-minute grace from `approved_at`:
    - Title: `Plan for 11-16 is approved but booking hasn't started`.
    - Body: "R41 was approved at 22:10Z, but booking hasn't started. Nothing is booked for 11-16's 1,512
      requirements until it does."
    - Action: `Start booking`.
  - **Interrupted:**
    - Title: `Booking for 11-16 stopped`.
    - Body: "Booking for R41 stopped with 12 of 41 passes booked; its last progress was at 22:14Z. The other 29
      aren't booked until it continues." The time is `booking.last_progress_at`: the last progress seen, not the
      moment it stopped, so it's never worded as "stopped at" (U20).
    - Action: `Continue booking`. With nothing booked yet: "Booking for R41 stopped before any pass was booked; its
      last progress was at 22:14Z."
  - Both actions call POST `/execute`, which is idempotent per pass. Someone who can't book gets `Open plan`
    instead.
  - Priority and marks follow the thresholds above.
  - **The action names its scope** (#268, fe-ops / api / domain, PR #356). The count is the server's
    `booking.bookable` (passes not yet booked, requesting included), never counted in the console:
    - Approved, not started: `Book 40 passes` (`Book 1 pass`).
    - Interrupted: `Book the other 29`.
    - Shown only when `viewer_can_book` is true; anyone else keeps `Open plan`.
  - **Nothing left to book** (every remaining pass's booking window has closed): no Book. The line stands in for
    it: "The booking window has closed for all 40 of R41's remaining passes, so nothing can be booked." (one pass:
    "…for R41's only remaining pass, …"; no count readable: "…for all of R41's remaining passes, …"). The button
    is K1's: `Draft a new plan for 11-16…` before the day starts, `Plan the rest of 11-16…` once it has. Never
    "already started" (#273, U20).
  - **The day has ended** (`409 contact_plan_day_ended {day}`; execute starts nothing): "Not booked: 11-16 has
    ended, so R41 can't be booked any more." It is a refusal, so it is announced (role=alert, a11y B6). That's
    the target: today a Now command result goes into the row sentence, which has no role. fe-ops builds it in the
    first #243 PR.

### U62 · Time range track interaction (ApTimeRange's RangeTrack; a user bug via the director) (dashboards builds / lead)
Used by the telemetry plot, the Timeline, the dashboard range, Book a pass and the kit. dashboards' base behaviour
stands: a handle moves one end; minimum 1 min and start < end; From/To update live and commit on release; Esc
cancels; dragging on the empty track draws a new range; handles are focusable with arrow nudges. Decisions:
- **(a) Dragging the band's body moves the whole window** and keeps its length (cursor `grab` / `grabbing`). The body
  is the band minus the handles' hit areas. The band is also a tab stop: ←/→ pan it by the step in (c).
- **(b) Handles:** a 2px `readout` bar the full track height, with a 12×20px grip (two `text-3` hairlines) at the
  middle.
  - Hit area: 24px wide with a fine pointer, 44px with `pointer: coarse` (390 and touch). It's centred on the bar,
    may overhang the track, and never steals the body's area below 16px of band width (handles then sit outside the
    band's ends).
  - Hover: the grip in `raised`. Dragging: the bar and grip in `bright`. Focus: §6's ring around the grip. No
    status colour.
  - `role="slider"` with `aria-valuetext` "From 11-14 03:10Z" / "To 11-14 04:40Z".
- **(c) Arrow steps depend on the zoom:** the step is the "nice" unit nearest 1/100 of the visible track span (1, 5,
  15 or 30 min, 1, 6 or 12 h, 1 d), never under 1 min. Shift (and PageUp/PageDown) is the next nice unit ×10 up.
  Home/End go to the track's bounds. Dragging snaps to whole minutes.
- **(d) During a drag**, From/To show the previewed values in `text-2` with a `readout` field border, marking them
  "pending". A small mono tooltip above the active handle shows its time, which matters at 390, where the fields
  may be off screen. On release the fields return to normal (committed) and a polite live region says "Range 11-14
  03:10Z–04:40Z". Esc restores the old values everywhere.
- **Click without a drag** (under 4px of movement) on the empty track does nothing: it never resets the range.
- **A live range** (`now−6h`): dragging the end handle back to the track's now-edge keeps the range live. Any other
  drag, or a body move, makes it absolute, and the picker then shows the absolute range (as a snapshot freezes one,
  Dashboards Q5).
- **Cursors:** `ew-resize` on handles, `grab`/`grabbing` on the body, `crosshair` on the empty track.
- **Future spans** (Book a pass): the track's span is `now … now+48 h`, and a handle can't go before now. The tick
  labels are relative to now: "Now · +12h · +24h · +36h · +48h", where a past span reads "−24h … Now".
- Nothing here needs the user.

### U63 · Preview hold `telemetry_app_not_installed` (domain's change-set parity, db20d6bb8) (domain / api / fe-setup)
Blocking. The item shape is telemetry_packet_inputs_required's. Name the spacecraft (U25: full names, never "-313").
- One: "Telemetry can't be turned on for EARENDIL-312: the telemetry app isn't installed on it. Install the app in
  Setup › Apps first."
- Several (up to 3 named): "Telemetry can't be turned on for EARENDIL-312, EARENDIL-313 and EARENDIL-314: the
  telemetry app isn't installed on them. Install the app in Setup › Apps first." Above 3: "…for 12 spacecraft…",
  with the names under `Show`.
- The link `Open Setup › Apps` goes to `M/setup/apps/<telemetry app key>`, the app's own page, where install
  happens. If the app has a display name, it replaces "the telemetry app" ("the Telemetry decom app isn't
  installed").
- Check label (the HOLD row's word): `Telemetry app not installed`. That's the console's title for the reason: the
  server keeps every hold in the `compatibility` check, as one item for all affected spacecraft (domain e587668da).
  The link uses `details.app_key` and the name `details.app_name`.
- **Apply-time refusals** (the backstop when the preview didn't catch it; api words them, never a generic
  failure):
  - `telemetry_app_not_installed`: "Not applied: the telemetry app isn't installed on EARENDIL-312. Install the app
    in Setup › Apps first."
  - `telemetry_packet_inputs_required`: "Not applied: telemetry can't be turned on for EARENDIL-312 until its
    packet inputs are set up."
  - Both follow the same naming rule for several spacecraft.

### U64 · Limits and derived telemetry through change sets (DECISIONS #93; ADR-020 phase 3; the user adopted ux's four conditions) (domain / api / fe-setup / fe-ops)
No screen work until phase 3. These are the editors' spec then:
1. **In-pass relief stays outside change sets.** Acknowledging and shelving an alarm deal with a nuisance limit;
   relief never needs a limit edit.
2. **One step under "Applies without approval":** the editor offers `Apply now` (stage and apply in one, with the
   preview inline: HOLDs such as U43's limit_alarm_active, and derived points that depend on it). There's no trip
   to Setup › Changes. Under "Needs a second person's approval", the step is `Stage change`, as for any set.
3. **An unrelated set in review never freezes limit or derived edits.** They need their own set, or immunity from
   another set's freeze. Domain settles which before phase 0 work reaches them.
4. **Editors show live and staged values side by side**, and who has a path staged (path_already_staged).
- When this ships, the governance help in SettingsAuditProviders.md loses its carve-out ("App settings that save
  immediately, such as limits, aren't covered."), and fe-setup changes the server copy with devops (the
  legacy-host contract rule).

### U65 · Catalog revision approval (domain's model approval gate, 742567770) (domain / api / fe-setup)
Operators know catalog revisions; the mission model revision is the compiled form behind one. Visible text says
"catalog rev 4", and the mission model revision id goes in Technical details.
- **Where:** a revision's row in Setup › Catalog carries `NEEDS APPROVAL` (caution) / `APPROVED` / `REJECTED`. The
  revision's page gets an **Approval** panel above C1 (Diff) while its model needs approval.
- **Approval panel, the comparison report against the revision it would replace:**
  - Verdict line: `■ Comparison passed against rev 3` / `◆ Comparison didn't pass against rev 3`, with the failing
    parts listed.
  - **Replay** (the director's condition): when `replay.status = not_run`, a caution callout **at the top of the
    panel**: "Replay: not run. There's no qualification corpus, so this revision hasn't been replayed against
    recorded telemetry." It's never folded away and never shown as passed.
  - Importer: "Imported by Mira K. at 11-14 22:10Z." Not recorded: `▲ Importer not recorded`, plus "Cadence doesn't
    know who imported this revision." (U20).
  - Runtime plans: `Ready` / `▲ Not ready yet`.
  - replay not_required (low-risk changes skip it, and the report passes): a neutral line, "Replay: not needed for
    a low-risk change." No callout, never shown as passed. The audit reads "(comparison passed against rev 3;
    replay not needed)".
  - Decision (ApDecision): `Approve rev 4` (primary) and `Reject…` (secondary, with a confirm). The importer, under
    "Needs a second person's approval", sees "You imported this revision, so another org admin has to approve
    it." and no buttons.
- **Panel title:** `Approval · catalog rev 4`, with the meta `AGAINST REV 3`.
- **No report yet:** "No comparison has been run for rev 4 yet." plus `Run comparison` (primary). Approve is
  disabled with the reason "Run the comparison first."
- **Reject confirm** (caution): title `Reject catalog rev 4?`, body "Spacecraft can't move to rev 4 after this. To
  try again, import a new revision." A required `Reason` (domain: reject takes one; blank → "Give a reason
  first."). Actions `Reject rev 4` / `Cancel` (default). Approve has no confirm: the decision panel is the confirm.
- **Report body** (api's merged wire): a neutral tag `RISK LOW` / `RISK MEDIUM`, or `▲ RISK HIGH` (caution) for high.
  Then one line per section, "Commands: 3 added · 1 changed · 0 removed" (zero parts dropped). "Failing parts" are
  the replay's failed cases, by name and reason, under the verdict.
- **Section kinds in words** (api's known vocabulary; an unknown kind reads its key with spaces):
  - command → Commands; command_argument → Command arguments; command_argument_type → Argument types;
    command_encoding → Command encodings; command_constraint → Command constraints; command_verifier → Command
    verifiers.
  - parameter → Telemetry points; parameter_type → Point types; container → Containers; calibrator → Calibrators;
    algorithm → Algorithms; monitoring_policy → Monitoring policies.
  - stream → Streams; service → Services; extension → Extensions; unit → Units; space_system → Space systems.
- **Audit** (org audit, kind config): "Approved catalog rev 4 (comparison passed against rev 3; replay not run)" /
  "Rejected catalog rev 4", with the reason in the reason column. Never "mission model", as on the screen.
- A blank reject reason reads "Give a reason first." (not "Enter a reason"). Too long (api's
  mission_model_decision_reason_too_long): "Keep the reason under 2,000 characters." The field shows a counter
  from 1,800 characters, so it's rarely hit.
- **Decided:** the panel collapses to one line with the report behind `Show report`: "Approved by Ana R. at 11-15
  09:12Z." / "Rejected by Ana R. at 11-15 09:12Z: “Wrong FSW build.”" The row tag follows.
- **Nothing to approve:** no panel, and no tag on the row. The index adds nothing.
- **Owner:** fe-ops builds the console side (fe-ops, 11-15).
- **Approve refusals:**
  - self_approval_forbidden: "Not approved: you imported this revision, so another org admin has to approve it."
  - comparison_not_passed: "Not approved: the comparison with rev 3 didn't pass."
  - comparison_mismatch: "Not approved: the comparison is out of date. Run it again." (`Run comparison`)
  - runtime_plans_not_ready: "Not approved: Cadence is still preparing this revision. Try again in a moment."
  - revision_not_approvable: "Not approved: this revision was already approved, rejected or replaced." (or the
    state, when it's sent)
  - human_approver_required: "Not approved: a person has to approve this, not a service identity."
- **Preview hold** `mission_model_not_approved` (blocking; check title `Catalog revision not approved`): "Catalog
  rev 4 isn't approved yet, so 499 spacecraft can't move to it. An org admin approves it in Setup › Catalog
  first." The link `Open rev 4` goes to the Approval panel.
- **Apply refusals:** not_approved: "Not applied: catalog rev 4 isn't approved yet." comparison_failed: "Not
  applied: catalog rev 4's comparison didn't pass." with `Open the report`.

### U66 · Telemetry buffer: the disk filling up, and one pass's buffer full (lead; api-ops read the code) (api-ops / api / fe-ops)
The buffer has a cap **per pass** (per stream), and all of them share **one disk**. Two cases:
- **One pass's buffer full:** only that pass refuses telemetry. That's U47 (ingress_backpressure), not a new item.
  At 100%, U47's journal_near_full title becomes `EARENDIL-008 · SVB 03:10Z pass · buffer full: telemetry refused`,
  and its body leads with "Cadence is refusing this pass's telemetry until storage catches up." Refused frames,
  when counted, are U47's frames_dropped ("12 telemetry frames lost").
- **The disk filling (this item, one per deployment as seen by each mission):** when it's full, every pass stops at
  once. Visible text says "buffer disk". The volume path goes in Technical details.
  - Thresholds: raised at 70% (caution, P2); crit and P1 at 90%; cleared below 60%.
  - Titles: `Telemetry buffer disk 72% full` / `Telemetry buffer disk 91% full: at 100% all telemetry stops` /
    `Telemetry buffer disk full: Cadence is refusing telemetry from every pass`.
  - Meta: `31 GB OF 43 GB · +1.8 GB/H · FULL IN ~6 H` (the growth only while growing; shrinking: `DRAINING`).
  - Body (api-ops' code read: most of it is already stored and kept 72 h for review): "Cadence keeps each pass's
    received telemetry on this disk, until it's stored and then for 72 h for review. When the disk is full,
    Cadence stops accepting telemetry from every pass at once."
  - Holders: this mission's own, largest first, up to 3, as links, each with its state: "EARENDIL-008 · SVB 03:10Z
    pass: 800 MB still being stored", "EARENDIL-003 · KSAT 02:40Z pass: 1.2 GB, kept until 11-16 02:48Z". Then "and
    4 more of this mission's passes", then "and 2.1 GB from other missions" (never named: tenancy).
  - "It frees up as passes reach 72 h after they end. A pass still being stored holds its share longer."
  - Full: "Telemetry arriving now is refused and isn't kept. It can't be recovered." (only when refusing).
  - Actions: only `Open pass` on the holders (api-ops: no catch-up or reclaim trigger exists). The disk size, the
    per-pass cap and the 72 h are deployment config. Caption: "Operators can open what's holding it. The buffer's
    size is set where Cadence is deployed."
  - "Refusing" shows only when appends are actually failing for lack of space. api-ops confirms refused_since.
  - Resolutions: "Back under 60% at 03:30Z." After a full spell: "Telemetry was refused from 03:21Z to 03:24Z."
  - Data (api-ops, confirmed 11-15): percent, used_bytes, size_bytes, rate_bytes_per_hour (signed), eta_full_s,
    holders [{realized_contact_id, label, bytes, state: storing | kept, kept_until}] (this mission's own, up to 3),
    more_count, other_missions_bytes, refusing, refused_since. Without `kept_until`, a kept holder reads "…: 1.2
    GB, kept for review".
  - **Early removal** (once the director doesn't object; api-ops builds it with this item): the drain line adds
    "Above 80%, Cadence removes review copies of passes already stored, oldest first." A resolution after removals
    adds "Freed by removing review copies of 6 stored passes." The kept holders are the first to go.

### U67 · Incomplete data at the end of a pass (director; api's incomplete_at_end_bytes) (api / fe-ops)
Shown only when > 0, in the contact's settlement view as a data-quality note: `text-3`, no mark, no status colour.
A stream that stops mid-frame is normal. It never goes to Now or the Timeline.
- Frames: "6 bytes at the end of the pass didn't form a complete frame, so they weren't stored." One byte: "1 byte at the end
  of the pass didn't form a complete frame, so it wasn't stored." (fe-ops)
- Packets: "…didn't form a complete packet…". Both: "6 bytes at the end of the pass didn't form a complete frame,
  and 12 didn't form a complete packet, so they weren't stored."

### U68 · Command priority, expiry and resolved arguments (§11c(C) tier 1, director GO; fe-ops) (fe-ops / api)
**Expiry** (Compose C5, the Release block, under the two release options):
- A checkbox `Expire if not released by` opens ApTimePicker (UTC, mission presets). Its hint: "Uplinks not released
  by then end as Expired." Unchecked = `expires_at: null`, the default.
- The time is refused when it's in the past ("Pick a time in the future.") or not after a `Hold until` time ("Pick a
  time after the hold time, 11-16 02:00Z.").
- C4 Delivery plan: a target whose next contact starts after the expiry gets a caution row "Expires before its next
  contact (AOS 04:12Z)." Arming isn't blocked; the operator may mean it.
- The arm button's confirm and the summary tiles add "Expires 11-16 04:00Z if not released."
- Approve's A1 header meta and the request page's Release line: `Expires 11-16 04:00Z` (§4: date when not
  today).
- When it happens, the end reason reads "Expired at 04:00Z before it was released." (the "Expired" stage word stays,
  never "Canceled").

**Priority** (api: integers 0–9, default 3, lower = sooner; it orders only within one target's queue lane, never
across spacecraft, and never overtakes a release in progress):
- Words, never a number. The Release block gets a `Priority` choice: `Normal` (sends 3, the default) · `High`
  (sends 1). Compose offers no other values.
- The hint: "High-priority uplinks go before normal ones queued for the same spacecraft."
- Normal (3) is silent everywhere. Below 3 shows as a neutral outline tag `HIGH PRIORITY`, and 4–9 (from the legacy
  pages or the API) as `LOW PRIORITY`. Both are tags, not status colours, in Approve's A1 header, the request
  page's Release line and the Commands list row. The number goes in Technical details.
- Edit and resend keeps a request's priority. A low one shows as a third, pre-selected choice `Low (as before)`, so
  a resend never quietly changes it.

**Resolved arguments** (the queue-step condition, ux review 2026-11-15). The server's value is shown only where it
differs from what was entered.
- **Shared values:** under A1's readout and stack line, one `text-3` line per differing argument, each naming its
  argument (fe-ops 1fabb79af):
  - `VOLTAGE: sent as 16,777,216 (entered 16,777,217)`
  - `TIMEOUT: default used, 30 s`
  - `MODE: fixed value used, 1`
  - `GAIN: catalog value used, 4` (filled from the catalog when the pinned definition can't say whether it's the
    default or fixed)
- **"Sent as" only when it changes the value.** It shows when the sent value, rounded to the entered value's
  decimal places, differs from what was entered. A float sent as 32-bit `0.100000001` for an entered `0.1` is the
  same value and shows nothing; the exact encoding is in Technical details. (api: today the only sent-as difference
  is 32-bit float encoding.)
- **Some targets only:** the line starts with up to 3 names, then "and N more" (the full list in its title):
  `EARENDIL-004, EARENDIL-009 · TIMEOUT: default used, 30 s`. When it applies to all targets, no names.
- **Own-values table:** the cell shows the value sent, with `entered 2.5` under it in `text-4`. A `default` cell
  becomes `default · 30 s`.
- **Arm** (Compose, no second GO): the arm confirm repeats the same lines under each command. Nobody arms without
  seeing them.
- **Uplink & verify and the request page:** the command line shows the value sent, in Technical details only.

### U69 · Frontend-only parity items (§11c(C) audit A4a, A5a, A6, A9a, A16a; fe-ops) (fe-ops)
- **A4a Verify times (Uplink & verify), per target.** Seconds, since the shift matters here.
  - Pending: "Verify by 03:12:30Z". Met: "Verified at 03:11:58Z". Timed out: "Timed out at 03:12:30Z: no matching
    telemetry".
  - Placement: the target's N card, its U1 cell name and title, and the U3 event row.
  - The pipeline's `Verifier window open` caption gains its end: "open until 03:12:30Z", or "windows close
    03:12–03:20Z" when the targets differ.
- **A5a Commands state filter.**
  - A `State` multi-select in the filter row (in the URL as `?state=`). Its options use the stage words:
    `Release failed`, `Verify failed` (or one `Failed` if the server only has failed), `Outcome unclear`,
    `Sending or verifying`, `Queued for AOS`.
  - While it's set, the results span every tab: the tabs give way to the line "12 commands · Failed, Outcome
    unclear" + `Clear filters`.
- **A6 Alarms.**
  - A filter row above L1 (`?sc=`, `?severity=`): `Spacecraft` (a searchable select) · `Severity` (`Critical`,
    `Caution`, multi-select).
  - By point stays in the L2 aside, and all filters combine.
  - Now's `?state=critical|caution` links map onto `?severity=`, which fixes D1.
  - Header meta "Last change 02:51Z on EARENDIL-047" (§4 date when not today), omitted when there's none.
- **A9a Timeline severity.** It sits with the kind toggles as a choice: `All` · `Caution and up` · `Critical`
  (`?severity=`), a threshold rather than a multi-select. E1's density strip stacks only what's shown.
- **A16a Book a pass offer row.**
  - Antenna: after the station, as given: `Svalbard · Antenna SG2` (the label; with no label, nothing, and its id
    goes to Technical details).
  - Availability: `available` says nothing. `limited` adds a caution word "Limited availability". `unavailable`
    disables `Book`, with the reason "Northlight reports this window as unavailable."
  - Synthetic: the plan's `SYNTHETIC` tag.
  - Cost: **not shown yet**. The wire has a bare number, with no currency and no word on whether it's a quote or an
    estimate (U20). api adds `{amount, currency, kind}`; it then reads `$240` for a quote or `≈ $240 (estimate)`.

### U70 · A target's command history: release attempts and verifier evidence (§11c(C) A3, A4b/c; api 45563ffe8) (fe-ops)
**Where:** a `History` button opens a sheet titled `EARENDIL-007 · history`.
- The button sits on the target's N card and on each target line. U1's cells have no selection (fe-ops).
- It's a dialog trigger (`aria-haspopup="dialog"`), not a disclosure, so it has no `aria-expanded`.
- In the sheet, one block per command, in stack order, headed by the command's stack line. Each block has two
  lists, `Attempts` and `Verifiers`.
- Both lists read **oldest first**, as a story. Paging follows the server, which gives no totals, so no number:
  `Show earlier attempts` at the top of Attempts, `Show later verifiers` at the bottom of Verifiers.
- Every time has seconds, since the shift matters here; the date only when not today.

**Attempts** (state words as in groups/words.ts):
- "Released at 03:11:58Z during EARENDIL-007 · PUQ 07:20Z pass · 12 bytes" (the contact label as api gives it).
- Refused: "Release failed at 03:02:10Z: <reason in words>", using the release-stop words ("the command window is
  closed"). `failure_reason` is internal and goes to Technical details.
- Uncertain: "Outcome unclear at 03:05:12Z: Cadence couldn't confirm whether it was sent." `timeout` instead ends
  "…: the send didn't answer in time, so Cadence can't tell whether it went." Any other uncertain code uses the
  first sentence.
- Resolved by an operator (U29, actor and time together):
  - not_sent: "Resolved as not sent by Mira K. at 03:20:05Z."
  - rejected: "Resolved as rejected by Mira K. at 03:20:05Z."
  - The resolver is a person or a service identity, never Cadence (api 1b61e57ac: an automatic timeout stays
    "Outcome unclear" and isn't a resolution). A service identity shows by its display name, marked as a service
    (U103): "Resolved as not sent by ops-automation (a service identity) at 03:20:05Z."
  - A service identity with no name (`kind` service_identity, `name` null): "Resolved as not sent by a service
    identity at 03:20:05Z." The kind is known, so it's said; the id goes in Technical details (U25).
  - With no name and no known kind: "Resolved as not sent at 03:20:05Z; who resolved it isn't known." (fe-ops
    293aa2cd2)
- Telemetry evidence carries the catalog unit ("= 8.0 °C (raw 412)"). A point without one shows no unit, never a
  guessed one.

**Verifiers:**
- Each row is the verifier's name, then its outcome.
  - Met: "Mode applied · verified at 03:12:04Z".
  - Failure criteria matched: "Mode applied · failed at 03:12:04Z: the reading matched its failure condition".
  - Timed out: "Mode applied · timed out at 03:12:30Z: no matching telemetry".
  - Still pending: "Mode applied · verify by 03:12:30Z" (U69 A4a).
- Under each outcome, the evidence on one `text-3` line:
  - Telemetry: "HK.sc_mode = 2, received 03:12:03Z".
    - The raw value appears only when it differs from the engineering one: "= 8.0 °C (raw 412)".
    - Quality appears only when it isn't good: "· quality: suspect", in caution text.
  - Transport: "<action> <phase> at 03:11:58Z", for example "Uplink request accepted at 03:11:58Z".
    - Actions: uplink_request "Uplink request", provider_request "Provider request", transport_event_handled
      "Transport event", control_input_handled "Control input", timer_handled "Timer".
    - Phases: acceptance "accepted", start "started", completion "completed", failure "failed" (crit text), custom
      "reported". With no phase: "<action> at 03:11:58Z".
  - The evidence record is gone: "The matching record is no longer available." (U20: the outcome stands; only the
    proof is missing).
- The phase word (`completion`) and severity go to Technical details, unless api says severity changes what an
  operator does.

**Technical details** (one disclosure per block): attempt, path, binding, packet, evidence and record ids; generated
time; recorded at; and the exact float encoding (U68).

### U71 · Alarm proof, Timeline event detail, event-type filter, Alarms' last change (§11c(C) A7, A8, A9b, A12; api 0619ac94a, a87bee73d, 4a2f470d8) (fe-ops)
**A7 Alarm proof.** It goes where an alarm is explained, in Investigate. The Alarms row stays lean: its source tag
and the spacecraft link are enough.
- **B1:** a `text-3` line under the header meta.
  - Ground limits: "From ground limit v3 in limit set DEFAULT · `View limit v3`". The link opens the limits app's
    Definitions surface with `?definition=&version=`.
  - Catalog monitoring (no definition): "From the catalog's limits", with no link.
- **The triggering sample:** `Show the sample that raised it (02:08:11Z)` on the same line.
  - It opens the Telemetry tab on that point, centred on `trigger.at`, with that sample ringed.
- **Escalations** (fe-ops' option b): B2 shows the episode's own line, "Became critical at 02:31:40Z · `Show
  sample`".
  - Within the episode's span (opened to cleared, or now), the timeline's limit events for that point are hidden,
    so nothing shows twice. Outside the span, they stay.
  - Lines are never matched by time.
  - History's H3 lists past episodes and gets nothing. When a past episode is selected, H2's chart rings its
    triggering sample.
- **Technical details:** definition id, sample id.

**A8 Timeline event detail.**
- **Opening it:** each row's time is a button (`aria-pressed`). The row's subject link stays as it is.
- **Where it shows:** selecting a row opens an aside panel (380px, Investigate's aside), so the log stays in view.
  Below 1100px it's a sheet.
- **First-class fields**, in this order:
  1. The sentence as the title.
  2. Mark + severity word.
  3. Its group and type (`Contacts · Contacts canceled`).
  4. "Occurred 11-15 02:51:03Z" (with seconds and date).
  5. The subject and the refs as named links: spacecraft, pass (its label), command, data source, dashboard.
     A ref without a name stays in Technical details.
  6. The status in words, when the record has one. A status code without a word goes to Technical details.
- **Technical details:** event id, raw kind, source record kind and id, source endpoint, path, capability instance,
  activation, correlation key (free text, mono).
- **Copy link** in the panel copies the `?event=<id>` permalink.
  - Opening that link centres the window on the event, selects its row (white left bar), opens the panel and
    focuses the panel's title.
  - An id that isn't there any more: "This event isn't in the timeline any more." + `Clear`.

**A9b Event-type filter.**
- A multi-select labelled `Event type` (not "raw kind"), next to the group toggles, in the URL as `?raw_kind=`.
  - Options use the fold words (`kindLabel`) with counts: "Contacts canceled (214)", most frequent first.
  - It lists only types in the groups currently shown.
  - Type-ahead only; no typed prefixes or wildcards.
- With types chosen, the strip and the log show only those, and `Clear filters` resets both filters.

**A12 Alarms' last change** (`summary.latest_change`). The header meta is a sentence, linked to the episode in
Investigate (`?alarm=`):
- raised: "Last change 02:51Z: a new alarm on EARENDIL-047."
- escalated: "Last change 02:51Z: an alarm on EARENDIL-047 became critical."
- deescalated: "Last change 02:51Z: an alarm on EARENDIL-047 eased to caution."
- cleared: "Last change 02:51Z: an alarm on EARENDIL-047 cleared."
- No spacecraft: "on the mission". No change at all: omitted. §4 date when not today.

### U72 · Commands search and target filter; paging without totals (§11c(C) A5b/c, A6d) (fe-ops)
- **Commands filter row:** a search field + `Target` + `State` (U69 A5a), all in the URL (`?q=`, `?target=`,
  `?state=`).
  - **Search:** placeholder `Search requests`, accessible name "Search requests by title, log entry, command or
    id". It holds 100 characters at most; past that, "Keep the search under 100 characters."
  - **Target:** a select of every fleet spacecraft by name, with type-ahead. It can't be narrowed, because the list
    has no per-target counts.
- **While any filter is set,** the tabs give way to one line + `Clear filters`, and the line claims only what's
  known.
  - More pages to come: "12 shown · Failed, Outcome unclear · matching “heater” · on EARENDIL-312".
  - Everything loaded: "12 commands · …" (now a true total).
  - Nothing: "No commands match: Failed · “heater”." + `Clear filters`.
- **Paging** (Commands and Alarms; cursor-based, no totals): `Load more` at the list's foot, only while there's a
  next page.
  - After loading, focus moves to the first new row's link.
  - The button disappears at the end.
  - Alarms' cap note gives way to it, and "· from the N loaded" stays true as N grows.
- **Rows that move between pages** (api's caveat): dedupe by id, silently. A live change reloads from the first
  page up to the number already shown, so a row skipped while it moved comes back by itself. No words for it.

### U73 · A plan's history: versions and every decision round (§11c(C) A10; api 7a83a958b) (fe-ops / fe-setup)
Versions read `R3`, as the plan header already does (`Contact plan · R41 draft`).

**Where it lives:**
- `History` in the plan takeover's header opens a wide sheet, "Contact plan for 11-14 · history". This keeps K1's
  Gantt layout untouched.
- The state panel's latest-decision line links to the same sheet ("All decisions").
- The sheet is one list, **newest first**, with version rows and decision rows in time order. A17's run history
  joins this list later.

**Version row:** "R3 · drafted by Maya T. at 11-13 02:44Z".
- When Cadence drafted it (a re-plan or the planner): "R3 · drafted by Cadence at 02:44Z". A service identity shows
  its display name, marked as a service (U103): "R3 · drafted by Nightly planner (a service identity) at 02:44Z".
- A `text-3` line: "1,512 selected · 36 locked · 4 rejected". The rationale follows as a quote, when there is one.
- Tags: `CURRENT` on the current version; its decision as a word tag (`APPROVED` or `SENT BACK`); nothing for none.
- `View R3` opens `?version=3`. There's no link on the current version.

**Decision rows** (actor and time together, U29):
- submitted: "Submitted R3 for approval by Maya T. at 02:46Z", with the note quoted.
  - A resubmit without changes: "Resubmitted R3 unchanged by Maya T. at 03:01Z".
  - With acknowledgements: "· 6 gaps accepted" and a `Show` that lists each gap with its reason (ScheduleFlow's
    accepted-gap words).
- approved: "Approved R3 by Ana R. at 03:10Z", with the note quoted.
  - With exceptions: "· 2 exceptions" and a `Show` that lists them.
  - Automatic: "Approved R3 automatically under the policy “Nightly approval” v2 at 03:10Z". The policy is the
    actor; with no policy name, "under an automation policy".
- rejected: "Sent back R2 by Ana R. at 02:58Z: “Svalbard is down tonight, re-draft without SVB.”" (the console's
  word for reject).

**An old version** (`?version=N`, read-only, all actions hidden): an info callout at the top, worded by that
version's decision:
- Sent back: "You're looking at R2, sent back 11-13 02:58Z. The current version is R4." + `Review current version`.
- Approved, then replaced: "…R2, approved 11-13 03:10Z and since replaced by R4."
- Submitted with no decision, then replaced: "…R2, submitted 11-13 02:46Z and since replaced by R4." (fe-setup)
- No decision: "…R2, never submitted."
- Automatic approvals read "under an automation policy" until api sends the policy's name and version (the wire has
  only `automation_grant_id`).
- **Gaps and exceptions under `Show`** name the requirement by spacecraft and label once api sends them
  ("EARENDIL-389 · Block 1 daily: no window can cover it"). The gap's window follows the label (qa: one
  requirement can have several gaps, and the rows read the same otherwise): "EARENDIL-389 · Block 1 daily ·
  06:00–12:00Z: no window can cover it" (§4). If the history read has no window, api adds it. Until then each row is the reason alone, and the
  requirement ids go in a Technical details under the list. Raw ids never lead a row (design-language §8).

### U74 · A pass's reservation and contact record in the drawer (§11c(C) A11, A13; L14) (fe-ops)
**One first-class line in D2** (it's navigation, not evidence): a `Booked` kv row.
- From a plan: "From the 11-14 plan (R3) · for Block 1 daily". Both parts are links, to the plan at that version and
  to the requirement.
- Off-plan bookings keep their existing "Booked outside a plan by …" line.
- No plan or requirement: the row is omitted.

**Inside D2's Technical details,** two disclosures, `Reservation` and `Contact record`. They're collapsed, and
everything in them is mono key/values.
- **Reservation:** reservation id · Provider revision `7` · State (the pass state words; an unknown code shows
  sentence-case) · Provider and transport (`Northlight · v4`) · Plan and requirement ids with versions · "Last
  reconciled 02:11:04Z".
- **Provider values:** a table, `Field · Requested · Confirmed · Accepted`.
  - Field names are the provider's, as given (`// free-text:`).
  - A value that differs from Requested is `text` weight 600; one equal to it is `text-4` (the own-values rule,
    C2).
  - A missing value reads `not set` in `text-4`, never a dash.
  - A withheld value reads `Not shown`, with the title "Structured or over 512 bytes; Cadence doesn't display
    it."
- **Provider audit:** rows "02:11:04Z · <action> · <outcome>", using the provider's codes in sentence case. Newest
  first, with `Show earlier` at the foot while there's more.
- **Contact record:**
  - Scheduled and realized, each with its state, window (§4) and clock mode, plus "Realized at 03:09:02Z".
  - A table `Path · Provider binding · Transport binding`, with sources and intents as key/values.
  - Schedule revisions: "r3 · 02:59:40–03:08:52Z · scheduled", newest first, `Show earlier` at the foot.

### U75 · A request that expires part-way (DECISIONS #97; api: one `expires_at` per request) (api / fe-ops)
Every member of a request shares one `expires_at`. When it passes, every unreleased member expires together and
ends `expired` on its own; nothing is held. The noun is **request**, and its members are **uplinks** (U46). Times
are §4.
- **Each expired uplink:** stage `Expired` (off), with U68's line "Expired at 04:00Z before it was released."
  There's no special action; `Edit and resend` stays the request's normal action.
- **The request, where it summarises** (request page, Uplink & verify's header area):
  - Some went out: "The request expired at 04:00Z after 2 of 5 uplinks went out. The other 3 weren't sent."
  - None went out: "The request expired at 04:00Z before any uplink went out."
- **Uplink & verify:** expired cells are dashed (off), with `Expired` in the legend. A **partial** expiry gets one N
  card per request: the sentence above + `Edit and resend`. Nothing went out: no card; the summary line is enough.
- **Commands list row:** `Expired · 2 of 5 sent`, or `Expired` when none went out.
- **Request log:** "Expired at 04:00Z · 2 uplinks sent, 3 not sent" (none: "Expired at 04:00Z · nothing sent").
- **Now** (`expired_group: {expired_count, released_count, target_count, expired_at}`), P2, `Open` → the request,
  resolved by `Mark as seen`:
  - Partial: caution, since a spacecraft may be part-way through the sequence. Title "EARENDIL-004 · Low power safe
    expired before all its uplinks went out", or "Low power safe expired on 3 spacecraft before all its uplinks
    went out". Meta `2 OF 5 SENT · EXPIRED 04:00Z`.
  - None released: neutral. Title "EARENDIL-004 · Low power safe expired before any uplink went out". Meta
    `NONE SENT · EXPIRED 04:00Z`.
- **Approve** isn't involved; expiry happens after approval.

### U76 · Planning replacements, final words (user accepted the four drops, 11-16) (fe-setup)
**Re-plan header meta (K2),** under the title:
- Format: "Window 02:45–10:45Z · from the outage's start, 8 h by the planning policy · attempt 2 of 3".
- The cause names itself, for example "from Northlight's change at 02:45Z" or "from the station outage at 02:45Z".
  The horizon is the policy's `repair_horizon_seconds`, in §4 duration form.
- No cause (api's `cause` null when it can't attribute one cleanly, 11-17): the clause goes and nothing is guessed
  (U20): "Window 02:45–10:45Z · 8 h by the planning policy · attempt 2 of 3".
- The last attempt is in caution: "attempt 3 of 3, the last the policy allows".
- With none left: `Propose a re-plan` is disabled (an attempt is spent when a re-plan starts; fe-ops, 11-17) with
  "No re-plan attempts left (3 of 3). The planning policy sets the limit." plus a link `Planning policy` for admins.
  Applying a proposal already made (the last attempt's) stays allowed.
- The window isn't editable (U-review 2026-11-15 A14d).

**Optional note on Submit and on Approve:**
- Field `Note for the record (optional)`, with the hint "Saved with your name in the plan's history."
- Over 2,000 characters: "Keep the note under 2,000 characters." The same 2,000 on Submit and on Approve (lead,
  11-17: api raises Submit's 500), so one field never has two limits. The counter appears from 1,800, as with U65's
  reasons.
- It appears in U73's history quoted under its decision row. `Send back` keeps its required `Reason`.

### U77 · Provider account: how Cadence hears about booking changes (`event_ingestion_mode`; lead, gates the 11-16 deletion batch) (fe-setup)
On Add account and Edit account. Show only the options the provider's model supports (Northlight's model: polling,
hybrid, disabled). Order: as below.
- **Label** `Booking updates` (not "Event ingestion").
- **Help text:** "How Cadence hears when Northlight confirms, moves or cancels a booking."
- **Options:**
  - polling, `Cadence checks`: "Cadence asks Northlight for changes regularly."
  - webhook, `Northlight sends`: "Northlight sends changes as they happen. Set up the webhook at Northlight first."
  - hybrid, `Both`: "Northlight sends changes as they happen, and Cadence also checks in case one is missed."
  - disabled, `Off`: "Cadence doesn't take in Northlight's changes."
- **When `Off` is chosen:** a caution line under the field reads "While this is off, Cadence won't see Northlight
  confirm, move or cancel bookings."
  - On Add, it adds "Turn it on in Edit when the account is ready."
- **Edit on a live account.** Saving makes a new account version, as other edits do. The line under the field
  depends on the change:
  - To `Off`, with active bookings: "While this is off, Cadence won't see Northlight confirm, move or cancel the 14
    bookings made with this account." Without a count, "…the bookings made with this account." Save reads `Save and
    turn off updates`.
  - From `Off` to any other: "Cadence starts taking in Northlight's changes when you save." No claim about changes
    made while it was off (U20).
  - To `Northlight sends` from `Cadence checks` or `Both`: "Cadence will stop checking. Make sure Northlight's webhook
    is set up, or changes will be missed."
- **Read-back on the account page** (a kv row `Booking updates`): `Cadence checks`, `Northlight sends`, `Both`,
  or `Off` (in caution text).
  - "Every 5 min" is added only if the account's configuration states an interval; never a guessed one.
  - Off adds "Cadence won't see Northlight's booking changes."
- **History and audit:** "Changed booking updates from Cadence checks to Off (v5) · Mira K. · 08:02Z".

### U78 · Contacts › History: a week of past passes (§11c(C) A12; dashboards builds, fe-ops reviews)
A 4th Contacts tab: `Live · Plan · Review · History`. The tab label is `History`. Route `contacts/history`
(`ops.contacts.history`). The page header stays Contacts'.

**What it lists.** Booked passes whose window has **started**, newest first: History is the past, and upcoming
passes are on Live and Plan. The current week runs to now.
- Hand-started contacts are listed too (api `include=hand_started`, live 11-16), so there's no "booked passes only"
  foot line.

**The week.**
- A week is Monday 00:00Z to the next Monday 00:00Z (UTC, ISO weeks). `?week=` holds the Monday. Any other date
  normalizes to its week's Monday, and a bad or future value falls back to this week.
- The stepper reads `‹ Older week` · `11-09 – 11-15` · `Newer week ›`. Dates follow §4: the year is added when the
  week isn't in this year (`2025-12-29 – 2026-01-04`). This week reads `11-16 – now`.
- On this week, `Newer week` is disabled with its reason (A6): "This is the current week."
- Off this week, a `This week` link sits after the stepper.
- Jump: a date field, `Go to date`, opens the week holding that date. A future date is refused: "Pick a date up to
  today."
- A step or jump keeps the filters and focus stays on the control used. A polite live region announces "Week of
  11-09 to 11-15, 1,284 passes."
- Header meta (mono `text-3`): `1,284 PASSES` for the shown week (`500+ PASSES` when a day is short; see Truncated).

**Filters** (in the URL, U72's pattern): `Spacecraft` (a select of every fleet spacecraft, with type-ahead),
`Station` (a select), and `State` (multi-select).
- State options are the console's contact-state words, never the raw lifecycle: Requesting, Requested, Confirmed,
  In contact, Ended · not verified, Rejected, Unknown, Canceling, Canceled.
  - The URL keeps the word keys (`?state=confirmed,in_contact`), because Confirmed and In contact share raw states and
    wouldn't round-trip.
  - The read gets the union of their raw states as `states=` (Unknown sends `unknown` and `failed`; Confirmed and In
    contact both send `confirmed` and `active`), and rows are split by phase on the client.
- While any filter is set, one line + `Clear filters`: "212 passes · Canceled · EARENDIL-312 · Fairbanks".

**Columns**, in this order. Mono where noted.
| Column | Value |
|---|---|
| Window | mono, the date always (a week spans days): `11-14 02:59:40 – 03:08:52Z`. It's the row's link: it opens the selected-pass drawer on `?contact=`. |
| Spacecraft | the name (text, not a second link; the drawer links it) |
| Station | the name with the code in mono `text-3`: `Fairbanks FBK` |
| State | mark + word from the contact-state words (`■ Ended · not verified`, `▲ Rejected`) |
| Provider revision | mono `3`; `—` when the read has none |
| Reservation | mono id, middle-truncated, with a copy button ("Copy reservation id") |
| Scheduled contact | the same, "Copy scheduled contact id" |

- The drawer is the record: realized id, scheduled revision and clock mode stay there (A13), not in new columns.
  On a pass that's over, it shows no live actions.
- **768–1099px:** Reservation and Scheduled contact drop (they're in the drawer's record).
- **Below 768px:** a table, not cards. Three columns: `Start` (mono `11-14 02:59:40Z`), `Pass` (the spacecraft over
  `Fairbanks FBK` in `text-3`), `State`. `Start` is the link. The drawer is a full-height sheet (§9).

**States.**
- Loading: `LOADING…` in the table panel.
- Empty week: "No passes between 11-09 and 11-15." This week: "No passes have started this week." Both offer
  `‹ Older week`.
- Empty with filters: "No passes match: Canceled · EARENDIL-312 · 11-09 – 11-15." + `Clear filters`.
- **Truncated** (api, live 08:16Z: the read is `order=desc`, so a cut keeps the **newest** 500 by start; spacecraft
  and states filter in the read, before the cut; station filters after it). A truncated week is re-read one UTC day at
  a time and merged, so only a day over 500 is short.
  - An info callout above the table, one sentence per short day: "11-12 has more than 500 passes, and only the newest
    500 are shown, back to 05:12Z. Pick a spacecraft or state to see the rest." The time is the earliest shown start.
  - In the list, below that day's oldest shown row, a `text-3` row: "Passes on 11-12 before 05:12Z aren't shown."
  - No advice to narrow by station: it runs after the cut and can't bring the rows back.
  - Meta reads `500+ PASSES` on a day that's short, and counts stay "500+" wherever they include it.
- Error: "Contact history couldn't load." + `Try again`.

**Hand-started contacts (when api lists them, BACKLOG's `booked: false` rows).** They join the list with no new
filter.
- The Window cell reads `11-14 02:59:40 – 03:08:52Z` with a `HAND-STARTED` tag. It's a contact, not a pass (U46):
  no AOS or LOS words, and no Reservation or Provider revision (`—`).
- State is its real state word (`In contact`, `Ended · not verified`), never "Hand-started".
- With no end yet (`ends_at` null): `11-16 02:59:40Z – no end yet`. That's true whether the contact is still open or
  its end was never recorded, so it claims neither (U20). Duration reads `—`.
- Defined but never live (`defined`): State `○ Not started` (the off mark; neutral, not a fault). It's not a
  pass that was missed. Its one time is when Cadence created the record (api's `realized_at`), not a start, so the
  Window cell labels it: `Created 11-16 02:59:40Z` ("Created" in `text-3` sans, the time mono). It sorts by that
  time. The phone's Start column shows it the same way. The row link's accessible name ends "never started".
- `stopped` reads `Ended · not verified`, like a completed pass: never green without flown evidence.
- **Swept without going live** (domain's orphan sweep closes a never-live contact after an hour as `stopped`): it
  reads like a defined one, never `Ended`, which would claim an hour-long contact that never happened (U20). This
  needs api's additive `not_started: true` on `booked: false` rows (true for `defined` too).
  - State `○ Not started`, and the Window cell `Created 11-16 02:59:40Z` (`starts_at` here is the creation time).
  - The drawer's record adds one line: "Closed by Cadence at 03:59:40Z: it never went live." (`ends_at`).
  - Until the field ships, such rows read as shipped (`Ended · not verified`).
- Count lines add them: "1,284 passes and 3 hand-started contacts". The foot line goes.
- The drawer shows the A13 record alone, titled "Contact record", with no reservation section and no pass actions.

**Timeline's contact ids** (lead's ruling, 11-16: no record-only `?record=` route). "Realized contact" and "Scheduled
contact" link to History `?contact=<id>` once api's `/passes/:id` accepts a scheduled or realized contact id (api's
next item). Until then they stay plain text, as today.
- The drawer opens whatever that read returns: a booked pass with its record, or, for a hand-started contact, the
  record alone (no reservation section, no pass actions).
- **Drawer titles** name the subject, since a sheet below 1100px takes its accessible name from the title:
  `Pass · EARENDIL-312 · Fairbanks`, and `Contact record · EARENDIL-312` for a hand-started contact.
- An id the read can't find: "No contact record with this id." (U25: the id isn't repeated as if it were a name.)

### U79 · A spacecraft's extra route (DECISIONS #3 per-spacecraft overrides; ux + domain answer to lead 11-16; domain 774471695 kind `spacecraft_route`) (domain / fe-setup)
One spacecraft gets a route its profile doesn't give it, such as a recovery downlink via Inuvik. It's staged through a
change set like any override. There's no separate routes editor.

**Where:**
- Its home is the spacecraft's page, in Setup › Spacecraft › <craft> › routing. The route list there carries a tag on
  each route: `From profile` or `This spacecraft only` (from the read's `origin`). `Add extra route` sits above the
  list.
- A `This spacecraft only` route has `Edit` and `Remove…`, both staged.
- **origin `legacy`** (hand-made per-spacecraft rules from the old routing save; dashboards' question, 11-16): tagged
  `This spacecraft only` (untagged would read as from the profile), with a quiet second line "Set up on the old
  routing page." and no actions; an A6 reason line under the row, "Older routes can't be changed here yet."
  - lead's ruling: domain converts legacy rules into extra routes (`spacecraft_route`); any rule that can't map gets
    a staged `Remove…` as the floor. Batch 2's deletion of the legacy save waits for it. Once converted they're
    ordinary extra routes and the second line and reason go.
  - lead ruled (11-16) on domain's assessment: **three routes per craft**, one per legacy rule (Earendil: 500 craft ×
    3), so names, purposes, legs, roles and transports stay exactly as today. The QA mission's station-less rule
    can't map; it gets a staged `Remove…` and keeps the interim words until removed.
  - **The director chose the change-set path, in batches** (lead's answers, 11-16): each click stages the NEXT
    batch (server default 50 craft), ALONE in its change set. The trial wait after batch 1 is a step for qa and the
    director, not the UI, so it has no words. A real person applies each set, and the history names them (U29).
    Each set's description (api): "Converted from the old routing page: batch 1 of 10, 150 routes on 50 spacecraft."
  - **The temporary staging action** (lead; deleted with 9ac6dc8ee). On a spacecraft's routing page, when the list has
    `legacy` rows, an info callout sits above the list:
    - "Routes set up on the old routing page can't be changed here until they're converted to extra routes. They're
      converted in batches, and nothing changes until each batch is applied." Progress: "450 of 1,500 routes
      converted."
    - The button `Stage batch 2 of 10` (secondary; busy "Staging…"). No confirm, because staging is undone by
      discarding. On success it opens the change set.
    - No permission (`can_stage` false; `manage_mission` = mission admins, organization admins): no button, and the
      A6 line "Mission admins and organization admins can stage the conversion."
    - A batch already staged (`staged_batch` / `conversion_already_staged`): the button is replaced by "Batch 3 is
      staged in Mira K.'s change set. Apply or discard it before staging the next." + `Open change set`.
    - The open change set has other changes (409 `open_change_set_not_empty`): "The mission's open change set has
      other changes. Apply or discard them first, so this batch is reviewed on its own." + `Open change set`.
    - Skipped routes (`skipped`, the rest still staged): "1 route wasn't converted: EARENDIL-389's transport has no
      station. Remove it on that spacecraft's routing page." Several: "3 routes weren't converted." + the list, each
      spacecraft by name linking to its routing.
    - Nothing left: "No routes from the old routing page are left to convert." (The callout normally doesn't show
      then.)
    - Failure: "Couldn't stage the batch. Nothing was changed." + `Try again`.
    - Stager ≠ reviewer is ENFORCED (api v3.2): conversion sets force approval, and approving applies them; the stager
      may submit, and someone else reviews and applies. The change set's `viewer: {can_review, review_blocked_reason}`
      is false + `reviewer_is_author` for the stager (every set gets the field; these words only where
      `legacy_conversion` is set). Under the description: "Staged by Mira K. Someone else reviews and applies it." For
      the stager, the review action is disabled with the A6 reason "You staged this batch, so someone else reviews and
      applies it." So the stager doesn't read it twice, their description line keeps only "Staged by Mira K." (#405,
      fe-ops' question 11-19). The conversion line is only for the batch's stager (the viewer is among the set's
      `authors`). Someone else who sent the batch for review gets #320's general line, "You staged part of this change
      set or sent it for review, so another person reviews it." (ca-ux, 11-19). The server still decides who may review;
      the authors list only picks the words. Other sets keep today's reviewer_is_author sentence.
    - **Every set, up front** (#320, ca-ux 11-19; amends the line above): the console reads the change set's
      `viewer.can_review` and `review_blocked_reason`, never its own `authors` list. The server sets
      `reviewer_is_author` only when the set needs approval, for whoever submitted it or authored any change, so under
      "Applies without approval" an author still reviews. When `can_review` is false, both review actions (Approve and
      Send back; the server refuses both) are disabled with the A6 reason, muted under them and as their
      description: "You staged part of this change set or sent it for review, so another person reviews it." (the conversion
      batch keeps its own line above). A reason the console doesn't know: "You can't review this change set, so another
      person reviews it." with the code in Technical details. The refusal stays the backstop: Approve "Not approved: you
      staged part of this change set or sent it for review, so another person reviews it. Your approval wasn't
      recorded."; Send back "Not sent back: you staged part of this change set or sent it for review, so another
      person reviews it. Nothing changed."
    - **Approve refused by the checks** (#262, ca-ux 11-19; the review runs the checks again, and these used to
      answer 500). Nothing is written, so the set stays in review, and each line says U95's "Your approval wasn't
      recorded." after the why (#375):
      - Up front: when the read already shows a blocking hold, Approve is disabled with the A6/A7 reason "A blocking
        hold stands; see the checks." The 409 stays the backstop.
      - 409 `holds_blocking` (approve's own line; the stage/apply line stays): "Not approved: a blocking hold stands,
        so nothing was applied and the change set stays in review. Your approval wasn't recorded. Approve it once the
        hold clears; the checks show it." The holds show in the checks, not in the line. After it, Approve is disabled
        with the up-front reason until a reload shows the hold cleared.
      - 503 `preview_failed` (Cadence couldn't run the checks: a database or connection error, a server fault):
        "Not approved: Cadence couldn't run the checks, so nothing was applied and the change set stays in review.
        Your approval wasn't recorded. Try again; if it keeps happening, tell the team that runs Cadence for you."
        Unlike U95's usual rule, Approve stays enabled after it, because trying again is the fix. The cause goes in
        Technical details, never in the line. Send back doesn't run the checks, so it never meets this.
      - K3's submit meeting 503 `preview_failed` (it used to fall to a generic 422), opened by the act the button
        named: `Apply as r5` "Not applied: Cadence couldn't run the checks, so nothing changed. Try again; if it
        keeps happening, tell the team that runs Cadence for you."; `Request review` "Not sent for review: Cadence
        couldn't run the checks, so nothing changed. Try again; …" (same ending). The button stays enabled; the Why
        and the hold acknowledgement stay filled.
    - Read fields (api v3.2, final): the button is `Stage batch <next_batch> of <batches_total>`; progress is
      routes_converted of routes_total. No per-craft "in batch 3" line. An author with no name: drop the name
      ("Batch 3 is already staged." / "Staged earlier."), never the id.
    - After staging (fe-setup's flow): with no skipped routes, open the change set at once. With skipped routes (the
      201's `unmappable`), stay on the routing page and show "Batch 2 is staged." + the skipped lines in the callout,
      with `Open change set` as the next step, so the skipped list isn't lost to a navigation.
    - Staging any OTHER change while a batch is staged (409 `conversion_in_progress`, domain; like
      `rollback_in_progress`), wherever the change is staged: "Batch 3 of the route conversion is staged, so other
      changes can't be staged in this mission until it's applied or discarded." + `Open change set`. The draft stays
      in the form, unsaved. With no batch number in the details: "The route conversion is staged, so…". It needs
      `{change_set_id, batch}` in the details.
    - No "temporary" caption: the callout goes away by itself once the routes are converted.
  - **Remove legacy rule** (director, 11-16; required before batch 2; domain's delete-only kind
    `legacy_routing_rule`, not temporary). Every `legacy`
    row gets `Remove…` (staged), so the A6 line becomes "Older routes can't be edited here until they're converted."
    - An inline confirm (ApInlineConfirm, focus on Cancel): "Stage removing “qa-pre-routing-175358”? EARENDIL-389
      stops using it once the change set is applied." Buttons `Stage removal` / `Cancel`. It stages into the open
      change set like any change (so a staged conversion batch refuses it with `conversion_in_progress`).
    - Summary line (ConfigLabels, api): "Remove older route “qa-pre-routing-175358” · EARENDIL-389" (a rule with no
      name: the station form, "Remove older route INU · EARENDIL-389"; no spacecraft name: drop " · …"). "Older
      route", matching the callout and the A6 line; never "legacy" on screen.
    - Once staged, the row reads `Removal staged` (a tag) with `Open change set`, until it's applied or discarded.
    - Refusals: already converted, "This route was converted already. Remove it as an extra route."; anything else
      (not a legacy rule, another mission's), "This rule can't be removed here." Never the rule's id.
    - History after apply: "Removed older route “qa-pre-routing-175358” · applied by Mira K. · 11-17 09:12Z".
    - Rollback over a removal (lead: (i), legacy only shrinks): a blocking item `legacy_route_not_restorable` in the
      rollback preview: "The older route “qa-pre-routing-175358” · EARENDIL-389 was removed and can't be restored.
      To route that way again, add an extra route." The rollback stays NO-GO while it stands.
- Summaries: a rendered name equal to the default ("<station> · <spacecraft>") counts as unnamed, and a name that
  already contains the spacecraft's name doesn't get " · EARENDIL-389" appended again (dashboards, 11-16).
- Profile P3 lists extra routes as override rows, "Extra route via Inuvik · downlink primary", each linking to the
  spacecraft's routing. P3 doesn't add them.

**The form** (generated from domain's fixed-field schema, option (a)):
| Path | Label | Options / help |
|---|---|---|
| spacecraft_id | `Spacecraft` | create-only, preset from the page |
| ground_station_id | `Station` | `Inuvik · INU` |
| transport_id | `Transport` | optional. Help: "Leave empty to use the station's transport for each direction." |
| downlink | `Downlink` | `Not used` · `Primary` · `Candidate` · `Contributing`; preselected `Primary` |
| uplink | `Uplink` | the same options; preselected `Not used` |
| display_name | `Route name` | optional. Help: "Leave empty for “{station} · {spacecraft}”. You can use {station}, {spacecraft} and {scid}." |
| purpose_label | `Purpose` | optional. Help: "Shown with the route, e.g. Anomaly recovery." |

- `Not used` is a real option, not an empty select. So downlink and uplink are **required**, and their "none" value
  is a non-empty value (`none`). Then the create-defaults rule (required fields preselect) gives `Primary` /
  `Not used`, and "empty means inherit" never applies to them.

**Errors** (on the field, with no final period, like the other F.error messages):
- Both `Not used` (on downlink): "Choose a role for downlink, uplink or both".
- No station: "Choose a station".
- Several transports and none chosen: "Inuvik has 2 transports that can carry downlink; choose one".
- A transport at another station: "INU S-band isn't at Inuvik".
- A transport that can't carry a leg: "INU S-band can't carry uplink".
- A duplicate (domain's, as built): "EARENDIL-389 already has this route from its profile."
- Changing the spacecraft of an existing route: "An extra route can't move to another spacecraft; remove it and add
  one there".
- The API's "Each direction once" and "Add at least one leg" stay for API callers. The form can't produce them.

**Change-set summary lines** use names, never ids (U25):
- "Add extra route INU · EARENDIL-389"
- "Edit extra route INU · EARENDIL-389"
- "Remove extra route INU · EARENDIL-389"

The as-built create summary "Add an extra route for <spacecraft_id>" shows a raw id.
- domain (11-16): the summary is the console's (the stage request's `summary`), so KindEditor writes it.
- Edit and Remove name the route itself when it has a name, because one craft can have two routes at one station
  (the converted Earendil pairs): "Remove extra route “Fairbanks (Demo) — uplink” · EARENDIL-389" (the rendered
  name, quoted). A route with no name: "Remove extra route INU · EARENDIL-389".

**Dropped on purpose (DECISIONS #104; user, via director, 11-16):** pinning a route to a transport
version, and routes over a transport with no station. Neither gets words or a control in the console.

### U80 · Investigate's Sample aside (§11c(D) D1; api's one-sample read, final shape 11-16) (api / fe-ops)
One place for the words. The review (`reviews/2026-11-16-parity-ops-d.md` D1) has the reasoning.

**Opening it:**
- From U71's `Show the sample that raised it (02:08:11Z)` on an alarm. Keep that label; never "Open exact sample".
- From History events that carry a sample, and from escalation lines (`Show sample`).
- T3's rows are buckets, not samples, so nothing opens from T3 for now.
- Every opener goes to the Telemetry tab. There the aside **replaces T1** while open, in T1's column at 360px, so
  the plot keeps its width. It's titled `Sample · <point name>`, with Close (×, "Close sample").
  - Focus goes to its heading on open.
  - Esc or Close brings T1 back and returns focus to the opener, else to T1's search.
  - Below 1100px it's a sheet. The chart rings the sample.
- URL: `?sample=<id>&received=<receipt ISO>` (`received` is optional; it makes the read exact), beside
  `points`/`focus`/`at`. Closing drops both. A reload of a sample that no longer resolves shows the not_found status,
  never a blank aside.

**Rows** (kv, in this order):
| Row | Value |
|---|---|
| Value | engineering `text` + `engineering_unit` (U24), mono |
| Raw | raw `text`, mono |
| Quality | `Good`, or `▲ Suspect` / `▲ Bad` (caution mark + word) |
| Generated | `02:08:11.204Z` (§4, with milliseconds; the date when not today) |
| Received | `02:08:12.880Z · 1.7 s later` (under 1 s in whole ms, `40 ms later`; under 60 s with one decimal, then `3 min later`, `2 h later`; never `0.0 s` or `0 ms`; a gap that would round up to a band's limit reads in the next band, so 59.95 s is `1 min later`, never `60.0 s`; omitted when generation is unknown or receipt isn't after it) |
| Packet | `HK_EPS v4` (the definition's name and version) |
| Record | see below; no row when `validity_state` is null |
| Came in through | `Fairbanks · binding Earendil telemetry v3`: `endpoint_label`, then `binding <label> v<version>`. If neither resolves, `data_source_name`; if nothing does, no row |
| Realm | only when not flight: `Rehearsal`, `Replay · run 14`, `Simulation` |

**Value states:**
- `ready`: the text.
- `not_recorded`: "Not recorded".
- `unsupported`: "Can't be shown for this point type".
- `limited`: "Too large to show here", with no text (over 4 KB, 64 nodes or 4 levels).
- JSON or hex values show in mono.

**Record** (`validity_state`):
- canonical: "The record Cadence uses"
- duplicate: "A duplicate: Cadence uses another copy"
- conflict: "▲ Conflicts with another record for this time"
- superseded: "Replaced by a later revision"
- advisory: "Kept for reference: not the record Cadence uses"

**Names** (U25): a null name drops its part of the line ("Came in through Fairbanks"), or reads "an unnamed binding"
where the line needs it. An id never stands in for a name.

**Technical details:** sample id, point id, packet id, evidence id, packet definition id, data source, binding and
endpoint ids, the replay run id, and the full JSON or hex.

**Statuses** (in the aside's body, instead of the rows):
- not_found: "Cadence couldn't find this sample in the history store."
- ambiguous: "More than one sample matches 02:08:11Z, so Cadence can't tell which one this is." + `Show 02:08:11Z on
  the plot` (closes the aside and keeps `at`, so the plot rings that time and T3 shows its buckets; T3 has buckets,
  not samples, so the label doesn't promise samples)
- timeout: "Reading the sample took too long." + `Try again`
- unsupported: "This data source can't look up a single sample."
- unavailable: "The history store can't be reached right now." + `Try again`
- (11-16, fe-ops' build 2a498b5b5) History: with an episode selected, H2's line carries B1's link, "Show the sample
  that raised it (02:08:11Z)", opening the aside; no per-row links.
- An unknown status: "Cadence couldn't read this sample." + `Try again`.
- An unknown value state shows its text if it has one, else "Can't be shown here"; never the raw state word (a
  closed list we haven't learned yet, not free text). A ready value with no text shows "—".

### U81 · Listen isolation words (lead + domain, class-level, 11-16) (domain / api / fe-setup)

**1. Same-SCID warning at spacecraft save (same organization only).** A caution, not a refusal: the save goes ahead.
As built (domain's shape, 11-16): an acknowledgeable HOLD in the change set's Compatibility check, reason
`scid_shared_in_organization`, on a create or a SCID change. Apply's Why placeholder (the set's only acknowledgeable
hold): mission_count 1, "Why it's safe for both spacecraft to use SCID 42"; mission_count ≥ 2, "Why it's safe for
these spacecraft to share SCID 42"; two or more holds keep the general placeholder. One item per other mission, its shared providers joined; missions the viewer can't open
fold into one item ("2 other missions in this organization also fly SCID 42 through KSAT."). The words:
- "▲ Another mission in this organization, Earendil Ops, also flies SCID 42 through KSAT. KSAT's stations can't tell
  the two spacecraft's uplinks apart."
- The other mission is named only when the viewer can open it; otherwise "Another mission in this organization also
  flies SCID 42 through KSAT." Never its id (U25).
- The provider is named. If more than one provider is shared, "through KSAT and AWS Ground Station. Their stations
  can't tell the two spacecraft's uplinks apart." The second sentence stays in the unnamed form.
- One account: "KSAT's stations"; two or more: "Their stations". An account with no name is counted, never shown by
  id: "through KSAT and 1 other provider account"; only unnamed ones: "through a provider account you share" / "2
  provider accounts you share", then "Its stations" / "Their stations".
- Folded, n ≥ 2: "2 other missions in this organization also fly SCID 42 through KSAT. KSAT's stations can't tell
  the spacecraft's uplinks apart."
- Not yet covered (queued by lead, 11-16: domain BACKLOG row after this lands): a mission adding a provider on an
  account a same-SCID mission already uses. Transports need no check: a transport can only pick its own mission's
  providers, and every provider already counts.
- Never across organizations: another tenant's SCID is not ours to show. That case waits for domain's follow-up (an
  authenticated delivery identity).

**2. A frame whose SCID doesn't match its single-craft pass** (no longer made into samples). Kind word:
`SCID doesn't match the pass`. Counted per pass, not one line per frame, wherever protocol anomalies are listed
(the contact record first; no console list exists yet):
- "▲ 14 frames with SCID 57 arrived during EARENDIL-312's pass (SCID 42), 02:08:11 – 02:09:40Z. Cadence kept them as
  raw evidence and made no telemetry from them."
- One frame: "▲ A frame with SCID 57 arrived during EARENDIL-312's pass (SCID 42) at 02:08:11Z. Cadence kept it as raw
  evidence and made no telemetry from it."
- Never a guess at whose SCID 57 is: it may be another tenant's. Technical details: VCID, frame sequence, evidence id.
- **As built (domain's shape, 11-16): the contact's settlement key `scid_mismatch`**, shown in the contact record's
  settlement view next to U67's note, but as a caution (▲, the line at full contrast), because unlike U67 it isn't
  normal. It carries counts, not times, so the settlement line has no time range:
  - "▲ 412 frames with SCID 3 arrived during this pass, which is EARENDIL-312's (SCID 1). Cadence kept them as raw
    evidence and made no telemetry from them." One frame: "▲ 1 frame with SCID 3 … kept it … from it."
  - Two or three SCIDs: "with SCIDs 3 and 7" / "with SCIDs 3, 7 and 9". More than three: "with 12 different SCIDs";
    the list goes in Technical details. This needs the full count of distinct SCIDs (`scid_count`), because the list
    stops at 8.
  - Several paths: one line per path, with its station: "…arrived through Fairbanks during this pass…". The path is
    named by its station, never by path or binding id (U25). One path: no station.
  - Not "weren't decoded": an operator reads "made no telemetry from them".
  - The read (api, final 11-16): `scid_mismatch: null | {expected_scid, paths: [{station, frames, scids, scid_count,
    path_id, provider_binding_id}]}`, paths by frames, most first. The station clause uses station.name, else
    station.code, else no clause; one path gets no clause. path_id and provider_binding_id go in Technical details
    only.
  - domain (11-16): the station is the contact's own, the same on every path. So lines group by station: entries
    with the same station (or none) make ONE line, frames summed. Its SCIDs are the union when every entry's list
    is complete (scid_count = list length); otherwise "with at least 9 different SCIDs" (the largest scid_count or
    the union's size, whichever is more). The station clause shows only when two or more stations remain.
- **Director's ruling (11-16): refused frames land on the record (above), plus one operational event per contact
  when most of its frames are refused.** The event is a Timeline row (▲ caution) AND a Now item (lead's question,
  ux's call 11-16). Why Now: for the operator it's a pass that gave their craft little or no telemetry, and maybe a
  station pointed at another craft. No Now source says that per pass today: the queue's "No telemetry for over N
  minutes" is spacecraft staleness, which a craft heard on another pass never trips, and contact_settlement is about
  storage. The Now item: acknowledgeable (`Mark as seen`), one per contact, P2 caution, same title and secondary as
  the event, action `Open contact record`. It resolves when marked seen; the fade reads "Seen by Mira K. at
  04:12Z" (U29). Unseen, it retires 7 days after settle (api, lead 11-16); that fade reads "Retired after 7 days
  without being seen", never as if someone saw it. The Timeline row and the record line stay.
  Now row (api's shape, 11-16): no countdown (nothing is due); meta `FBK 03:10Z · settled 04:12Z`. The pass time
  is the realized start. Fallbacks: no spacecraft name → the title drops "EARENDIL-312 · " and the secondary reads
  "not this pass's SCID 1"; no station → "on the 03:10Z pass". Never an id.
  Built (fe-ops 6f31a4933): Now titles carry no trailing period, like the other Now titles; with no access, Mark
  as seen reads "Operators mark these passes as seen." (the U45/U37 pattern). The record line with no spacecraft
  name: "…arrived during this pass, which expected SCID 1."
  Timeline kind word (fe-ops' fold words): `contact_scid_mismatch` → "Frames with another SCID" (detail: "Contacts ·
  Frames with another SCID"), plural like "Contacts ended early".
  Wire (api): action `seen` (resolved_by the person, with name; resolved_at = when seen; a null name reads "Seen at
  04:12Z", never the id) or `retired` (system, settle + 7 days). The words:
  - Title: "EARENDIL-312 · Most frames on the FBK 03:10Z pass carried another SCID."
  - Secondary: "412 of 430 frames carried SCID 3, not EARENDIL-312's SCID 1. Cadence kept them as raw evidence and
    made no telemetry from them." SCID lists follow the record line's rules. The event needs the contact's total
    frame count.
  - Action `Open contact record` (History ?contact=, U78).

**3. Listen port taken by another mission** (domain 0a3426e7d, ListenClaims). Accepted as built, on the port field:
"Another mission already listens on this host and port. Choose a different port." It names no mission and no
organization; keep it so.
- The store-level refusal (`listen_endpoint_claimed` from a transport or provider-profile write) maps to the same
  words on the port field (knownErrorCode), never a generic failure or the code.
- A pass refused at start for the same reason: U45's contact_start row (its title already says "hasn't started"),
  reason `listen_endpoint_claimed`. Reason line: "Another mission already listens on the port INU S-band uses
  (5012). Change that transport's port." With no transport name: "Another mission already listens on port 5012,
  which this pass's transport uses. Change that transport's port." Second action `Open transport` (the transport's
  Setup page; none without a transport). The transport by name; never the mission, even if one is sent.

### U82 · Archiving a transport or a ground station (director; lead, fe-setup, 11-16) (domain / api / fe-setup)
Staged like any change. It needs domain's in-use check, which refuses while something still uses the item.

**Where:** `Archive…` in the row's `⋯` menu on Setup › Comms › Transports and Setup › Stations, and in the edit
page's header actions. It's not a primary button anywhere.
- **Provider-managed transports are archived the same way** (domain, 11-16: they're created through a change set
  and the kind archives any origin, with the same in-use check). The same confirm and words; no special line.

**Confirm** (ApInlineConfirm, as for removing an older route; focus on Cancel):
- Transport: "Stage archiving INU S-band? Once the change set is applied, it can't be chosen for new routes or
  passes. Its history stays." Buttons `Stage archive` / `Cancel`.
- Station: "Stage archiving Inuvik · INU? Once the change set is applied, it can't be chosen for new routes or
  passes. Its history stays."
- No reason field: the change set's own review covers it.

**In use** (domain's refusal, on stage; shown in place of the confirm, crit, with nothing staged):
- Lead: "INU S-band is still in use, so it can't be archived:" then one line per kind of use, each naming up to 3,
  then "and 4 more":
  - "Routes: EARENDIL-312 · Inuvik (Demo) — downlink, EARENDIL-389 · Inuvik — uplink and 4 more" (an extra or older
    route by spacecraft and route name; links to that spacecraft's routing);
  - "Profile routes: Earendil standard" (the profile by name; links to its routing section);
  - "Booked passes: 2, the next at 11-17 03:10Z" (links to Contacts › Plan for that station);
  - "Listening now: the EARENDIL-312 FBK 03:10Z pass" (a pass whose listener holds its port; links to Contacts ›
    Live);
  - a station also lists "Transports: INU S-band, INU X-band" (links to each).
- Then: "Move or remove these first." No id ever. A use with no name is counted ("1 route on a spacecraft with no
  name").
- domain sends counts and up to 3 named items per kind; the console words them.
- As built (api 409 `in_use`; domain 16ee2ed00): every kind is always sent; a kind with count 0 shows no line.
  Unnamed uses are only counted, so they fall into "and N more". A route with no name reads by spacecraft,
  station and direction ("EARENDIL-312 · INU downlink"), never the rule id. If every count is 0 and the refusal
  still comes, the lead sentence ends "Something still uses it."
- **Later, at submit or review** (something started using it after staging; the set reopens): on the change set,
  "INU S-band is in use now, so this change set can't be applied:" + the same lines, then "Move these first, or
  take the archive out of the change set." The archive's own row in the set carries the same crit mark.

**Summary and history:**
- Summary: "Archive transport INU S-band" / "Archive station Inuvik · INU" (a station with no code: its name only).
- History: "Archived transport INU S-band · applied by Mira K. · 11-17 09:12Z".

**Archived rows:** hidden by default. A `Show archived` switch in the list header shows them under the active ones,
with an `ARCHIVED` tag (no status colour), the name at full contrast, and no actions but opening. Pickers (routes,
bookings) never offer archived items.
- **Pass through an archived transport's pinned profile** (domain ae6ae335a: a pinned path version no longer
  resolves once its transport is archived). Today it reaches U45 as `unknown`, "Starting failed." It's rare: the
  in-use check blocks bookings, routes and open passes first. api adds `transport_archived` (11-17, after the 11-18
  in-use restart); its words are in U45's table. Re-adding the transport doesn't help (it makes a new provider
  profile), and changing the route doesn't fix a pass already booked; another booking does.

### U83 · A transport's listener: own or shared (lead, 11-16; DECISIONS #87) (domain / api / fe-setup)
A listen-mode downlink transport chooses whether its passes get their own listener or share one that routes each
connection by its first frame's SCID (#87). The words go on the transport kind's field definition (the server's
schema labels), so fe-setup's KindEditor shows them as they are.

- **Where:** the TCP Capability group, right after `TCP Port`.
- **Shown only** when `TCP Mode` is `TCP server (listen)` AND `Direction` is `Downlink` (U85). Otherwise it's
  hidden, not disabled. A value hidden by a change to either field isn't sent; the transport keeps the default.
- **Label:** `Listener`
- **Options** (select, in this order):
  - `Own listener for each pass` (`own`)
  - `Shared, routed by SCID` (`shared`)
- **Help** (the field's description): "Own: each pass opens this port itself, so passes that overlap on it can't
  all connect. Shared: passes that overlap share one listener, and Cadence sends each connection to its pass by the
  SCID in its first frame. A connection it can't match is refused."
- **Refusal** (the field's error, when `listener` is set on a transport it doesn't apply to, e.g. through the API
  or a stale form):
  - Not listening (`connect`): "Only a transport that listens (TCP server) can choose its listener."
  - Not a downlink (`outbound` or `bidirectional`): "Only a downlink transport can choose its listener."
  - Both at once: the first line only.
- **Change summary and diff:** the option words, e.g. "Listener: Own listener for each pass → Shared, routed by SCID".
- **A shared transport switched to connect, Uplink or Both** (lead/api, 11-16): the field hides and the
  console sends `listener: own` in the same stage, so the server doesn't refuse a hidden field.
  - In the form, at the switch, an info line under the field that changed (TCP Mode or Direction):
    "This transport will stop sharing its listener: only a downlink transport that listens can share one."
  - The diff line shows, because it changes how passes connect, with the reason after it: "Listener: Shared, routed
    by SCID → Own listener for each pass (only a downlink transport that listens can share one)". The same words in
    the change set's review.
  - Switching back before staging restores the field with `Own listener for each pass` chosen; the info line goes.
  - Who renders it (fe-setup, 11-16): the console writes the stage summary. The review's field rows come from the
    server's diff, so api adds the option labels for every select field (`before_label` / `after_label`, null when
    there's none; the console then shows the raw value) and, for this case, a server-derived note in brackets after
    the after value. Until then the review reads "Listener  shared → own", as the other select rows do; not a blocker.
- **Not here:** the refusals a shared listener makes during a pass are U50's `listener_refusal` (and U58 for an own
  listener held by another pass). This field adds no new Now or record words.

### U84 · Now source `replay_conflict`: stuck processing (after #99; api's words request, director's conditions) (api / domain / fe-ops)
A part of the mission's processing hit a fault in Cadence and keeps retrying the same input. Nothing in the console
fixes it; only a fix to Cadence clears it. One item per stuck unit, acknowledge-only, system-closed when the fix lands.
Director's conditions: word it for whoever operates the mission, name who to tell (there's no support desk), and
say a restart won't help only because api confirms it. api (11-17, corrected): it can't confirm that, because one
known cause (a replay that rebuilds in-memory state differently) might get past by chance after a restart, so the
console says nothing about restarting; whether a restart is worth trying is the Cadence team's call. Who to call is the team that runs
Cadence for the mission's organization (today, domain).

- **Name for operators:** `Stuck processing` (filters, the cause tag, Technical details' source line). Never
  "replay", "conflict", "partition", "journal", "effect" or "runtime" in visible text; they go in Technical details.
- **Spacecraft names:** up to 3, then "and N more"; one craft leads the title, as in U37/U47. A craft whose
  `name` is null is counted, never shown by id (U25): "EARENDIL-004 and 1 other spacecraft"; all unnamed, "2
  spacecraft". A `storage` item whose only craft is unnamed titles with the pass: `SVA 18:49Z pass · telemetry
  storage is stuck`.
- **Title** (by `path`):
  - (1) pass: `EARENDIL-001 · SVA 18:49Z pass · telemetry storage is stuck` (several craft: `EARENDIL-001 and 2
    others · SVA 18:49Z pass · …`; the pass label as U47).
  - (2) incoming data: `EARENDIL-004 · incoming data is stuck`; several: `Incoming data for 12 spacecraft is stuck`.
  - (3) timed actions: `EARENDIL-004 · timed actions are stuck`; several: `Timed actions for 4 spacecraft are stuck`.
- **What stopped** (first body line, by `path`):
  - (1) "Cadence stopped storing this pass's telemetry, so EARENDIL-001's alarms and current values aren't updating."
  - (2) "Cadence stopped processing incoming data for 12 spacecraft: EARENDIL-004, EARENDIL-005, EARENDIL-009 and 9
    more. Their telemetry isn't stored, and their alarms and current values aren't updating." (One craft: "…for
    EARENDIL-004. Its telemetry isn't stored, and its alarms…")
  - (3) "Timed actions for 4 spacecraft aren't running: EARENDIL-004, …"
- **Who's affected, `processing` and `timer`** (api's shape, 11-17): `spacecraft_ids` is the craft known to be
  affected and can undercount, so these paths never claim an exact set (U20). Their titles name nobody:
  `Incoming data is stuck` / `Timed actions are stuck`. The what-stopped line then says, by what's known (review of
  fe-ops' build, 11-17):
  - one craft: "It affects EARENDIL-009, and may affect others."
  - two or more, all named: "It affects at least 2 spacecraft: EARENDIL-004 and EARENDIL-005."
  - some unnamed, or more than 3: "It affects at least 3 spacecraft, including EARENDIL-004 and EARENDIL-005." (up
    to 3 names, however many are named: "…at least 3 spacecraft, including EARENDIL-004."; never "1 other
    spacecraft, and may affect others"). A name never breaks at its hyphen when the line wraps.
  - one unnamed craft only: "It affects at least 1 spacecraft." None known: "It isn't known yet which spacecraft it
    affects."
  - `storage` (one pass) keeps the named title above; with several craft its line reads "…so alarms and current
    values for this pass's spacecraft aren't updating."
- **Why** (second line, all paths): "It's a fault in Cadence, not in this mission's setup or data. Cadence retries
  by itself and hits the same fault each time: 14 tries since 03:10Z, the last at 03:52Z." (`occurrences`, `since`,
  `last_seen`; drop a clause whose field is null, U20.) For (3) the retries come only when new data or a timed
  action comes due (api: at most about every 30 s), and the same sentence holds. There's no restart loop and no
  given-up state (api, 11-17).
  - (3) stopped at start (domain's #99 check, lead 11-17; api's `stopped` signal): nothing counts tries, so the
    why line has no counts: "It's a fault in Cadence, not in this mission's setup or data. It stopped while
    starting up and won't start again until Cadence is fixed." Meta `STOPPED · SINCE 03:10Z` (no TRIES). The
    what-stopped and what-to-do lines are unchanged.
    - By `stopped_while` (api, #99 R1, 11-17): `starting` as above; `applying`: "…It stopped while applying a
      configuration change and won't start again until Cadence is fixed."; null: "…It stopped and won't start
      again until Cadence is fixed." Since an apply that trips leaves the configuration unapplied, U38's runtime
      item can now carry `stuck_processing_id` (tag `STUCK PROCESSING`) when that's its cause.
- **What to do** (third line): "Tell the team that runs Cadence for you, and send them the details. Nothing in
  the console fixes this." No restart line (see above).
  - `Copy details` is a quiet button (it copies, it doesn't navigate): the item's Technical details as plain text
    (source, path, unit, spacecraft, pass, since, last seen, occurrences, buffer, error). Afterwards "Copied"
    for 2 s in a live region; if the clipboard is blocked, "Couldn't copy. Select the Technical details instead."
    It changes nothing on the server.
- **Buffer, (1) and (2)** (the U47 word "buffer", never "journal"; bytes with the console's formatter):
  - Filling: "Incoming telemetry is kept in Cadence's buffer meanwhile: 3.3 of 8.6 GB used. Once it's full, new
    telemetry is lost." Meta `BUFFER 38% · SINCE 03:10Z · 14 TRIES` (the % rounds down, so it never reads 100% before it's full).
  - Dropping (the urgent state, crit ◆, sorts first): "Cadence's buffer is full, so new telemetry from these
    spacecraft is being lost." (`storage`: "…new telemetry from this pass is being lost.") Then "Telemetry received before 04:40Z is kept." (`dropping_since`, when sent;
    else "Telemetry already received is kept.") Meta `BUFFER FULL · LOSING NEW TELEMETRY`.
  - Otherwise the mark is caution ▲.
- **Acknowledge** (operate_mission; without it, in the sheet only, never on the row: "Operators acknowledge
  this."): an optional note, placeholder
  "Who you told, e.g. domain at 03:18Z". After it: "Acknowledged by Mira K. at 03:20Z: told domain at 03:18Z." (no
  note: "Acknowledged by Mira K. at 03:20Z."). The row stays listed, sorted last in its priority (U31), with
  `ACK MIRA K.` in the meta. The dropping state un-sorts it again: frames being lost is new.
  - api (11-17): the note is plain text, 500 characters at most (`acknowledged_note`, with `acknowledged_by` and
    `acknowledged_at`). When dropping starts after an ack, the item is open again and keeps the ack; the line reads
    "Acknowledged by Mira K. at 03:20Z, before new telemetry started being lost: told domain at 03:18Z." and the
    meta drops `ACK`, so it can be acknowledged again.
  - Acknowledged again after that (fe-ops, 11-17): the line shows only the newest ack, as the first form. The
    earlier one belongs to the audit, not the row, so api sends only the latest.
  - Fields: `occurrences`, `first_seen_at`, `last_seen_at` back the why line; `journal_used_bytes` /
    `journal_max_bytes` back the buffer line.
- **Row and sheet** (fe-ops' split, 11-17; ApListRow has one sentence):
  - Row sentence: the what-stopped line; while dropping, the dropping line instead (the urgent fact; the title
    already says what's stuck). The ack stays out of the sentence: it's `ACK MIRA K.` in the meta.
  - Row action: `Acknowledge…` for operators while it isn't acknowledged (primary when dropping); otherwise
    `Details`. Both open the same side sheet.
  - Sheet: titled with the row's title, then `Stuck processing` as a small label under it (the kit's sheet has no
    kicker slot; fine as built). In order: what stopped, why, buffer, what to do,
    the ack line if any (so whoever takes over sees who was told), `Copy details`, Technical details (a
    disclosure), then for operators the note field and `Acknowledge`; without operate_mission "Operators
    acknowledge this."
- **Resolved** (system, U31: the action only): the row fades for 5 s with `Resolved: telemetry storage resumed` /
  `Resolved: processing resumed` / `Resolved: timed actions running`. Frames lost while dropping stay as U47's
  `frames_dropped` item.
- **Cause tag on the folded rows** (U37 telemetry not stored, U47 buffer filling, U38 runtime not applied, for the
  same unit): tag `STUCK PROCESSING`, rows shown under this item. A tagged U37 row has no `Retry storing`, not
  even disabled: its action is `Review` (the contact drawer), and its evidence already says why (below).
  - api (11-17): `stuck_processing_id` is set only when the item's own cause is this conflict. U37 gains
    `failure_kind: "replay_id_conflict"`, evidence "1,204 entries (3.4 MB) are on disk. Cadence can't store them
    until the stuck processing is fixed." (no retry sentence, no "Next try"); it folds by its own key, as U37's
    other kinds. U38 carries it only if its reason can be the conflict (api checks at build).

### U85 · A transport's direction: one set of words (ux, 11-17) (api / fe-setup)
The Transports list says `Downlink` / `Uplink` / `Both` (`directionLabel`), but the TCP kind's form says `Direction
Capability` with `Inbound` / `Outbound` / `Bidirectional`. The same choice reads two ways, one screen apart. The
operator's words win: a mission team thinks in downlink and uplink, and "capability" adds nothing to the label.

- **Label:** `Direction` (the server's field definition; the field stays `direction_capability`, so values and the
  API don't change).
- **Options** (select, in this order): `Downlink` (`inbound`), `Uplink` (`outbound`), `Both` (`bidirectional`).
- **Help** (the field's description): "Downlink carries data from the spacecraft, Uplink carries commands to it,
  and Both carries each."
- **Everywhere else** the console names a direction it uses the same three words: the list, the change summary,
  the review's diff (through U83's `before_label` / `after_label`, e.g. "Direction: Downlink → Both") and any
  refusal. Never `inbound`, `outbound` or `bidirectional` in visible text; they go in Technical details.
- **U83 follows it:** shown when `Direction` is `Downlink`; "Only a downlink transport can choose its listener.";
  "only a downlink transport that listens can share one" (info line, diff note and server note alike).
- **Who:** api changes the field definition's label and option labels, and writes U83's refusal and note in these
  words. fe-setup needs no code change for the form (KindEditor shows the schema's words); only fixtures and tests
  that assert the old words or U83's earlier "inbound" note (`diff-words.test.ts`) change. No legacy page renders
  this schema, so the server copy is free to change.

### U86 · Items the console can't read (lead's console resilience item; accepted as written, lead 11-17) (fe-ops / lead)
The Now queue and the attention lists decode each item on its own. An item the console can't read (a source this
build doesn't know yet, or a shape it can't decode) is dropped and the rest still show. Dropping it silently would
break U20 and U45's "never silent": a dropped item may be the most urgent thing on the list.

- **The line** (caution, a callout, not a row):
  - One: "This console can't show 1 item. Reload to try again. If it's still missing, tell the team that runs
    Cadence for you."
  - Several: "This console can't show 3 items. Reload to try again. If they're still missing, tell the team that
    runs Cadence for you."
  - Action: `Reload` (quiet button; it reloads the page, which picks up a newer console if there is one).
  - Technical details (disclosure, closed): one line per dropped item, its kind and id as sent (`attention ·
    contact_start · 7f3c…`), or "an item with no readable kind" when even that is missing. Never the payload.
    The same goes to `console.warn`.
- **Where:** at the TOP of the list, above the first row, because a dropped item's priority isn't known. The same
  line, with its own count, in each list that drops something (Now's queue; a pass's attention blocks; the
  resolutions callout).
- **Counts and badges include dropped items:** an open item is open whether or not this console can draw it. Now's
  header reads `6 open · sorted by urgency` with 5 rows and the line for 1. The mobile Now badge and any `/counts`
  total do the same. A count split by priority, source or filter counts only the items it can read, since a dropped
  item's priority and source aren't known.
- **Every item dropped:** the line shows alone. Never the list's empty state ("Nothing needs you"), which would be
  false.
- **It goes** as soon as a read has nothing dropped. A whole read that fails is not this line; it keeps the list's
  own error state.
- **More lists (fe-ops, lead's go, 11-17):** Contacts' schedule panel, Now's Passes panel (A4), Investigate's Passes
  tab and Org Audit's results, each with the line at the top, above the first row or the table.
  - The noun follows the list: "This console can't show 1 pass." / "… 3 passes."; Audit: "… 1 event." / "… 3
    events." The rest of the line is as above. Technical details: `contact · pass-123`; Audit: the event's kind and id.
  - Counts include them, as above. A plan's pass resolutions don't count a dropped pass, since its attention isn't
    known.
  - **Audit export:** the file is built from the events the console could read, so it must say what's missing. The
    export's note, where the size cap already speaks: "3 events couldn't be read, so they aren't in this file."
    Never a silent short file.

### U87 · A group member can't be approved on its own (director's procedure rule; accepted, lead 11-17) (fe-ops / api or api-ops)
Director's rule, now enforced by the product (P0 guard live 11-18 02:15Z; the procedure rule is lifted): a command
that belongs to a command group is approved only through the group's GO/NO-GO, never through the standalone command
request approve, reject or enqueue (ops page or REST), and a standalone create can't name a group. The server's refusal is
the fix (with the P0 result); the console's disable is its reader.

- **Request page:** `Approve` stays disabled, with the A6 reason line under it: "This command is part of a command
  group. Approve it with the group's GO/NO-GO." Beside the line, a link `Open command group` to the group's page.
- **No console surface today** (fe-ops checked, 11-17): the console's only approval write is the group's GO/NO-GO,
  and its request page is keyed by group id. The request-page rule above is for any future surface that approves a
  single command.
- **REST and the legacy ops page:** the standalone approve refuses a group member in the same words. The standalone
  reject says what it does (api, P0 review): "This command is part of a command group. Reject it with the group's
  NO-GO." Whoever owns
  the P0 fix (api or api-ops) builds it.
- **Standalone enqueue** (REST `POST /command_requests/:id/enqueue` and the legacy ops page's Queue; 409
  `command_request_in_group`; #121, ca-ux 11-19): "This command is part of a command group. Its group's GO queues it."
  It replaces the approve line the enqueue reused, which named the wrong act; a correctness fix, so it may change
  although the legacy ops page renders it.
- **Any other standalone action on a group member** (REST `409 command_request_in_group`; the fallback when the
  action is none of approve, reject or enqueue; unreachable today; #121, ca-security's review, ca-ux 11-19): "This
  command is part of a command group. Use its group instead." It names no act, so a future caller never gets
  another act's instruction.
- **Standalone create naming a group** (REST): "Not created: this request names a command group. A group's commands
  are submitted with the group."
- **Not here:** the group's own GO/NO-GO is unchanged; this only closes the standalone way round it.

### U88 · Refusal `mission_model_revision_not_in_catalog`: a revision the catalog doesn't list (domain's interim guard, strict form; lead, 11-17) (domain / api / fe-ops)
Some imports leave a compiled revision that no catalog revision names: the console's Reimport, a REST import run on an
existing file without asking for a catalog revision, possibly a failed catalog-revision step (domain, 11-17). It was
never listed, so the words say "doesn't list", never "no longer lists", and never "reimport". Domain's guard refuses
approving it and requesting its activation; **Reject stays allowed** (lead, domain), so it can be cleared from the
queue. Rare: dev had none at 13:19Z. Per U65, visible text never says "mission model" or "model"; the revision ids
and the code go in Technical details. The refusal carries no catalog rev and none can be found, so none is named.

- **Before a click** (api's approval read, new nullable `cannot_approve_because: "not_in_catalog"`;
  `cannot_decide_because` unchanged): `Approve` disabled, with the A6 reason line "The catalog doesn't list this
  revision, so it can't be approved. To approve it, import its file as a new catalog revision. Reject it to clear it
  from the queue." Link `Open the catalog` (Setup › Catalog). `Reject…` stays as U65 has it (reason required).
- **Approve refused** (409, U65's refusal list): "Not approved: the catalog doesn't list this revision. To approve it,
  import its file as a new catalog revision." Same link. Never the 503 words.
- **Activation request refused** (422 reason): "Not requested: the catalog doesn't list this revision. Request
  activation of a revision the catalog lists instead." Same link.
- **Apply or Retry apply** (U41's error sentence, `retryable: false` per domain): "The catalog doesn't list the
  revision this request names, so it can't be applied." Then U41's request-again sentence; no `Retry apply`.
- The panel or form stays as it was after a refusal; nothing was recorded.
- **Not here:** whether such revisions show in the approval queue at all is domain's question to the director.

### U89 · The four-eyes record in Audit and change history (P3; dashboards' shape diff, lead and director accepted the design, 11-17) (dashboards / api / domain / fe-ops)
P3 makes every approval gate keep its own record. These are the words for what readers show. Server-made sentences
stay server-made; the lines below are what they should say. No digest is ever shown (P3 §3).

- **`not_required`** (the policy needed no second person). The setting is "Approval for changes and app
  activations", option `Applies without approval`, so the sentence names it in those words, never "direct":
  - Change set: "Applied r10 without a second person's approval, as this mission's setting allows." Activation:
    "Applied <the activation's summary> on 11-17 09:12Z without a second person's approval, as this mission's
    setting allows." (#227 3ce344243). That line only once the apply succeeded, and its time is when the apply
    finished (api's `execution.finished_at` on L10's list and detail, set on succeeded or failed, null while
    applying and after a resume until it finishes; ships with api's (B) set, read as optional), never the decision's: a held apply can resume
    later. Without that time, the line has none (U20). While it's applying, after it failed, or before it starts,
    the decision line is "No second person's approval was needed, as this mission's setting allows · 11-17
    09:12Z" (the decision's time), and the apply state and U41's words below it say the rest (never "Applied"
    before it has).
  - The setting's words are the server's (`console_settings.ex`), shown by Settings as they are.
  - Commanding has no one setting; the command policies (People › Command policies) decide, and the console already
    says "No second GO was needed; it was released at submit." So: "Released <group> at submit without a second GO:
    none of this mission's command policies needed one."
  - Provider changes have no visible setting; Now says "Accepted by the mission's policy at T." So, with the actor
    `Cadence` (never an id): "Accepted <the change in words> by the mission's policy, without a person's approval."
- **Admin mode:** a neutral tag `ADMIN MODE` right after the actor's name, wherever `admin_mode` is true (Org Audit
  rows, change history, approval lines). Its title and accessible name: "Acting as a platform admin, not as a
  member of this organization." Admin Audit's rows carry the same tag, so its sentence drops "(admin mode)": "Approved
  change set v3 in Earendil Ops", not both. `false` shows no tag. Audit's CSV export (#228) adds
  `Admin mode` (Yes / No; blank on rows that aren't decisions), `Subject`, `Subject id`, `Subject version` (raw:
  the export is data), and for governance rows `Before` / `After` in the option words (U96), plus `Mission sets its own` (Yes / No; mission rows, only when override changed) and `Missions may override` (organization rows, only when it changed). On screen the server
  sentence already names the subject and the change, so nothing more shows.
- **Every field is always recorded** (DECISIONS #112, director 11-18): `admin_mode` is never null, `subject` and
  `separated_from` are always present, and `applied_by` is whoever ran the apply on every row. Dev missions are
  recreated, so there are no pre-cutover rows and no "Not recorded" words.
- **Audit kinds:** `activations` → `Activations`, `provider_changes` → `Provider changes` (add both to `kindLabel`).
- **Contact plan events** (dashboards: `contact plan vN` is the number the console shows as `R41`): every contact
  plan event names it as the console does, "Submitted plan R41 for 11-16", "Approved plan R41 for 11-16", in place
  of "contact plan v41". The day is derived as the console derives it (the plan's window, first pass); api builds
  it. If no day can be derived: "Submitted plan R41".
- **Change history** (Setup › Changes › revisions):
  - Table: `By` becomes `Submitted by` (`submitted_by`), plus a new `Approved by` column: the approvers' names, or
    `Not needed` for `not_required`.
  - Revision header: "Submitted by Mira K. · approved and applied by Ana R. · 11-17 09:12Z" (approver = applier). If
    they differ: "· approved by Ana R. · applied by Owen P.". Direct: "Submitted and applied by Mira K. · 11-17
    09:12Z · no second approval needed".

### U90 · A comparison with nothing to compare against (director, via lead, 11-17; amends U65) (domain / api / fe-ops)
A mission's first catalog revision can now be compared with no earlier configuration. The report then passes with
`against: null`, every declaration counts as added, and replay is `not_run`. That pass checks nothing like for like,
so the panel must never read it as one. The read already has `against` nullable (the console decodes it); today a
null `against` reads "Comparison passed", which is the wrong claim.

- **Verdict line** (the Approval panel, in place of `■ Comparison passed against rev 3`): `▲ Not compared: there's no
  earlier configuration` (caution). Never "passed", never the pass glyph, whatever `passed` says.
- **Callout at the top of the panel** (caution, above the replay callout, never folded away): "There's no earlier
  configuration for this mission, so there was nothing to compare it with. All 1,284 declarations are new, and
  none has been checked against an earlier version." The count is the sum of the sections' added; without one,
  "Every declaration is new, and none has been checked against an earlier version."
- **Panel meta:** `NO EARLIER CONFIGURATION` in place of `AGAINST REV 3`.
- **Report body:** unchanged: "Commands: 412 added", and so on.
- **Above `Approve rev 1`:** "Approving it accepts every declaration as new." The button and Reject stay as U65.
- **Short form, everywhere the summary shows** (the decided line's `Show report`, the catalog row's detail, the
  audit): "not compared: no earlier configuration". Audit: "Approved catalog rev 1 (not compared: no earlier
  configuration; replay not run)".
- **Rule for the console** (domain, 11-17): `against: null` on a report means exactly this case. The baseline is
  the previous import, else the revision most spacecraft run; only when neither exists is it null. No new field,
  and no split by reason: the approver needs the same words either way. "No comparison has been run yet" (U65) is
  a missing report, not this.

### U93 · Applying a change set on a mission with nothing running (domain's design, via lead, 11-17) (api / fe-ops)
On a mission with nothing running, a change-set apply saves the changes but makes no generation and starts nothing.
A mission's first run comes from each spacecraft's configuration (Review, then Activate). Today neither the preview
nor the Apply aside says so, and after apply the outcome reads "r1 is active · 2 changes.", which suggests it runs.

- **Before (preview and the Apply aside, info, above the Apply button):** "Nothing is running on this mission yet,
  so applying saves these changes and starts nothing. Each spacecraft starts when its configuration is reviewed and
  activated."
- **After (the outcome line, nominal):** "r1 is saved · 2 changes. Nothing is running on this mission yet, so
  nothing started." Not "is active", and no runtime clause.
- **Signal:** only when api's preview read (and the apply result) says nothing is running on the mission, never
  inferred from the submit result's `not_applicable` alone, which also covers changes the runtime doesn't use.
  api's key (11-17; named by lead): `has_active_configuration`, a
  boolean, never null, on the preview read and on the apply result; false gives these lines. It's false when the
  mission has no active activation; it's about an activation existing, not the runtime's health (U91's banner covers that). fe-ops reads
  it first.
- Once anything runs, the line goes; the runtime clauses (U38's verbs) take over as today.

### U92 · Refusal `command_group_members_changed`: the group changed after it was submitted (P0 fix; api-ops 8f60ccd94) (api-ops / fe-ops)
The GO (and GO with exclusions) is refused with 409 when the group's member rows no longer match the count it was
submitted with. With the P0 fix nothing on a product path can change a submitted group, so this is defence in depth
and should never fire; when it does, something went round the product. NO-GO, send back and abort still go through.

- **The line** (the GO/NO-GO panel, crit, in the "Not released" pattern): "Not released: this group's commands
  changed after it was submitted (12 then, 13 now), so it isn't what was reviewed. Give it NO-GO and submit the
  commands again. Tell the team that runs Cadence for you: a group shouldn't change after it's submitted."
  - The counts come from the 409's `submitted_member_count` and `current_member_count`; without both, the bracket
    is left out.
- **After it:** the panel stays open, `GO` disabled with this line as its A6 reason, and `NO-GO` is the way out.
- **Up front** (#120, ca-ux 11-19; it was "Not up front" until the read had a flag): the group read carries
  `members_changed` (true / false) with `submitted_member_count` and `current_member_count` (both or neither, as on
  the 409). When it's true, `GO` and `GO excluding…` are disabled before a click, with the line as their A6 reason,
  less "Not released:" since nothing was tried: "This group's commands changed after it was submitted (12 then, 13
  now), so it isn't what was reviewed. Give it NO-GO and submit the commands again. Tell the team that runs Cadence
  for you: a group shouldn't change after it's submitted." The reason sits muted under the GO buttons and as their
  description. U92's line has no "nothing was released" ending to drop. `NO-GO`, send back and abort stay enabled.
  Without the counts the bracket goes.
  - The read computes the flag with the same function as the GO refusal (api-ops), so the two never disagree. It
    compares counts, not which commands, so the words say only that the commands changed.
  - When the flag is missing or null (an older server, or a group not awaiting a decision: the server always sends
    the three fields, all null together outside `approval_pending`, api-ops 11-19), the console blocks nothing up
    front and the 409 stays the backstop; it never guesses from its own member list (U20). A null count is a missing
    one: no bracket.
  - In the decide panel (radio options and one commit), the reason replaces the GO options' "N targets · N uplinks"
    description (its uplink count is the submitted one), and choosing either GO option gives the commit that reason,
    the same path as after the 409 (ca-ux to ca-engineer, 11-19).
- **Nowhere else:** it isn't on Now or in the audit by itself; only at GO.

### U91 · The runtime can't verify its configuration: telemetry, passes and who fixes it (11-17 Earendil incident; amends U38) (api / domain / api-ops / fe-ops)
Today's incident was U38's `spec_mismatch` with `reason_detail: binding_set_content_sha256`: after a restart, the
stored activation's binding-set hash didn't verify under the running code, so nothing ran and no pass could start.
It's U38's item (same title, banner, P1, system close); this entry changes its words and adds what happens to
telemetry. Facts: api, domain, api-ops (the telemetry cases from reading the code, not a live run).

- **`spec_mismatch` evidence** (replaces "What's running doesn't match it."): "Cadence can't verify this mission's
  active configuration, so it won't run it." When `applied_generation` isn't null, it adds "It's still running the
  earlier one."
- **Who fixes it** (domain: the mission can't; a code fix or a rollback restart can): replaces the retry sentence
  for `spec_mismatch`: "It's a fault in Cadence, not in this mission's setup. Tell the team that runs Cadence for
  you; nothing in the console fixes it." No `Review` primary, and never a suggestion to activate a configuration
  again: that would re-record the hash and hide the fault (director). The banner's added sentence becomes " It needs
  a fix in Cadence." for `spec_mismatch`, and so does the Changes outcome after an apply ("r6 is active, but the
  runtime hasn't applied it yet. It needs a fix in Cadence."). Never "support is working on it" (U20: the console can't know that, and
  there's no support desk, U84). `reconcile_crashed` is a Cadence fault too (api confirmed: the generation couldn't be built), so it
  takes the same who-fixes sentence and banner sentence, and no `Review`; `runtime_not_running` and `apply_failed` keep U38's "Cadence keeps
  trying every 30 s." No reason that reaches this row is the mission's to fix.
- **Telemetry, only while nothing runs** (`applied_generation` null; passes can't start then):
  - "Until this is fixed, passes can't start, so their telemetry isn't received. Cadence keeps trying to start a
    pass while its window is open, so it receives telemetry from the moment this is fixed."
  - `next_pass` (api's new optional key; within 2 h or in progress):
    - Not started: "The next pass starts at 15:10Z: EARENDIL-004, SVA."
    - In progress and started before this (`started: true`): "EARENDIL-004's SVA pass started before this, so its
      telemetry is kept and processed once the runtime is back." (U47 covers the buffer filling.)
    - In progress, couldn't start: "EARENDIL-004's SVA pass couldn't start, so its telemetry isn't being received."
      It also has its own U45 row (`no_runtime_spec`).
- **U45's `no_runtime_spec` is two causes:** no configuration activated (the mission fixes it, from the
  spacecraft's configuration, not Changes: U45's row, corrected after domain's review 11-17), and a
  configuration Cadence can't verify (today's incident: Cadence's to fix). For the second, the pass row reads
  "Cadence can't verify this mission's active configuration, so this pass can't start. It's a fault in Cadence: tell
  the team that runs Cadence for you." with `Open pass`, never `Open Changes`. The pass detail (Contacts drawer) adds
  "Cadence keeps trying while the window is open, so the pass receives telemetry from the moment this is fixed."
  and has no action. api's key: `reason_detail` `configuration_unverifiable` (this form) / `no_configuration` and null (U45's corrected words and `Open
  spacecraft`). The field that failed stays in `failure_message`, for Technical details.
    - The forms key on api's final shape: not started = `in_progress` false; started before = `started` true;
      couldn't start = `in_progress` true and `started` false.
    - Nulls: no `spacecraft_name`, the line drops the name ("The next pass starts at 15:10Z: SVA." / "The SVA
      pass started before this, …"), never an id (U25). No `station`: "The next pass starts at 15:10Z:
      EARENDIL-004." / "EARENDIL-004's pass …". Neither: "The next pass starts at 15:10Z." The station reads its
      `code`, else its `name`, as U47's pass label. `reason_detail` goes in Technical details only.
  - While the earlier configuration still runs, passes start on it, and no telemetry line shows.
- **Resolved:** the row "Resolved: runtime started"; the banner as U38, "Telemetry processing resumed at 14:26Z."

### U94 · A spacecraft's configuration in the console: save, request, activate (director's (B), 11-17; api's shape diff; ported from the host) (api / domain / fe-ops)
The per-craft configuration workspace moves from the host's spacecraft page into the console's (Setup › Spacecraft ›
EARENDIL-004 › `Configuration`). Approve and reject stay on L10 (Setup › Changes › activations), where these
requests already list as "Spacecraft configuration for EARENDIL-004". Field words reuse U40's; the host's other words
are re-said here. fe-ops proposes the layout (the host's four sections: Overview, Catalog & applications,
Communications, Changes) for ux's look.

- **Never in visible text:** generation, binding or "bind", token, "legacy configuration", "active fleet
  configuration", "runtime application", ids. They go in Technical details.
- **Versions:** the craft's configuration reads `v4` ("EARENDIL-004's configuration v4"), never `r4`, which is a
  change-set revision on Setup › Changes (api: versions count 1, 2, 3… per craft). An active `version` of 0 (set
  before this workspace) reads `Active` with no number.
- **Status tag** (the section header; state only, fe-ops 11-17, since tags uppercase): `ACTIVE` / `DRAFT SAVED`
  (caution while it differs from active) / `UNSAVED EDITS` (caution) / `NOT SET UP` (`active` null). The versions go
  in the header line, mono: "EARENDIL-004's configuration · v3 active · v4 saved" (only the parts that exist).
- **Not set up** (`active` null): heading `Set up EARENDIL-004`, and an info line "Nothing runs for EARENDIL-004
  until its configuration is activated." While telemetry is off it adds ", and nothing is decoded until a change
  set turns telemetry on." (ux review of fe-ops' shots, 11-17).
- **Steps before it can be sent** (the host's setup issues):
  - "Choose a catalog revision": "Pick the catalog revision that matches EARENDIL-004's flight software."
  - "Choose what to decode": "Pick the packet source and the APIDs Cadence decodes for EARENDIL-004."
- **Fields:** the catalog revision reads `catalog rev 14` (U65), from the server's `number` (catalogs rows) or
  `catalog_number` (packets read), never parsed from a label, with `Choose…` / `Change…`; Telemetry and
  Commanding use U40's labels, help and on/off sentences; handled APIDs use U40's chip list; framing keeps the
  protocol terms (TM, AOS, USLP, TC, frame and header sizes), since the people setting it know them.
- **Save:** `Save draft` (busy `Saving…`) and `Discard edits`. Saved: "Saved as v4. v3 stays active until v4 is
  activated." (first: "Saved as v1. Nothing runs until it's activated.").
- **Someone else saved meanwhile** (`spacecraft_configuration_changed`, and `external_changes`): a caution panel
  "Someone saved EARENDIL-004's configuration after you started editing. Your edits are kept." with rows "Saved: TM
  → Yours: AOS", and `Use the saved version` / `Keep my edits`.
- **Comparison** (the Changes section): columns `Setting`, `Active`, `Draft`; no changes: "The draft matches the
  active configuration."; nothing active: the line "Nothing is active yet, so every setting is new." (U90) and the
  Active column is left out, not a column of dashes. The Changes tab carries the count, `Changes 2`.
- **Send it** (by the mission's approval setting, U89's words; the source line "Mission setting" / "Organization
  default" / "Set by the organization", with `Approval settings`):
  - Applies without approval: `Activate v4`.
  - Needs a second person's approval: `Request approval for v4`.
  - Disabled reasons (A6), first that applies: unsaved "Save the draft first."; someone else saved "Choose which
    version to keep first."; steps left "Finish the steps above first."; nothing changed "The draft matches the active
    configuration."; already waiting "v4 is waiting for approval."; `can_request` false "You can't activate
    configurations on this mission."
- **Results** (submit's `state`):
  - `approval_pending`: "Sent for approval. Another person approves v4 in Setup › Changes." with `Open request`
    (the L10 page).
  - `active`: "v4 is active on EARENDIL-004." then the runtime as U38's verbs say (applying / applied / not applied).
  - `needs_review`: "v4 is approved, but Cadence couldn't confirm it was applied yet." with `Open request`; U41 and
    U38/U91 say the rest, never "check runtime status".
- **The request's state, in the workspace** (`review.state`, with `Open request` for who and when, U29):
  approval_pending "v4 is waiting for approval."; approved and active as above; rejected "v4 was rejected. Change
  the draft and send it again."; withdrawn "The request for v4 was withdrawn."; superseded "Replaced by a newer
  request."; stale "EARENDIL-004's configuration changed after v4 was sent, so it can't be approved. Send it again."
- **Refusals** (submit and save):
  - `spacecraft_configuration_review_stale`: "Not sent: EARENDIL-004's active configuration changed since you loaded
    this. Check the comparison and send it again."
  - `activation_policy_changed`: "Not sent: the mission's approval setting changed. Check it and send it again."
  - `spacecraft_configuration_review_unavailable`: "Not sent: save the draft and choose which version to keep
    first."
  - `spacecraft_catalog_required`: "Not sent: choose a catalog revision first."
  - `spacecraft_packet_inputs_required`: "Not sent: telemetry is on for EARENDIL-004, so choose a packet source and
    the APIDs to decode first."
  - `spacecraft_configuration_changed` (save, stale token): the panel's sentence under "Someone saved…" above; as a
    plain message: "Not saved: someone saved EARENDIL-004's configuration after you started editing. Your edits are
    kept; choose which version to keep."
  - `catalog_revision_not_found` (404, the packets read): in the picker, "This catalog revision isn't in the
    mission's catalog any more. Choose another." and it can't be chosen.
  - `invalid_params` with `document` (a malformed draft, a console fault): "Not saved: Cadence couldn't read this
    draft. Reload and try again." With `section` or a bad `intent` (never sent by the console): the generic line.
  - The console routes' messages are these words. The host's page keeps its own copy until it's deleted (the
    legacy host still renders it), so api sets them on the console routes only.
  - `mission_model_revision_not_approved`: "Not sent: catalog rev 14 isn't approved yet. An org admin approves it in
    Setup › Catalog first." with `Open rev 14` (U65). Several: "Not sent: catalog revs 4 and 5 aren't approved yet.
    An org admin approves them in Setup › Catalog first."
  - `spacecraft_catalog_set_by_profile` and `spacecraft_catalog_unavailable` can also come from a submit: there they
    open "Not sent:" with the rest of the sentence unchanged.
  - `forbidden`: "You can't change EARENDIL-004's configuration." `not_found`: "This spacecraft isn't on this mission."
    `invalid_params`: the field's own error.
  - `spacecraft_catalog_set_by_profile`: "Not saved: EARENDIL-004's profile sets its catalog revision. Change it on
    the profile, through Setup › Changes." with `Open profile`.
  - `spacecraft_packet_input_unavailable`: "Not saved: the packet source you chose isn't available to EARENDIL-004
    any more. Choose another."
  - `spacecraft_configuration_catalog_not_loaded`: "Not saved: Cadence couldn't load catalog rev 14's telemetry
    packets. Try again, or choose another revision."
  - `spacecraft_source_limit_exceeded` (the snapshot and submit): "EARENDIL-004 has more packet sources than one
    configuration can carry, so it can't be shown or sent. Remove some in Setup › Comms." On the snapshot it's the
    section's error state, with `Open Comms`.
  - `spacecraft_catalog_unavailable` (the packet choices): in the picker, "Catalog rev 14 can't be used for
    EARENDIL-004." and the revision can't be chosen. On save or submit: "Not saved: catalog rev 14 isn't one of
    this mission's catalog revisions. Choose another."
  - `spacecraft_not_found` (404): "This spacecraft isn't on this mission." (no snapshot, so no name; never the id
    or a cached name, U20/U25). The `forbidden` line keeps the name only when a snapshot loaded, else "You can't
    change this spacecraft's configuration."
  - Any other code: "Not saved." / "Not sent." plus the code in Technical details (U20); `spacecraft_configuration_
    pending` doesn't reach these routes (api).
- **On L10, for these requests:**
  - `What changes` panel from `configuration_changes` (rows `label: before → after`, e.g. "Catalog revision:
    catalog rev 13 → catalog rev 14"); a first start (`before` null) reads as U90: "Nothing is active for
    EARENDIL-004 yet, so every setting is new." and the rows show only the new value. Switches are never rows
    (#109). api's labels and values (sent as text; a missing value is `Not set`):
    - `catalog_revision_id` → `Catalog revision`, "catalog rev 14" (U65).
    - `telemetry_source_endpoint_id` → `Packet source`, the source's name (never an id, U25). A source that's set but
      whose name the server couldn't look up (`name` null; #415, #235): `Unknown packet source`, with the id in
      Technical details. It isn't `Not set`, which means no source was chosen.
    - `handled_apids` → `Handled APIDs` (U40's name, as the workspace has it), the APIDs comma-separated up to 8, else "14 APIDs"; none: `None`.
    - `protocol.downlink` / `.uplink` → `Downlink protocol` / `Uplink protocol` (TM, AOS, USLP, TC);
      `frame_size` → `Frame size`, `secondary_header_length` → `Secondary header`, `insert_zone_length` →
      `Insert zone`, `ocf_length` → `OCF` (each "1,115 bytes"); `truncated_primary_header` → `Truncated primary
      header`, Yes / No.
    - The crit telemetry-off warning on this panel needs the craft's telemetry switch value on the L10 detail too.
  - **Fleets (#235; api, lead, ux settled 11-18):** a request can review up to 500 craft, so the panel reads api's
    groups: `{groups: [{rows, first_start, telemetry_enabled, count, spacecraft: [{spacecraft_id, name}] ≤100}],
    total}`; a group is craft whose rows, first start and switch are exactly equal (server-computed), every group is
    sent, and a group's full names page from `…/configuration-changes?group=N&offset=K`. Nothing is cut, so Approve
    is never the only way past a craft the approver can't see.
    - Heading `What changes · 312 spacecraft` (one craft: `What changes`, and the panel reads as above).
    - Summary, from the groups' counts, each only when nonzero: "300 spacecraft change: Catalog revision (300),
      Handled APIDs (12)." / "12 have no changes." / "5 start for the first time."
    - Crit, fleet form: "Telemetry is off for 3 of the 312 spacecraft, so once this is active they start but
      decode nothing: no live values, alarms or history. Turn telemetry on with a change set first." with `Open
      Operation`.
    - Each group (changed groups in api's order, the no-change group last): heading "300 spacecraft" (count 1: the
      craft's name); names "EARENDIL-001, EARENDIL-002, EARENDIL-003 and 297 more" with `Show all 300`; a `TELEMETRY
      OFF` tag when its switch is off; first start "Nothing is active for these spacecraft yet, so every setting is
      new."; then its rows.
    - Decided requests (api, lead OK): `configuration_changes` is null once decided, so no panel and never "no
      changes". In its place, a muted line: "What changes is shown only while a request waits for approval. To see
      what runs now, open the spacecraft's configuration." with `Open configuration` (one craft) or `Open
      spacecraft` (a fleet: Setup › Spacecraft).
    - The rows-[] group: "No changes on 12 spacecraft: EARENDIL-010, EARENDIL-011, EARENDIL-012 and 9 more." with
      `Show all`. Every group lists 3 names before "and N more". One craft with no changes: "Nothing changes for
      EARENDIL-004: this configuration matches what's active."
    - `Show all` failing: "The names couldn't be loaded. Try again." (caution; the button stays).
    - The fleet form's crit action is `Open spacecraft` (Setup › Spacecraft); `Open Operation` is the one-craft
      form's (fe-ops 98d8f7688).
    - A group or row the console can't read (U86): the U86 line at the top of the panel ("This console can't show
      2 changes." / for groups, with the exact number `total` minus the readable counts: "This console can't show
      what changes for 12 spacecraft.", then U86's Reload sentence and Technical details). With an unreadable
      group the summary adds "These counts cover 300 of the 312 spacecraft. This console can't show what changes for
      the other 12."; the telemetry-off crit adds "This console can't show whether it's on for the other 12.", or,
      with no off line, a caution line of its own: "This console can't show whether telemetry is on for 12 of the
      312 spacecraft." (dashboards' review, 11-18). `Approve` is disabled (A6): "Part of what changes can't be
      shown in this console, so it can't be approved here. Reload to try again. If it's still missing, tell the
      team that runs Cadence for you, or reject it." `Reject` stays enabled.
  - Approve refused stale (409, nothing recorded): "Not approved: EARENDIL-004's configuration changed after this was
    requested, so it isn't what was reviewed. The requester sends it again."
  - Separation, the requester (403 `activation_self_approval_forbidden`, the console code since #275, as
    `contact_plan_` and `mission_model_`; it was `self_approval_forbidden`; no `details`; nothing recorded, so U95's
    ending): "Not approved: you requested this, so another person approves it. Your approval wasn't recorded." The
    decide panel already shows the requester `Your request` and no Approve, so this line is the server's backstop.
    It replaces the older "You requested this. Someone else approves it." on the refusal. Authors aren't this code:
    since #236 they get `activation_approver_authored_content` and `activation_approver_authors_unknown` (the two
    bullets below), so there's no `details.rule` and no author or fallback line here (#275, ca-ux 11-19).
  - Authored content (#236, 403 `activation_approver_authored_content`, `details.spacecraft` ≤5 names and
    `spacecraft_ids`; nothing recorded, so U95's ending): one craft "Not approved: you saved EARENDIL-004's
    configuration in this request, so another person approves it. Your approval wasn't recorded."; several "Not
    approved: you saved the configurations of EARENDIL-004, EARENDIL-009 and 3 more spacecraft in this request, so
    another person approves it. Your approval wasn't recorded." (3 names, then "and N more"); no names: "Not
    approved: you saved part of what this request activates, so another person approves it. Your approval wasn't
    recorded." Up front (#240: `cannot_approve_because` `authored_content` | `authors_unknown` on the detail;
    `can_decide` stays true, so Reject stays on): Approve is disabled, and its reason (muted, under the Decide
    panel's intro line, and as the button's description) is the same sentence without "Not approved:" and the
    ending; for authors_unknown it keeps "Reject it so the requester…". A reason the console doesn't know: "You
    can't approve this request, so another person approves it. Reject it if it shouldn't wait." with the code in
    Technical details (never the authors_unknown line, U20).
  - Authors unknown (#236 fail closed, lead 11-18; 403 `activation_approver_authors_unknown`, nothing recorded): "Not
    approved: Cadence can't tell who saved this configuration, so it can't check that you weren't one of them.
    Your approval wasn't recorded. Reject it so the requester can send it again; if it keeps happening, tell the
    team that runs Cadence for you." The legacy approve paths keep their generic text (no host copy, lead).
- **The mission-wide decom app after this** (lead, 11-17): once any craft's configuration is saved here, the
  telemetry_decom app's Save is closed for the mission. It shows disabled with: "Telemetry decoding is now set per
  spacecraft, in each spacecraft's Configuration, so it can't be saved here." and `Open spacecraft` (Setup ›
  Spacecraft).
- **The interim lines point here once it ships:** U45's `no_configuration` reads "…Review and activate
  EARENDIL-004's configuration to start it." with `Open configuration`; U93's before-line keeps its words, adding
  `Open configuration` when the preview names one spacecraft.
- **Telemetry and Commanding switches: change sets own both, always** (DECISIONS #109; lead, director agreed
  11-17; one owner per setting, since what runs is the configuration document). The workspace shows both read-only, from the snapshot's per-switch owner and value (api),
  each with `Open Operation` (U40's panel, where they're staged):
  - Set by a change set: "On · set by r7." / "Off · set by r7." (the change-set revision that set it; without it,
    "On · set through Setup › Changes.").
  - Never set: "Off · no change set has turned it on yet. Turn it on in EARENDIL-004's Operation panel; it applies
    with the next change set."
  - Keys (api): `switches.telemetry_enabled` / `switches.commanding_enabled`, each `{value, set, revision}`. `set`
    false gives the never-set line; `set` true with `revision` gives "set by r7", without it "set through Setup ›
    Changes".
  - The draft takes the switch values, and switches never show as a change in the comparison: a change set that sets
    one also moves the running configuration, so draft and active can't differ (and neither document carries the
    switch keys). The crit telemetry-off warning keys on the switch's value and shows on Save as well as on Activate /
    Request approval.
  - No "unset while running on" state: after #109 an unset switch runs off, and the only older data (Earendil's
    craft) is aligned before this ships (lead, 11-18, under the breaking-changes direction), so `switch.active` and
    its line were dropped.
  - A draft that sends either switch (422, API clients only; the console never sends them): top level "Not saved:
    Telemetry and Commanding are changed with a change set, not in a spacecraft's configuration."; on
    `document.telemetry_enabled` / `document.commanding_enabled`: "Change this with a change set, from the
    spacecraft's Operation panel."
  - `spacecraft_switch_set_by_change_set` stays a backstop only: "Not saved: Telemetry and Commanding are set
    through Setup › Changes, and they changed after this page loaded. Reload to see them." On submit (409, api-ops'
    review of (B) set 1): "Not sent: a change set turned Telemetry or Commanding on or off for EARENDIL-004 after
    this draft was saved. Save the draft again, then send it."
- **Activating with telemetry off** (crit, right above `Activate v4` / `Request approval for v4`, and on L10's What
  changes panel; it warns, it doesn't block): "Telemetry is off for EARENDIL-004, so once this is active it starts
  but decodes nothing: no live values, alarms or history. Turn telemetry on with a change set first." with `Open
  Operation`. A new craft's first start is a change set turning telemetry on, then this Activate (director's end-to-
  end test on a fresh mission, then qa's live check).

### U95 · Approve refused before anything is recorded (L10 decide panel; P3 "approved = applied", ahead of (B)) (api / fe-ops)
The Activations decide panel's Approve now checks that the request can apply, and refuses before recording a decision.
Every line starts "Not approved:" and says why. "Your approval wasn't recorded." comes after the why and after
anything another person does ("The requester sends it again."). When the reader has something to do ("Try again",
"Reload…", "Send it back…", "Approve it once…"), that sentence comes after it, so the line ends on the reader's act;
otherwise "Your approval wasn't recorded." ends the line. (Order amended 11-19: lines had landed both ways. New lines
follow this; a landed console line moves when its screen is next changed.) After a refusal, Approve is disabled with
the line as its A6 reason; Reject stays, so the request can be cleared. Words reuse U41, U65, U88, U90 and U94.

- `approved_activation_content_mismatch` (U41's cause): "Not approved: what this request would apply changed after it
  was requested, so it isn't what you reviewed. The requester sends it again."
- `mission_model_revision_not_approved` (U65; `details.catalog_revisions`, a list): one with a number "Not approved:
  catalog rev 4 isn't approved yet, so this can't apply. An org admin approves it in Setup › Catalog first." with
  `Open rev 4`; several "catalog revs 4 and 5 aren't approved yet, so this can't apply. An org admin approves them
  in Setup › Catalog first." (up to 3, then "and N more") with `Open the catalog`; an entry with no number "a catalog revision it uses isn't approved yet".
- `mission_model_revision_not_in_catalog` (U88): "Not approved: the catalog doesn't list the revision this request
  uses, so it can't apply. The requester sends a request for a revision the catalog lists." with `Open the catalog`.
- `mission_model_comparison_failed` (U65): "Not approved: catalog rev 4's comparison didn't pass, so this can't
  apply." with `Open the report` (`comparison_report_id`); without a number, "the comparison for the catalog revision
  it uses didn't pass".
- `mission_model_comparison_report_required` (U65): "Not approved: the catalog revision it uses hasn't been compared
  yet. Run the comparison in Setup › Catalog first." with `Open the catalog`.
- `mission_model_runtime_plans_not_ready` (U65): "Not approved: Cadence is still preparing the catalog revision it
  uses. Try again in a moment."
- `activation_policy_changed` (U94): "Not approved: the mission's approval setting changed after this was requested.
  The requester sends it again."
- `spacecraft_configuration_review_stale` (U94; `details.spacecraft_ids`, names from the fleet): "Not approved:
  EARENDIL-004's configuration changed after this was requested, so it isn't what was reviewed. The requester sends
  it again." Several: "The configuration of EARENDIL-004 and EARENDIL-005 changed…" (up to 3, then "and N more");
  none or unnamed: "A spacecraft's configuration changed…" (U41, U25).
- `change_set_activation_stale`: "Not approved: what's running on this mission changed after this was requested, so
  it isn't what was reviewed. The requester sends it again."
- `spacecraft_configuration_review_required` (the mission's activations go through each spacecraft's configuration,
  so a plain request can't be approved): "Not approved: on this mission, changes are activated from each
  spacecraft's configuration (Setup › Spacecraft), so this request can't apply. Reject it, and send the change from
  the spacecraft's configuration instead."
- `spacecraft_model_not_active`: "Not approved: the catalog revision EARENDIL-004 was reviewed with isn't the active
  one any more, so this isn't what was reviewed. The requester sends it again." Without spacecraft ids: "a
  spacecraft was reviewed with" (U25).
- `mission_model_activation_manifest_required` (the request doesn't name the catalog revision it activates; a request
  from the console always does): "Not approved: this request doesn't say which catalog revision it activates, so it
  can't apply. The requester sends it again; if it keeps happening, tell the team that runs Cadence."
- Any other 409 code (api lists `invalid_mission_model_activation_manifest`, `mission_model_manifest_mismatch`,
  `mission_model_runtime_plan_manifest_mismatch`, `invalid_spacecraft_model_bindings`): "Not approved: this request
  can't apply as it stands." plus the code in Technical details, then "Your approval wasn't recorded."
- Refusals before the check keep their words (self approval, not pending, not found).
- **After Approve** (#319, ca-ux 11-19; ux's ruling to fe-ops; U20, U94): only when the answer says the approval was
  recorded, and the line comes from the answer, never from "it didn't fail". Each is announced as an outcome (B6):
  - `execution.state` `failed` (crit): "Approved, but it didn't apply." + U41's apply sentence (a known failure).
  - `outcome` `needs_review`, not failed (caution): "Approved, but Cadence couldn't confirm that it applied." + U41's
    apply sentence, as U94 hands it on. No "yet": it pairs a finished attempt with waiting.
  - `execution.state` `in_progress` (neutral): "Approved. It's applying now."
  - `outcome` `applied` with `execution.state` `succeeded` (nominal): "Approved and applied."; with
    `execution.finished_at`: "Approved and applied at 03:46Z."
  - Anything else (no outcome, an unknown one, no execution; neutral): "Approved. Cadence hasn't confirmed that it
    applied yet. Reload to see it."
- **The decide panel's other words** (L10; built before a spec, ratified here): the intro "Approving applies it to the
  mission now. Rejecting leaves things as they are."; a reason is required for both ("Give a reason first.", A7);
  after Reject "Rejected. Nothing changes."; after Withdraw "Withdrawn. Nothing changes."; the tags `WAITING`,
  `APPROVED`, `REJECTED`, `WITHDRAWN`, `SUPERSEDED`, `UNKNOWN`; decisions read "Approved by Mira K. at 11-13
  02:20Z" ("at", never "on", U29). The pre-check refusals open by the act, as U95: `not_pending` by the act: Approve "Not
  approved: it's already decided, so your approval wasn't recorded. Reload to see how."; Reject "Not rejected: it's
  already decided, so nothing changed. Reload to see how."; Withdraw (decided while the requester looked) "Not
  withdrawn: it's already decided, so nothing changed. Reload to see how."; `activation_policy_changed` keeps U94's
  line.

### U96 · Who may change a mission's approval setting (#233; api's shape on domain 10d59bb78, 11-18) (api / domain / fe-setup)
Settings › Approvals (`cadence.governance`): the field keeps its server words, "Approval for changes and app
activations", `Applies without approval` / `Needs a second person's approval`, and the organization's "Missions may
override". Who may choose what comes from the read (`allowed_values`, `can_inherit`); the console shows each limit
before a save, never only as a refusal (A6).

- **Field states** (A6 reason under the field or on the disabled option):
  - `allowed_values` missing or null in the read (ca-security's C1; fe-setup 444bb6363, 5b3eccb32): the setting is read-only, its
    current value still shown, and the field and the disabled Reset say "Cadence couldn't read who may change this
    setting, so it can't be changed here. Reload to try again. If it's still missing, tell the team that runs Cadence
    for you." (U86).
  - `allowed_values` [], picked by the current value (the console can't see the role): `Applies without approval`
    → "Only a mission admin or an organization admin can change this."; `Needs a second person's approval` →
    "It's already set to the strictest option. Only an organization admin can loosen it."
  - A mission admin, `[independent]`: `Applies without approval` disabled, "Only an organization admin can let
    changes apply without approval."
  - `can_inherit` false: the inherit control (the console's `Reset to inherited`) disabled, "The organization's setting lets changes apply
    without approval, so only an organization admin can switch EARENDIL to it."
- **Pinning the strict value** (lead's question, ux 11-18): a mission admin on a mission that inherits `Needs a
  second person's approval` may set it as the mission's own, so a later organization loosening doesn't reach it.
  api sends `allowed_values` [independent] then ([] only once the mission has its own). When the value comes from the
  organization and `allowed_values` holds that same value, the field shows `Set for EARENDIL` with "EARENDIL uses the
  organization's setting. Set it for EARENDIL to keep it if the organization's setting changes." Afterwards the
  strictest-option hint applies; the audit reads U96's override-only form. A field's source is only ever organization or
  mission (api: an unset organization reads its section default as `organization`), so no default-source line.
- **Refusals** (403, "Not saved:" pattern; the console picks the line by the level saved):
  - `approval_policy_change_requires_organization_admin`, on a mission: "Not saved: only an organization admin can
    let changes on EARENDIL apply without approval."; on the organization (and a mission admin's `forbidden`
    there): "Not saved: only an organization admin can change the organization's approval setting."
  - `approval_policy_change_requires_mission_admin`: "Not saved: only a mission admin or an organization admin can
    change approval settings."
- **Audit** (AU1, kind `config`, from `change.before` / `change.after`; actor, time and the ADMIN MODE tag as U89):
  - Mission, value changed: "Loosened approval on EARENDIL: Needs a second person's approval → Applies without
    approval" / "Tightened approval on EARENDIL: Applies without approval → Needs a second person's approval". When
    `override` becomes false, add " (the organization's setting)".
  - Mission, only `override` changed: "EARENDIL now uses the organization's approval setting (Needs a second
    person's approval); what applies doesn't change." / "EARENDIL now sets its own approval setting (Needs a second
    person's approval); what applies doesn't change."
  - Organization: "Loosened approval (organization default): Needs a second person's approval → Applies without
    approval" / "Tightened approval (organization default): …". `allow_override`: "Missions may now set their own
    approval setting." / "Missions can no longer set their own approval setting." Both in one save: the two
    sentences, value first.
  - Option words always as the field's options, never `direct` / `independent`.
- **Enforced by the organization** (`allow_override` false; the section reads `locked: true`, and the mission level
  reads [] and false for everyone): the locked callout for this section reads "The organization sets this for every
  mission, and missions can't change it. An organization admin changes it in the organization's settings." with
  `Open organization settings` for an organization admin. The 409 `settings_enforced_by_organization` keeps the
  server's message (the legacy host still shows it).


### U97 · Approving a contact plan: its own action, its refusals, and never a false success (#257, 11-19; api's contract v2) (api / fe-ops)
#257: the plan review's `Approve and book N passes` posted to **submit**, which answered 200 and changed nothing, so an
approver saw the plan come back as if done. Approve now has its own action (`POST …/approve` with `operation_id`,
`expected_version`, `decision_note`, `acknowledgements`), and submit only submits, for everyone, under both approval
settings. Console only; amends U36. Every approve refusal says why and that the approval wasn't recorded (U95); codes
are api's, switched on with `knownErrorCode`.

- **Success only from the answer (U20):** "Approved. Booking 40 passes." only on the 202 with `outcome: "approved"`.
  When the answer lists expired passes, the success line is U61's partial line with the answer's counts: "Approved.
  Booking 37 passes; 3 weren't booked because their booking window had closed." The callout below keeps only its list
  (`Show 3`), so the screen says it once (#257 check, ca-ux and fe-ops).
  Any other success answer: "Cadence didn't record an approval for R41. Reload to see the plan; if it's still waiting,
  try again or tell the team that runs Cadence for you." The UI never tells an approver something happened when it
  didn't. Submit likewise: "Sent for approval." only when `outcome` is `pending_approval`; any other answer (an older
  server's `executing`, an unknown outcome): "Cadence didn't confirm that R41 was sent for approval. Reload to see the
  plan."
- **One act under "Applies without approval"** (ux's call for the director, 11-19). The API stays split. When the read
  says `approval_setting: "direct"` and the viewer is an org admin, a draft or sent-back plan gets ONE action, `Approve
  and book N passes` (sheet title `Approve and book the plan`): the console calls submit, then approve with the
  version it saw, and both are recorded.
  - Confirm body: "This sends R41 and approves it, and booking starts for its 40 passes." Muted (`text-3`) line under
    the footer's `Approve and book N passes` button (PlanFooter), not in the sheet: "No second person's approval is needed, as this mission's setting allows. Sending and approving are
    both recorded."
  - Re-plan's Apply the same: `Approve and apply the proposal`, confirm "This sends the proposal and approves it, and
    sends 12 booking requests." plus the muted line.
  - The note for the record goes only as the approval's `decision_note` (the act the admin took); the submission
    carries none, so the history shows it once, on the decision.
  - The submit is refused: the submit line below; nothing was sent or approved. A submit answer other than
    `pending_approval` stops the chain too (no approve call), with the submit's U20 line.
  - The submit lands and the approve gets no clear answer: "R41 was sent for approval, but Cadence didn't give a clear
    answer about the approval. Reload to see whether it was recorded before you try again."
  - The submit lands and the approve is refused: "R41 was sent for approval, but not approved: <the approve refusal's
    reason>. It's waiting for approval." The reason is the refusal's first sentence after "Not approved:", with
    "R41" as "it" and without its ending (e.g. `forbidden`: "…not approved: only an org admin approves contact
    plans."). Example: "R41 was sent for approval, but not
    approved: it changed after you opened it, so it isn't what you reviewed. It's waiting for approval." The plan then
    opens awaiting approval with `Approve and book the plan` to try again; after a self-approval refusal (the setting
    changed to "Needs a second person's approval") Approve is disabled with its A6 reason instead. The typed note stays
    in the field for the retry.
    Where the rule doesn't read right, the reason is given explicitly (ca-ux's review):
    - `plan_not_ready` with conflicts: "2 of its passes conflict with other bookings"; unmet only: "it isn't ready:
      10 spacecraft aren't covered".
    - `plan_superseded`: "it's superseded by newer contact rules".
    - `duplicate_operation`: "Cadence matched it to an earlier, different request".
    - `plan_not_found`: "R41 was sent for approval, but Cadence can't find it any more. Reload to see 11-16's plans."
      (no "It's waiting for approval").
  - The approve's 403 stays the backstop: the setting can change between the read and the click.
- **Everyone else** (members, and admins under "Needs a second person's approval", `approval_setting: "independent"`):
  `Request approval` (sent back `Submit the plan again`; Re-plan `Request approval for the proposal`, confirm "This
  sends the proposal for approval; another org admin approves it before anything is booked."). An org admin opening a
  plan that awaits approval gets `Approve and book the plan`, which calls approve only. Without
  `approval_setting` in the read, the console offers `Request approval` to everyone and never guesses.
- **Approve refusals:**
  - 403 `contact_plan_self_approval_forbidden`, `because: "submitted"`: "Not approved: you submitted this plan, so
    another org admin approves it. Your approval wasn't recorded and nothing was booked." `because: "edited"` (api: the
    author of the version being approved, so the drafter): "Not approved: you drafted this version of the plan, so
    another org admin approves it. Your approval wasn't recorded and nothing was booked." Then Approve is disabled
    (A6) with the sentence without "Not approved:" and the ending, muted; Send back stays. (No authors-unknown case
    for plans: the plan and version rows always carry their actor.)
  - 403 `forbidden`: "Not approved: only an org admin approves contact plans. Your approval wasn't recorded."
  - 409 `plan_not_pending` (`state`; `decided_by` and `decided_at` together or neither): "R41 was already approved by
    Ana R. at 03:46Z, so your approval wasn't recorded. Reload to see it." / "…already sent back by Ana R. at
    03:46Z…". When the decider is the viewer: "You already approved R41 at 03:46Z. Reload to see it." / "You already sent back
    R41 at 03:46Z. Reload to see it." No decider, or
    another state: "Not approved: R41 isn't waiting for approval any more, so your approval wasn't recorded. Reload to
    see it." Never an id for the name (U25).
  - 409 `plan_changed`: "Not approved: R41 changed after you opened it, so it isn't what you reviewed. Your approval
    wasn't recorded. Reload to review it again."
  - 404 `plan_not_found`: "Not approved: Cadence can't find this plan any more, so your approval wasn't recorded.
    Reload to see 11-16's plans."
  - 409 `plan_superseded` (contact rules changed since the draft, U27): "Not approved: contact rules changed after R41
    was drafted, so it's superseded and can't be booked. Your approval wasn't recorded. Draft the day again." As the
    partial line's reason: "it's superseded by newer contact rules".
  - 422 `acknowledgements_required` (`missing`): "Not approved: 3 gaps need a reason first. Your approval wasn't
    recorded. Give a reason for each, then approve." (A gap is an uncovered spacecraft, U23.) When the count can't
    be worked out (no `missing`, or it doesn't match the plan the console has): "Not approved: some gaps need a
    reason first. Your approval wasn't recorded. Give a reason for each, then approve." Never a number that may be
    wrong (U20), and never the unknown-code line for this known code (ux, from ca-ux's #338 review).
  - 422 `plan_not_ready` (`unmet`, `conflicts`): with conflicts, "Not approved: 2 of R41's passes conflict with other
    bookings, so it can't be booked. Your approval wasn't recorded. Send it back so it can be planned again." With
    unmet only, "Not approved: R41 isn't ready to approve: 10 spacecraft aren't covered. Your approval wasn't
    recorded. Reload to see the gaps." With neither count, "Not approved: R41 isn't ready to approve. Your approval
    wasn't recorded. Reload to see what's missing."
  - No clear answer (a network failure, a timeout, a 5xx or an answer the console can't read; it may have been
    recorded): "Cadence didn't give a clear answer, so
    your approval may not have been recorded. Reload to see the plan before you try again."
  - 422 `invalid_params` on `decision_note`: the server's field message ("Keep the note under 2,000 characters.") under
    the note.
  - A code the console doesn't know: "Not approved: Cadence refused this approval. Your approval wasn't recorded."
    with the code in Technical details.
- **Passes whose booking window closed** (#273, director's two conditions; domain's one expiry rule with its 60 s
  lookahead; api's final shape: the plan read's `expired` `{count, reservable_count, items}`, `expired_digest` and
  `next_expiry_at`; the approve sends `expected_expired_digest`). The words say "booking window closed", never
  "started": a provider's window can close before AOS (U20). The list is the server's; the console never edits it.
  - **Up front** (Plan day's review and Re-plan's proposal), caution, above Approve: "36 of R41's passes can't be
    booked any more: their booking window has closed. Approving books the other 1,476; the 36 are recorded as
    skipped." with `Show 36` (spacecraft, station, AOS; U61's list; no close time, since a pass within the 60 s margin counts as
    closed before its raw `expires_at`). Over 5,000 (items are capped, `count` isn't): the list ends "Showing the first
    5,000 of 6,200." The commit counts only bookable passes: `Approve
    and book 1,476 passes`, and so does the confirm body. Re-plan: "3 of the proposal's passes can't be booked any
    more… Applying it books the other 37; the 3 are recorded as skipped."
  - **No window from the provider** (domain fails closed: a pass without a usable `expires_at` counts as closed and
    is skipped; each item's `reason` is `opportunity_expired` or `no_booking_window`, and the words key on `reason`,
    never on a null `expires_at`; an unknown `reason` adds nothing to its row): a `no_booking_window` row adds "No
    booking window from the provider", and while any
    listed item has none, the sentence's clause reads "their booking window has closed, or the provider gave none"
    (U20: "closed" alone would claim what isn't known). The record and audit then say "skipped (no open booking
    window)".
  - **While the page is open:** when now passes `next_expiry_at` (the server's next close with its `expiry_margin_seconds` already applied; the
    console adds no margin), a
    caution line: "A pass's booking window has closed since this loaded. Reload to update the list." Never keyed on
    AOS. With `next_expiry_at` null, no line.
  - **409 `contact_plan_all_opportunities_expired`** (checked first): U61's all-expired line, and up front the same
    sentence as Approve's A6 reason: "The booking window has closed for all 36 of its passes, so nothing can be
    booked."
  - **409 `contact_plan_expired_passes_changed`** (nothing recorded; the console diffs `details.expired.items`
    against the list it showed): "Not approved: the booking window closed for 3 more of R41's passes after you
    opened it, so what you'd approve changed. Your approval wasn't recorded. Check the list and approve again." with
    `Show 3` for the new ones; when the diff isn't possible, or either list is capped (`count` > the items' length;
    ca-security): "…closed for more of R41's passes after you opened it…". The review then shows the new list and count; the console never retries on its own (ca-security).
    Re-plan: "Not applied: the booking window closed for 2 more of the proposal's passes after you opened it, so
    what you'd apply changed. Nothing was booked. Check the list and apply it again." In the one act (U97): "R41
    was sent for approval, but not approved: the booking window closed for 3 more of its passes after you opened
    it. It's waiting for approval."
  - **Interim, step 1** (409 `contact_plan_opportunity_expired`, no details; retires once domain's rule lands): "Not
    approved: the booking window has closed for some of R41's passes, so R41 can't be booked as it is. Your approval
    wasn't recorded. To book the others, draft the day again without them." With a count, "for 3 of R41's
    passes". No Reload (the windows stay closed); beside it K1's `Draft a new plan for 11-16…` before the day
    starts, `Plan the rest of 11-16…` once it has.
  - **The decision record** (the 202's `expired`, the same set the record lists as skipped): history "Approved by
    Ana R. at 11-19 06:52Z · 1,476 passes to book; 36 skipped (booking window closed)." with `Show 36` (the history
    read's skipped items, with the same `reason`); nothing skipped, or a decision from before #273 (`skipped` null),
    no clause. Audit: "Approved R41 for 11-16: 1,476 passes to book, 36 skipped (booking window closed)."
- **Submit refusals:** 409 `plan_changed`: "Not sent: R41 changed after you opened it. Reload to see it, then send it
  again." 409 `plan_already_submitted` (`submitted_by` and `submitted_at` together or neither): "Not sent:
  R41 was already sent for approval by Mira K. at 03:40Z, so nothing changed. Reload to see it." The viewer: "Not sent:
  you already sent R41 for approval at 03:40Z, so nothing changed." Neither: "Not sent: R41 is already waiting for
  approval, so nothing changed. Reload to see it."
- **Replays (both actions):** the same `operation_id` with the same actor, plan, action and body returns the original
  answer with `replayed: true`; the console shows that answer's result as this one's ("Sent for approval." /
  "Approved. Booking 40 passes." by its outcome). 409 `duplicate_operation` (the id with anything different): on
  submit "Not sent: Cadence matched this to an earlier, different request, so nothing changed. Reload and try again.";
  on approve "Not approved: Cadence matched this to an earlier, different request, so your approval wasn't recorded.
  Reload and try again."
  (`operation_conflict` keeps its line.)
- **With gaps:** the one act keeps today's pattern: `Accept 2 gaps, approve and book` on the plan, `Accept 2 gaps,
  approve and apply` on Re-plan.
- **The submitter, up front** (fe-ops' review: no such check existed on develop): under `independent`, the plan's
  submitter (`submission.actor.id` is the viewer) gets no Approve, only the muted line "You submitted this plan, so
  another org admin approves it."; Send back stays. Under `direct`, or an unknown setting, Approve shows (the
  submitter may approve under `direct`) and the 403 stays the backstop.
- **The drafter, up front (follow-up, not #257):** a drafter under `independent` learns it only on press until the
  plan read says why, as #240 did for Activations; then "You drafted this version of the plan, so another org admin
  approves it." shows before the press.

### U98 · Can't view: a 403 on a read (#272, mms-ux; the pattern for every squad) (api / every squad)
Someone in the mission without the read right opens a page (outsiders get 404 and never learn it exists). Nothing they
asked to change was refused, so the line has no "Not saved:" style opener and never says "change".

- **Line:** "You can't view <object>. Ask a mission admin or an org admin for access." A nameless object reads "this
  <thing>": "You can't view this spacecraft's configuration…", never "Unknown spacecraft's" (mms-ux's review). First case (#272, the spacecraft
  configuration workspace and its packet choices, one line on both routes): "You can't view EARENDIL-004's
  configuration. Ask a mission admin or an org admin for access."
- **Where:** in place of the content the read would fill, the page or a panel, as its empty state (`role="status"`;
  the person didn't act, B6). Packet choices load inside the workspace, so the line takes that list's place, and any
  act that needs it is disabled with its reason (A6). The
  object is named as the page names it, never by id (U25).
- **Not this:** a 403 on a write keeps its act's opener ("Not saved:", "Not approved:" …), and a 403 with a known
  specific code keeps that code's line; U98 is for the generic `forbidden` on a read.

### U100 · A service identity's acts count as its people's for approvals (#280, director 11-19; mms-security's impact list, ca-security approved; words with ca-ux) (api / mms-security / ca-ux / every squad that approves)
Rule (director): what a service identity does counts as the act of everyone who issued it or rotated its key, of
anyone an org admin records as accountable for it, and of that recording admin ("a service identity you're accountable
for" covers them all). It only widens who counts as "you" where a kind already refuses approving your own; it adds no
refusal of its own. Affected today: catalog revisions (imports), activations (every mode), contact plans (and
approvals under an automation grant) and command requests. Not affected: change sets, planning policies, command
groups, provider changes, qualification cases (no service authors them).

- **The reused self-approval 403s** always carry `details.via_service`: `{id, name}` when the overlap came through a
  service, null when it was the approver.
  Then the line names the service, since "you requested this" would be untrue (U20). Every line ends "Your approval
  wasn't recorded." (U95), plus what the kind adds:
  - `activation_self_approval_forbidden`: "Not approved: Nightly planner, a service identity you're accountable for,
    requested this, so another person approves it. Your approval wasn't recorded."
  - `mission_model_self_approval_forbidden`: "Not approved: Nightly planner, a service identity you're accountable
    for, imported this revision, so another org admin approves it. Your approval wasn't recorded."
  - `contact_plan_self_approval_forbidden`: "Not approved: Nightly planner, a service identity you're accountable for,
    submitted this plan, so another org admin approves it. Your approval wasn't recorded and nothing was booked."
  - `command_request_self_approval_not_allowed`: "Not approved: Nightly planner, a service identity you're
    accountable for, sent this command request, so another person gives the GO. Your approval wasn't recorded."
  - `via_service` with a null `name` (an import run's recorded actor may have none): the name and its commas drop,
    never an id (U25; the service's id goes in Technical details): "Not approved: a service identity you're accountable for imported this revision, so another
    org admin approves it. Your approval wasn't recorded."
  - `via_service` null, or absent (an older server; decoders take it as optional and read absent as null): each
    kind's own line (U65, U94, U97, U87's family).
- **403 `<kind>_approver_authors_unknown`** (api's shape: `activation_approver_authors_unknown` (#236's code),
  `contact_plan_approver_authors_unknown`, `mission_model_approver_authors_unknown`,
  `command_request_approver_authors_unknown`), one meaning: who made this can't be established. They always send
  `details.service` (null, never omitted; #236 sends null too), which picks the line:
  - `{id, name}` (a service whose accountable people aren't recorded; under an automation grant it can be the approving
    service): "Not approved: Nightly planner has no one recorded as accountable for it, so this can't be approved yet.
    An org admin records who's accountable in People › Service identities. Your approval wasn't recorded." With a
    null `name`: "the service identity that imported this revision" (submitted this plan, sent this command request;
    the approving one under a grant: "the service identity approving for this automation") in its place, never an
    id (U25; the id goes in Technical details).
    - **Activations say "a service identity involved in this request"** (api's #453 question, from mms-security's
      review). Since #435 the unnamed service may be the requester or the author of a version the request
      includes, such as a change set's applier, and the 403 doesn't say which, so "requested this" could be untrue
      (U20). "Not approved: a service identity involved in this request has no one recorded as accountable for it,
      so this can't be approved yet. An org admin records who's accountable in People › Service identities. Your
      approval wasn't recorded." If the details ever name the role, the line names it instead.
  - null (no service involved), or absent (an older server): the kind's own authors-unknown line (in #280 only
    activations can send null, via #236; the others are kept for safety and won't show today): U94's for activations ("Not approved: Cadence can't tell who
    saved this configuration…"). Kinds that had none get the same form: "Not approved: Cadence can't tell who made
    this plan, so it can't check that you weren't one of them. Your approval wasn't recorded. Send it back so it can
    be submitted again; if it keeps happening, tell the team that runs Cadence for you." (revision: "who imported this
    revision" … "Reject it; a corrected catalog imported again becomes a new revision." since re-importing the same
    file returns the same revision (mms-ux's #119 entry); command request: "who sent this command request" … "Reject
    it so it can be sent again").
  - REST command requests carry no details (that envelope has none): the server's message, still a refusal.
  - Up front (the approval read's `cannot_decide` `authors_unknown`, with `service` when known): Approve is disabled
    (A6) with the matching line without "Not approved:" and without "Your approval wasn't recorded."; the what-to-do
    stays. Reject or Send back stays.
- **Automation grant refused** (contact plans under "Needs a second person's approval"), on the plan's state line:
  "Not approved automatically: the people this automation approves for also count as R41's authors, so a person
  outside them approves it."
- **People › Service identities, confirm sheets** (muted line above the action):
  - Create: "What this service identity does counts as yours for approvals. Wherever you can't approve your own catalog
    import, activation request, contact plan or command request, you can't approve one it makes either." ("Wherever"
    keeps it true per kind: activations in every mode, the others under "Needs a second person's approval".)
  - Rotate: "Once you rotate its key, what it does counts as yours for approvals too." and the same second sentence.
  - Recording accountable people (org admin): "What it does then counts as theirs, and as yours, for approvals."
  - The planning grant form: "On a mission that needs a second person's approval, this grant can't approve plans the
    service makes itself."
- U104 (ca-ux, #281) holds the service identity's own refusals (create,
  rotate, revoke, list) and points here.

### U104 · Service identities: who may create one and what access it may get (#281) (api / ca-engineer / fe-setup)
#281 closes two gaps on creating a service identity and rotating its key: a service identity can't make, rotate,
revoke or list one, and a person can't give one more access than they hold. #281 also removes the REST
service-identity endpoints (api-ops and lead, on ca-security's advice: a REST bearer is always a service identity, so
a person-only REST endpoint could succeed for no one), so these are console lines. Each refusal comes before anything
is created or rotated. Capability words are the role words, never enum values: only `Org admin` and `Mission admin`, the two capabilities
a service identity can ever be given (`ServiceIdentity.normalize_capability`; ca-security). Never `Platform admin`,
which would read as grantable.

- **403 `authenticated_user_required`** (the caller is a service identity, not a person). **Unreachable today:** the
  console's organization scope refuses a service identity first (`404 organization_not_found`) and REST has no
  endpoint. The domain keeps the check as a backstop (`Policy :manage_service_identities` is person-only), and these
  lines are kept for any future surface that reaches it:
  - Create: "Not created: only a person can create a service identity, not another service identity. An org admin
    creates it in People › Service identities."
  - Rotate: "Not rotated: only a person can rotate a service identity's key, not a service identity. An org admin
    rotates it in People › Service identities."
  - Revoke: "Not revoked: only a person can revoke a service identity, not a service identity. An org admin revokes
    it in People › Service identities."
  - List (a read, so no "Not …" opener, as U98): "Only a person can list the organization's service identities, not
    a service identity."
- **403 `capability_beyond_issuer`** (the request gives access the person doesn't hold; `details.capabilities`, the
  ones beyond them, as codes; the server's message turns them into role words, up to 3, then "and N more"). It can't
  fire today, since an org admin holds every capability a service identity can get; the lines are for when that
  changes:
  - Create: "Not created: you can't give a service identity access you don't have yourself (Org admin). Leave
    it out, or ask someone who has it to create the service identity." Without `details`: the same without the
    bracket.
  - Rotate (the identity already holds access the person doesn't): "Not rotated: this service identity has access
    you don't have yourself (Org admin), so you can't rotate its key. Ask someone who has that access to rotate
    it." Without `details`: the same without the bracket.
  - **Up front (A6):** the create form offers only access the person holds; any other shows disabled with "You don't
    have this access yourself, so you can't give it." `Rotate key` is disabled with the rotate line's reason (from
    "this service identity has access" to "rotate its key") once the read says so; #281 adds no such flag, so until
    then the 403 is the backstop.
- **Not here:**
  - A person without the right to manage service identities at all keeps today's `forbidden` line.
  - A refusal for naming the id: the console builds the id, and the REST body that could name one went with the
    endpoint, so there's no `service_identity_id_not_assignable`.
  - That a service identity's acts count as its issuer's and rotators' for approvals (ux, 11-19): not in these
    refusals. It goes on the create and rotate confirm sheets, where a person takes on a service's acts: U100 (#280).

### U99 · An import that matches a catalog revision that already exists (#119) (mms-ux / mms-engineer / mms-security)
An import whose content matches a mission model revision that already exists creates no new revision. The run's
result must say so, and must never read "Imported" or show a rev N → rev N+1 header. A rejected revision can't be
reviewed again, so re-importing its content never reopens it: a corrected catalog is new content and becomes a new
revision. Data (mms-engineer): the run's result `matched existing <status>`, plus the matched revision's catalog
name (U65: "catalog rev 4"), its status, and who decided it, when and why. The import run read carries them, joined
at read time and not snapshotted, so a match that was waiting shows its later decision once it's made. The words
describe the revision as it is now.

Shape (mms-engineer, #119): `matched_revision: null | {revision: {id, number, label|null} | null, status:
candidate|approved|rejected|retired (read live), decision: null | {kind: approved|rejected, by: {name|null}, at,
reason|null}, cannot_approve: null | {reason: "self" | "authors_unknown", via_service: {id, name|null} | null,
service: {id, name|null} | null}}`, the same fields as the separation check's refusal. `decision` is null unless both who and when are known. `cannot_approve` is the gate's own answer: whatever
refuses this viewer's approve, from the one separation check the approve path itself uses (fe-setup's call: one
source, extracted as #280's first commit), never re-derived from "the viewer is among the importers"
(mms-security). It's null when nothing bars the viewer. Until #280 lands, only `self` with both services null
occurs.

- **Where:** the run's verdict callout on the import page (Catalog.md § C), in place of "Parsed and validated, no
  schema errors.". The header reads `Catalog rev 4` (the matched revision), never `rev 14 → rev 5`. Each case's
  action is `Open rev 4`, which opens that revision in Setup › Catalog.
- **Matched an approved revision** (info):
  "This file matches catalog rev 4, so no new revision was created. Rev 4 was approved by Ana R. at 11-15 09:12Z."
  C3 Roll out to stays, because rolling out rev 4 is a real next step.
- **Matched a revision waiting for approval** (caution):
  "This file matches catalog rev 4, so no new revision was created. Rev 4 is waiting for approval in Setup ›
  Catalog." No C3: spacecraft can't move to it until it's approved (U65's hold).
  - **When the viewer can't approve rev 4** (mms-security; the gate's own answer, never inferred by the console),
    the line adds a sentence, picked by the server's one answer (U100's cases, up-front form: no "Not
    approved:" and no "Your approval wasn't recorded."). The server picks one cause, and the console never
    combines them:
    - `self`, `via_service` null (the viewer imported it; importing it again makes you an importer): "Because you
      imported this content, another org admin has to approve rev 4."
    - `self`, `via_service` {name}: "Because Nightly planner, a service identity you're accountable for, imported
      this content, another org admin has to approve rev 4."
    - `authors_unknown`, `service` {name}: "Rev 4 can't be approved yet: Nightly planner has no one recorded as
      accountable for it. An org admin records who's accountable in People › Service identities."
    - `authors_unknown`, `service` null: U100's revision form, up front, with no "yet", since nothing can be
      recorded later (ux): "Rev 4 can't be approved: Cadence can't tell who imported it, so it can't check that
      you weren't one of them. Reject it; a corrected catalog imported again becomes a new revision." "Yet" stays
      only in the `service` {name} case, where an org admin can record who's accountable.
    - A service with no name (`name` null; nothing guarantees one on the run's recorded actor): the sentence
      drops the name, never shows the id (U25; the id goes in Technical details):
      - `self`: "Because a service identity you're accountable for imported this content, another org admin has
        to approve rev 4."
      - `authors_unknown`: "Rev 4 can't be approved yet: the service identity that imported it has no one
        recorded as accountable for it. An org admin records who's accountable in People › Service identities."
    - A reason this console doesn't know: "You can't approve rev 4, so another org admin has to." It never
      guesses which case applies. (`reason` is read as known text.)
    - `cannot_approve` null or absent: nothing is added; U65's and U100's refusals stay the backstop.
- **Matched a rejected revision** (caution):
  "This file matches catalog rev 4, which was rejected by Ana R. at 11-15 09:12Z: “Wrong FSW build.” No new
  revision was created. To try again, correct the catalog and import the corrected file. It becomes a new
  revision." No C3. Nothing on the page offers to review rev 4 again.
- **Amends U65's reject confirm:** its body's "To try again, import a new revision." becomes "To try again, correct
  the catalog and import the corrected file." After #119, importing the same file again returns the rejected
  revision, so the old advice leads nowhere. The rest of U65's confirm is unchanged.
- **Missing parts (U20, U29):** `decision` null shows neither who nor when ("Rev 4 was approved." / "which was
  rejected"). `by.name` null with a time drops only the name ("Rev 4 was approved at 11-15 09:12Z."), never "by
  Unknown" and never an id. No reason: drop the quote. A reason that doesn't end in . ! or ? gets a full stop after
  its closing quote (“Wrong FSW build”.); the person's own text inside the quotes is never changed. `revision` null
  reads as the unnumbered case, and keeps `Open the revision` (as built, #325): it opens the model revision's page,
  where U88 already says why it can't be approved and offers Reject. The words key on `status`; `decision` only supplies who, when and why. An unnumbered revision (U65): "This file matches a catalog revision that
  already exists…" with `Open the revision`. A status this console doesn't know: only the first sentence, "This
  file matches catalog rev 4, so no new revision was created.", with the status in Technical details. It's never
  mapped onto a known case.
- **Retired** (in the read's vocabulary, but nothing on develop sets it): it reads as the unknown-status case,
  with only the first sentence and `Open rev 4`, and no C3. It never reads like approved, because that would offer
  a rollout the model gate may refuse. It gets its own line once domain defines what retired means.
- **The same content in another catalog database** (domain's #119 ruling): within one catalog database a match
  makes no revision (above). Identical content uploaded into a *different* database of the mission does make that
  database's revision (its rev 1, say), naming the existing model revision. That revision already carries its
  decision: it can't be approved again or reopened, and one decision covers both. The run made a revision, so none
  of the "no new revision" lines apply. The header is the normal one for this database (`Catalog rev 1` for a first
  import). The verdict callout names both revisions, with the other database's name:
  - Approved (info): "Imported as catalog rev 1 of Payload catalog. Its content is the same as catalog rev 4 of Bus
    catalog, approved by Ana R. at 11-15 09:12Z, so rev 1 is approved too." C3 stays.
  - Waiting (caution): "Imported as catalog rev 1 of Payload catalog. Its content is the same as catalog rev 4 of
    Bus catalog, which is waiting for approval. One approval covers both." No C3 (U102). The `cannot_approve`
    sentence follows, as above.
  - Rejected (caution): "Imported as catalog rev 1 of Payload catalog. Its content is the same as catalog rev 4 of
    Bus catalog, which was rejected by Ana R. at 11-15 09:12Z: “Wrong FSW build.” So rev 1 is rejected too, and
    spacecraft can't move to it. To try again, correct the catalog and import the corrected file." No C3.
  - Missing parts follow the rules above: who and when together or not at all, no reason means no quote, and an
    unnumbered match reads "a catalog revision of Bus catalog". With no database name, "of Bus catalog" becomes "in
    another catalog of this mission", never an id. An unknown status: the first two sentences only ("Imported as
    catalog rev 1 of Payload catalog. Its content is the same as catalog rev 4 of Bus catalog.").
  - Both revisions link: `Open rev 4 of Bus catalog` beside the callout. This run's own rev 1 is the page's
    subject.
  - Runs table: the normal tag for a new revision, plus `Same as Bus catalog rev 4` (info).
  - Data (mms-engineer): the run's own `revision` is set in this case and null in a same-database match; that's the
    tell, with no extra flag. `matched_revision.revision.database {id, name|null}` names the database of the catalog
    revision the model is first recorded under (U65), which here is the other database's. Decisions belong to the
    one model revision, so both catalog revisions always show the same status, and deciding through either decides
    both.
- **A source file whose content matched** (U103's source-file page): a file uploaded with content that matches a
  revision in the same database has a valid run and no revision of its own. So "Revisions from this file" doesn't
  show its usual empty state ("No revisions yet. An import of this file becomes a revision once it's valid.",
  which would be false). It reads "This file made no revision of its own: its content matches catalog rev 4." with
  `Open rev 4` (unnumbered: "…matches a catalog revision that already exists."). Data: the page's
  `import_runs[].matched`.
- **Import runs table:** the Status tag reads `Matches rev 4` (info). For a rejected match it reads
  `Matches rejected rev 4` (caution, mark + word). Never `Succeeded`, which would imply a new revision.
- **Technical details** (a plain panel, like the console's other Technical details panels; the kit has no collapsed
  state, mms-engineer): the run's result as sent (`matched existing · rejected`) and the mission model revision id
  (`model_revision_id`, never in a sentence).
- **Security (mms-security, confirmed 11-19):**
  - Matching is only within the mission and organization (mms-engineer: identical bytes in another mission get their
    own revision). The decider's name and reason shown here are on rev 4's page already (U65's decided line).
    This holds while everyone who can import can also read a revision's decision. Revisit it if mission roles ever
    split who may import from who may read.
  - When the server's organization or mission check fails closed, the page shows a plain import error. It never
    shows a match line, or another revision's status, decider or reason.
  - The rejection reason is a person's free text: rendered as text, never as HTML.
  - A re-import never resets, reopens or copies an approval or a rejection. (It does add the importer; see the
    waiting case.)
  - The words never suggest re-importing as a way around a rejection.

### U101 · Which change set last set a spacecraft's switch (#151; extends U94) (mms-ux / api / fe-setup)
A mission admin sees where a Telemetry or Commanding switch was last changed, and where to change it back. The words
build on U94's switch lines and its keys `switches.telemetry_enabled` / `switches.commanding_enabled`, each `{value,
set, revision}`, plus (api, #151) `applied_by {kind, id, name}` and `applied_at`, sent both or neither.

- **Where:** the same words in two places: the read-only switch rows in the configuration workspace (U94), and the
  Operation panel on the spacecraft page (U40), as a muted line under each switch's state sentence. The Operation
  panel's read sends the same per-switch shape; it doesn't keep its own.
- **The lines:**
  - Set by a change set, with the apply: "Off · set by r7, applied 11-18 03:40Z by Mira K." (`On` likewise). Who and
    when are the apply, one event (U29). The line names whoever `applied_by` names, whatever their role. (api: that's
    whoever ran the apply, which under "Needs a second person's approval" is the approver.) The person who asked for
    the change is on the revision page. The time is §4's short form with the date always, because a switch can be
    set days ago.
  - `applied_by` by kind (ux's review):
    - A person: their name, as above.
    - The system: "applied 11-18 03:40Z by Cadence".
    - A service identity: "applied 11-18 03:40Z by Nightly planner (a service identity)" (U103).
    - A null `name` on a person or service: "Off · set by r7, applied 11-18 03:40Z." The name drops, never an id
      (U25); the time stays, as in U99.
    - A `kind` the console doesn't know: the same as a null name.
  - Set by a change set, without `applied_by` / `applied_at`: "Off · set by r7." (U94).
  - Set, with no revision: "On · set through Setup › Changes." (U94), plain text with no link, since there's no one
    change set to open.
  - Never set: U94's line unchanged ("Off · no change set has turned it on yet…").
- **The link:** `r7` is a link in the mono revision style to Setup › Revisions › r7 (route `setup.revision`,
  `/setup/revisions/7`), where the change set's changes, its submitter and approver, and `Roll back` are. Its
  accessible name is "Change set r7" (B7; it contains the visible `r7`, so label-in-name holds). The link shows even
  if that page can't open the revision; Revisions shows its own not-found state. The console never guesses a
  revision.
- **People who can only view Setup** see the same line and link (Changes §5: never hide the data).

### U102 · Roll a catalog revision out from the catalog page (#195; amends Catalog.md C3) (mms-ux / fe-setup / mms-engineer)
C3 "Roll out to" is built (fe-setup 96256074, 1d5335e6, 0391a9a5), but only on an import run's page. A revision
approved after its import, or an older one, can't be rolled out from Setup › Catalog. This entry adds the catalog
page's entry point and settles the cases C3 left open. The counts still come only from the server (api's rollout
read, the dry run).

- **Where:** a revision's page (the `Catalog revision` page that rev 4's link in A1 Revisions opens,
  `setup.catalog.model`) gets C3 under the Approval panel, or under its decided line. The import run's page keeps C3 too. It's the same
  panel with the same rules in both places. As on the import page today, C3 shows only to people with
  `config.stage`. That's presentation; the server enforces who may stage.
- **Only an approvable target is offered, up front (A6):**
  - Approved, or needs no approval: C3 as built.
  - Waiting for approval: in C3's place, "Spacecraft can't move to rev 4 until it's approved." The Approval panel
    sits right above. The dry run's NO-GO (`mission_model_not_approved`) and the apply-time model gate stay the
    backstops (mms-security: the gate refuses at apply on both paths, change set and per-spacecraft review).
  - Rejected: in C3's place, "Rev 4 was rejected, so spacecraft can't move to it. To try again, correct the
    catalog and import the corrected file." (U99's words). Not U65's "import a new revision": after #119,
    re-importing the same file returns this rejected revision.
  - A revision with no number (U65): "this catalog revision" in place of "rev 4": "Spacecraft can't move to this
    catalog revision until it's approved." / "This catalog revision was rejected, so spacecraft can't move to it.
    To try again, correct the catalog and import the corrected file." The same goes for the breaking fallback
    below.
  - Retired (status `retired`): in C3's place, "Rev 4 is retired, so spacecraft can't move to it. Any already on
    it keep it." The apply-time gate refuses a model revision that isn't approved, retired included, and approve
    refuses it too; a spacecraft already running it keeps it (mms-engineer, develop ed9bf56b0). Nothing sets
    retired today, so this is ready for when something does. A status the console doesn't know: no C3 and no
    line, with the status in Technical details, as U99 does (the page has no status tag to say it). Waiting for
    approval reads the same under either approval setting: "Applies without approval" only lifts who may approve,
    and a model is never approved automatically.
  - A revision without a model revision (`mission_model_revision_id` is nullable, mms-engineer): A1 keeps its row
    unlinked, and there's no C3.
- **Profile cards** (api's rollout read):
  - `Earendil Block 1 · 500 spacecraft · rev 14`, written out as "spacecraft", not "SC" (no shorthand on screen).
    `current_revision` null means the profile sets no catalog (api), so the card reads `· no catalog set`, never
    "catalog set per spacecraft".
  - A profile where nothing would move (`moves_all` 0): checkbox disabled, with the reason built from api's
    buckets (setup.md; `override_pinned + already_on_revision + moves_all = spacecraft_count`). Only nonzero parts
    appear, singular for 1: `already_on_revision` gives "499 are already on rev 15" / "1 is already on rev 15";
    `override_pinned` gives "1 keeps its own catalog" / "3 keep their own catalog". For example: "Nothing on this
    profile would move: 499 are already on rev 15 and 1 keeps its own catalog." With `spacecraft_count` 0: "This
    profile has no spacecraft."
  - Chosen, with `moves_default` 0 but `moves_all` > 0 (everyone is on an older version): under the card, "None of
    its spacecraft are on the profile's current version, so only the option below moves any." The older-versions
    checkbox follows.
  - The older-versions line, when the current version isn't known: "Also move the 499 on older versions. They move
    to the profile's current version with every profile change since theirs, not only the catalog." Never `v?`.
  - No profiles at all: `By profile` is disabled, with "This mission has no profiles yet. Use A few spacecraft
    first."
- **A few spacecraft first:** the picker and its chips name each craft as `EARENDIL-004 · SCID 4` (SCID only when
  set). A craft with no name reads "Unknown spacecraft" (U25), never its id.
- **Breaking callout, singular:** "Rev 15 changes 1 command or point in a way that breaks existing use. Cadence
  can't tell yet what uses it." Plural as C3. Checkbox: "I've checked the breaking change" / "I've checked the 3
  breaking changes".
- **On a revision's page,** the breaking count is the one against the revision before it in the same database (by
  number), the base C3's diff uses on the import page. Both revisions are immutable, so the count doesn't move when
  later revisions are imported (only a release that changes what counts as breaking can change it). Data
  (mms-engineer and fe-setup, 11-19, #195's two-reads build; final): the revision read carries `import_run_id`
  (never null when the revision is there), `breaking` (an integer, or null when it isn't known) and `breaking_base`
  (`{catalog_revision_id, revision}`, the revision compared against; null when there is none). The same three
  states the server sends, never computed in the console:
  - `breaking` > 0: the callout and checkbox below, as on the import page, plus what it compared against: "Rev 4
    changes 3 commands or points in a way that breaks existing use, compared with rev 3. Cadence can't tell yet
    what uses them." `breaking` 0: no callout,
    no checkbox.
  - No earlier revision (`breaking_base` null): "Rev 1 is the first revision of this catalog, so Cadence has
    nothing earlier to compare it with and can't tell what it breaks. Check what uses its commands and points
    before you stage." The acknowledgment checkbox reads "I've checked what rev 1 changes". There's no
    `Open its import`, since its diff has nothing to compare.
  - The diff couldn't be read (`breaking_base` set, `breaking` null): the uncompared line below, with no link.
    Its import has the same base and diff, so its page can't count either, and `Open its import` would lead to a
    page that says the same (mms-engineer, #386).
  - A server without these fields: "This page can't show whether rev 4 breaks anything in use. Check its import's
    diff before you stage." with `Open its import` only when `import_run_id` is there, and the acknowledgment
    checkbox "I've checked rev 4's diff". (U86: say what the console can't read.)
  - **The import page's C3 follows the same cases**, from its own fields, and is never 0 breaking for an
    unknown count (U20: 0 would claim nothing breaks):
    - `diff.summary.breaking` an integer: the count, as above.
    - `base_revision` null with `diff` null: a first revision, the words above.
    - `base_revision` set with `diff` null, or `diff.summary.breaking` null: the import page's own line, since
      the person is already on the import whose diff couldn't be read (a revision's page uses it too, above):
      "Cadence couldn't compare rev 4 with rev 3,
      so this page can't show whether it breaks anything in use. Check what uses its commands and points before you
      stage." No link. The checkbox reads "I've checked what rev 4 changes".
  - **Stage's disabled reason** (A6) mirrors the checkbox that's still unticked: "Check the breaking change
    first." / "Check the 3 breaking changes first."; a first revision, and the uncompared line on either page:
    "Check what rev 4 changes first."; a server without the fields: "Check rev 4's diff first." C3
    always has a number: catalog revisions are always numbered, and a model revision without one has no C3 (see
    above), so these lines have no "this catalog revision" form.
- **The dry run, in the person's words:**
  - While it runs: `CHECKING…` (as C3). Stage's disabled reason is "Checking what this moves…", not "Waiting for
    the dry run.".
  - When it fails: "Couldn't check this rollout, so it can't be staged yet." plus the server's sentence when it
    sends one, with `Check again` (quiet; it re-runs). Stage's reason is "Check the rollout again first." It isn't
    a "Not staged:" line, because nothing was asked to stage.
- **The footer** states acceptance criterion 5 instead of "one generation" (an internal word): "Nothing changes until
  this change set is applied in Setup › Changes. The mission's approval setting decides whether someone else must
  review it first." (mms-security: under "Applies without approval" a submit applies with no review.)
- **At scale (> 100 spacecraft):** C3 shows counts only, never names. The names are on the Changes review's
  groups (U94's fleets).

### U103 · Import again, a source file's page, and a spacecraft's apps (#146; L18, L19) (mms-ux / fe-setup / mms-engineer)
All three are built (api 05aa7e399, b18dcf7b5; fe-setup d72327020, 72fb52c0f, 704960442, 7836fc692). This entry
fixes their words and lists what the legacy pages offered that the console doesn't yet (acceptance criterion 5).

**Import again (the source file's page)**
- The help under the header no longer promises a new revision. The match is on the compiled result, not the file
  (mms-engineer: the digest covers the compiled declarations and the importer and compiler versions). So the same
  file makes a new revision only after an importer or compiler upgrade. The versions are part of the match, so
  an upgrade makes a new revision even when the declarations are identical. The line: "Import again runs the
  current importer on this file. It makes a new revision only if the importer has been updated since, or its
  result differs. Otherwise it matches a revision that already exists. Nothing changes on spacecraft until a
  revision is rolled out."
- The run that results shows U99's words when it matches.
- 409 `import_running`: "Not started: an import of this file is already running." with `Open the run`. Any other
  failure: "Not started:" plus the failure sentence.
- "Recorded as mine" (acceptance criterion 1): the import runs table's `Started` cell reads "11-19 05:40Z by Mira K."
  (U29, one event). A system actor reads "by Cadence"; a missing actor shows the time alone. A service identity
  of the mission's own organization is named and marked as a service, so it doesn't read as a person: "11-19
  05:40Z by Nightly planner (a service identity)". A service with no name (`kind` service, `name` null) says what
  it was and not who: "11-19 05:40Z by a service identity", as U70 (mms-security: the kind names no one and says it
  wasn't a person). A person with no name, or no actor, shows the time alone, never an id (U25). (Amended 11-19,
  fe-setup's #364 question and ux's #371.)
  Data: the run row stores `requested_by` (an actor: kind and user id), so the runs read adds its display name
  (#146's read; fe-setup assigns it).

**A source file's page and the runs table**
- `Download` keeps its visible word, and its accessible name adds the file: "Download
  earendil_fsw_3.2.0.xtce.xml" (B7; the name starts with the visible word). The same goes for the `Download`
  beside each row in A1 Revisions and on the import run's file line, where several sit on one page.
- No runs: the panel's empty state reads "No imports of this file yet." (legacy had "No runs yet.").
- A `Finished` column (legacy's "Completed"): the time, or "Still running" while it runs. Status words stay
  Catalog.md's (`Parsing`, `Valid`, `Failed`, plus U99's `Matches rev 4`).

**A spacecraft's apps (panel S9 on the spacecraft page)**
- **Acts name their object** (B7): accessible names "Install Telemetry Decom", "Disable Telemetry Decom",
  "Enable Telemetry Decom", "Uninstall Telemetry Decom". The visible word stays short.
- **Disable and Uninstall confirm first** (the server's lifecycle registry has confirms; this page never showed
  them). In plain words, checked by mms-engineer:
  - `Disable Telemetry Decom for EARENDIL-004?`: "Its pages close and its settings can't be edited until it's
    enabled again. Its settings are kept. What runs for EARENDIL-004 doesn't change." Actions `Disable` / `Cancel`. The way back is `Enable`, the
    install action on a disabled app (the server records it as enabled), so the words match the button.
  - `Uninstall Telemetry Decom from EARENDIL-004?`: "Its settings are kept, so installing it again brings them
    back, on the app's current version. What runs for EARENDIL-004 doesn't change." Reinstall reuses the installation and takes the version registered then.
    Actions `Uninstall` (danger) / `Cancel`. Focus starts on `Cancel`.
  - **"What runs … doesn't change"** is confirmed (api, a code read on a48743995): disable and uninstall publish no
    domain facts, and `spacecraft_configuration_changed` only invalidates reads. What runs comes from the activated
    configuration. A disabled app blocks later edits made through it, not what runs.
- **Uninstall from installed too** (legacy offered it whenever the server allowed it; the console makes you
  disable first). Show it whenever the server says it's allowed.
- **Outcomes**, from the server's answer only (U20), announced (`role="status"`, a11y B6):
  - Applied now: "Telemetry Decom is installed for EARENDIL-004." / "…is disabled…" / "…is enabled…" /
    "…is uninstalled from EARENDIL-004."
  - Staged: info, not caution: "Staged. It applies when the change set is applied." with `Open Changes`.
  - Refused: by the act, "Not installed:" / "Not disabled:" / "Not enabled:" / "Not uninstalled:", plus the
    failure sentence.
- **Status words** match the mission list (acceptance criterion 4): `Installed`, `Disabled`, `Not set up`,
  `Platform · always on`. The server's status also has `unavailable`: it reads `Unavailable` (mark + color + word)
  when sent, never mapped onto the other three. fe-setup widens the list reader so a new value can't break the
  page. Legacy's `Upgrade required` is left out because no server on develop sends it; add its word when one does.
  A state the console doesn't know reads `Status not known` (as the L9 status line).
- **Empty and missing:**
  - No apps at spacecraft scope (the list holds the apps that can be installed for one spacecraft, so empty means
    none can): "No apps can be installed for a single spacecraft." plus "Apps for the whole mission are in
    Setup › Apps." with that link.
  - A 404 `spacecraft_not_found` uses the spacecraft page's own not-found state, never "Spacecraft apps aren't
    available in the console yet", which is only for a server without the route.

**Parity left for fe-setup** (legacy L19, not in the console yet; build, or record why not): the `Readiness` link in
the page header; the protocol preset picker ("Choose protocol preset", "No protocol preset selected", with "Pinned
profile" and "Current"); the installed, available and app versions (the console shows `v3` only).

### U105 · An automation grant takes effect only after a second admin approves it (#283) (mms-security / ca-ux / fe-ops)
Under "Needs a second person's approval", issuing a grant (Contact planning › Policy › Grants) makes a proposal that
authorizes nothing until a different org admin approves it. That admin must be outside the people accountable for the
service it names (U100). Under "Applies without approval", the proposer's own approval stands, as for other kinds.
Revoking or narrowing is a tightening: any org admin does it alone, at once. The panel mirrors the policy's own
"Waiting for approval" (P5). Shape: mms-security's, agreed with api 11-19; codes switched on with `knownErrorCode`.

- **States** (`State` column; mark + word, B2): `PROPOSED` (caution), `ACTIVE` (nominal), `REJECTED` (off),
  `REVOKED` (off), `WITHDRAWN` (off), `EXPIRED` (stale). `expired` is derived on read and means two things; the row says which:
  - a proposal undecided past `proposal_expires_at` (72 h): "Proposed by Mira K. at 11-19 06:40Z; no one decided it
    in time." Told apart by `approved_at` being null.
  - an active grant past `valid_until`: today's line.
  - A proposed row: `Valid until` reads "30 days from approval" (from `validity_seconds`; `valid_from` and
    `valid_until` are null until approval), and the state line "Proposed by Mira K. at 11-19 06:40Z · decide by
    11-22 06:40Z".
  - A rejected row (`rejected_by`, `rejected_at`, `rejection_reason`, together or none): "Rejected by Ana R. at 11-19
    06:52Z: <reason>". Without them: "Rejected."
  - A withdrawn row (a widening proposal ended because its grant was revoked; `withdrawn_by`, `withdrawn_at`):
    "Withdrawn at 11-19 07:05Z, when Ana R. revoked the grant it would replace." Without them: "Withdrawn: the grant
    it would replace was revoked."
- **The sheet** (`Grant automation…`):
  - Under "Needs a second person's approval": title `Propose a grant`, commit `Propose grant`, muted line above the
    footer: "It takes effect once another org admin approves it. Until then Nightly planner can't act under it."
    After a `proposed` answer: "Proposed. It takes effect once another org admin approves it. If no one decides by
    11-22 06:40Z, it expires."
  - Under "Applies without approval": title `Grant automation`, commit `Grant`, muted line "It takes effect at once.
    No second person's approval is needed, as this mission's setting allows." After an `active` answer: "Granted.
    Nightly planner can act under it until 12-19 06:40Z."
  - The approval setting unread (missing from the read): the propose wording, never "at once"; the answer's state
    says what happened.
  - Any other answer (U20): "Cadence didn't confirm the grant. Reload to see it."
- **Waiting for approval** (panel on a proposed grant): "Proposed by Mira K. at 11-19 06:40Z: <reason>. It takes
  effect once another org admin approves it. If no one decides by 11-22 06:40Z, it expires." Actions `Approve grant for Nightly planner` and
  `Reject…`. Reject needs a reason: up front "Give a reason first." (A7); the 422 `invalid_params` field message
  (`Say why.`) shows under the field.
  - **Up front (A6) from `viewer_can_decide` and `cannot_decide_because`, never computed in the console** (#233's
    pattern). Approve is disabled with its reason, muted under it and as its description; Reject stays:
    - `proposer`: "You proposed this grant, so another org admin approves it."
    - `accountable` (`cannot_decide_details.grantee`, the same key as the 403): "You're accountable for Nightly planner, so another org admin
      approves its grant."
    - `authors_unknown` (`cannot_decide_details.service`): "Nightly planner has no one recorded as accountable for it, so its grant can't be approved
      yet. An org admin records who's accountable in People › Service identities." (U100's words)
    - `not_admin`: no actions; the panel's line ends "Org admins approve grants."
    - `not_proposed`: no panel (the row's state says why).
    - `not_a_person`: never shown in the console (a service can't sign in); as `not_admin` if it is.
    - `policy_changed` (#497: the mission's approval setting changed since the proposal, so approving would answer
      the 409 below): "The mission's approval setting changed after this grant was proposed, so it can't be approved.
      It has to be proposed again." Reject stays, so the proposal can be cleared.
    - A reason the console doesn't know: "You can't approve this grant, so another org admin approves it." with the
      code in Technical details.
- **Approve refusals** (nothing recorded; each says "Your approval wasn't recorded." after the why, U95):
  - 403 `automation_grant_self_approval_forbidden`, `because: "proposed"`: "Not approved: you proposed this grant,
    so another org admin approves it. Your approval wasn't recorded." `because: "accountable"` (`grantee`, the service the grant empowers; a different key from U100's
    `via_service` on purpose): "Not
    approved: you're accountable for Nightly planner, so another org admin approves its grant. Your approval wasn't
    recorded." Then Approve is disabled with the up-front line.
  - 403 `automation_grant_approver_authors_unknown` (`service`): "Not approved: Nightly planner has no one
    recorded as accountable for it, so its grant can't be approved yet. An org admin records who's
    accountable in People › Service identities. Your approval wasn't recorded." (U100's words)
  - 409 `automation_grant_not_proposed` (`state`; `decided_by` and `decided_at`, both or neither): with them, as U97: "This
    grant was already approved by Ana R. at 11-19 06:52Z, so your approval wasn't recorded. Reload to see it." /
    "…already rejected by…"; the viewer: "You already approved this grant at 11-19 06:52Z. Reload to see it." (with
    the date, since a 72 h proposal spans days) Without them, by state:
    `expired`: "Not approved: no one decided this grant in time, so it expired. Your approval wasn't recorded.
    It has to be proposed again."; `rejected`: "Not approved: this grant was already rejected, so your approval wasn't
    recorded. Reload to see it."; `active`: "…was already approved…"; `revoked`: "Not approved: this grant was
    revoked, so your approval wasn't recorded. Reload to see it."; `withdrawn`: "Not approved: this proposal was
    withdrawn when the grant it would replace was revoked, so your approval wasn't recorded. Reload to see it."
  - 409 `approval_policy_changed` (`kind: "automation_grants"`; until #201, api's interim name): "Not approved: the
    mission's approval setting changed after this grant was proposed. Your approval wasn't recorded. It has to
    be proposed again."
  - 403 `authenticated_user_required` (a service, even one with organization_admin; the code U104 uses). Every grant
    act is person-only (mms-security, #283; #282's default): a leaked service token must not decide, narrow or
    switch off automation. **Unreachable today:** there's no REST grant route and a service can't sign in to the
    console, so the domain rule is the backstop and these lines are for any future surface:
    - Approve: "Not approved: only a person can approve a grant, not a service identity. Your approval wasn't
      recorded."
    - Propose: "Not proposed: only a person can propose a grant, not a service identity."
    - Reject: "Not rejected: only a person can reject a grant, not a service identity. Nothing changed."
    - Narrow: "Not narrowed: only a person can narrow a grant, not a service identity. Nothing changed."
    - Revoke: "Not revoked: only a person can revoke a grant, not a service identity. Nothing changed." Revoke stays
      one person and immediate; it just has to be a person.
  - Replays (approve, reject and narrow take an `operation_id`, as #257's plans): the same id and body returns the
    original answer with `replayed: true`, shown as this one's result. 409 `duplicate_operation`: "Not approved:
    Cadence matched this to an earlier, different request, so your approval wasn't recorded. Reload and try again."
    (reject: "Not rejected: … so nothing changed."; narrow: "Not narrowed: … so nothing changed.")
  - A code the console doesn't know: "Not approved: Cadence refused this approval. Your approval wasn't recorded."
    with the code in Technical details.
- **Use under a grant that isn't active** (403 `automation_grant_not_active`, `state`), on the plan's state line as
  U100's automation line, by the service's act (plan: "Not drafted automatically:", submit: "Not submitted
  automatically:", approve: "Not approved automatically:") then by state: `proposed` "Nightly planner's grant isn't
  approved yet."; `rejected` "Nightly planner's grant was rejected."; `expired` "no one approved Nightly planner's
  grant in time."; `withdrawn` "Nightly planner's grant was withdrawn." The existing `automation_grant_revoked`, `automation_grant_expired` and
  `automation_grant_not_yet_valid` keep their lines.
- **Narrow** (`Narrow…` on an active grant; one person, at once): sheet title `Narrow the grant`, commit `Narrow`,
  muted line "It takes effect at once. Narrowing only takes access away, so no approval is needed." After the answer:
  "Narrowed. Nightly planner can now <what's left>." A change that isn't strictly narrower is refused, 422
  `automation_grant_not_narrower` (`fields`, the widening ones, named by the sheet's labels: `allowed_actions` Can,
  `maximum_horizon_seconds` Plans ahead up to, `maximum_contacts` Contacts per plan, at most,
  `maximum_execution_concurrency` At once, at most, `validity_seconds` Valid for; an unknown field by its code in
  Technical details only): "Not narrowed: this
  change gives Nightly planner more than it has now (Contacts per plan, at most), so it needs approval. Propose it as
  a new grant instead." Without `fields`, the same without the bracket. The console offers only narrower values in the sheet, so this is the backstop.
  - Nothing changed (422 `automation_grant_narrow_unchanged`, #497): "Not narrowed: these values are the ones the
    grant has now, so nothing changed. Choose less than it allows, or cancel." Up front (A6/A7), `Narrow` is disabled
    until a value is narrower, with the reason "Choose less than the grant allows now."; the 422 is the backstop.
- **Access the person doesn't hold** (403 `automation_grant_capability_required`, #497; #281's rule: whoever proposes,
  grants or approves must hold every capability the grant gives; no `details`). **Unreachable today:** an org admin
  holds every capability a grant can give; the lines are for when that changes. By the act:
  - Propose: "Not proposed: this grant would let Nightly planner do something you can't do yourself, so you can't
    propose it. Ask an org admin who can do everything it allows to propose it."
  - Grant (under "Applies without approval"): "Not granted: this grant would let Nightly planner do something you
    can't do yourself, so you can't grant it. Ask an org admin who can do everything it allows to grant it."
  - Approve: "Not approved: this grant lets Nightly planner do something you can't do yourself, so you can't approve
    it. An org admin who can do everything it allows approves it. Your approval wasn't recorded."
  - No list of what's beyond them: the 403 carries none (U20), so the lines don't name it. With no name, "the service
    identity this grant is for" replaces "Nightly planner".
- **Revoke** stays one act, at once, with a reason, even while a widening of the same grant is proposed. If one is,
  the revoke sheet adds: "This also withdraws the proposal waiting for approval, so it can't switch automation
  back on later." (A widening proposal records `replaces_grant_id`; revoking that grant withdraws it in the same
  transaction.)
- **A grant made before Cadence checked grants against the approval setting** (#497; the row's
  `issued_before_two_person_approval: true`) can only be revoked. Never "legacy" or "two-person" on screen, and not
  "before grants needed a second person's approval", which isn't true on a mission set to "Applies without approval"
  (ux).
  - The row's state line adds, muted: "Made before Cadence checked grants against the mission's approval setting, so
    it can only be revoked. To change it, propose a new grant."
  - Up front (A6/A7): `Narrow…` is disabled with "This grant can only be revoked. To change it, propose a new
    grant." `Revoke…` stays.
  - The backstop, 409 `automation_grant_legacy`, by the act: Narrow "Not narrowed: this grant was made before Cadence
    checked grants against the mission's approval setting, so it can only be revoked. Nothing changed. To change it,
    propose a new grant."; Approve "Not approved: this grant was made before Cadence checked grants against the
    mission's approval setting, so it can only be revoked. Your approval wasn't recorded."; Reject "Not rejected: …
    so it can only be revoked. Nothing changed." (Approve and Reject can't show on an active grant, so those two are
    for completeness.)
- **Widening** (more actions, more services, longer validity) is a new proposal, worded as the sheet above.
- **Audit** (who and when as one event, U29): "Proposed a grant for Nightly planner", "Granted Nightly planner
  automation (no approval needed under this mission's setting)" for a grant that takes effect at once, "Approved Mira K.'s grant for
  Nightly planner", "Rejected Mira K.'s grant for Nightly planner: <reason>", "Revoked the grant for Nightly planner:
  <reason>", "Narrowed the grant for Nightly planner: <what changed>", "The proposed grant for Nightly planner
  expired; no one decided it in time.", "Withdrew the proposed grant for Nightly planner, when revoking the grant it
  would replace" (the actor and time lead, U29)
- **A nameless service** (`grantee` or `service` with a null `name`, as U100/#287): the name drops, never an id (U25;
  the id goes in Technical details). "Nightly planner" becomes "the service identity this grant is for": "You're
  accountable for the service identity this grant is for, so another org admin approves it."; "The service identity
  this grant is for has no one recorded as accountable for it…"; the sheet's "Until then the service identity can't
  act under it."; "Not submitted automatically: the service identity's grant isn't approved yet."; the action reads
  `Approve grant`. Sheets and rows already name the service from the
  grant's own read; a null name there reads "Unknown service identity" (U25).
- **Not here:** whether a grant approved under "Applies without approval" keeps working after the mission moves to
  "Needs a second person's approval" (#283's open question 1, the director's call); widening who may propose or
  approve to mission admins (open question 2).

### U106 · A decided sample gets a newer revision: the decision stands, the operator is told (#369, lead's ruling 11-19) (domain / api / Telemetry & Data)
An operator's decision on a sample stands until an operator changes it (lead, #369): a newer canonical revision of
the same sample doesn't clear it (clearing it silently was the bug). Because the decision stands, the newer revision
isn't used, and without a word nobody would notice. Tell the person who decided, and anyone who can decide, so they
can look again. Words only; no build yet.
Not a crit: nothing is wrong, a person's call may simply be out of date.
- **Decision words** (U80's Record states, as acts; `decision.kind`):
  - mark_conflict: "marked it as a conflict"; mark_advisory: "kept it for reference only"; mark_superseded: "marked it
    as replaced"; mark_canonical (a promote): "made it the record Cadence uses".
  - A kind the console doesn't know: "decided on it" (the kind in Technical details, never the raw word).
- **Now item**, one per point, collecting the samples that got a newer revision since the item was raised:
  - Title: `EARENDIL-004 · EPS.batt_voltage · a decided sample has a newer revision` / `… · 3 decided samples have a
    newer revision`.
  - Meta: `FIRST 02:08:11Z · LAST 02:14:40Z · DECIDED BY MIRA K.` (sample times; "DECIDED BY 2 PEOPLE" when several).
  - Body, one sample: "Mira K. marked the 02:08:11Z sample as a conflict at 11-18 03:40Z. A newer revision of it
    arrived at 11-19 05:40Z from the 11-19 backfill. Cadence still follows Mira K.'s decision, so the newer revision
    isn't used. Look at both, and keep the decision or change it."
  - Several: "3 samples that operators decided have a newer revision. Cadence still follows each decision, so the
    newer revisions aren't used. Look at each, and keep the decision or change it." with `Show all 3` listing each as
    "02:08:11Z · marked as a conflict by Mira K. at 11-18 03:40Z · newer revision 11-19 05:40Z".
  - The source of the revision is named when the read has it ("from the 11-19 backfill"; late or corrected data
    too, never a replay, whose samples are their own, domain); without one the clause drops (U20). The decider and
    the time are one event (U29); a nameless person drops the name ("marked … as a conflict at 11-18 03:40Z"), never
    an id (U25); a service gets "(a service identity)" (U103).
  - Actions: `Review` opens the sample (U80's aside, at that time, with all revisions shown) for one sample; `Show
    all 3` for several. `Keep the decisions` (`Keep the decision`) for anyone who can decide: an acknowledgement, it
    changes nothing in the data. Someone who can't decide gets `Review` only, and the line "An operator who can decide
    on telemetry keeps or changes it."
  - Priority: P3, neutral mark (no tone). It isn't raised again by more revisions of a sample already in it; a sample
    added later reopens a kept item.
- **Resolutions** (who and when as one event):
  - Kept: "Kept by Ana R. at 11-19 06:10Z: the decision stands." / "…: the decisions stand."
  - Changed: when every sample in it gets a new decision, "Changed by Ana R. at 11-19 06:12Z." A sample whose decision
    changes leaves the item; the rest stay.
  - The samples are no longer kept (retention): "These samples are no longer kept, so there's nothing to review."
- **The sample's Record row** (U80's aside), under the state, while a newer revision is set aside by a decision:
  "Marked as a conflict by Mira K. at 11-18 03:40Z. A newer revision arrived at 11-19 05:40Z; the decision still
  applies." Kept: adds "Kept by Ana R. at 11-19 06:10Z."
- **Data asks (domain → api; for the build, not now):** per item mission, spacecraft and point (names), and per
  sample `{sample_at, decision {kind, by {kind, name}, at, decision_event_id}, newer_revision {arrived_at, source
  label | null}}`, plus `viewer_can_decide` and the kept acknowledgement `{by, at}`. The Record row needs the same
  `decision` and `newer_revision` on U80's one-sample read. `newer_revision.arrived_at` is the state's `last_seen_at`
  when `latest_revision` > `canonical_revision` (domain).
- **"The newer revision isn't used" holds for every kind only once #369 is fixed as widened** (domain 11-19): an
  exclusion leaves out every sample of the identity; a promote keeps its `canonical_*` columns, which today a newer
  revision moves. U106 isn't built before #369 lands.

### U107 · Now: a row's buttons carry the row's title in their names (#243 B7, audit N5) (fe-ops)
Now's per-row buttons (`Review`, `Open pass`, `Details`, `Mark as seen`, `Acknowledge…`, `Retry storing`,
`Retry…`, `Close without retry…`, `Discard…`, `Book 40 passes` and the rest) repeat on every row, so a screen reader
hears "Discard, Discard, Discard" (a11y B7). Every row title is already worded here and already names what the row
is about, so the name reuses it; no short noun is invented per kind.
- **The accessible name:** the visible label without its trailing "…", a comma, then the row's title with each
  " · " read as ", ". "Discard, EARENDIL-001, SNTG 00:13Z pass, 3 connections refused"; "Book 40 passes, Plan for
  11-16 is approved but booking hasn't started"; "Open, 3 spacecraft, below red limit".
- The label comes first, so what's spoken starts with what's seen (WCAG 2.5.3). It's long, but exact: two rows
  about the same spacecraft still differ.
- Built once in the panel from the row's title, not per row kind, so a new kind gets it for free.
- A row without a title (none today) uses its kind and position, as B7 says: "Discard, row 3".
- Sheets the buttons open keep their own titles (A2); this is only the button's name.

### U108 · The monitoring lane: limits, derived points and alarm rules through change sets (#28; DECISIONS #92 phase 3, #93; ADR-020 addendum, change-set lanes) (domain / api / mms-ux / the squads that build the editors)
**The UX spec for phase 3's monitoring lane** in domain's mission-model build plan (#440,
`docs/apogee/domain/mission-model-build-plan.md`, issue J). It applies U64 (the user's four conditions) to domain's
design. Limits, alarm rules and derived points are change-set kinds in a second lane, **monitoring**. The lanes
never freeze each other, and revisions from both share one sequence. Monitoring has one **open** set per mission;
its sets in review don't count, so review never closes it. Configuration is unchanged (DECISIONS #13): one shared
set, frozen while in review. Applying a monitoring set recompiles the effective model and
activates it, and the set's review is the approval of the authored layer. U43 (limit words) and U42 (a derived point
in use) still hold. Domain's answers on #438 (11-19) settled the model points.

- **Words.** The lanes are **Configuration** and **Monitoring**. The kind words on Changes are `Limits` (U43),
  `Derived point` and `Alarm rule`. Summaries follow U43: "Add derived point BATT_HEALTH" / "Edit …" / "Retire …";
  "Add alarm rule <name>" / "Edit …" / "Retire …". Mission limits on a point the catalog limits read "Replace
  catalog limits for BATT_V". Point names are in mono. Visible text never says "layer", "authored layer",
  "effective revision" or "recompile". The effective model revision ids go in Technical details, as with U65.
- **Where they're edited (IA).** Setup gets **Monitoring** (`M/setup/monitoring`, tabs `limits` · `derived` ·
  `alarm-rules`). It replaces the Limits and Derived telemetry entries in Setup › Apps once the old modules retire.
  - Each tab lists imported and authored definitions together. A `Source` column reads `Catalog rev 4`
    (read-only; its row says "From the catalog. Change it by importing a new revision.") or `Mission` (editable).
  - Ops opens the same editor as a side sheet: `Edit limits…` on a point's row in Investigate and on an alarm. Ops
    shows no staged bar; the sheet shows its own outcome.
- **Operational relief stays outside (U64 1).** Acknowledge and Shelve on Alarms never stage anything. The limit
  editor opened from an alarm doesn't offer them, and nothing in it suggests an edit is how to quiet an alarm.
- **Live and staged side by side, and who staged it (U64 4).** Each field shows the live value. When a change to it
  is staged, the staged value shows beside it as the Profile board's edited state (Changes.md §1), and the meta reads
  "Staged by Mira K. at 14:02Z" (U29; a service is marked as U70 says). In a set under review it reads "In review ·
  staged by Mira K. at 14:02Z".
  - **A point staged by someone else** (in the open set): the editor shows it, and its actions are disabled up front
    (A6) with "Mira K. has BATT_V's limits staged (at 14:02Z). Change them in that staged change, or ask Mira K. to
    withdraw it." plus `Open the staged change`. The refusal, path_already_staged, is the same sentence after "Not
    staged:" (or "Not applied:" from `Apply now`). Without a name (U25): "BATT_V's limits are already staged (at
    14:02Z). Change them in that staged change, or ask whoever staged them to withdraw it."
  - **A point in a set under review** (the one block review leaves, domain #438 2): disabled the same way with
    "BATT_V's limits are in a change set under review (staged by Mira K. at 14:02Z). You can change them once it's
    applied or sent back." Without a name: "(staged at 14:02Z)". The refusal opens "Not staged:" or "Not
    applied:". Only that point is blocked; every other point stays editable.
  - With you as the stager, the editor opens your staged values instead, so neither shows to you.
- **Apply now, when monitoring changes apply without approval (U64 2).** The editor's primary is `Apply now`. It
  makes a one-change set from your edit and applies it at once; others' staged monitoring changes stay staged,
  untouched (domain #438 1). Its preview is inline, above the button:
  - the change as `− old` / `+ new` rows;
  - the checks (below), with their holds and NO-GOs;
  - the effect, "Applies to 500 spacecraft" (from the server's dry run, never counted in the browser);
  - a required `Why` (10 characters or more, as Changes.md K3). With one hold it takes that hold's placeholder
    (U43).
  - Outcome, with U91's verbs: "Applied as r7. The runtime is applying it." then "BATT_V is checked against the new
    limits from 14:02:10Z." If the runtime hasn't applied it, U91's caution line. Never "Saved".
- **Stage change, when monitoring changes need a second person's approval.** Staging and review are as in
  Changes.md, on the monitoring lane.
  - The Ops sheet's outcome after staging: "Staged. BATT_V's limits change when another person approves and
    applies them in Setup › Changes." plus `Open monitoring changes`.
  - The reviewer is never one of the set's authors (U97's family); refusals are Changes.md §3's.
- **Replacing the catalog's limits** (domain #438 3: the mission's limit wins, only as an explicit replace). When the
  point has limits from the catalog, the editor says so above the action, before anything is staged: "BATT_V has
  red limits from catalog rev 4 (3.10–4.20 V). These replace them on this mission." The action names it:
  `Stage replacement` / `Apply replacement now`. No check result is needed for it then.
- **Two lanes on Changes.**
  - **Staged bar:** one line per lane with an open set or a set in review: `CONFIGURATION · 2 changes: …  [Review &
    apply]` (its in-review state as Changes.md §2) and `MONITORING · 1 change: Edit limits for BATT_V · 1 set in
    review  [Review & apply]`. Neither button
    carries a revision number: with one sequence, the number depends on which set applies first. It shows on the
    review page's commit (`Apply as r6`), and Changes.md §2's `Review & apply as r6` drops its number once the lane
    ships.
  - **Review page:** `M/setup/changes` (Configuration) and `M/setup/changes/monitoring`. A tab pair at the top
    reads `Configuration · 2` / `Monitoring · 1`. The page and its h1 name the lane: "Apply monitoring changes · 1
    change". Sets of that lane in review are listed above the open set, one line each: "In review · 3 changes ·
    sent for review by Mira K. at 14:02Z" (no name: "sent for review at 14:02Z") plus `Open review`.
  - **Review doesn't pause monitoring staging** (domain #438 2, monitoring only). Sending a monitoring set for
    review leaves the lane open, and new edits start its next set. frozen_in_review on the monitoring lane fires
    only for a point in a set under review, with the words above. Configuration keeps Changes.md §2's *In review*
    state ("r6 in review · staging is paused"), its frozen_in_review and its disabled Stages, and U79's
    conversion_in_progress still holds while a conversion set is in review.
- **Checks (K2) on the monitoring lane.**
  - **Compiles** ("Every limit, derived point and alarm rule compiles against the live model"): NO-GO. Each
    failure names the definition, then what it refers to. Dangling reference: "BATT_HEALTH uses BATT_SOC_PCT,
    which isn't in the live model." With the cause when the server gives it: "… (renamed or removed in catalog rev
    5)."
  - **Conflicts with the catalog:** a replaced catalog limit that changed since the replacement (the fingerprint
    drifted) is a NO-GO on whichever set causes the drift, until someone confirms or retires the mission's limit:
    "BATT_V's catalog limits changed in catalog rev 5 after this mission replaced them. Confirm the mission's
    limits again or retire them in Monitoring." plus `Open in Monitoring`. In Monitoring, that row's editor offers
    `Confirm replacement`, a monitoring change like any other. A catalog rollout causes it on the configuration
    lane, so it shows in C3's dry run (U102) too, as the dangling reference does.
  - U43's limit_alarm_active and U42's derived_point_in_use, unchanged.
- **Across the lanes.** The lanes never freeze each other, but they compile together. A configuration set that would
  leave a monitoring definition dangling gets a NO-GO on the configuration lane, and in C3's dry run (U102) too, so
  a catalog rollout that would fail at review can't be staged from the catalog page: "Catalog rev 5 removes BATT_V,
  which 2 limits and 1 derived point use. Retire or change them in monitoring changes first." The names go behind
  `Show all`, as U42 lists them. The fix goes through the monitoring lane, which the configuration set's review
  doesn't block. These are the two cross-lane checks: a dangling reference and a drifted replacement (above). The
  lanes never stage the same thing, so there's no overlap check.
- **Revisions.** One sequence: a monitoring apply takes the mission's next revision number (r6 configuration, r7
  monitoring), ordered by when each applies. The Revisions list tags it `Monitoring`, Timeline reads `Config r7
  applied · Monitoring · 1 change · Mira K.`, and roll back works as for any revision.
- **The model gate.** Applying a monitoring set never puts anything up for catalog approval (U65), because domain
  counts the effective revisions as approved. No catalog row, panel or Now item mentions them.
- **Catalog and spacecraft surfaces keep naming the catalog revision.** U65 and U102 (Catalog, a revision's page,
  C3), U94 (a spacecraft's configuration and What changes) and U99 never show a monitoring apply. A spacecraft
  stays "on catalog rev 14" after one. Effective model revision ids appear only in Technical details, including the
  revision page's "Mission model revision" row.
- **The old side stores.** Dev has nothing to move (0 rows, domain 11-19), so they retire as code, with no screen.
  If an environment ever has rows, a person stages them in the console as a monitoring set, "Move 48 limits and 6
  derived points from the old apps", and another applies it under four-eyes. Never a script, and never under
  someone's name (TEAM RULE, Controls). No history backfill (#92).
- **Per-spacecraft limits (open with the user, #92).** Domain recommends declarations scoped to a context, one
  revision for the fleet. If the user adopts that, each definition gets `Applies to`: `All spacecraft` (default),
  a profile, or a context (U43's named sets, `ECLIPSE`). Summaries name it as U43 does: "Edit ECLIPSE limits for
  BATT_V", "Edit limits for BATT_V on Block 2". Per-spacecraft deltas in any other form come back to ux.
  - **The Profile page's hook** (mms-ux): limits scoped to a profile sit beside Profile P3's overrides, so the
    profile's summary carries a line with the server's count, e.g. "3 limits apply only to this profile · Open in
    Monitoring". Its words come with the follow-up once the user rules.
