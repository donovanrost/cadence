# Scheduling flow: Prediction · Plan · Re-plan · Review (phase 3)

Boards `ScheduleFlow`, `PassPrediction` (K0), `SchedulePlan` (K1), `Replan` (K2), `PassReview` (K3).

> **Billing is out of scope (DECISIONS #63, U34).** Every money element below is **hidden**, not shown as
> "not reported": K1 Cost and budget tiles and the Cost column, K2's footer cost and billed-cancel counts,
> K3's dispute amount, billed minutes, R5 reconciliation and `Dispute` actions. Layouts reflow without them.
> Time-based facts stay (minutes flown, realized %).
Live view is `Contacts.md` (J4). Owner: fe-ops. Data: `docs/apogee/plans/ops.md` (requirements,
planning runs, contact plans, provider reservations). Scope: DECISIONS #4 (**no propagation**:
Cadence-computed prediction is deferred; opportunities come from providers).

**Principle: schedule the fleet, not a spacecraft.** Start from demand (each profile says how often
its spacecraft must be heard); Cadence drafts the day against every provider's opportunities; the
planner works only the exceptions. One contact, one state model (Opportunity → Drafted → Requested
→ Confirmed → In contact → Realized; off-ramps Partial, Rejected, Missed, Unknown, Cancelled), drawn
on one timeline. Time runs left→right, stations top→bottom. Searching a spacecraft highlights it in
place. Cost sits next to Submit. Every change is a revision (plan `r41 → r42`).

Routes (IA): `M/contacts/plan?day=YYYY-MM-DD` · `M/contacts/replan/:stationId` ·
`M/contacts/review?day=…&span=day|week|month`. All share the Contacts tab row; Plan and Re-plan are
**takeover console** screens with a station step bar; Review is a **reading** page.

---

## K0 · Pass prediction — deferred (DECISIONS #4)
Not built in this project. What carries over: Plan's step 02 **Opportunities** shows provider
windows with their source named (`NORTHLIGHT · provider window`) and, per the K0 board, each window
carries its inputs ("inputs, assumptions and limits travel with every window"). When server-side
propagation lands, K0 becomes `M/contacts/prediction` with its pipeline strip (orbit snapshot →
propagate → access → station calendar → opportunities), orbit-input quality list (worst first),
pass inspector, "changed since last run" (only changes that touch the plan) and a "what this run
trusts" panel with validation level and known limits in plain words. Keep that honesty when it's
built.

