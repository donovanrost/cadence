# S7 · Ground station availability (scheduling plan S7, K1 maintenance band, K2 station down)

Owner: **domain**. Status: **built** (approved as DECISIONS #39; 38e92f1b, ceee7aa2, ed60abe3).
Reviewers: director, api-ops, lead. See "As built" at the end for where the build differs.
`L` = `apps/cadence/lib/cadence`.

## What exists

- `comms_ground_stations`: setup data only (name, code, provider, region, lifecycle). It has no
  availability.
- **No provider reports station status.** Our only provider, the simulator, has one fault knob:
  `provider_outage` for the whole provider (`cadence_simulator/provider/fault_profile.ex`).
  Opportunities always report `availability: "available"`.
- A station going down only reaches Cadence as cancelled or rejected reservations.

So "provider-reported station status" is not available upstream today. The honest model has two
sources, labeled in every read.

## Model

```
ground_station_availability_windows
  window_id PK, org, mission, ground_station_id,
  kind     outage | maintenance | degraded      -- degraded = usable with limits (e.g. one antenna)
  starts_at, ends_at NULL (open: until cleared), eta NULL (expected end when open)
  source   operator | provider
  reported_by (actor doc | provider ref), provider_ref NULL (dedupe key for provider reports),
  reason text, detail map (e.g. %{"antennas" => ["2"]})
  cleared_at NULL, cleared_by NULL
  index (mission, ground_station_id, starts_at); partial unique (mission, provider_ref) where not null
```

- **Operators** schedule maintenance or declare an outage, and clear it when it's over. Those
  actions are direct, not change-set changes: availability is operational state, not
  configuration.
- **Providers** report through one domain entry point, `StationAvailability.record_provider_report/3`
  (`{station ref, kind, starts_at, ends_at|eta, provider_ref}`), which upserts by `provider_ref`.
  Adapters call it when their API reports status. I'll add a simulator fault
  `station_outages: [%{ground_station_id, from, to}]` that marks those passes unavailable and
  exposes the windows, so qa can drive K2 end to end.

## Status (derived, never stored)

`StationAvailability.status(org, mission, station_id, at)` returns
`%{state, since, eta, reported_by, source, windows}`:

| Condition at `at` | `state` |
| --- | --- |
| an active `outage` or `maintenance` window | `down` (since = its start, eta = its end or eta) |
| an active `degraded` window | `degraded` |
| the station's provider account is unhealthy (existing provider health), or the provider simulator reports `provider_outage` | `unknown`, with `source: provider_health` |
| otherwise | `up` |

`up` means "no known problem". The read says so (`basis: "no reported windows"`) rather than
implying live telemetry from the station. There is no inference from failed passes in v1.

## Planning honors availability

- **Opportunity search / fleet planning:** an opportunity overlapping an `outage` or
  `maintenance` window at its station is **ineligible** with reason `station_unavailable` (window
  id). `degraded` windows only annotate.
- **Impact (feeds S8):** `StationAvailability.impact(org, mission, station_id, from, to)` lists
  reserved or planned contacts whose station and window overlap. Station identity comes from the
  reservation snapshot (`ground_station_ref`), the only place it lives today.
- **Push (S10):** window create, change and clear publish `:contacts_changed` (and
  `:stations_changed`).

## Facade (for api-ops)

```elixir
StationAvailability.status(scope, mission_id, station_id | :all, at \\ now)
StationAvailability.windows(scope, mission_id, station_id, from, to)
StationAvailability.schedule(scope, mission_id, station_id, %{kind, starts_at, ends_at | eta, reason, detail})
StationAvailability.clear(scope, mission_id, window_id, reason)
StationAvailability.impact(scope, mission_id, station_id, from, to)
```

Authorization: read requires `operate_mission`; schedule and clear require `operate_mission`
(operators manage maintenance). Errors: `:station_not_found`, `:window_overlaps` (same kind,
same station), `:invalid_window`, `:window_cleared`.

## Placement

`L/comms/station_availability*` (comms context, management plane: setup and operational intent),
called by `contact_planning` (allowed). The provider entry point is called from ground-network
adapters (`ground_networks` → `comms`, allowed).

## Questions

- **director:** Is "operator-entered + provider entry point + simulator fault" OK as S7 v1, given
  that no real provider reports station status yet?
- **api-ops:** this facade matches your S7 endpoint shape (`state`, `since`, `reported_by`,
  `eta`, `windows[{from, to, kind, source}]`). `kind` is `outage | maintenance | degraded`; the
  plan said `unusable`, and I renamed it `degraded` to match the state. OK?

## As built

- **Status has no `unknown` state yet.** Nothing links a ground station to the provider account
  serving it, so provider health can't be attributed to a station. `state` is `down`,
  `degraded` or `up` (with `basis: "no reported windows"`).
- **Views** carry `source` (`operator | provider`), `reported_by`, `reported_at`, `created_by`
  and `eta` (null when unknown); windows carry `id`.
- **Impact** is a read, not part of the comms facade (comms can't reach contacts):
  `Cadence.Reads.StationImpact.impact(scope, mission_id, station_id, from, to)` returns
  `%{passes_hit, reservation_ids, spacecraft_ids, truncated}` for live reservations whose
  provider snapshot (confirmed, else requested) or metadata names the station.
- **Provider ingestion** runs on provider inventory sync (`GroundNetworks.sync_provider`):
  `StationAvailability.ProviderReports.sync/4` takes the provider's full report from each
  station's `availability_windows`. It upserts each window by `"<provider_id>:<window id>"`,
  clears this provider's windows no longer listed, and reactivates a re-reported window even
  if it was cleared. Stations are matched by id (the convention opportunities already use for
  `ground_station_ref`); unknown stations are skipped. Sync is on demand today, not periodic.
- **Simulator fault** `station_outages: [%{id, ground_station_id, kind, starts_at,
  ends_at | nil, reason}]` lists the windows on `/provider/v1/ground-stations`. Outage and
  maintenance windows mark overlapping opportunities `availability: "unavailable"` and reject
  bookings with `status_reason: "station_unavailable"`; degraded windows are only reported.
- **Planning**: opportunities overlapping an outage or maintenance window at their station get
  hard failure `station_unavailable`.
