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
2. **Rule source:** show the rule text (`≥ 3 CONTACTS A DAY · NO GAP OVER 10h00`) with its true source,
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

