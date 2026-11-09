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
| M8 | channel events: see [realtime.md](realtime.md) | `invalidate` and `fleet` push live |
| shell | `GET /missions/:mission_id/counts` (lead) | **implemented** |
| M17 | `GET /missions/:mission_id/commands[/:command_id]`: see [commanding.md](commanding.md) | **implemented** |

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
      "in_contact": 4, "passes_next_2h": 31, "critical_delta_1h": null
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
        "in_contact": false,
        "next_aos_at": "2026-11-08T03:12:00Z",
        "last_los_at": "2026-11-08T01:39:00Z"
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
  requests. `commands.approval_pending` and `awaiting_viewer` count **decisions**: a standalone
  approval-pending request is one, and a command group waiting for its second GO is one however
  many members it has. `awaiting_viewer` is the viewer's share ("await your GO", U11): requests
  they didn't make, and groups where they're an eligible approver (not the requester, and the
  named approver if one was picked).
- `limits.configured`: `false` when the mission has no limit definitions. Show the P3 "Limits &
  Alarming not configured" item and treat `limit_state` as `no_data`.
- **Contact facts** (M7) come from **booked provider reservations** (see contacts.md), judged at
  `observed_at`:
  - row `in_contact`: a reservation for it is `active`, or its `pass_phase` is `pass`, and now is
    inside its window. `next_aos_at`: start of its next `confirmed`/`active` reservation.
    `last_los_at`: the planned end of its most recent booked reservation that has ended. They are
    planned times (there are no actual AOS/LOS records yet, S9).
  - `counts.in_contact`: rows in contact. `counts.passes_next_2h`: booked passes starting within 2 h.
  - When the mission has **no reservations at all**, all of these are `null` ("not tracked").
    Contacts that weren't booked through Cadence (for example a direct simulator link) aren't
    seen.
  - Refetch on `invalidate` with `contacts`. AOS and LOS happen without an event, so a static
    page drifts; the fleet push's 10 s tick picks them up.
- `counts.critical_delta_1h` is always `null` (no limit-transition history yet). Show `—` and
  "not tracked yet" (U10).
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
        "point": {"id": "EPS.VBAT", "name": "VBAT", "subsystem": "EPS", "unit": "V", "description": null},
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
- `point.unit`: the engineering unit of the decoded packet field in the mission's **active** binding
  set, falling back to the active revision's catalog declarations (parameter → parameter type →
  unit, which is where XTCE import puts it). `null` when the catalog declares no unit or nothing is
  active. `point.description` is
  always `null` for now: catalog import doesn't carry parameter descriptions through to the binding
  set yet (api-ops backlog, with M23).
- **Not yet:** the D6 alarm lifecycle (ack/assign/hand-off).

## `GET /api/console/v1/missions/:mission_id/counts`

Small counts for the shell (Ops rail, mobile on-call tabs), so the shell doesn't load `GET /fleet`
(~300 KB) for numbers. Refetch on `invalidate` with `alarms`, `commanding` or `spacecraft`, throttled.

```json
{"data": {
  "observed_at": "2026-11-08T02:41:17Z",
  "alarms": {"active": 4, "critical": 3, "caution": 1, "unacknowledged": 2, "limits_configured": true},
  "commands": {"open": 25, "awaiting_viewer": 2},
  "fleet": {"total": 500},
  "contacts": {"in_contact": 4}
}}
```