## K1 · Plan tomorrow (`M/contacts/plan`)
Takeover header: close · mono `CONTACT PLAN · R41 DRAFT · MAYA T.` over the day (`Friday 24 Oct`) ·
step bar `01 Demand · 02 Opportunities · 03 Draft · 04 Reserve · 05 · 06` · clocks `UTC` +
**`NEXT OFFER EXPIRES T−15:15:51 · KSAT`** (white; caution under 1 h). Providers publish no day-level
cutoff, so there's no "freeze" (U20). The clock is the earliest `expires_at` among the plan's passes not yet
sent (domain), with that offer's provider. It's absent when nothing is left to send.
- Hover/focus detail: "KSAT's offer for EARENDIL-012 · SVB-1 · 03:00Z expires at 02:30Z. Send before then,
  or that pass can't be booked." With several providers, one line each, earliest first: `KSAT T−15:15:51 ·
  Northlight T−18:02:10`. Add "3 more offers expire in the next hour." when that's so.
- **Expired offers** (lead 47ef6310 asked): an offer that lapsed before it was sent can't be fixed, so the clock
  doesn't count up from it. It moves on to the next live offer and adds a caution count, `NEXT OFFER EXPIRES
  T−01:12:40 · KSAT · 1 EXPIRED`. When every unsent offer has lapsed: `3 OFFERS EXPIRED` (caution, no clock).
  Expired passes lead Demand like rejections: `Expired · SVB-1 03:00Z: the offer lapsed at 02:30Z before it was
  sent.` The detail line reads "…expired at 02:30Z. That pass can't be booked; re-plan to replace it."
- The pass link goes to the pass in B (`snapshot_id`). On the simulator offers expire at AOS, so the same
  words apply.
```
┌ A Demand (300, pane) ┐ ┌ B Draft · by station (Gantt, pane) ───────┐ ┌ D Selected (340, pane) ┐
│ search · exceptions  │ ├ C <focused spacecraft> · 24 h strip ──────┤ │ pass detail + options   │
│ rule summary         │ └──────────────────────────────────────────┘ └────────────────────────┘
footer: Passes │ Minutes / budget │ Cost / budget │ Rule met │ Conflicts │ caption + [Submit N requests]
```
- **A Demand:** header meta `6 NOT COVERED` (caution) or `ALL COVERED` (nominal). Search ("any
  spacecraft"); list = **only spacecraft whose rule isn't met** (start from demand, R01), each `dm`
  row: mark, name (mono), why, stat (`2 / 3 CONTACTS`). For `max_gap_exceeded` (#74) the why reads "No contact
  for 11h20, 03:10Z–14:30Z. The rule allows 10h00." (`from`/`to` with the §4 date prefix when not on this day). Selecting
  focuses C and highlights the spacecraft on B. Footer: the profile rule (`≥ 3 CONTACTS A DAY · NO
  GAP OVER 10h00 · ≥ 1 UPLINK-CAPABLE PASS`) + `EDIT IN SETUP · PROFILE →`. Rules come from profile
  demand (requirements/templates today, IA §3).
- **B Draft:** rows = antennas (18), id + uplink capability (`UP`) small; marks: drafted (white
  `mk.own`), the focused spacecraft's drafted passes (`mk.own` + ring), its other windows (dashed
  white), windows taken by others (dashed, caution when clashing), newly added (white + green ring
  `mk.new` **[only place nominal green appears on the Gantt: "now covered"]**), station maintenance
  (amber hatch band). Hour axis. Header meta `1,512 PASSES · 18 ANTENNAS · 00–24Z`. Legend above.
- **C Focused spacecraft · 24 h:** rule chips (`rc`: `Contacts 3/3` GO, `Longest gap 11h20 · max 10h00` HOLD (GO when within; with no limit, a
  measure with no verdict and no `max`),
  `Uplink passes 1` GO), then a 24 h strip of passes (`cb`, uplink-capable with a notch) and gaps
  (`gp`: 1px line with label, caution + 2px when over the rule). Header meta `RULE MET` /
  `RULE NOT MET` tinted.
- **D Selected:** selected pass or window: title + spacecraft tag; `kvs` Window, Length, Antenna,
  Link (`S-band up/down`), Max el (provider-supplied only), Cost; note sentence; action (`Add pass`
  / `Remove pass`). Below, **alternatives** for the focused spacecraft (`alt` rows: when + antenna,
  meta, effect "closes gap to 6h10" in nominal / "clashes with 251" in caution, `Add`). Empty:
  "Click a pass or a dashed window on the Gantt, or pick an option below."
- **Footer (cost is part of the plan, R04):** `ft` tiles Passes · Minutes `/ 15,000` · Cost `/
  $190k day` (budgets only if configured; otherwise no denominator) · Rule met `494 / 500` (caution
  until all) · Conflicts. Caption (`4 PROVIDERS · CONFIRMATIONS RETURN TO THIS PLAN`) + primary
  `Submit 1,512 requests` (step 04). After submit the plan shows per-contact Requested → Confirmed /
  Rejected live; rejections become new A rows.

### K1 day strip (DECISIONS #100, A14; the user's ruling 11-16)
The day picker is a strip of the next **7 UTC days**, today first. Each day is a link (`?day=`), and the selected
day has the white inset bottom bar. A cell holds the day (`Tue 17`) over its plan's state in one word or phrase. The
words match U61's titles, so the strip and Now say the same thing:

| The day's newest plan | Word | Mark |
| --- | --- | --- |
| `reserved` | `Booked` | ■ nominal |
| `partially_reserved` | `1,490 of 1,500 booked` (of `requested_count`, what the approved plan books; api) | ▲ caution |
| `failed` | `Booking failed` | ▲ caution |
| `unconfirmed` | `4 unconfirmed` | ▲ caution |
| `executing` | `Booking…` | none |
| `pending_approval` | `Awaiting approval` | none, then U61's |
| sent back | `Sent back` | none, then U61's |
| `draft`, `drafting`, `interrupted`, `superseded` | `Draft` | none, then U61's |
| no plan, with requirements | `No plan` | none, then U61's |
| no requirements | `Nothing to plan` | none |

- **"Then U61's":** the strip uses U61's thresholds, so it never disagrees with Now.
  - ▲ caution from T−24h before the day's first window.
  - ◆ crit once the first window opens with no approved plan, when the word becomes `Started unplanned`.
- The booked count is always measured against what the plan books, never against demand: demand the plan doesn't
  cover is the accepted-gaps story, not a booking failure. The same holds in K1's header (`R41 · 1,490 OF 1,500
  BOOKED`).
- **Accessible name per cell:** "Tue 17 Nov: awaiting approval, first window 00:00Z". Marks are `aria-hidden`.
- `not_set_up` replaces the strip with K1's not-set-up callout. A day further than 7 days out is reached with the
  existing date picker beside the strip.

### K1 plan states (DECISIONS #27, #28; lead's model in plans/scheduling.md)
The takeover header's mono line names the state. There's **one primary per state**, always in the
footer's commit slot, and a blocked primary always says why in visible text under it (U6/§6).
| State | Header line (mono) | Body | Primary (footer) |
| --- | --- | --- | --- |
| `not_set_up` | `CONTACT PLAN · NOT SET UP` | `off` callout: "Cadence needs a planning policy and at least one contact rule before it can draft a day." Lists what's missing (`No policy`, `312 spacecraft have no rule`). | `Set up contact planning` → Setup › Contact planning |
| `no_draft` | `CONTACT PLAN · FRI 24 OCT · NO DRAFT` | Demand list (from rules) + "Last plan for this day: r40, booked 1,498 of 1,512" if any. | `Draft the day` |
| `drafting` | `DRAFTING · OPTIMIZING · 00:41` | Step bar shows 03 Draft as current, and a phase line `MATERIALIZING → SEARCHING → OPTIMIZING → PLAN` with the current phase in readout and elapsed time. Panels show what's known so far. | none (secondary `Cancel` only if the domain supports it) |
| `superseded` (draft) **[decision]** | `R41 DRAFT · SUPERSEDED` | stale callout: "This draft was made against contact rules that have since changed (template Block 1 daily v2 → v3, 05:40Z by api seed). It can't be submitted." The old draft stays readable: its Gantt bars and panel chrome are dimmed, its text stays at full contrast (U27). | `Draft again with the current rules` |
| `interrupted` (draft) | `DRAFTING STOPPED` | stale callout: "Drafting stopped at 02:31Z. Nothing was submitted." (name a cause only when the server reports one) | `Continue drafting` |
| `draft` + **conflicts** | `R41 DRAFT · 2 CONFLICTS` | Conflicts as crit rows at the top of D (`SVB-1 double-booked 03:20Z: 073 and 251 overlap 3 min`), each with `Move` / `Remove`. Conflicting passes dashed caution on the Gantt. | `Submit` **disabled**, reason under it: "2 conflicts on SVB-1 and FBK-2. Move or remove a pass to submit." (Conflicts always block, #28.) |
| `draft` + **unmet requirements** (no conflicts) | `R41 DRAFT · 6 SPACECRAFT NOT COVERED` (U23) | A Demand lists them first (see below). Footer `Rule met 494 / 500 spacecraft` caution; A meta `6 SPACECRAFT · 14 CONTACTS SHORT`. | `Accept 6 gaps and submit` → **Accept gaps sheet** |
| `draft` ready | `R41 DRAFT · READY` | Totals; `Rule met 500/500` nominal. | admin: `Submit and book 1,512 passes` (confirm sheet: totals, providers, "This books passes with 3 providers"); member: `Request approval` |
| `pending_approval` | `R41 · WAITING FOR AN ADMIN` | member: info callout "Sent to org admins 02:44Z." Read-only plan. admin: ApDecision (`Approve and book` / `Send back` with a comment). Reviewer ≠ author. Accepted gaps listed with their reasons. | admin: `Approve and book 1,512 passes` |
| `executing` | `BOOKING · 812 OF 1,512` | Per-contact trail Requested → Confirmed / Rejected live on the Gantt (rejected = caution dashed), with counts in the footer. When every request is out and the plan only waits on providers (#52): info callout "All 4 requests went out · waiting for Northlight to confirm." | none |
| `unconfirmed` **[U30]** | `R41 · 36 BOOKED · 4 UNCONFIRMED` | caution callout: "Northlight hasn't confirmed 4 bookings after 10 min. They may or may not be booked, so Cadence won't send them again. Check them with Northlight." (window from the server; per-provider split when several: "(Northlight 3, KSAT 1)"). Under it, the passes: spacecraft · station · AOS (mono) · `T−` to the first. On the Gantt they're stale-hatched with the tag `UNCONFIRMED`. | none; secondary `Open Contacts` only if Contacts shows them as unconfirmed |
| `interrupted` (execute) | `BOOKING STOPPED · 812 OF 1,512` | stale callout: "Booking stopped. 812 requests went out; 700 didn't." (U20: state what's known; name a cause only when the server reports one.) Only requests that never went out count here (#52). | `Continue booking` (resumes those; never re-sends a sent one) |
| `reserved` | `R41 · BOOKED` | nominal callout "1,512 passes confirmed." | secondary `Open Contacts` |
| `partially_reserved` / `failed` | `R41 · 1,490 OF 1,500 BOOKED` / `R41 · BOOKING FAILED` | Rejections become A Demand rows (`Rejected by Northlight: antenna fault`). | `Re-plan after provider changes` (K2) |

**A Demand when a spacecraft can't be covered at all:** the row says so plainly, with no alternatives.
Caution mark, name, and "No window can cover it: no station sees EARENDIL-389 with uplink today"
(the cause from the server: no opportunity / all windows taken / constraint excludes every station),
then mono `0 / 3 CONTACTS`. D's alternatives list says "Nothing else is visible from the network that
day." and offers only `Accept gap` (adds it to the sheet with the reason prefilled from the cause). An
uncoverable spacecraft never shows a disabled `Add`.

**Accept gaps sheet** (side sheet, opened by the primary): title `Accept 6 gaps · 14 contacts short` (a gap = one uncovered spacecraft, U23 amendment; its unmet requirements are listed inside the row, with an optional `Different reason per requirement` disclosure); one row per unmet
requirement: mark, spacecraft (mono), the rule and shortfall (`2 / 3 contacts · longest gap 11h20 >
10h00`), the cause, and a required reason field. A `Same reason for all` checkbox fills empty reasons
from the first. Footer: caption `AUDITED · VISIBLE TO THE APPROVER` + primary `Accept 6 gaps and submit`
(member: `Accept 6 gaps and request approval`), disabled until every row has a reason, with the
count still missing under it ("2 gaps still need a reason"). Accepted gaps show in the plan as `GAP
ACCEPTED · <reason>` rows, and in the revision history.

**Repairs (U28):** K1 never opens a repair proposal as the day's plan. It shows the day's own plan + an info
callout `A re-plan proposal is open for this day … Open in Re-plan →`.

### K1 booking reasons (`passes[].booking.reason`, api list)
Demand leads with `<Word> · SVB-1 03:00Z: <reason>.`, where the word is the bar's state: `Rejected`, `Failed`,
`Unconfirmed` (uncertain), `Not sent` (Cadence stopped before the provider call) or `Lost` (after a booking was
placed). When api exposes the provider's free-text `detail`, it's appended in quotes: `…no capacity then
("Station full")`. Any code not listed: the code with underscores as spaces, plus the raw code in Technical
details.

| Code | Reason text | Next step shown |
| --- | --- | --- |
| no_capacity | the station has no capacity then | `Re-plan` |
| conflict | it clashes with another booking at the provider | `Re-plan` |
| invalid_request | the provider refused the request as invalid | — |
| provider_unavailable | the provider couldn't be reached | (retry) |
| authentication_failed | the provider didn't accept Cadence's credentials | `Check provider account` |
| authorization_failed | the provider account isn't allowed to book this | `Check provider account` |
| unsupported_capability | the provider doesn't offer this kind of pass | — |
| not_found | the provider doesn't know this pass or station | — |
| provider_not_ready | the provider wasn't ready to take bookings | — |
| rate_limited | the provider asked Cadence to slow down | — |
| known_timeout | the provider didn't answer in time | — |
| ambiguous_outcome | the provider's answer didn't say whether it's booked | (U30/U32 resolve) |
| malformed_response | the provider's answer couldn't be read | (U30/U32 resolve) |
| provider_error | the provider reported an error | — |
| contact_plan_execution_opportunity_expired | the window passed before it was sent | `Re-plan` |
| contact_plan_execution_snapshot_not_found | the pass isn't in the plan's opportunities any more | `Re-plan` |
| contact_plan_execution_route_changed | its route changed after the plan was drafted | `Re-plan` |
| contact_plan_execution_route_not_ready | its route isn't ready yet | — |
| mission_provider_not_found | this mission has no provider set up for that station | `Fix in Setup` |
| provider_account_version_not_found | the provider account's settings are missing | `Fix in Setup` |
| provider_account_grant_not_found | this mission isn't granted the provider account | `Fix in Setup` |
| provider_account_grant_revoked | this mission's access to the provider account was revoked | `Fix in Setup` |
| credential_reference_not_found | the provider credentials can't be found | `Fix in Setup` |
| invalid_provider_context | the provider setup for this mission isn't valid | `Fix in Setup` |
| missing/invalid_provider_booking_field, invalid_provider_booking, invalid_contact_interval, unknown_provider_client, malformed_provider_booking_result, provider_booking_failed | Cadence couldn't build the booking request. This needs a Cadence fix | — (code in Technical details) |
| booking_lost | the provider dropped a confirmed booking | `Re-plan` |
| provider_canceled | the provider canceled it | `Re-plan` |
| provider_reservation_not_found | the provider has no record of the booking | `Re-plan` |
| provider_configuration_failure | the provider setup failed | `Fix in Setup` |
| operator_not_booked / rejected / not_sent | marked not booked / rejected / not sent by Mira K. at 10:52Z (U29; without an actor: "by an operator") | — |
| provider_rejected, provider_failed, other provider_<status> (status-based answers, domain fix) | the provider rejected it / the provider couldn't book it / the provider answered "<status>", plus its detail | — |
| null | the provider didn't say why | — |

`Fix in Setup` → Setup › Ground stations › Providers. `Check provider account` → Organization › Provider
accounts. `Re-plan` → K2. A next step shows only when the viewer can take it. A `(retry)` or `—` row says nothing
about retrying unless the read says so (api, after 8e): `retryable: true` with `retry_after_seconds` adds "Cadence
retries at 03:12Z."; `true` without it adds "It can be retried."; `false` adds "Retrying won't help."; null adds
nothing. `resolved {by, at}` supplies the actor and time for operator resolutions.

## K2 · A station goes down (`M/contacts/replan/:stationId`)
Entered from Now (P2 station degraded), the Contacts station row or ⌘K. Takeover header: close ·
mono `RE-PLAN · LIVE PLAN R41 · 02:45–10:45Z` over `Svalbard outage` · step bar `01 Impact · 02
Proposal · 03 Apply` · clocks + **`FIRST HIT PASS T−00:00:58`**.
```
┌ A Impact (300, pane) ┐ ┌ B1 Live plan r41 (Gantt) ─────┐ ┌ C Changes (360, pane) ┐
│ station · tiles      │ ├ B2 Proposed r42 (Gantt)       ┤ │ tiles · need you list │
│ rides on these passes│ └───────────────────────────────┘ │ provider requests     │
footer: Revision r41 → r42 │ Passes −N │ Cost today │ Rule met │ [Wait for provider ETA] [Apply r42 · send N requests]
```
- **A Impact:** station + `◆ DOWN` tag, provider's report in a sentence (cause, ETA, "isn't
  confirmed"), antenna marks; tiles Passes hit · Spacecraft · Downlink · Uplinks; "Rides on these
  passes": queued requests and plans affected, each one sentence on what happens when you apply
  ("2 queued uplinks follow their passes when you apply.").
- **B1/B2:** the same window, before and after. B2 draws the outage as a red-hatched band with
  `OUTAGE · PROVIDER ETA 06:30Z`, moved passes white, unchanged gray. Header metas `64 PASSES ON A
  DOWN STATION` / `52 MOVED · 3 DROPPED · 9 NEED YOU`.
- **C Changes:** tiles Moved (`to FBK, INU, KIR`) · Dropped (`rule still met`) · Need you (`3 break
  the rule`); **Need you** rows: mark, spacecraft + when, proposed fix (mono, tinted) and one action
  (`Buy AWA-2`, `Accept gap`); sample of moves (`from → to`, offset); provider requests summary
  (`CANCEL 64 · NORTHLIGHT · 22 INSIDE 2 h ARE BILLED`, `BOOK 52…`, `BUY 1…`).
- **Footer:** revision delta, passes, cost today, rule met (caution until all), secondary `Wait for
  provider ETA`, primary `Apply r42 · send 117 requests`. Apply is one revision with batched provider
  requests (R05).
- **Apply sheet (U28):** "This approves the proposal and sends 4 booking requests. The 36 kept passes
  stay booked." A repair keeps every committed pass locked (S8), so Apply only books: requests = moves +
  adds, and drops send nothing. If cancellations ever become possible, split the count by kind.
- **After Apply:** the step bar sits on `03 Apply`. Execution states reuse K1's table: an interrupted
  execution shows the same stale callout under the header ("Booking stopped. 2 requests went out; 2
  didn't.", or "Booking stopped before every request went out." when counts
  aren't known, per U20) with `Continue booking` in the footer. Partial or failed results also follow K1.

## K3 · Close the books (`M/contacts/review`, reading)
Header (not a takeover): back · mono `PASS REVIEW · PLAN R39 · 3 PROVIDERS` over the day ·
`choice` `Day │ Week │ Month` · `Export CSV` (time facts only: R1 by station, R4 missed/partial; built client-side). `Monthly close` is dropped with billing (#63, U34).
- **h1:** `98.5% realized · $1,180 to dispute` (dispute amount in caution when > 0). Meta: provider
  report freshness (`REPORTS IN FROM ALL 3 PROVIDERS · LAST AT 01:12Z · 0 UNKNOWN`; unknown > 0 in
  stale text; an unreported provider makes the realized % provisional, said in words).
- **Stat strip:** Planned · Realized · Partial (caution) · Missed (crit; caption splits by owner:
  `5 provider · 3 us · 1 weather`) · Downlink vs plan · Minutes flown vs billed (`+31` caution when
  billed > flown).
- **R1 By station** (table): station, provider, planned, realized (meter + %), partial, missed, minutes
  flown, minutes billed; sorted by realization ascending.
- **R2 Why passes were lost** (`Why passes fell short` when nothing was missed): cause bars (red = missed,
  amber = partial), meta `BY WHO OWNS THE CAUSE` (no payment wording, U34).
- **R3 Realization · 30 days:** daily bars vs a dashed target line, annotated dips (`8 OCT · AWA
  RAIN`).
- **R4 Missed and partial passes** (table): AOS, spacecraft, antenna, outcome tag (mark + word),
  planned, flown, cause, owner (`Provider` / `Us` / `Weather`), action (`Dispute` when the provider
  owns it). Footer `SHOWING 10 OF 23 · 5 DISPUTABLE`.
- **R5 Provider reconciliation:** one tile per provider: billed (minutes + money), flown, dispute;
  `Draft dispute` or `Matches` (disabled, nominal text).
- Money appears only if providers report prices; otherwise the cost columns and the h1 dispute
  clause are absent.

## Acceptance (for qa)
- Plan opens on the uncovered list, never on a spacecraft picker.
- Re-plan applies as one revision with batched provider requests; the footer shows the cost.
- Review never shows a final percentage while a provider report is missing; it says provisional.
- No Cadence-computed prediction (elevation, sky plot, AOS error) appears until propagation exists.
