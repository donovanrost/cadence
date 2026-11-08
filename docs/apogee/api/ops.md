# Ops endpoints (Now, Investigate, Contacts, Command)

Conventions: [README.md](README.md). Asks are tracked by their IDs in `docs/apogee/plans/ops.md`.

| Ask | Endpoint | Status |
| --- | --- | --- |
| M1 M2 M3 M5 | `GET /missions/:mission_id/fleet` | **implemented** |
| M9 | `GET /missions/:mission_id/alarms` | next |
| M10 | `GET /missions/:mission_id/telemetry/points/:point_id/history` | planned |
| M11 | `GET /missions/:mission_id/limits/points/:point_id/intervals` | planned |
| M6 | `GET /missions/:mission_id/action-queue` | planned |
| M8 | channel events: see [realtime.md](realtime.md) | `invalidate` live, `fleet` delta planned |

## `GET /api/console/v1/missions/:mission_id/fleet`

The fleet's operational state, one row per spacecraft, with the Now stat-strip counts.
Refetch on `invalidate` with `telemetry`, `limits`, `spacecraft` or `commanding`.

```json
{
  "data": {
    "observed_at": "2026-11-08T02:41:17Z",
    "stale_after_s": 900,
    "last_received_at": "2026-11-08T02:41:15Z",
    "counts": {
      "total": 500, "critical": 3, "caution": 14, "stale": 12, "nominal": 471,
      "never_heard": 0, "fresh": 488,
      "in_contact": null, "passes_next_2h": null, "critical_delta_1h": null
    },
    "commands": {
      "queued": 23, "in_flight": 0, "failed": 0,
      "approval_pending": 2, "awaiting_viewer": 2
    },
    "limits": {"configured": true},
    "spacecraft": [
      {
        "id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312,
        "profile": {"id": "…", "name": "Reflector bus", "version": 1},
        "plane": 13, "slot": 12, "phase_deg": 167.04, "operational_phase": "routine",
        "state": "critical",
        "limit_state": "critical",
        "violating_points": 1,
        "worst_point": {
          "point_id": "…", "point_name": "VBAT", "value": 23.1,
          "limit_state": "critical", "raw_limit_state": "red_low",
          "received_at": "2026-11-08T02:41:15Z"
        },
        "last_received_at": "2026-11-08T02:41:15Z",
        "stale": false,
        "in_contact": null
      }
    ]
  }
}
```

### Semantics

- `state`: `critical | caution | stale | nominal | never_heard`. It is the spacecraft's worst
  condition, in precedence order critical > caution > stale > nominal. `never_heard` means
  nothing was ever received. The five `counts` of these partition `total`.
- `limit_state`: `critical | caution | nominal | no_data`, from the latest limit evaluation of
  each point (`red` = critical, `yellow` = caution, `green`/`blue` = nominal). A critical
  spacecraft stays critical even when its data is stale, because the last known condition was
  critical. `stale` is still `true` on that row, so you can show both.
- `last_received_at`: the newest receipt time across the spacecraft's current telemetry values
  and limit evaluations. `stale` = `now − last_received_at > stale_after_s` (server-decided, U9).
- `counts.fresh`: spacecraft heard within `stale_after_s` (the "TLM FRESH 488/500" meta).
- `worst_point`: the most severe violating point, newest first among equals. It is `null` when
  nothing violates.
- `plane`, `slot`, `phase_deg` (from `metadata.orbit.mean_anomaly_deg`) and `operational_phase`
  come from spacecraft metadata until domain makes them first-class. Any of them may be `null`;
  apply U8 for the matrix shape.
- `profile` is `null` when the spacecraft has no profile. `profile.name` may be `null` if the
  profile was deleted.
- `commands.queued` counts queued plus release-pending requests. `commands.in_flight` counts
  released requests awaiting verification. `commands.failed` counts failed or indeterminate
  requests. `commands.awaiting_viewer` counts approval-pending requests the viewer did not
  request; this is the "await your GO" number (U11). It does not yet apply the D7 eligibility
  policy.
- `limits.configured`: `false` when the mission has no limit definitions. Show the P3 "Limits &
  Alarming not configured" item and treat `limit_state` as `no_data`.
- **Not tracked yet, so always `null` for now:** `counts.in_contact`, `counts.passes_next_2h`,
  `counts.critical_delta_1h`, and per-row `in_contact`. Show `—` and "not tracked yet" (U10).
  They fill in with M4/M7 (contacts) and limit-transition history.
- Rows are sorted by `plane`, `slot`, `scid`, `name`, with nulls last.

Errors: `404 mission_not_found`.

Size: about 600 bytes per row, roughly 300 KB for 500 spacecraft before gzip. It is unpaginated
by design (the matrix needs every row). The planned `fleet` channel delta sends only changed rows.
