# Scheduling data plan (lead)

Owner: lead (K0/K1, shared plan pieces, ApGantt); **K2 Re-plan: fe-setup** (DECISIONS #43,
`features/replan`, importing shared pieces from `features/scheduling/index.ts`). Status: draft 3, 2026-11-09 (ux U22, DECISIONS #25–#27 folded in). Scope (DECISIONS #24): ScheduleFlow, K0 Pass prediction,
K1 Plan, K2 Re-plan, K3 Review. Design: `docs/apogee/ux/screens/ScheduleFlow.md`. Reference:
`frontend/docs/contact-scheduling-architecture.md`, `frontend/modules/planning-and-contacts`.
Missing items are numbered **S1…** and collected in the [ask list](#ask-list-for-api-ops). Related
fe-ops asks: **M4** (in contact now), **M7** (passes by station in a window), **M22** (conflicts).

## What exists today (backend inventory, 2026-11-09)

| Concept | Where | Notes for the SPA |
| --- | --- | --- |
| Provider opportunities | `ProviderControl.search_opportunities` → `POST /api/cadence/contact-workspace/v1/missions/:m/actions/search` | Per spacecraft + route, ≤ 7 days, ≤ 100 results, signed 15-min `token` per window. Fields: `starts_at, ends_at, expires_at, availability, synthetic, station, antenna, cost`. The only provider today is the simulator: `deterministic_pass_v1` (5400 s cadence, 600 s pass, ±120 s jitter), `synthetic: true`. **No orbit propagation anywhere.** |
| Reserve / cancel | same API, `reserve {token}` / `cancel {reservation_evidence}`, durable operation journal (`operation_id`, `accepted / unconfirmed / completed / rejected`) | Workspace endpoints need `x-cadence-workspace-user/organization` headers on top of the session and use their own envelope. |
| Demand | `ContactRequirementVersion` (window, success measure `any_contact / minimum_duration / minimum_data_volume / contact_count`, priority, direction, station allow/deny), templates | Only on the application-host bridge (`cadence.ops.contact_requirement_*`). Not profile-level yet (IA §3: profile demand later). |
| Fleet draft | `FleetPlanningRun` (phases `materializing → searching → optimizing → materializing_plan → finished`), `FleetPlanningDecision` (`selected / displaced / ineligible / locked`, score, rank, rationale), resources (`peak_parallel / capacity / over_capacity`) | App-host only (`cadence.ops.fleet_planning_*`). This is K1's "Cadence drafts the day". |
| Contact plans | `ContactPlan` (`draft → pending_approval → approved → executing → partially_reserved / reserved / failed`, versions), execution items (`pending / requesting / reserved / uncertain / rejected / failed`) | App-host only (`cadence.ops.contact_plan_show`). **No list endpoint** (`Management.Contacts.list_plans` exists, unused). Versions give the `r41 → r42` revision. |
| Re-plan | `FleetRepairs`: repair run from a plan in `executing / partially_reserved / failed`, locking `reserved / uncertain / requesting` commitments | App-host only. Triggered by provider changes, not by a station status. |
| Reservations | `ProviderReservation` (`requesting … confirmed / active / completed / unknown / rejected / canceled / failed`, `pass_phase`, `delivery_state`) + provider-change review | **Station and antenna live only inside the requested/confirmed snapshot documents.** |
| Ground stations | `GET /api/console/v1/missions/:m/ground-stations` (session JSON) | Setup data only: `code, provider, region, lifecycle_state`. **No availability, outage or maintenance windows.** |
| Flown data | live runtime per realized contact (token API only); persisted downlink observations keyed by `realized_contact_id`; contact interval events | **No planned-vs-flown read**, no actual AOS/LOS on Cadence records (`RealizedContact` has no end), no per-pass bytes/frames/gaps summary. The simulator produces planned-vs-actual results, but Cadence never ingests them. |
| Push | none for contacts/plans | Workspace polls every 5 s. The console `mission:<id>` channel has no `contacts` resource. |

**Transport decision (lead):** the SPA won't speak the application-host bridge or the workspace
header protocol. Every read and action below goes through session-authenticated `/api/console/v1`
endpoints that wrap the existing domain (same authorization, same operation journal semantics:
client `operation_id`, `accepted / unconfirmed / completed / rejected`, observe without retrying the
provider). That's the S-list.

## One contact model in the UI

ScheduleFlow's state model maps onto today's records as follows. One decoder in
`features/scheduling/contact.ts` owns the mapping; screens never see raw lifecycle strings.

| UI state | From |
| --- | --- |
| Opportunity | provider window not in the plan (search result / plan opportunity `disposition` not selected) |
| Drafted | fleet decision `selected` or `locked` in the working draft |
| Requested | plan execution item `pending / requesting`, reservation `requesting / pending` |
| Confirmed | reservation `confirmed`, `pass_phase` `scheduled / prepass` |
| In contact | reservation `active` / `pass_phase` `pass`, or realized contact `active` |
| Realized | reservation `completed` + realized contact `completed` |
| Partial | **needs S9** (flown < planned) |
| Rejected / Cancelled / Missed / Unknown | reservation `rejected` / `canceled` / scheduled `expired` without realization / reservation `unknown` |

## Per screen

### K0 · Pass prediction: not a screen (DECISIONS #4)
No route. Its honesty moves into K1 step 02: every window names its source, e.g.
`SIMULATOR · SYNTHETIC WINDOW` (from `synthetic: true`) or `NORTHLIGHT · PROVIDER WINDOW`, and the
D-panel shows "Provider-supplied. Cadence doesn't compute passes yet." No elevation, sky plot or
AOS error anywhere (acceptance). Max elevation only if a provider sends it (S1 carries it as
nullable).

### K1 · Plan tomorrow (`M/contacts/plan?day=`)
| Region | Data | Today | Gap |
| --- | --- | --- | --- |
| Header: plan line `CONTACT PLAN · R41 DRAFT · MAYA T.` | plan id, version, state, author | plan versions (app-host) | **S3** draft read |
| Header clock `PROVIDER FREEZE T−…` | per-provider booking cutoff | none | **S5** (omit clock until present) |
| A Demand: uncovered spacecraft, why, `2 / 3 CONTACTS` | per-spacecraft rule evaluation against the draft | requirement versions + fleet decisions `failures` | **S2** demand evaluation |
| A footer: rule text + `EDIT IN SETUP · PROFILE →` | rule summary | requirement/template | S2; link target per ux Q2 |
| B Draft Gantt: rows = stations/antennas, marks by state | all windows + drafted passes for the day, station + antenna + uplink capability | per-spacecraft search only; decisions have no station field | **S1** passes in a window (shared with fe-ops **M7**) |
| B maintenance band | station unavailability | none | **S7** |
| C focused spacecraft 24 h strip, gaps vs rule | S1 filtered + S2 per spacecraft | | S1, S2 |
| D Selected: window, length, antenna, link, cost, alternatives with effect | S1 row + alternatives with "closes gap to 6h10" | none (effect needs rule evaluation) | **S4** (what-if per alternative), or compute client-side from S1 + S2 rules (lead prefers server: one rule engine) |
| Add / remove pass | edit the draft | lock/unlock decisions inside a fleet run (app-host) | **S4** |
| Footer: passes, minutes / budget, cost / budget, rule met, conflicts | totals of the draft | resources + decisions | **S3** totals; budgets only if configured (none exist → no denominators) |
| Submit N requests | create plan from draft + execute (batched reservations) | `create-plan`, `submit`, `approve`, `execute-plan` (app-host) | **S5** one action, operation-journaled |
| After submit: per-contact Requested → Confirmed / Rejected live | execution items + reservations | polling only | **S1** states + **S10** push |

### K2 · A station goes down (`M/contacts/replan/:stationId`)
Today there's no station outage concept: a "station down" only reaches Cadence as provider changes
or cancellations on individual reservations, and replanning is a fleet **repair run** on a plan.
| Region | Data | Gap |
| --- | --- | --- |
| A Impact: station `◆ DOWN`, provider report, ETA, tiles (passes hit, spacecraft, downlink, uplinks), "rides on these passes" | station status + outage window from the provider; affected reservations; queued uplinks tied to those passes | **S7** station availability; **S8** impact read (uplinks need commanding's link to contacts, M17/M7) |
| B1 / B2 live r41 vs proposed r42 | S1 for the window + the repair proposal | **S8** repair proposal (moved / dropped / need-you, from → to) |
| C Changes + provider requests summary (cancel / book / buy, billed inside 2 h) | repair proposal + provider terms | **S8**; billing terms only if providers report them |
| Apply r42 · send N requests | one revision + batched provider requests | **S8** apply (operation-journaled) |
v1 if S7 slips: enter K2 from a plan with provider-rejected/cancelled reservations ("Re-plan after
provider changes"), same layout, with A Impact listing the changed reservations instead of a
station. Question for ux (Q5).

### K3 · Close the books (`M/contacts/review?day=&span=`)
| Region | Data | Gap |
| --- | --- | --- |
| h1 `98.5% realized · $1,180 to dispute` | realized/planned for the span; dispute only if providers report prices | **S9** |
| Provider report freshness / provisional | per provider: last report time, missing reports | **S9** |
| Stat strip, R1 by station, R4 missed/partial table, R2 causes | per contact: planned window, actual AOS/LOS, flown minutes, downlink bytes/frames vs plan, outcome, cause, owner | **S9** (actual AOS/LOS and volume aren't persisted on Cadence records today) |
| R3 30-day realization | daily aggregates | **S9** (`span=month`) |
| R5 reconciliation, Draft dispute | provider billing (minutes, money) | **S9**, later; v1 omits R5 and money unless providers report billing |
v1 without S9 is not honest enough to ship as "realized %" (no actual LOS, no volume). Ship K3 only
on S9; until then the Contacts tab row shows Review as "not available yet" (ApEmptyState `off`).

## Shared pieces (lead builds in `@cadence/apogee-ui` / `features/scheduling`)
- **ApGantt** (design-language ApPassStrip/ApGantt): rows (station/antenna, degraded code tint), lanes,
  bars by contact state (scheduled outline, live white, conflict dashed caution, new = white + green
  ring), outage (red hatch), maintenance (amber hatch), unusable (dark hatch), now-line, hour axis,
  gap markers, keyboard focus per bar with an inspector. Reused by fe-ops' Contacts (J4) and Now A4.
- `features/scheduling/contact.ts`: the one contact-state decoder/mapping above.
- K1/K2 use ApTakeoverHeader + ApStationBar-style step bar, ApTimePicker for the day, ApDecision
  isn't needed (no two-person rule on plans today; ask ux if plan approval should be).

## Phasing
1. **Now (no new endpoints):** ApGantt in the kit, reviewed on /console/kit with fixtures; the
   contact-state mapping + tests; routes for K1/K2/K3 render honest "not available yet" states.
2. **With S1 + S2 + S3:** K1 read-only (demand, draft Gantt, focused strip, selected pass).
3. **With S4 + S5 (+ S10):** K1 edits and Submit with live confirmations.
4. **With S7 + S8:** K2.
5. **With S9:** K3.

## Ask list for api-ops
All under `/api/console/v1/missions/:mission_id`, session + CSRF, `{data}` envelope, errors
`{error:{code,message,details?}}`. Actions carry a client `operation_id` and follow the existing
journal semantics. Please document each in `docs/apogee/api/scheduling.md`.

- **S1 Passes in a window** `GET /passes?from&to[&spacecraft_id][&station_id][&states=]`: one row per
  contact or window in the unified model: `{id, kind: opportunity|contact, state, spacecraft_id,
  station{id,code}, antenna{id,label}|null, starts_at, ends_at, uplink_capable|null, source{provider,
  synthetic}, max_elevation_deg|null, cost{amount,currency}|null, plan{id,version}|null,
  reservation_id|null}`. Bounded window (≤ 7 d), capped count with `truncated`. Shares with fe-ops M7.
- **S2 Demand evaluation** `GET /demand?day=&plan=draft|<plan_id>`: per spacecraft `{spacecraft_id,
  rule_met, contacts{have,need}, longest_gap_s{value,max}, uplink_passes{have,need}, reasons[]}` +
  the rule text and its source (requirement / template / profile). Filter `only_unmet=true`.
- **S3 Draft for a day** `POST /contact-plans/drafts {day}` (starts a fleet planning run for
  00–24Z) and `GET /contact-plans/drafts/:id`: phase, author, base plan + version, totals (passes,
  minutes, cost if known, rule met n/total, conflicts n), and the drafted passes (or reuse S1 with
  `plan=draft:<id>`).
- **S4 Edit the draft** `POST /contact-plans/drafts/:id/passes {add: window token | remove: id}` →
  updated totals + per-spacecraft effect; plus `GET …/alternatives?spacecraft_id` returning windows
  with their effect on that spacecraft's rule ("closes gap to 6h10", "clashes with 251").
- **S5 Submit** `POST /contact-plans/drafts/:id/submit {operation_id}` → creates the plan revision
  and executes it (batched reservations); per-provider booking freeze times in the draft read.
- **S6 Plans list** `GET /contact-plans?day|state` (id, version, state, day, author, counts).
- **S7 Station availability** `GET /ground-stations/:id/availability?from&to` and a status on the
  stations list: `{state: up|degraded|down|unknown, since, reported_by, eta|null, windows[{from, to,
  kind: outage|maintenance|unusable, source}]}`. Provider-reported; say so.
- **S8 Re-plan** `POST /contact-plans/:id/repairs {station_id?, from, to, operation_id}` → proposal
  `{moved[{contact, from, to, offset_s}], dropped[], need_you[{spacecraft_id, when, fix_options[]}],
  provider_requests{cancel, book, buy, billed_inside_s}, totals}`; `POST …/repairs/:id/apply
  {operation_id}`. Plus the impact read for A (passes hit, spacecraft, uplinks queued on them).
- **S9 Pass review** `GET /contacts/review?from&to&span=day|week|month`: per contact planned window,
  actual AOS/LOS, minutes flown/billed, downlink bytes/frames vs plan, outcome, cause, owner
  (`provider|us|weather|unknown`); per provider report status (`last_report_at`, missing); daily
  aggregates. Needs ingest of provider contact results (the simulator already produces them).
- **S10 Push** a `contacts` resource on the `mission:<id>` invalidate event (reservations, plans,
  runs, availability changes).

## Decisions (2026-11-09)
- **DECISIONS #25:** K2 v1 = "Re-plan after provider changes" on the existing repairs, entered from a
  plan or a rejected reservation; the station-down entry waits for S7. K3 waits for S9 (tab hidden).
  S7 and S9 are in domain's backlog after profile-routing P2. K1 proceeds on S1–S6.
- **DECISIONS #26:** S2–S6 and S8 → api; S1 (+ stations read, S10) → api-ops with M7.
- **api-ops shaping:** S3 is async (202 + draft id, progress via a channel event like
  `change_set_progress`); S1 `cost` / `max_elevation_deg` null unless provider-supplied.
- **ux U22:** Q1 plan day = 00–24Z. Q2 show the rule with its true source (`FROM REQUIREMENT TEMPLATE
  … ↗` to the existing page). Q3 no budgets, no denominators. Q4 omit the freeze clock. Q5 yes (as
  #25). Q6 hold K3, hide its tab. Q7 window source = `<SOURCE> · <KIND>`; the simulator always says
  `SIMULATOR · SYNTHETIC WINDOW`, plus a stale callout when any window is synthetic. Q8 rows =
  stations, antennas as sub-rows only when reported. Q9 follow server policy: one planner by default;
  ApDecision with reviewer ≠ author when a plan is `pending_approval`.

- **DECISIONS #27:** supervised task per draft/execute, but a run/plan with no live task reads as
  **interrupted · Continue**, never running forever; `operation_id` persisted on the run/plan row;
  admin submit = submit + approve + execute in one confirmed action, member submit →
  `pending_approval`; `422 plan_not_ready` returns the blockers; planning setup becomes a fe-setup Setup screen ("Contact planning"), readiness surfaces
  `planning_not_set_up`.

- **DECISIONS #28:** approve **with explicitly acknowledged exceptions**: each unmet requirement
  needs an acknowledgement (reason, actor, time; audited). Conflicts still block. api implements,
  domain reviews.

## K1 state model (from #27/#28)
One union in `features/scheduling/plan-state.ts`; every state has a header line and one primary.
| State | Shows | Primary |
| --- | --- | --- |
| `not_set_up` (422 planning_not_set_up) | what's missing (policy / requirements) | `Set up contact planning` (Setup screen when it exists; legacy page until then) |
| `no_draft` | the day, last plan for it if any | `Draft the day` |
| `drafting` (phase from `scheduling_progress`) | materializing → searching → optimizing → plan, with elapsed | none (Cancel if the domain supports it) |
| `interrupted` | "Drafting stopped when the server restarted." | `Continue` |
| `draft` + conflicts (`plan_not_ready`) | conflicts listed (station double-booked); Submit disabled **with the reason** | `Submit` disabled: "2 conflicts on SVB-1 and FBK-2. Remove or move a pass." |
| `draft` + unmet requirements | A Demand lists them; Submit opens an **Accept gaps** sheet: one row per unmet requirement (spacecraft, why), a reason per row (with "same reason for all"), audited on approve | `Accept 6 gaps and submit` |
| `draft` ready | totals, rule met n/n | admin: `Submit and book N passes` (confirm sheet); member: `Request approval` |
| `pending_approval` | "Waiting for an admin" (member); admin sees ApDecision (reviewer ≠ author) | admin: `Approve and book` |
| `executing` / `interrupted` | per-contact Requested → Confirmed / Rejected (S1 + S10) | interrupted: `Continue booking` |
| `reserved` / `partially_reserved` / `failed` | outcome counts; rejections become A rows | partial/failed: `Re-plan after provider changes` (K2) |

## Questions for ux (answered: U22)
- **Q1** Day boundary: plan "tomorrow" = 00–24Z UTC, or the shift-aligned window?
- **Q2** Rule source today is requirements/templates (not profile demand). Footer link: to a
  requirement-templates page (no home in the IA yet), or omit until profile demand exists?
- **Q3** Budgets (minutes, money) aren't configured anywhere. Confirm: no denominators, no budget
  caution, until a budget setting exists.
- **Q4** Provider freeze clock: omit until providers report a cutoff?
- **Q5** K2 v1 without station status (S7): "Re-plan after provider changes" entered from a plan or
  a rejected reservation, same layout. OK, or hold K2 until S7?
- **Q6** K3: hold the screen until S9 rather than ship counts-only (my recommendation)?
- **Q7** Source naming for windows: `SIMULATOR · SYNTHETIC WINDOW` vs provider name. Any wording rule?
- **Q8** Gantt rows: stations (antenna as sub-rows only when the provider reports antennas)?
- **Q9** Plan approval: today plans can require approval (`pending_approval`). Two people for plans
  too (ApDecision), or submit-and-execute by one planner?
