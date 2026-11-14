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
| no_runtime_spec | "The mission's runtime has no active configuration, so passes can't start." | `Open Changes` |
| unknown | "Starting failed." | — |
| (missing) | "No reason was recorded." | — |

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
  - After LOS, or already canceled or ended: neither. Hand-started contacts get `End contact now…` too, in
    "contact" words (U46).
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
  - `no_scheduled_contact`: "Not canceled: this pass has no contact in Cadence."
  - `pass_not_found`: "Not canceled: the pass wasn't found."
  - Others: the server's message.
- **History from the read:** `contact_ended {kind, by, at, reason, cause}`. `cause: provider_failed` uses U56's
  "Canceled by Cadence … Northlight couldn't book this pass (“…”)", and an operator's cancel uses the lines above.
  The org audit row reads "Canceled the PUQ 13:04Z contact for EARENDIL-007: “…”" (typographic quotes).
- **Confirmed (domain, 11-14):** neither action cancels queued command requests. The queue is per spacecraft, so
  they wait for the next releasable contact, armed groups stay armed, and a named release (U46) keeps what it
  already sent. One addition: when some will expire before that next contact, the commands line adds "1 of them
  expires at 14:00Z, before then." (one: "It expires at 14:00Z, before then."). Data (api): per pass, the queued
  count, how many expire before the next contact with the earliest expiry, and the next contact's station and
  AOS.

### U56 · Contact events `window_moved` and the `provider_failed` cancel reason (domain's window-truth fix) (domain / api / fe-ops)
- **window_moved** `{before, after, provider_change}`: an accepted provider timing shift moved the contact.
  - **Times:** a shift is often seconds, so these lines give HH:MM:SSZ (§4's minutes form would hide a 30 s move).
    The date is added when it isn't today.
  - **Direction:** both ends move the same way: "30 s later" / "2 min earlier" (under a minute in s; above, min,
    or "1 min 30 s"). Otherwise the length changed: "changed this pass's window".
  - **Contact history:** "Northlight moved this pass 30 s later: now 12:11:27–12:19:27Z (was 12:10:57–12:18:57Z)."
    It links `Open the change` to the provider change (U44), which says who accepted it and when. Changed length:
    "Northlight changed this pass's window: now 12:11:27–12:21:27Z (was 12:10:57–12:18:57Z)."
  - **Timeline:** "EARENDIL-003 · BRS 12:11Z pass moved 30 s later by Northlight: 12:11:27–12:19:27Z". The label
    uses the new AOS.
  - While live: the history line adds "Cadence now listens until 12:19:27Z." when the end moved.
  - Without the provider's name: "The provider moved…". A hand-started contact can't be moved by a provider, so
    there's no "contact" form.
- **provider_failed** (Cadence cancels a contact whose booking the provider couldn't make; the phantom fix):
  - History: "Canceled by Cadence at 12:58Z: Northlight couldn't book this pass (“no antenna available”)." The
    provider's reason is free text and goes in quotes; when it's a code, it's worded or left out, never raw.
    Without a reason: "…couldn't book this pass."
  - Timeline: "EARENDIL-007 · PUQ 13:04Z pass canceled by Cadence: Northlight couldn't book it". The tag is
    `CANCELED` (off), as for an operator's cancel (U55).
