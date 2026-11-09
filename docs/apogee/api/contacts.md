# Contacts endpoints (passes, stations)

Owner: **api-ops** for passes (ops M7 = scheduling S1, DECISIONS #25/#26). Stations are api's
`GET /missions/:mission_id/ground-stations` ([setup.md](setup.md)). Scheduling actions (S2–S6,
S8) are api's: [scheduling.md](scheduling.md). Conventions: [README.md](README.md).

| Ask | Endpoint | Status |
| --- | --- | --- |
| M7 / S1 | `GET /missions/:mission_id/passes` | **implemented** (booked contacts; opportunities not yet) |
| S10 | `contacts` on the `mission:<id>` `invalidate` event | partial, see below |

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
- Refetch on `invalidate` with `contacts` (below), and periodically (about 30 s) until S10 is complete.

Errors: `422 invalid_params`, `404 mission_not_found`.

## S10: `contacts` invalidation

Planned, partial: fires when a scheduled or realized contact or a contact action is committed
(contact facts). Reservation-only transitions (for example `requesting → rejected`) don't publish
anything yet; domain is adding a post-commit signal. Until then, also poll the passes read.
