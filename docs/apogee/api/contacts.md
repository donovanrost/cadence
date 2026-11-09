# Contacts endpoints (passes, stations)

Owner: **api-ops** for passes (ops M7 = scheduling S1, DECISIONS #25/#26). Stations are api's
`GET /missions/:mission_id/ground-stations` ([setup.md](setup.md)). Scheduling actions (S2–S6,
S8) are api's: [scheduling.md](scheduling.md). Conventions: [README.md](README.md).

| Ask | Endpoint | Status |
| --- | --- | --- |
| M7 / S1 | `GET /missions/:mission_id/passes` | **implemented** (booked contacts; opportunities not yet) |
| S7 | `GET/POST /missions/:mission_id/station-availability…` | **implemented** (api-ops on domain's facades, DECISIONS #39/#44) |
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
    "scheduled_contact_id": "scheduled_contact_…"
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
- `truncated: true`: more than 500 reservations overlap the window. Narrow it.
- Refetch on `invalidate` with `contacts` (below). AOS/LOS happen without an event; refresh a
  "now" line on a timer if you draw one.

Errors: `422 invalid_params`, `404 mission_not_found`.

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
  revisions that booked the hit passes (start a repair, S8, from them): live bookings at that station in the window (K2's
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
