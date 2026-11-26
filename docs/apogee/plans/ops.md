# Ops data plan (fe-ops)

Owner: fe-ops (`w0R:p4`). Status: draft 1, 2026-11-08. Scope: `Now` (J1), `Investigate` (J2),
`Command` (J3), `Contacts` (J4), `Palette` (J5), then `Compose` / `Approve` / `Uplink`, then `Mobile` (J6).

Sources for "today": code reading of `apps/cadence`, `apps/cadence_web`, `frontend/modules/{commanding,
limits-and-alarming,planning-and-contacts}`, `frontend/apps/ops-console`, and the Earendil fixture
(`dev/reflect_orbital/fixture.exs`). Paths are repo-relative. Missing items are numbered **M1…** and
collected in [the ask list](#missing-data-ask-list-for-api) at the end.

## Cross-cutting facts that shape every screen

- **Fleet geometry lives in spacecraft `metadata`, untyped.** The Earendil fixture writes
  `plane` (1–20), `slot` (1–25) and `orbit{altitude_km, inclination_deg, eccentricity, raan_deg,
  mean_anomaly_deg, epoch}` (`dev/reflect_orbital/fixture.exs:33-60`). Note: the demo is
  **20 planes × 25**, not the canvas's 10 × 50, so the matrix and orbit views must be data-driven.
  Nothing in the domain types these fields (`apps/cadence/lib/cadence/spacecraft.ex:8-28`).
- **Ground-station lat/lon exist only in the simulator scenario** (`fixture.exs:78-108`); the
  `comms_ground_stations` struct has no location, antenna or mask fields and no JSON API
  (`apps/cadence/lib/cadence/comms/ground_station.ex:13-33`).
- **No propagation anywhere.** Passes come from the simulator's deterministic pass model
  (97-min cadence, 8-min windows), not from orbits. No eclipse/umbra data exists.
- **"Alarm" = latest limit state of a point.** No alarm entity, no acknowledge/assign/shelve,
  no procedure link. Limit definitions are per point (mission-wide), not per spacecraft.
- **No browser push except LiveView.** The only socket is `/live`. The PubSub topic
  `read-updates:<event>:<org>:<mission>` is invalidation-only (no payload). Telemetry and limit
  facts are on the internal EventBus (`{:cadence, :telemetry, :facts}`, `{:cadence, :limits, :facts}`)
  and never reach a browser.
- **Existing Vue features run through LiveView or the application-host query bridge**, not the
  REST API. Commanding, catalog and contact-workspace reads are mostly not on plain JSON.
- **Staleness and in-contact are not per spacecraft today.** Freshness exists per data source
  (`apps/cadence/lib/cadence/projections/data_sources/health.ex`) and as an OTel metric.

## Shared ops building blocks (domain components in my feature dirs)

These are ops-specific; generic primitives (Panel, Tag/StateGlyph, Button, Readout, clock bar,
rail) are lead's. I'll ask lead before promoting any of these to shared.

| Component | Used by | Notes |
| --- | --- | --- |
| `FleetMatrix` | Now, Compose, Uplink | One cell per spacecraft, rows = planes. Cell states: nominal / caution / critical / stale / not-set-up, plus an in-contact ring. Rows and columns come from data. Keyboard-navigable grid with a text summary. |
| `ConstellationView` (SVG) | Now | Planes as ellipses from `raan_deg`; dots from `mean_anomaly_deg`. **Decorative/schematic** until real propagation exists. Can ship after the matrix. |
| `PassStrip` / `PassTimeline` | Now (A4), Contacts (D3), Command (C4) | Per-station rows on a time axis; pass states done / live / scheduled / conflict / selected. |
| `TrendPlot` | Investigate (B1), Uplink (U2), Mobile | Point history vs. red/yellow bands over time; optional shaded intervals (umbra once it exists). |
| `EventLine` list | Investigate (B2), Uplink (U3) | From mission events. |
| `GoNoGoPoll` | Command (C3), Approve (A2) | A list of checks, each with GO / HOLD / NO-GO, a reason and evidence. |
| `CommandStageBar` | Compose, Approve, Uplink | The seven stations as the page header. |
| `TargetRow` | everywhere | Name + SCID + profile, always (rule 01: "identity on every line"). |

## Per screen

### J1 · Now

**Panels:** status header ("N spacecraft need you" + freshness line), six KPI tiles (Nominal,
Caution, Critical, Stale, In contact, Uplinks queued), A1 constellation, A2 action queue, A3 fleet
matrix, A4 passes for the next 2 h. Rail counts (Fleet, Alarms, Commands, Contacts AOS) come from the same summary.

| Data | Today | Gap |
| --- | --- | --- |
| Spacecraft list (id, name, SCID, profile, plane, slot) | `GET /api/organizations/:org/missions/:mid/spacecraft` returns the full list; plane/slot only in `metadata` | **M1** typed fleet geometry |
| Per-spacecraft worst limit state | console `GET …/fleet` `spacecraft[]` (`limit_state`, `violating_points`, `worst_point`; the old `mission_health` REST read is gone, #780) and formerly `scope_summaries[]` (red/yellow/green/blue counts per spacecraft, `apps/cadence/lib/cadence/reads/mission_health.ex:79-114`). The dashboards `ConstellationHealth` source already computes `worst_state` + `:no_data` per spacecraft but only inside the dashboards engine | **M2** one fleet-status read |
| Stale (no TLM > 15 min) per spacecraft | none (per data source only) | **M3** per-spacecraft `last_received_at` + freshness |
| In contact now, per spacecraft | `RealizedContact.lifecycle_state = active`, but no `spacecraft_id` (via source endpoints/paths) | **M4** active contact → spacecraft |
| Uplinks queued / awaiting GO | `Cadence.Reads.Commands.summary/3` (`queued_count`, `release_pending_count`, `in_flight_count`), mission-wide only; approval-pending count not exposed | **M5** add to fleet status |
| "Not set up" (Limits & Alarming not installed) | installation inventory `:not_installed` (`reads/applications/inventory.ex:364-391`) | include in **M2** |
| Action queue P1–P3 | Alarms snapshot ranks by severity then recency (`reads/alarms.ex`); missed passes and station degradation are not derived | **M6** action-queue read (ranked; v1 can be alarms + approvals waiting + not-installed apps) |
| Passes next 2 h by station | contact-workspace `schedule` (paged 25, no station field on reservations) | **M7** pass window read by station |
| Station degraded | provider-level health only (`ground_networks/provider_account.ex:9`) | part of **M7** |
| MET, mission epoch | none found | **Q-ux-1** |
| Live updates | ops shell polls; commanding has a payload-free PubSub signal | **M8** fleet-status channel |

**v1 slice I can build first:** tiles + matrix + action queue from **M2/M6** with polling, an
honest "not available" in the A1/A4 panels until **M7**. Stale and in-contact tiles show
"not tracked yet" until **M3/M4** land, never a guessed 0.

### J2 · Investigate (one spacecraft's alarm)

**Panels:** breadcrumb (fleet / plane / spacecraft, with [ ] prev/next), identity strip (SCID,
profile, orbit, last LOS, next AOS, next eclipse), sub-tabs, B1 trend vs. limits, B2 event log,
B3 recommended procedure, B4 same-signature sisters in the plane, technical details.

| Data | Today | Gap |
| --- | --- | --- |
| Spacecraft identity + profile name | `GET …/spacecraft/:id` (+ profile via spacecraft types) | profile display name in one call would help (fold into **M1**) |
| Active alarms for this spacecraft | `Cadence.Reads.LimitAlarmConditions.load/3` (filters `spacecraft_id`, `state=active`), LiveView only | **M9** JSON alarm list (`?spacecraft_id=&state=`) |
| Point history | `GET …/telemetry/points/:point_id/history?spacecraft_id=&from_receipt_time=&to_receipt_time=&limit=` returns raw samples only. Decimation exists only in QuestDB inside dashboards (`reads/telemetry.ex:142-180`) | **M10** decimated history (1 h / 6 orbits / 24 h) |
| Limit bands over time | `Reads.Limits.definition_intervals/…` (`reads/limits.ex:164-173`) — perfect for bands, not on JSON | **M11** limit intervals for a point |
| First-crossed time, rate | `Reads.Limits.event_history` gives transitions; rate is derivable client-side from history | include first-crossed in **M9** |
| Event log | console `GET …/events?spacecraft_id=&from=&to=&limit=` (the old `mission_events` REST read is gone, #780) | minor: expose from/to |
| Last LOS / next AOS | none per spacecraft (see **M4/M7**) | **M7** |
| Umbra / next eclipse | none | **M12** (propagation; see decision D1) |
| Sisters with the same signature | plane is in metadata; no "same signature" logic | v1: same plane + same point in caution/critical (client-side from **M2/M9**). Real similarity is later |
| Recommended procedure | none | **M13** (product decision, D2) — v1 omits B3 rather than invent one |
| Acknowledge / Assign | none (no alarm lifecycle) | **M14** (D3) — v1 hides the buttons |
| Live value | none pushed | **M8** telemetry/limit push for one spacecraft |

### J3 · Command a group (contingency uplink sequence)

**Panels:** step header (Targets → Commands → GO/NO-GO → Arm & uplink), C1 live-query targets,
C2 command stack, C3 GO/NO-GO poll, C4 per-target delivery plan (own next AOS, umbra margin),
C5 summary + release options + second-GO picker + log entry.

| Data | Today | Gap |
| --- | --- | --- |
| Target by query (plane, profile, condition) | none; `WorkspaceSubmission` takes 1–25 explicit targets, same command, distinct targets (`control/commanding/workspace_submission.ex:10,43,177-181`) | **M15** target query → resolved list (client can resolve plane/profile from **M1/M2** in v1) |
| > 25 targets, multi-command stacks | one request = one command × one target; batch cap 25 | **M16** a group request (N targets × K commands) or lift the cap |
| Catalog commands + args | `AuthoringCatalog.page/4` (args: type, required, choices, default/fixed/hazardous; no min/max) — LiveView only | **M17** JSON catalog for a mission revision (+ per-target compatibility) |
| GO/NO-GO checks | create-time validation exists (identity, basis, args, encoding, choices; `request_validation.ex:20-50`); release-time constraints. No conflicts / plan impact / umbra checks; no preflight object | **M18** preflight endpoint returning per-check GO/HOLD/NO-GO with evidence |
| Two-person | conditional: only when critical/hazardous/policy hint (`request_validation.ex:311-322`); self-approve blocked | **D4** policy for "power mode needs a second GO" |
| Delivery plan at each target's next AOS | release fires when a contact becomes defined/active (`contact_fact_consumer.ex:30`); no look-ahead | **M7** (next AOS per spacecraft) + **M12** (umbra) |
| Release "hold until a set time" | `not_before` / `expires_at` on requests | ok |
| Log entry | none | **M19** request note/log (metadata could carry it in v1) |
| Abort until each uplink starts | **no cancel/abort routes** | **M20** cancel queued entry / request |

### J4 · Contacts

**Panels:** header counts, D1 ground-track map with station masks, D2 selected pass (window,
duration, max el, sky plot, planned uplink, expected downlink), D3 6-h pass schedule by station,
D4 needs-a-decision (double-booking, coverage gap → move / request opportunity).

| Data | Today | Gap |
| --- | --- | --- |
| Stations with location, antennas, status | struct has none of these; lat/lon/antennas only in the simulator scenario | **M21** station read with location, antennas, mask, status |
| Reservations by station in a window | contact-workspace `schedule` (paged 25, no window filter, station only in `metadata["ground_station_ref"]`) | **M7** |
| Ground track, footprints, sky plot, max el | none (no propagation) | **M12** / D1 |
| Planned uplink for a pass | queued requests are per target lane; not bound to a pass | derivable once **M7** + commanding are joined |
| Expected downlink volume | `estimated_capacity` is opaque; actuals exist (`contact_json.ex:134-153`) | show actuals for done passes only |
| Conflicts / coverage gaps | only inside contact plans and the fleet optimizer (`contact_planning/contact_plans.ex:769-810`, `fleet_optimizer/constraints.ex`) | **M22** findings across live reservations |
| Book / swap station / request opportunity | contact-workspace `search` / `reserve` / `cancel` with signed tokens (`contacts/schedule_operations.ex`) — usable from the SPA, but needs the `x-cadence-workspace-*` headers | swap = cancel + reserve; ask api whether a single "move" action is wanted |
| Live | none; existing SPA polls every 5 s | **M8** or polling in v1 |

**v1 slice:** D3 schedule + D2 window/duration from reservations + D4 from provider changes;
D1 map shows stations only (once **M21**), with an honest "orbit propagation not available" note.

### J5 · Palette (⌘K)

Groups: Spacecraft, Telemetry, Actions, Commands, Stations, Pages. Shortcuts `G N`, `G C`, `[ ]`.

| Data | Today | Gap |
| --- | --- | --- |
| Spacecraft search | full list via REST (client-side filter of 500 is fine), or `spacecraft_q` on contact-workspace | ok (client-side) |
| Telemetry point search | `canonical_telemetry_points` (`reads/application_surfaces/reference_providers/canonical_telemetry_points.ex:17`), LiveView-only | **M23** `GET …/telemetry/points?q=` |
| Command search | `AuthoringCatalog.query/1` (`command_query`), LiveView-only | **M17** with `?q=` |
| Stations | none | **M21** |
| Pages | SPA router (client-side) | ok |
| Status subtitle ("Critical · VBAT below limit") | from **M2/M9** | — |

### C1 · Compose, Approve, Uplink & verify

| Need | Today | Gap |
| --- | --- | --- |
| Catalog with ranges/units, opcode, verifier window | args have type/encoding/choices; **no min/max/units**; verifiers in `verifier_plan.ex` | **M17** + catalog ranges/units (XTCE `ValidRange`, units) |
| Per-target values (CSV) | `argument_values` per request | fine once **M16** exists |
| Encoded packet preview ("what will radiate") | encoding happens at release (`commanding.ex:625-700`) | **M24** encode preview per command |
| Approve: queue of requests waiting on me, decide with exclusions / send back | `approval_pending` + approve/reject routes; `Reads.CommandReview` (`can_decide`, `expected_review` token) | **M16** (group exclusions), "send back" state, JSON for the review read |
| Waves with gates | none | **M25** (D5, later phase) |
| Uplink: per-target state Queued→Radiating→Executed→Verified + off-ramps | request lifecycle + release attempts + verifier instances have the states (`command_request.ex`, `command_release_attempt.ex`, `command_verifier_instance.ex`) | an aggregate per-group progress read + per-entity events (**M8**) |
| Retry on no ACK | none found | **M26** (later) |

### J6 · Mobile

Reuses J2 (alarm, trend, next AOS) + Approve (GO / NO-GO) + acknowledge/hand-off (**M14**).
No new data beyond the above.

## Decisions needed (director / ux / api)

**Resolved** in [`docs/apogee/DECISIONS.md`](../DECISIONS.md) #4–8 (2026-11-08):

- **D1** Propagation is deferred. Its panels show "not available", with no flight dynamics in the browser.
- **D2** Procedures are deferred. B3 is omitted.
- **D3** A minimal alarm lifecycle (ack, assign, hand-off note, auto-clear) will be built by domain + api after the
  Now/Investigate reads. Acknowledge and Assign stay hidden until then.
- **D4** Two-person rule is policy-driven: hazardous, critical, or fleet-wide requests need a second GO.
- **D5** Waves are phase 3+.

ux decided B4's title is "Plane NN · same point in limits" unless the backend computes real similarity.
Screen specs: `docs/apogee/ux/screens/{Now,Investigate}.md`.

Original options:

- **D1 Propagation.** Ground tracks, umbra, next eclipse, max elevation and AOS predictions
  need a propagator. Options: (a) server-side Keplerian/SGP4 from typed orbit elements, (b) a
  client-side Keplerian helper for the schematic views only, (c) defer and show honest
  "not available" panels. I recommend (c) for phase 2, with (a) as a phase-3 api item; (b) would
  put flight dynamics in the browser and diverge from the server.
- **D2 Recommended procedures.** No procedure model exists. Defer; omit B3.
- **D3 Alarm lifecycle** (ack / assign / hand-off). Needed by J2 and J6. Real model work in
  `apps/cadence` (a limits-app concern).
- **D4 Two-person rule** for every request vs. only critical/hazardous.
- **D5 Waves and gates.** A new commanding concept; phase 3+.

## Missing-data ask list (for api)

Priority A blocks the first ops screens (Now, Investigate):

- **M1** Typed fleet geometry on spacecraft (`plane`, `slot`, orbit elements) or at least the
  `metadata.plane/slot` surfaced on the spacecraft list, plus the profile display name.
- **M2** `GET …/fleet/status`: per spacecraft `{spacecraft_id, name, scid, profile, plane, slot,
  worst_state (critical|caution|nominal|no_data), violating_points}` + mission counts +
  Limits-app installation state. (Reuse `ConstellationHealth` or `MissionHealth.summary`.)
- **M3** Per-spacecraft `last_received_at` + freshness (`fresh|stale|never`), threshold configurable.
- **M5** Command counts in the fleet status: queued, in flight, awaiting approval.
- **M6** Ranked action-queue read (v1: active critical/warning alarms + approval-pending requests + not-installed apps).
- **M9** `GET …/alarms?spacecraft_id=&state=active`: point, value, state, threshold crossed, first-crossed time.
- **M10** Decimated history on `…/telemetry/points/:id/history` (`?from&to&max_points`).
- **M11** Limit-definition intervals for a point over a time range.
- **M8** A Phoenix Channel for the console: fleet-status deltas (Now), latest value + limit state
  for subscribed points of one spacecraft (Investigate), commanding lifecycle per request (Uplink).

Priority B (Contacts, Command, Palette):

- **M4** Active contact per spacecraft (in contact now, station).
- **M7** `GET …/passes?from&to` → by station: spacecraft, start/end, lifecycle/pass phase, delivery
  state; and per spacecraft next AOS / last LOS. Station must be a field, not metadata.
- **M15/M16** A group command request: N targets × K commands (no 25 cap) with target query evidence.
- **M17** JSON command catalog for the active revision: commands, args (type, choices, default,
  hazardous, and **range + units**), verifier, plus `?q=`.
- **M18** Preflight checks endpoint (identity, catalog, conflicts, two-person, …) with per-check result.
- **M19** Request note / log entry. **M20** Cancel/abort a queued request or queue entry.
- **M21** Stations read: id, name, code, lat/lon, antennas, status/degraded since.
- **M22** Cross-reservation findings (station double-booked, spacecraft coverage gap).
- **M23** Telemetry point search.

Priority C (later phases): **M12** propagation (D1), **M13** procedures, **M14** alarm lifecycle,
**M24** encode preview, **M25** waves, **M26** retries.

## Questions for ux

**Answered** in [`docs/apogee/ux/decisions.md`](../ux/decisions.md) U7–U11 (2026-11-08):

- **U7 (Q1)** Omit MET when there's no epoch, including in the time picker. `mission.epoch_at` goes on the api backlog.
- **U8 (Q2)** Rows = planes when known, columns = max slots. Spacecraft with no plane go in a `—` row at the end.
  No plane metadata at all → a flat grid by SCID, 50 per row, labels `001–050`. Never heard from → a dashed "off" cell.
- **U9 (Q3)** 15 min default, but the **server** decides and returns `stale_after_s`. Never hardcode it in the SPA.
- **U10 (Q4)** Structural panels (constellation, passes, trend) stay, with an empty state and a reason.
  Things that recommend or act (procedure, acknowledge, assign) are **hidden**. A single missing fact is omitted.
  Summary tiles show `—` + "not tracked yet".
- **U11 (Q5)** Use the P1–P3 proposal below, plus: verify-failed and safe mode count as P1. A GO counts only when it's
  waiting on *you*. Sort by time-to-consequence, then age. Group identical causes.

Original questions:

- **Q-ux-1** MET: what epoch? There is no mission epoch in the model. Drop MET from the clock
  bar until there is one?
- **Q-ux-2** Matrix shape: the demo is 20 × 25. Should the matrix always use rows = planes, and what
  happens for a fleet without plane metadata (a single flat grid)?
- **Q-ux-3** The canvas's stale threshold is 15 min. Is that a product default or should it come
  from per-profile config?
- **Q-ux-4** Panels whose data doesn't exist yet (constellation, umbra, procedure): hide the panel,
  or show it with a "not available" state? The charter says "honest empty state"; I'd show the panel
  with a short reason for constellation and passes, and hide the procedure panel entirely.
- **Q-ux-5** The action-queue priorities P1–P3: what is the rule? Proposal: P1 = critical alarm, or
  a missed pass; P2 = caution, a GO poll waiting on you, or a station degraded; P3 = setup gaps.

## Comments on api's realtime shapes (`docs/apogee/api/realtime.md`, 2026-11-08)

1. **`fleet` delta rows should be the full `GET …/fleet` row**, not a subset (`id, state, worst_state,
   last_received_at, stale`). Then the client replaces rows by `id` and recomputes the tile counts
   locally, with one row type and no partial-merge rules. Please include `in_contact` and
   `never_heard` once those exist. Also: what is `state` vs. `worst_state`? One field is enough,
   unless `state` is something else, such as lifecycle.
2. **Add a monotonic `seq` (or the `observed_at` of the snapshot the delta is based on)** to both the
   `GET …/fleet` response and each `fleet` push. If the client sees a gap, or a push older than its
   snapshot, it refetches. Without it, a push that lands mid-refetch can be applied twice or lost.
3. **Tile counts in the push.** If `GET …/fleet` returns mission counts that the server computes (e.g.
   `critical_delta_1h`, uplinks awaiting me), the push needs them too, or they go stale between
   refetches. Fine to send `counts` on every push, since it's small.
4. **Limit-state transitions need their own invalidation.** `limits` currently fires on *definition*
   changes and `telemetry` on every committed sample. With Earendil feeds at 1 Hz, `telemetry` will
   fire every 500 ms. The Now action queue and the alarm list only care about transitions, so
   please add an `alarms` resource (fires when any point's limit state changes) and I'll key the
   alarms/action-queue refetch on that, not on `telemetry`.
5. **`points` samples:** keep the value as the server's exact representation (number for numeric, string
   for enum/text), plus `unit` on the join reply rather than per sample. Please include
   `generation_time` as well as `received_at`, since the chart's x-axis is generation time. Use the same
   `limit_state` vocabulary as the alarms read.
6. `uplink:<command_request_id>` is fine. With DECISIONS #7 fleet-wide requests, I'll want a topic per
   group request, not per single-target request, once M16 exists.

## Proposed read shapes for api-ops (2026-11-08, DECISIONS #21)

Same conventions as `docs/apogee/api/README.md`. These are what the SPA will decode; adjust and tell me.

### Events (Investigate B2, Timeline): `GET /missions/:id/events`
Query: `from`, `to` (ISO, default last 24 h), `spacecraft_id`, `plane`, `kind` (comma list), `limit`
(≤ 500, default 200), `cursor`. Newest first. Invalidate resource: `events`.
```json
{"data": {"from": "…", "to": "…", "events": [{
  "id": "evt_…", "at": "2026-11-08T02:08:11Z",
  "kind": "limit | flight_event | contact | command | config | operator",
  "severity": "critical | caution | nominal | info",
  "text": "VBAT crossed red low 24.0",
  "spacecraft": {"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312} ,
  "refs": {"alarm_id": null, "point_id": "EPS.VBAT", "command_request_id": null, "contact_id": null}
}]}, "meta": {"next_cursor": null}}
```
`spacecraft` is null for mission-scope events; `severity` says how to mark the row (crit/caution
for limit events; nominal for verified/cleared; info for plan/operator events).

### Event density (Timeline E1): `GET /missions/:id/events/density`
Query: `from`, `to`, `bucket_s` (≥ 60), same filters as events.
`{"data": {"bucket_s": 900, "buckets": [{"t": "…", "critical": 1, "caution": 3, "nominal": 0, "info": 5}]}}`

### Point search (M23; Telemetry explore T1, ⌘K Telemetry): `GET /missions/:id/telemetry/points`
Query: `spacecraft_id` (optional), `q` (name / description / id substring), `limit` (≤ 200).
```json
{"data": {"points": [{
  "id": "EPS.VBAT", "name": "VBAT", "description": "Battery voltage", "unit": "V",
  "subsystem": "EPS", "type": "numeric | enum | text",
  "latest": {"value": 23.1, "received_at": "…", "limit_state": "critical | caution | nominal | no_data"}
}]}}
```
`latest` is present only when `spacecraft_id` is given (null if never received).

## fe-ops comments on `docs/apogee/domain/group-requests.md` (2026-11-09)

1. **Q3 stop on failure per target: agree.** On the group read, give canceled members a `reason`
   (`earlier_command_failed | excluded_at_review | expired | aborted | not_sent`) and the
   triggering member id, so Uplink's "Needs you" can say "SET_POWER_MODE failed on 312, so
   PAYLOAD_PAUSE wasn't sent".
2. **Q4 send back = a new prefilled group: agree.** Please carry `sent_back_from: group_id` and the
   reviewer's note on the new draft, or let Compose clone from `GET /command-groups/:id` (all the
   inputs are there: query chips, explicit ids, commands with argument values, release, log).
   Compose will open `M/commands/new?from=group:<id>`.
3. **Unclear submits (ux U20).** When a submit or decision times out, the UI must find out what
   happened without resubmitting. Please support `GET /command-groups?operation_id=` (or return the
   group id in a `409 duplicate_operation` on replay), so "Check now" can resolve it.
4. **Preflight `contact` check:** per target, include `next_contact {station_code, aos, los}` (or
   null). C4's delivery plan draws from exactly that, so it doesn't have to join passes itself.
5. **Preflight `size`:** put the bounds in `evidence` (`max_targets`, `max_commands`,
   `max_members`) so the NO-GO sentence can say the limit.
6. **`two_person` reasons:** stable keys plus facts (`hazardous_command: name`,
   `fleet_reach: n over threshold t`), so the UI words them per CommandFlow R05 and Approve shows
   "why a second GO".
7. **Progress:** per stage counts plus per-target rows `{spacecraft_id, stage, member stages
   [position → stage], last_event_at, blocked: {reason} | null}`, so the Uplink matrix and
   "Needs you" render from one read. `executed` vs `verified` needs the verifier window end time
   (`verify_by`) for "verifier window open".
8. **`awaiting_me`:** the action queue's approval item should then count groups, as in §6.
   `requested_approver_user_id` must match the viewer.
9. The `targets[].matched_by` chips are great for Approve's "why is this spacecraft in".
