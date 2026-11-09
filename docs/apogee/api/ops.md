# Ops endpoints (Now, Investigate, Contacts, Command)

Owner: **api-ops** (from 2026-11-08, DECISIONS #21); api built the first four endpoints below.
Conventions: [README.md](README.md). Asks are tracked by their IDs in `docs/apogee/plans/ops.md`.

**Handover (api → api-ops):** M1–M3, M5, M9, M10 and M11 are implemented and tested. Still open from
the threads: point `unit`/`description` on M9 and M10 (ux, fe-ops, via the M23 catalog join); the
`fleet` channel push (shape in realtime.md, with fe-ops' seq/counts/full-row comments); and an
events read for Investigate B2 and Timeline. The `LimitTransitions` relay (`alarms` invalidations)
is yours too.

| Ask | Endpoint | Status |
| --- | --- | --- |
| M1 M2 M3 M5 | `GET /missions/:mission_id/fleet` | **implemented** |
| M9 | `GET /missions/:mission_id/alarms` | **implemented** |
| M10 | `GET /missions/:mission_id/telemetry/points/:point_id/history` | **implemented** |
| M11 | `GET /missions/:mission_id/limits/points/:point_id/intervals` | **implemented** |
| M6 | `GET /missions/:mission_id/action-queue` | **implemented** (api-ops) |
| M8 | channel events: see [realtime.md](realtime.md) | `invalidate` live, `fleet` delta planned |

## `GET /api/console/v1/missions/:mission_id/fleet`

The fleet's operational state, one row per spacecraft, with the Now stat-strip counts.
Refetch on `invalidate` with `alarms`, `spacecraft` or `commanding` (and `telemetry` if you show
freshness to the second; at 1 Hz feeds, throttle that to about 10 s client-side).

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
- `last_received_at`: the newest receipt time across the spacecraft's current telemetry values,
  limit evaluations and the **durable history store** (U15). Once heard, a spacecraft stays
  heard across restarts; it can only be fresh or stale. `stale` = `now − last_received_at > stale_after_s` (server-decided, U9).
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

## `GET /api/console/v1/missions/:mission_id/alarms`

Limit alarms from the latest limit-state projection, one row per (spacecraft, point, limit set).
Refetch on `invalidate` with `alarms` (limit-state *transitions* only) or `limits` (definition
changes).

Query: `state` = `active` (default) | `nominal` | `all`; `severity` = `critical` | `caution`;
`spacecraft_id`; `q` (substring of point id/name/subsystem/limit set). Unknown `state`/`severity`
values get `422 invalid_params` with `details`.

```json
{
  "data": {
    "observed_at": "2026-11-08T02:41:17Z",
    "summary": {"active": 4, "critical": 3, "caution": 1, "latest_transition_at": "2026-11-08T02:35:02Z"},
    "alarms": [
      {
        "id": "limit_event_…",
        "spacecraft_id": "spacecraft-earendil-312",
        "point": {"id": "EPS.VBAT", "name": "VBAT", "subsystem": "EPS"},
        "severity": "critical",
        "active": true,
        "condition": "red_low",
        "value": 23.1,
        "limit_set_name": "DEFAULT",
        "thresholds": {"red_low": 24.0, "yellow_low": 25.0, "yellow_high": 33.0, "red_high": 34.0},
        "first_crossed_at": "2026-11-08T02:35:02Z",
        "generation_time": "2026-11-08T02:41:14Z",
        "received_at": "2026-11-08T02:41:15Z"
      }
    ]
  }
}
```

- `severity`: `critical | caution | nominal`, the same vocabulary as the fleet `limit_state`
  (`red` = critical, `yellow` = caution, `green`/`blue` = nominal).
- `condition`: the raw limit state (`red_low`, `yellow_high`, …). It tells you which side was crossed.
- `summary` counts **all** active alarms in the mission, ignoring the filters.
- `thresholds`: the bands of the limit definition version that produced this state. A missing band
  is `null`. The whole object is `null` if the definition can't be found.
- `first_crossed_at`: when the point entered its current state. It is the oldest evaluation in the
  current unbroken run of that state, by generation time (falling back to receipt time). The
  server looks back up to 200 evaluations, so for a state held longer than that it is the oldest
  one in the window. Only the first 200 rows are enriched; later rows have `null`.
- `value`: the evaluated engineering value, as a number, string or boolean.
- Sorting: severity (critical first), then newest received first.
- **Not yet:** point `unit` and `description` (they need the catalog point join; planned with M23
  point search), and the D6 alarm lifecycle (ack/assign/hand-off).

## `GET /api/console/v1/missions/:mission_id/action-queue`

The viewer's ranked action queue (Now A2), ranked by ux U11. Refetch on `invalidate` with `alarms`,
`commanding`, `spacecraft`, `limits`, `catalog`, `data_sources` or `settings`, plus `telemetry`
throttled to about 10 s (stale groups change with time).

```json
{"data": {
  "observed_at": "2026-11-08T02:41:17Z", "stale_after_s": 900, "failure_lookback_s": 86400,
  "counts": {"p1": 2, "p2": 3, "p3": 1, "spacecraft_p1": 4},
  "items": [{
    "id": "alarm:critical:EPS.VBAT:red_low",
    "priority": 1, "kind": "alarm", "state": "critical",
    "since": "2026-11-08T02:35:02Z", "due_at": null, "count": 3,
    "spacecraft": [{"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312, "plane": 13,
                    "stale": false, "last_received_at": "…", "violating_points": 1,
                    "value": 23.1, "first_crossed_at": "2026-11-08T02:35:02Z"}],
    "point": {"id": "EPS.VBAT", "name": "VBAT", "subsystem": "EPS"}, "condition": "red_low",
    "plane": null, "command": null, "outcome": null, "command_requests": [], "finding": null
  }]
}}
```

Every item has every field; fields that don't apply to its `kind` are `null` (or `[]` for lists).

| kind | priority | state | grouped by | filled fields |
| --- | --- | --- | --- | --- |
| `alarm` | 1 critical, 2 caution | `critical` / `caution` | `{severity, point, condition}` of each spacecraft's **worst** active alarm | `spacecraft` (with `value`, `first_crossed_at`), `point`, `condition` |
| `command_failed` | 1 | `critical` | `{command, outcome}`, failures within `failure_lookback_s` | `command {id, name}`, `outcome` (`failed` = release or verify failed, `indeterminate` = release uncertain), `command_requests`, `spacecraft` (resolved targets) |
| `approval` | 2 | `caution` | one item: approval-pending requests **not** requested by the viewer | `command_requests`, `spacecraft` |
| `stale` | 2 | `stale` | plane (`plane: null` = no plane metadata) | `plane`, `spacecraft` |
| `setup` | 3 | `off` | one per readiness finding with severity `blocker` or `not_set_up` | `finding` (the readiness finding: `id, area, severity, cause, title, body, affected_count, fix`) |
| `limits_not_configured` | 3 | `off` | — (omitted when the limits app itself isn't installed; that is a `setup` item) | none |
| `never_heard` | 3 | `off` | one item | `spacecraft` |

- `id` is stable across refetches (use it as the list key and for "seen" state).
- Order: `priority`, then `due_at` (soonest first), then `since` (oldest first, `null` last), then `id`.
  The server returns the order; don't re-sort.
- `since`: alarm = earliest `first_crossed_at` in the group; command = oldest failure / request time;
  stale = the oldest `last_received_at` (silent the longest); setup / never-heard = `null`.
- `due_at` (time to consequence: next AOS, umbra entry, release time) is **always `null` for now**.
  It fills in with M7 (passes) and D1 (propagation).
- Groups can have one member. The server groups every identical cause; the UI may show small
  groups as individual rows.
- `spacecraft` members are ordered oldest-first by `since` for alarms, fleet order otherwise.
- `command_requests[]`: `{id, command_name, target: {id, name}, spacecraft_id, requested_by, requested_at, status, occurred_at}`.
  `requested_by` is a display label. `status` uses the command-status vocabulary (`failed`, `indeterminate`, `approval_pending`, …).
- `counts.spacecraft_p1`: distinct spacecraft across P1 items (the "N spacecraft need you" headline).
- **Not derived yet** (no source): critical flight events (safe mode), missed passes, degraded
  stations, no-ACK retries. Alarm items are limit-state based; they switch to alarm episodes (D6/#17)
  when domain's lifecycle lands.
- `failure_lookback_s` is `config :cadence, :action_queue_failure_lookback_s` (default 24 h).
  Failures older than that drop off the queue; they stay on the commands pages.

Errors: `404 mission_not_found`.

## Time windows (shared by M10 and M11)

Query: `from` and `to` are ISO-8601 (default: the last hour ending now); `spacecraft_id` is
optional but you almost always want it; for M10, `max_points` is 1–2000 (default 500). History
windows are capped at 31 days; intervals are not. Bad values get `422 invalid_params` with
`details` keyed by parameter. URL-encode `point_id` (ids contain dots, and some may contain
slashes).

## `GET /api/console/v1/missions/:mission_id/telemetry/points/:point_id/history`

Decimated history by **generation time** (it falls back to receipt time for samples without one).
The data is fixed-width buckets on a UTC-day grid (multiples of `bucket_width_ms` from midnight UTC of
the window's first day, the same as QuestDB `ALIGN TO CALENDAR`); there are at most about
`max_points` buckets, and empty buckets are omitted.

```json
{"data": {
  "point_id": "EPS.VBAT", "spacecraft_id": "spacecraft-earendil-312",
  "from": "2026-11-08T01:41:17.000Z", "to": "2026-11-08T02:41:17.000Z",
  "bucket_width_ms": 7200, "truncated": false,
  "buckets": [{"t": "2026-11-08T01:41:17.000Z", "t_end": "2026-11-08T01:41:24.200Z",
               "min": 23.4, "max": 23.6, "mean": 23.5, "count": 7}]
}}
```

- Only numeric values are bucketed (booleans count as 0/1). Enum and text points return no
  buckets for now; a state-timeline shape will come if a screen needs it.
- `truncated: true` means the raw-sample fallback (used on backends without native decimation)
  hit its 20,000-sample cap. Narrow the window if you see it.
- `503 history_unavailable`: the history store can't be reached (in this worktree's dev env,
  QuestDB isn't running; see the qa runbook). Show the chart's unavailable state.
- Refetch on `invalidate` with `telemetry`, throttled. For a live tail, prefer the planned
  `spacecraft:<id>` `points` push.

## `GET /api/console/v1/missions/:mission_id/limits/points/:point_id/intervals`

The limit-definition bands in effect over the window, for drawing bands behind the history chart.

```json
{"data": {
  "point_id": "EPS.VBAT", "spacecraft_id": null, "from": "…", "to": "…",
  "intervals": [{
    "from": "2026-10-19T00:00:00Z", "to": null,
    "limit_set_name": "DEFAULT", "limit_definition_id": "…", "limit_definition_version": 3,
    "scope": {"type": "mission", "ref": null},
    "thresholds": {"red_low": 24.0, "yellow_low": 25.0, "yellow_high": 33.0, "red_high": 34.0}
  }]
}}
```

- `to: null` means the definition is still active. Missing bands are `null`.
- Intervals come from governed limit-definition lifecycle events. A definition persisted without a
  lifecycle event (some fixtures) has no interval, but the alarm row's `thresholds` still shows
  its bands.
- Refetch on `invalidate` with `limits`.
