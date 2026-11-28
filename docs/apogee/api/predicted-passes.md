# Predicted passes

Owner: **ground**. Issue #891 (slice 3 of #732). Design: `docs/pass-prediction-design.md` and
DECISIONS #114. Element sets: [element-sets.md](element-sets.md).

A predicted pass is one spacecraft above one station's elevation mask, computed with SGP4 from the
spacecraft's current element set and the station's location. Passes are stored rows, recomputed
by background jobs, never in a request:

| When | What is recomputed |
| --- | --- |
| A stored element set becomes a spacecraft's current one | That spacecraft, every station, from now to the horizon end |
| A station's location, mask or lifecycle changes (the mission's edit, or a provider report where the mission set no location) | That station, every spacecraft, from now to the horizon end. An archived station loses its passes |
| A spacecraft is archived | That spacecraft: its passes from now on are deleted |
| `POST .../predicted-passes/recompute` | Everything, from now to now + horizon |
| Daily | The horizon moves on a day; passes that ended more than 7 days ago are deleted |

The horizon is 7 days by default and at most 14, per mission (settings section
`cadence.pass_prediction`, key `horizon_days`). A recompute replaces the passes that end after
"now", a pass in progress included; passes that already ended stay, for planning history, until
the prune. Only active spacecraft and active stations are predicted. The first element sets a
mission stores start a full run.

Predicted passes are geometry, not bookings. They don't feed the fleet row's next AOS or a
contact's next pass, which come from bookings.

## Auth

- **Persons** use the session cookie, plus CSRF on writes. Any member who can open the mission
  can read. `recompute` needs mission management (an organization admin, or a mission admin of
  this mission).
- **Service identities** reach none of these endpoints: `403 service_not_allowed`.

## Read

```
GET /api/v1/missions/:mission_id/predicted-passes
      ?from=&to=&station_id=&spacecraft_id=&cursor=&limit=
GET /api/v1/missions/:mission_id/spacecraft/:spacecraft_id/predicted-passes
      ?from=&to=&cursor=&limit=
```

- **Window.** `from` and `to` are ISO 8601 times, both required. A page holds the passes that
  **overlap** `[from, to)`: `los > from` and `aos < to`, so a pass already in view at `from` is
  included.
- **Length.** `to` must be after `from` (else `invalid_params` with `details.field: "to"`). A
  window filtered by `station_id` or `spacecraft_id` (or on the spacecraft path) spans at most 14
  days. An unfiltered mission window spans at most 1 day
  (24 hours): a whole fleet's passes over two weeks is a few hundred thousand rows.
- **Order and paging.** AOS, then id. `limit` is 1–500 (default 200). `meta.next_cursor` is
  opaque; pass it back as `cursor` with the same other parameters. `null` means the last page.

```json
{
  "data": [
    {
      "id": "predicted_pass_…",
      "aos": "2026-11-27T00:41:12.000000Z",
      "tca": "2026-11-27T00:46:30.000000Z",
      "los": "2026-11-27T00:51:49.000000Z",
      "max_elevation_deg": 38.2,
      "aos_azimuth_deg": 201.4,
      "los_azimuth_deg": 77.9,
      "spacecraft": {"id": "craft-1", "name": "Earendil 1", "scid": 701},
      "station": {"id": "ground_station_…", "display_name": "Svalbard", "code": "SVA"},
      "element_set": {"id": "elset_…", "epoch": "2026-11-26T12:00:00.000000Z"},
      "computed_at": "2026-11-27T00:00:00.000000Z"
    }
  ],
  "meta": {
    "next_cursor": "WyIyMDI2LTEx…",
    "coverage": {
      "horizon_end": "2026-12-04T00:00:00.000000Z",
      "computed_at": "2026-11-27T00:00:00.000000Z",
      "unpredicted": {
        "spacecraft_without_element_set": 0,
        "spacecraft_deep_space": 0,
        "stations_without_location": 1,
        "passes_not_bracketed": 0
      }
    }
  }
}
```

Times are UTC with `Z`. Azimuths are degrees from north through east. `max_elevation_deg` is at
TCA.

### Coverage

Every page carries the same `coverage`, so a client can show an honest empty or partial state
without a per-spacecraft read.

- `horizon_end`: passes are computed up to here. **`horizon_end < to` is the partial state**: the
  window runs past what is computed, so a later part of it shows no passes because none are
  computed yet, not because there are none. `null` (with `computed_at`) before the mission's first
  run.
- `computed_at`: when the mission's last recompute ran.
- `unpredicted`, counts of what has no passes for a reason other than geometry:
  - `spacecraft_without_element_set`: active spacecraft with no stored orbit;
  - `spacecraft_deep_space`: spacecraft whose current set has a period of 225 minutes or more,
    which waits for SDP4 (#732 slice 7);
  - `stations_without_location`: active stations with neither the mission's location nor a
    provider's;
  - `passes_not_bracketed`: passes the search found above the mask but whose AOS or LOS it could
    not find within one synodic period of the window's start or end, so it stored nothing rather
    than a clipped time. Near-earth geometry makes this very unlikely; a non-zero count points to an
    element set that is wrong (an epoch far from now, a decayed orbit) and is worth checking.
- **Scope.** With `spacecraft_id` (or on the spacecraft path), the spacecraft counts and
  `passes_not_bracketed` cover that spacecraft only. With `station_id`, `stations_without_location`
  and `passes_not_bracketed` cover that station only.

### Refusals

| Status | Code | When |
| --- | --- | --- |
| 422 | `invalid_params` | `details.field` is `from`, `to`, `cursor`, `limit`, `station_id` or `spacecraft_id`: missing, not a time, out of range, or not this mission's. `to` at or before `from` is `field: "to"`, `reason: "must be after from"` |
| 422 | `predicted_pass_window_too_long` | The window is longer than its maximum. `details.max_days` is 14, or 1 for an unfiltered mission window |
| 404 | `spacecraft_not_found` | The spacecraft path names a spacecraft the mission doesn't have |

## Recompute

```
POST /api/v1/missions/:mission_id/predicted-passes/recompute
```

Enqueues a full recompute and answers `202`:

```json
{"data": {"run_id": "pass_prediction_run_…", "status": "queued"}}
```

`status` is `queued` or `running`. A repeat request while the mission's full run is still queued
or running stages nothing and answers that same run (its `run_id` and current `status`), so
pressing Recompute twice runs once. The run's end is the `predicted_passes` live update (below).
Seeds don't need this endpoint: the first element sets a mission stores start a full run.

## Live updates

Every finished recompute (full, spacecraft, station, extension, an archived spacecraft's)
publishes `predicted_passes` once on the mission channel (`invalidate` with
`resources: ["predicted_passes"]`), whether or not rows changed, so a client waiting on a run sees
it end; then `coverage.computed_at` is that run's time. The daily prune publishes only when it
deleted passes. Never once per pass.

A failed run isn't reported in this read yet: it fails as a background job and `computed_at`
stays at the last run that finished.