- `alarms`: from **alarm episodes** (both sources, DECISIONS #17); `unacknowledged` = active
  episodes with status `new`. `limits_configured` is the same as `GET /fleet` `limits.configured`.
  Per U13, show a real `0` only when something can raise alarms (ground limits configured, or
  catalog monitoring). The whole object is `null` if episodes can't be read.
- `commands.open`: queued + release pending + in flight + approval pending. `awaiting_viewer`:
  approval-pending requests the viewer didn't request (the same number as `GET /fleet`).
- `contacts.in_contact`: spacecraft in a booked contact now (same rule as `GET /fleet`). `contacts` is
  `null` when the mission has no reservations (not tracked).
- A `null` count means "can't compute": omit it in the UI, never show `0`.

- **Planned (DECISIONS #54, U31):** `attention: {open, acknowledged}`, counting the mission's
  open "needs acknowledgment" items (pass-resolution conflicts for now). It feeds Now's queue header
  and the mobile Now badge, not a rail count. `null` when the attention read can't be read.
  Refetch on `invalidate` with `attention`.

Errors: `404 mission_not_found`.

## `GET /api/console/v1/missions/:mission_id/action-queue`

The viewer's ranked action queue (Now A2), ranked by ux U11. Refetch on `invalidate` with `alarms`,
`commanding`, `spacecraft`, `limits`, `catalog`, `data_sources` or `settings`, plus `telemetry`
throttled to about 10 s (stale groups change with time).

```json
{"data": {
  "observed_at": "2026-11-08T02:41:17Z", "stale_after_s": 900, "failure_lookback_s": 86400,
  "alarms_truncated": false,
  "counts": {"p1": 2, "p2": 3, "p3": 1, "spacecraft_p1": 4},
  "items": [{
    "id": "alarm:critical:EPS.VBAT:red_low",
    "priority": 1, "kind": "alarm", "state": "critical",
    "since": "2026-11-08T02:35:02Z", "due_at": null, "count": 3,
    "spacecraft": [{"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312, "plane": 13,
                    "stale": false, "last_received_at": "…", "violating_points": 1,
                    "value": 23.1, "first_crossed_at": "2026-11-08T02:35:02Z"}],
    "point": {"id": "EPS.VBAT", "name": "VBAT", "subsystem": null, "unit": "V"}, "condition": "red_low",
    "source": "ground_limit", "acknowledged": 0,
    "plane": null, "command": null, "outcome": null, "command_requests": [], "finding": null
  }]
}}
```

Every item has every field; fields that don't apply to its `kind` are `null` (or `[]` for lists).

| kind | priority | state | grouped by | filled fields |
| --- | --- | --- | --- | --- |
| `alarm` | 1 critical, 2 caution | `critical` / `caution` | `{source, severity, point, condition}` of each spacecraft's **worst** active alarm episode (critical, then unacknowledged, then newest) | `source` (`catalog_monitoring` / `ground_limit`), `acknowledged` (members acknowledged), `point` (with `unit`), `condition` (the episode's `source_state`), `spacecraft` (with `value` = last value, `first_crossed_at` = episode opened, `episode_id`, `status` `new`/`acknowledged`, `assignee`) |
| `command_failed` | 1 | `critical` | `{command, outcome}`, failures within `failure_lookback_s` | `command {id, name}`, `outcome` (`failed` = release or verify failed, `indeterminate` = release uncertain), `command_requests`, `spacecraft` (resolved targets) |
| `approval` | 2 | `caution` | one item: decisions waiting on the viewer: standalone approval-pending requests they didn't make, plus **command groups** awaiting their GO (one each) | `command_requests` (standalone only), `command_groups [{id, title, member_count, target_count, requested_by, requested_at}]`, `spacecraft`; `count` = requests + groups |
| `stale` | 2 | `stale` | plane (`plane: null` = no plane metadata) | `plane`, `spacecraft` |
| `setup` | 3 | `off` | one per readiness finding with severity `blocker` or `not_set_up` | `finding` (the readiness finding: `id, area, severity, cause, title, body, affected_count, fix`) |
| `limits_not_configured` | 3 | `off` | — (omitted when the limits app itself isn't installed; that is a `setup` item) | none |
| `never_heard` | 3 | `off` | one item | `spacecraft` |

- `id` is stable across refetches (use it as the list key and for "seen" state).
- Order: `priority`, then alarm items whose episodes are **all acknowledged** after the rest of
  that priority, then `due_at` (soonest first), then `since` (oldest first, `null` last), then `id`.
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
- `alarms_truncated`: the queue reads at most 200 active episodes (domain's page cap). `true` means
  more are active, so alarm items may be incomplete; show "Showing the first 200 alarms" and link to Alarms.
- Every item also has `source` and `acknowledged` (`null` for non-alarm kinds), and every
  `spacecraft` member has `episode_id`, `status`, `acknowledged_by` (`{kind, id, name}`) and
  `assignee` (`null` outside alarm items). Acknowledged rows show "ACK <name>" (ux U21).
- `counts.spacecraft_p1`: distinct spacecraft across P1 items (the "N spacecraft need you" headline).
- **Not derived yet** (no source): critical flight events (safe mode), missed passes, degraded
  stations, no-ACK retries. Alarm items come from **alarm episodes** (both sources, DECISIONS #17).
- **Planned: `attention` items (DECISIONS #54, U31).** Not built yet; it waits on domain's attention
  read. One item per open or acknowledged item from that read, never grouped:
  - `id` `attention:<source>:<attention id>`; `kind` `attention`; `source` is the subkind
    (`pass_resolution` for now).
  - `priority` 1 (`state` `critical`) when the pass starts within 2 h or is in progress;
    otherwise 2 (`state` `caution`). Acknowledged items sort last within their priority (U21),
    the same as fully acknowledged alarms.
  - `due_at` is the pass's `starts_at`, the consequence time that Now's meta shows as "AOS T−01:12".
    `since` is `raised_at`.
  - `spacecraft` has one member with the **resolved name** (title `EARENDIL-001 · …`, never the id).
  - A new field, `attention` (`null` on other kinds), holds `{id, source, conflict:
    cancel_failed | late_confirmation | contradicts_attestation, state: open | acknowledged,
    acknowledged_by: {kind, id, name} | null, contact_id, station {ref, id, code, name},
    provider {id, name}, starts_at, raised_at, provider_message, resolution: {action, actor {kind,
    id, name}, at, note, provider_reference} | null}`. `contact_id` is the `Review` target
    (`M/contacts/:contactId`).
  - The response gains `resolved: [{id, resolved_by {kind, id, name}, resolved_at}]`: attention items
    resolved in the last 60 s, so the fade-out can read "Resolved by Mira K." after a refetch.
  - Refetch on `invalidate` with `attention`.
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
  "point_id": "EPS.VBAT", "unit": "V", "description": null, "spacecraft_id": "spacecraft-earendil-312",
  "from": "2026-11-08T01:41:17.000Z", "to": "2026-11-08T02:41:17.000Z",
  "bucket_width_ms": 7200, "truncated": false,
  "buckets": [{"t": "2026-11-08T01:41:17.000Z", "t_end": "2026-11-08T01:41:24.200Z",
               "min": 23.4, "max": 23.6, "mean": 23.5, "count": 7}]
}}
```

- `unit` / `description`: same source and caveats as the alarm `point.unit` / `point.description`.
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

## `GET /api/console/v1/missions/:mission_id/events` (owner: api, DECISIONS #26)

The event log for Investigate B2 and Timeline. It reads the canonical mission timeline (projected
mission events merged with operational events). Refetch on `invalidate` with `events` or `alarms`.

Query: `from`, `to` (ISO, default the last 24 h), `spacecraft_id`, `kind` (comma list of
`limit, flight_event, contact, command, config, operator, data`; `data` is data-plane housekeeping
such as source watermarks and source health, which you'll usually filter out), `limit` 1–500 (default 200), and
`cursor` (opaque, from `meta.next_cursor`). Newest first.

```json
{"data": {"from": "…", "to": "…", "events": [{
  "id": "mission_event:…", "at": "2026-11-08T02:08:11Z",
  "kind": "limit", "raw_kind": "limit_violation", "severity": "critical",
  "text": "VBAT crossed red low", "detail": "…",
  "spacecraft": {"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312},
  "refs": {"alarm_id": null, "point_id": "EPS.VBAT", "command_request_id": null, "contact_id": null,
           "subject": {"kind": "data_source", "id": "…", "name": "Flight telemetry source"}}
}]}, "meta": {"next_cursor": "…"}}
```

- `text` is an operator sentence naming what the event is about, built on the server (ux review
  2026-11-09-timeline #1): "Flight telemetry source caught up to 10:23:54Z", "Contact with
  EARENDIL-004 completed, 10:22:54Z–10:23:52Z", "Dashboard Comms payload v1 published by Mira K.",
  "Catalog rev 2 (QA-E2E re-import) registered". Unknown kinds fall back to the sentence-case key
  plus the spacecraft ("Limit violation on EARENDIL-004"), never Title Case. `detail` is `null`.
- Contact events (`scheduled_contact_*`, `realized_contact_*`) have kind `contact`. A realized
  contact that completed reads "ended (not verified)" until S9 verifies it. A provider-cancelled
  contact names its spacecraft, station and window. Ranges carry one Z ("10:22:54–10:23:52Z").
- The same fact can reach the timeline from two sources (a projected mission event and its
  operational event). Rows with the same raw kind, subject and second collapse into one, keeping
  the more severe.
- `activation` subjects have no console page yet; leave them unlinked (Setup's change history is
  the nearest place).
- `refs.subject` is the link target `{kind: "data_source" | "contact" | "dashboard" |
  "catalog_revision" | "activation", id, name}`, or `null` when there is none.
- A watermark retreat is `caution` only when it means something for the operator (a replay or
  late data), and the sentence says so ("… went back to 22:28:30Z (data replay)"); otherwise
  it's `info` (#3).
- `kind` is derived from the entry's source and category; `raw_kind` keeps the original.
  `severity`: timeline critical/error → `critical`, warning → `caution`, cleared/resolved status →
  `nominal`, everything else → `info`.
- The `kind` filter is applied to each fetched page, so a page can hold fewer than `limit` events
  while `next_cursor` is still set. Keep following the cursor. `plane` filtering isn't supported
  (filter client-side with `/fleet` plane data).
- `refs.alarm_id` is `null` (alarm episodes link by point; see alarms.md).
- Errors: `422 invalid_params` (`kind`, `limit`, `cursor`, `from`/`to`).

## `GET /api/console/v1/missions/:mission_id/events/density`

`{"data": {"bucket_s": 900, "buckets": [{"t", "critical", "caution", "nominal", "info"}], "truncated": false}}`.
Same filters (no cursor). `bucket_s` is 60–86400 (default: about 96 buckets over the window). Buckets
are aligned to `from`; empty buckets are omitted. The window is at most 31 days, and at most 5,000
events are counted (`truncated: true` beyond that).

## `GET /api/console/v1/missions/:mission_id/telemetry/points` (M23, owner: api)

Point search for Telemetry explore (T1) and ⌘K Telemetry. Query: `q` (a case-insensitive
substring of the id, name or description; empty lists everything), `spacecraft_id` (optional;
must be a mission spacecraft), and `limit` 1–200 (default 50).

```json
{"data": {"points": [{
  "id": "EPS.VBAT", "name": "VBAT", "description": null, "unit": "V",
  "subsystem": "EPS", "type": "numeric",
  "latest": {"value": 23.1, "received_at": "…", "limit_state": "critical"}
}]}}
```

- The points are the mission's canonical set: fields of the active binding set's packet
  definitions (`subsystem` is the packet name) plus governed derived telemetry (`subsystem:
  "Derived"`). It's the same set the LiveView point picker offers, sorted by id.
- `type`: `numeric | enum | text`, from the field's data type.
- `latest` appears only with `spacecraft_id`, and is `null` if that point was never received.
  `limit_state` is `critical | caution | nominal | no_data`.
- `description` is often `null`: packet fields don't carry one yet.
- Errors: `422 invalid_params` (`limit`, `spacecraft_id`).
