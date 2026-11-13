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
  definition in the Derived telemetry app (from `used_by[].point_id`).
- It doesn't fire when every dependent is retired or changed in the same change set. If domain makes it
  acknowledgeable instead, the first clause becomes "Retiring BATT_SOC_PCT breaks BATT_HEALTH, whose expression
  uses it." and ux adds a placeholder.
