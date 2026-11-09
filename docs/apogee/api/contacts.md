# Contacts endpoints (passes, stations)

Owner: **api-ops** for passes (ops M7 = scheduling S1, DECISIONS #25/#26). Stations are api's
`GET /missions/:mission_id/ground-stations` ([setup.md](setup.md)). Scheduling actions (S2–S6,
S8) are api's: [scheduling.md](scheduling.md). Conventions: [README.md](README.md).

| Ask | Endpoint | Status |
| --- | --- | --- |
| M7 / S1 | `GET /missions/:mission_id/passes` | **implemented** (booked contacts; opportunities not yet) |
| S7 | `GET/POST /missions/:mission_id/station-availability…` | **implemented** (api-ops on domain's facades, DECISIONS #39/#44) |
| S9 | `GET /missions/:mission_id/pass-review[/rows|/daily]` | **implemented** (K3) |
| S10 | `contacts` on the `mission:<id>` `invalidate` event | **implemented** (contact facts + reservation changes; plans/runs not yet) |

## `GET /api/console/v1/missions/:mission_id/passes`

One row per **provider reservation** whose window overlaps `[from, to)`, oldest start first.

Query: `from`, `to` (ISO-8601; default `from` = now, `to` = `from` + 24 h; at most 7 days),
`spacecraft_id`, `station` (matches the row's `station.ref`, `station.id` or `station.code`),
`states` (comma list of reservation states, below). Bad values: `422 invalid_params` with
`details` keyed by parameter.

```json
{"data": {
  "from": "2026-11-08T02:00:00.000Z", "to": "2026-11-09T02:00:00.000Z", "truncated": false,
  "passes": [{
    "id": "provider_reservation_…", "kind": "contact",
    "state": "confirmed", "pass_phase": "scheduled", "delivery_state": "pending",
    "spacecraft_id": "spacecraft-earendil-312",
    "spacecraft": {"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312},
    "station": {"ref": "SVL", "id": "ground_station_…", "code": "SVL", "name": "Svalbard"},
    "antenna": {"id": "ant-3", "label": null},
    "starts_at": "…", "ends_at": "…",
    "uplink_capable": null,
    "source": {"provider": "provider_…", "provider_name": "Simulator", "synthetic": true},
    "max_elevation_deg": null,
    "cost": null,
    "plan": {"id": "contact_plan_…", "version": 42},
    "reservation_id": "provider_reservation_…",
    "scheduled_contact_id": "scheduled_contact_…",
    "ended_by": null,
    "replaced_by": null
  }]
}}
```

- `spacecraft`: identity on every line (R01). `name` and `scid` are `null` if the spacecraft was
  deleted since the booking.
- `kind` is always `contact` for now. **Opportunities** (provider windows not yet booked) need a
  live provider search per spacecraft and route; they come with scheduling S4 (alternatives), not
  this read.
- `state` is the reservation lifecycle: `requesting | pending | confirmed | active | completed |
  unknown | rejected | canceling | canceled | failed`. `pass_phase` and `delivery_state` are the
  provider's pass and delivery progress. The UI's state model (Requested / Confirmed / In contact /
  Realized / …) is a client decoding of these three fields (lead's `features/scheduling/contact.ts`).
- `station`: from the reservation's newest snapshot (Cadence-accepted, then provider-confirmed,
  then requested). `ref` is the provider's station reference. `id`, `code` and `name` are filled
  when `ref` matches a Cadence ground station (by id, `metadata.code` or
  `metadata.provider_station_ref`), and are `null` otherwise. Show `ref` then.
- `antenna`: `null` unless the provider names one. `label` is always `null` (providers only give a ref).
- **Nothing is derived** (DECISIONS #4, no propagation): `max_elevation_deg`, `uplink_capable` and
  `cost` are `null` unless the provider supplied them in the snapshot. `source.synthetic` is `true`
  for the simulator's deterministic windows. Say so in the UI.
- `plan`: the contact plan revision that booked it, or `null` for direct bookings.
- `ended_by` (qa #30): who ended a `canceled`, `rejected` or `failed` booking, else `null`.
  `{kind: "user", id, name}` for a cancel from the contact workspace or an operator's #53
  "not booked" resolution; otherwise `{kind: "provider", id, name}`.
- `replaced_by` (qa #30): on a lost booking that an applied repair replaced,
  `{plan_id, reservation_id}` (`reservation_id` is `null` until that pass is placed), else
  `null`. A lost row with `replaced_by: null` is still lost: that's what re-plan's Impact shows.
  Replacement is persisted when the repair plan is created and never re-derived.
- `truncated: true`: more than 500 reservations overlap the window. Narrow it.
- Refetch on `invalidate` with `contacts` (below). AOS/LOS happen without an event; refresh a
  "now" line on a timer if you draw one.

Errors: `422 invalid_params`, `404 mission_not_found`.

### Booking evidence and attention on pass rows (U32, DECISIONS #53/#54/#55): proposed, not built

Every row gains four fields:

- `booking_evidence`:
  - `provider` when the provider confirmed the booking (`state` `confirmed | active | completed`);
  - `operator_attested` when an org admin marked it booked (#53) and the provider hasn't confirmed;
  - otherwise `null` (not booked, or lost).
- `attested_by`: `{kind, id, name}` of who marked it booked, when `booking_evidence` is
  `operator_attested`; otherwise `null`. Reads "BOOKED · ATTESTED BY MIRA K.".
- `uplink_confirmed`:
  - `true` when the provider confirmed the booking's uplink leg;
  - `false` when an uplink leg was requested but isn't confirmed (always for an attested booking,
    while #46 D1 holds). The UI reads "UPLINK UNCONFIRMED".
  - It turns `true` when the provider confirms before AOS (#55).
  - `null` when no uplink leg was requested (a downlink-only booking), so there's nothing to
    confirm.
- `attention`: this booking's open or acknowledged attention item, the same object as the action
  queue's `attention` (ops.md), or `null`. It's also `null` for a viewer who can't operate the
  mission. The action queue's object also gains `reservation_id`, the pass row's `id`. A conflict
  on a booking that never got a scheduled contact (`cancel_failed`, `late_confirmation`) has
  `contact_id: null`, so link by `reservation_id`.

### `POST /api/console/v1/missions/:mission_id/attention/:source/:id/acknowledge` · `…/resolve`: proposed

`:source` and `:id` are the attention object's `source` and `id` (`pass_resolution`, the
resolution id). Members who can operate the mission (`operate_mission`); the actor is always the
signed-in user (#30).

- `acknowledge`: no body. The item stays listed, sorted last (U21).
- `resolve`: body `{"action_text": "Called Northlight; the cancel is confirmed, ticket 4471."}`
  (required, at most 200 characters). The text is shown as "Resolved: <action_text>" in history.
- Both return `{data: <attention object>}` (`state` `acknowledged` / `resolved`) and invalidate
  `attention` (plus `contacts`).
- Errors: `404 attention_item_not_found` (also an unknown `:source`), `409 attention_item_not_open`
  (already resolved, or acknowledging one that's acknowledged), `403 forbidden`,
  `422 invalid_params` (`details.action_text`), `422 actor_not_assignable` (the body names an
  actor field), `404 mission_not_found`.

## S10: `contacts` invalidation

`invalidate` with `contacts` fires when a scheduled or realized contact or a contact action is
committed (relayed from `Cadence.Contacts.Facts` by `CadenceWeb.Console.ContactChanges`), and on
the `:contacts_changed` read update, which every `ProviderReservations` writer publishes after
commit (domain `db8c9953`), so reservation-only transitions (for example `requesting → rejected`)
invalidate too. Contact **plan and fleet-run** changes don't publish yet; ask domain if a screen needs them.

## Station availability (S7)

Over domain's `Cadence.Comms.StationAvailability` and `Cadence.Reads.StationImpact`
(`docs/apogee/domain/station-availability.md`). Station ids are api's
`GET /ground-stations` ids. Refetch on `invalidate` with `stations` (and `contacts`; every window
change publishes both).

- `GET /station-availability?at=` (default now) → `{at, stations: [status]}`, one row per station.
- `GET /station-availability/:station_id?from&to` (default now → +7 d, ≤ 31 d) →
  `{status, from, to, windows: [window]}`.
- `POST /station-availability/:station_id/windows` `{kind: outage | maintenance | degraded,
  starts_at, ends_at?, eta?, reason?, detail?}` → `201` window. Operator-entered
  (`source: operator`, `reported_by` = you).
- `POST /station-availability/windows/:window_id/clear` `{reason?}` → the window with `cleared_at`.
- `GET /station-availability/:station_id/impact?from&to` → `{ground_station_id, from, to, passes_hit,
  reservation_ids, spacecraft_ids, plans: [{id, version}], truncated}`. `plans` are the contact plan
  revisions that booked the hit passes (start a repair, S8, from them). `lost: {count, reservation_ids,
  spacecraft_ids, plans}` lists bookings at the station in the window that already ended without a
  pass (`canceled`, `rejected`, `failed`), for example ones a provider canceled because of the outage.
  Those are the ones K2 re-plans: live bookings at that station in the window (K2's
  "passes hit"). Reservations that never named a station can't be attributed and aren't counted.

```json
status = {"ground_station_id": "gs-…", "state": "up | degraded | down", "since": null, "eta": null,
          "source": "operator | provider | simulator | null", "reported_by": {…} | null,
          "reported_at": null, "basis": "no reported windows", "windows": [window]}
window = {"id": "station_window_…", "ground_station_id": "gs-…", "kind": "outage | maintenance | degraded",
          "from": "…", "to": "…" | null, "eta": "…" | null, "source": "operator | provider | simulator",
          "reported_by": {…}, "created_by": {…}, "reported_at": "…", "reason": "…" | null,
          "detail": {}, "cleared_at": null}
```

- `state`: `down` while an outage or maintenance window is active; `degraded` while a degraded one
  is; `up` means **nothing is reported**, not live telemetry. Say so (`basis`).
- `eta`: when it's expected back (`to`, or the reported ETA). `null` when unknown; never guess.
- `status.windows` lists active and upcoming windows (7 d).
- Provider-reported windows come from provider sync. A window the provider stops reporting is
  cleared. The simulator fault `station_outages` produces `source: simulator` windows.

Errors: `422 invalid_params` / `invalid_window`, `404 station_not_found` / `window_not_found`,
`409 window_overlaps` (same kind, same station) / `window_cleared`, `403 forbidden`.

## Pass review (S9, K3 "Close the books")

Over domain's `Cadence.Reads.PassReview` (`docs/apogee/domain/pass-review.md`, "As built";
DECISIONS #47/#48). One result per booked pass, filled by provider results and a once-a-minute
close-out. Refetch on `invalidate` with `pass_results`.

Window (all three reads): `from`/`to` (ISO-8601, ≤ 31 d), **or** `day` (`YYYY-MM-DD`, default today
UTC) + `span` (`day | week | month`, default `day`; `daily` defaults to `month`), ending at the close
of `day`. Optional `plan` (contact plan id) narrows to one plan.

### `GET /pass-review` (h1, stat strip, R1, R2, freshness)

`{from, to, planned, realized, partial, missed, failed, canceled, pending_count, realized_ratio,
threshold, target, provisional, missed_by_owner, partial_by_owner, by_station[], by_cause[], plans[],
volume, freshness[]}`:

- `realized_ratio = realized / (planned − canceled − pending_report)`. `null` when nothing counts yet.
- `threshold` is `pass_realized_threshold` (a pass counts as realized when flown ≥ that share of
  planned, default 0.95). `target` is `realization_target` (the fleet's target share, the h1 verdict
  and R3 line, default 0.98). Both are mission settings (ST1).
- `provisional: true` when any pass in the span awaits its provider report or a provider's event
  cursor is unhealthy. Say the % is provisional, in words.
- `missed_by_owner` / `partial_by_owner`: `{provider, us, weather, unknown}` counts (the strip caption),
  every key always present. `missed` **includes** `failed` (as on the strip); `failed` is also given alone.
- `volume` ("Downlink: received vs provider-reported"): span totals `{provider_bytes,
  provider_frames, received_bytes, received_frames, provider_reported_passes, received_known_passes}`.
  A total is `null` when no pass in the span has that figure; the `*_passes` counts say how many
  passes contributed it (unknown volumes are null, not 0).
- `by_station[]` (R1): station identity, provider, planned, realized, partial, missed, failed,
  canceled, flown and planned seconds. There's no billing, so billed minutes are absent.
- `by_cause[]` (R2): `{cause, cause_source, owner, missed, partial}`.
- `freshness[]` (h1 meta): per provider `{provider {id, name}, last_report_at, pending_reports,
  oldest_pending_los, cursor_healthy}`.

### `GET /pass-review/rows` (R4)

Query: the window, `outcome` (comma list of `realized | partial | missed | failed | canceled |
pending_report`; R4 uses `missed,partial`), `station`, `spacecraft_id`, `plan`, `limit` (1–500,
default 50), `cursor` (`next_cursor`). Returns `{from, to, rows[], total, disputable, next_cursor}`
(`next_cursor` is also in `meta`). For the footer, use "SHOWING n OF total · disputable DISPUTABLE".

Row: `{id, spacecraft {id, name}, station {ref, id, code, name}, provider {id, name}, antenna_ref,
plan {id, version} | null, planned_aos, planned_los, actual_aos, actual_los, planned_seconds,
flown_seconds, planned_bytes, provider_bytes, provider_frames, received_bytes, received_frames,
observations, outcome, cause, cause_source, owner, disputable, provisional, provider_reported_at,
realized_contact_id, scheduled_contact_id}`.

- Two volumes, never merged: `provider_*` is what the provider says it delivered, and `received_*` is
  what Cadence ingested. `received_*: null` means unknown (never realized), not 0. `planned_bytes`
  is `null` unless the provider supplies a number, so show received vs provider-reported, not "vs plan".
- `owner`: `provider | us | weather | unknown`. `disputable` = owner is the provider (show `Dispute`).
  A provider-reported station window counts as the provider's; an operator-declared one counts as ours.
- `provisional`: no provider report yet.

### `GET /pass-review/daily` (R3)

`{from, to, days: [{day, planned, realized, realized_ratio, top_cause, top_station, …}], target,
threshold}`.
Draw `target` as the dashed line. `top_cause`/`top_station` annotate dips.

Money (R5, disputes in $) is out of scope: no provider reports prices.
