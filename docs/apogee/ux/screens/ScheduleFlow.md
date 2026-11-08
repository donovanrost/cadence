# Scheduling flow: Prediction · Plan · Re-plan · Review (phase 3)

Boards `ScheduleFlow`, `PassPrediction` (K0), `SchedulePlan` (K1), `Replan` (K2), `PassReview` (K3).
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
**`PROVIDER FREEZE T−15:15:51`** (white; caution under 1 h).
```
┌ A Demand (300, pane) ┐ ┌ B Draft · by station (Gantt, pane) ───────┐ ┌ D Selected (340, pane) ┐
│ search · exceptions  │ ├ C <focused spacecraft> · 24 h strip ──────┤ │ pass detail + options   │
│ rule summary         │ └──────────────────────────────────────────┘ └────────────────────────┘
footer: Passes │ Minutes / budget │ Cost / budget │ Rule met │ Conflicts │ caption + [Submit N requests]
```
- **A Demand:** header meta `6 NOT COVERED` (caution) or `ALL COVERED` (nominal). Search ("any
  spacecraft"); list = **only spacecraft whose rule isn't met** (start from demand, R01), each `dm`
  row: mark, name (mono), why ("Longest gap 11h20 > 10h00"), stat (`2 / 3 CONTACTS`). Selecting
  focuses C and highlights the spacecraft on B. Footer: the profile rule (`≥ 3 CONTACTS A DAY · NO
  GAP OVER 10h00 · ≥ 1 UPLINK-CAPABLE PASS`) + `EDIT IN SETUP · PROFILE →`. Rules come from profile
  demand (requirements/templates today, IA §3).
- **B Draft:** rows = antennas (18), id + uplink capability (`UP`) small; marks: drafted (white
  `mk.own`), the focused spacecraft's drafted passes (`mk.own` + ring), its other windows (dashed
  white), windows taken by others (dashed, caution when clashing), newly added (white + green ring
  `mk.new` **[only place nominal green appears on the Gantt: "now covered"]**), station maintenance
  (amber hatch band). Hour axis. Header meta `1,512 PASSES · 18 ANTENNAS · 00–24Z`. Legend above.
- **C Focused spacecraft · 24 h:** rule chips (`rc`: `Contacts 3/3` GO, `Longest gap 11h20` HOLD,
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

## K3 · Close the books (`M/contacts/review`, reading)
Header (not a takeover): back · mono `PASS REVIEW · PLAN R39 · 3 PROVIDERS` over the day ·
`choice` `Day │ Week │ Month` · `Export CSV`, `Monthly close`.
- **h1:** `98.5% realized · $1,180 to dispute` (dispute amount in caution when > 0). Meta: provider
  report freshness (`REPORTS IN FROM ALL 3 PROVIDERS · LAST AT 01:12Z · 0 UNKNOWN`; unknown > 0 in
  stale text; an unreported provider makes the realized % provisional, said in words).
- **Stat strip:** Planned · Realized · Partial (caution) · Missed (crit; caption splits by owner:
  `5 provider · 3 us · 1 weather`) · Downlink vs plan · Minutes flown vs billed (`+31` caution when
  billed > flown).
- **R1 By station** (table): station, provider, planned, realized (meter + %), partial, missed, minutes
  flown, minutes billed; sorted by realization ascending.
- **R2 Why passes were lost:** cause bars (red = missed, amber = partial), "OWNER DECIDES WHO PAYS".
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
