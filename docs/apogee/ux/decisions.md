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
  - All expired: "Not approved: all 36 of its passes have already started, so nothing could be booked." with
    `Plan the rest of 11-16`.
  - Partial approval: "Approved. Booking 1,476 passes; 36 had already started, so they weren't booked." The
    left-out passes are listed under `Show 36`, with spacecraft, station and AOS.
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
    "Outcome unclear" and isn't a resolution). An API credential shows by its display name: "Resolved as not sent
    by ops-automation at 03:20:05Z."
  - With no name: "Resolved as not sent at 03:20:05Z; who resolved it isn't known." (fe-ops 293aa2cd2)
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
  its display name.
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
- The last attempt is in caution: "attempt 3 of 3, the last the policy allows".
- With none left: Apply is disabled with "No re-plan attempts left (3 of 3). The planning policy sets the limit."
  plus a link `Planning policy` for admins.
- The window isn't editable (U-review 2026-11-15 A14d).

**Optional note on Submit and on Approve:**
- Field `Note for the record (optional)`, with the hint "Saved with your name in the plan's history."
- Over 2,000 characters: "Keep the note under 2,000 characters." The counter appears from 1,800, as with U65's
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
      applies it." Other sets keep today's reviewer_is_author sentence.
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
  in-use check blocks bookings, routes and open passes first. If domain adds `transport_archived` (a follow-up, lead
  to prioritise), U45's line is "Its transport, INU S-band, was archived, so this pass can't start. Choose another
  route for this spacecraft."

### U83 · A transport's listener: own or shared (lead, 11-16; DECISIONS #87) (domain / api / fe-setup)
A listen-mode downlink transport chooses whether its passes get their own listener or share one that routes each
connection by its first frame's SCID (#87). The words go on the transport kind's field definition (the server's
schema labels), so fe-setup's KindEditor shows them as they are.

- **Where:** the TCP Capability group, right after `TCP Port`.
- **Shown only** when `TCP Mode` is `TCP server (listen)` AND `Direction Capability` is `Inbound`. Otherwise it's
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
  - Not a downlink (`outbound` or `bidirectional`): "Only an inbound (downlink) transport can choose its listener."
  - Both at once: the first line only.
- **Change summary and diff:** the option words, e.g. "Listener: Own listener for each pass → Shared, routed by SCID".
- **A shared transport switched to connect, outbound or bidirectional** (lead/api, 11-16): the field hides and the
  console sends `listener: own` in the same stage, so the server doesn't refuse a hidden field.
  - In the form, at the switch, an info line under the field that changed (TCP Mode or Direction Capability):
    "This transport will stop sharing its listener: only an inbound transport that listens can share one."
  - The diff line shows, because it changes how passes connect, with the reason after it: "Listener: Shared, routed
    by SCID → Own listener for each pass (only an inbound transport that listens can share one)". The same words in
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
    to 3 names; never "1 other spacecraft, and may affect others")
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
