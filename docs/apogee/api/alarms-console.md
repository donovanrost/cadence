# Alarm episodes: console endpoints

Owner: **api-ops** (DECISIONS #22). Conventions: [README.md](README.md). Domain facade and
semantics: [alarms.md](alarms.md) (domain), design `docs/apogee/domain/alarm-lifecycle.md`.

Base: `/api/v1/missions/:mission_id/alarm-episodes`. Writes need `x-csrf-token`.
Refetch on `invalidate` with `alarms`, which now also fires on every episode change (domain's
`:alarms_changed`: catalog transitions, ground evaluations and lifecycle commands).

## `GET /alarm-episodes`

Query: `state` = `active` (default) | `cleared` | `all`; `severity` = `critical` | `caution`;
`source` = `catalog_monitoring` | `ground_limit`; `spacecraft_id`; `assignee_id`; `limit` 1–200
(default 50). Bad values: `422 invalid_params` with `details` keyed by parameter.

```json
{"data": {
  "summary": {"active": 4, "critical": {"new": 1, "acknowledged": 2}, "caution": {"new": 1, "acknowledged": 0}},
  "permissions": ["alarm.acknowledge", "alarm.assign"],
  "episodes": [{
    "id": "alarm_episode_…", "source": "ground_limit",
    "status": "new", "cleared_unacknowledged": false,
    "severity": "critical", "peak_severity": "critical", "source_state": "red_low",
    "spacecraft_id": "spacecraft-earendil-312",
    "spacecraft": {"id": "spacecraft-earendil-312", "name": "EARENDIL-312", "scid": 312},
    "point": {"id": "EPS.VBAT", "name": "VBAT", "unit": "V"},
    "thresholds": {"red_low": 24.0, "yellow_low": 25.0, "yellow_high": 33.0, "red_high": 34.0},
    "context": {"limit_set_name": "DEFAULT", "limit_definition_id": "…", "limit_definition_version": 3},
    "opened_at": "…", "cleared_at": null,
    "first_value": 23.4, "last_value": 23.1, "last_observed_at": "…",
    "last_evaluated_at": "…",
    "acknowledged_at": null, "acknowledged_by": null,
    "assignee": null, "assigned_at": null
  }]
}}
```

- Order (server-decided, don't re-sort): active = critical first, New before acknowledged, newest
  opened first. Cleared = newest cleared first.
- U69 A6d paging: the response carries `meta: {next_cursor}` (`null` on the last page); pass it
  back as `?cursor=` with the same filters for the next page, in the same order (active: critical
  first, unacknowledged first, newest opened; cleared: newest cleared). A row that keeps its
  place never repeats or goes missing; one that moves between pages (acknowledged, escalated)
  shows where it now sorts, so it can appear twice or not at all. A cursor from another `state`
  matches nothing; a malformed one is `422 invalid_params` (`details.cursor`).
- `summary` counts all active episodes in the mission, ignoring filters.
  `summary.latest_change` (U69 A6): the mission's newest state change, any episode, ignoring
  filters: `{at, kind: raised | escalated | deescalated | cleared, spacecraft_id | null,
  episode_id}`, or `null` when there's none. People's actions (acknowledge, assign, notes) aren't
  changes. `raised` is the episode opening (the event log's word).
- `permissions`: the **viewer's** lifecycle permissions on this mission. Show Acknowledge only with
  `alarm.acknowledge` and Assign / Hand off with `alarm.assign`. The server enforces them anyway (`403 forbidden`).
- `status`: `new | acknowledged | cleared`. `cleared_unacknowledged`: it cleared before anyone
  acknowledged it. Escalation clears the acknowledgement (ISA-18.2), so a re-raised episode is
  `new` again.
- `source` (U16 source tags): `catalog_monitoring` is live; `ground_limit` is batch. For ground
  limits, always show `last_evaluated_at` ("evaluated 3m ago") and never imply live.
- `thresholds`: ground limits only (`null` for catalog monitoring). `context` is source-specific.
- `point.unit`: from the catalog (same source as the alarms read). `null` when the catalog has none.
- `acknowledged_by` / event `actor`: `{kind, id, name}`. `assignee`: `{id, name}`.
- Values (`first_value`, `last_value`, thresholds) keep their type (number, string or boolean).
- U68 R5 (parity A7a/c): `limit_definition_id`, `limit_definition_version`, `limit_set_name`: the
  ground-limit definition that OPENED the episode (`null` for catalog monitoring). Deep link
  "Inspect producing vN": the limits app takes `?definition=<id>&version=<n>`.
  `trigger: {sample_id, sample_type: telemetry_sample | derived_telemetry_sample | null, point_id,
  at, receipt_time}`: the sample that opened it, `at` its generation time, else receipt;
  `receipt_time` its receipt time (§11c(D) D1: the one-sample read matches on it). Catalog-monitoring
  transitions record no sample: `sample_id`, `sample_type` and `receipt_time` `null`, `at` =
  `opened_at`.

## `GET /alarm-episodes/:episode_id`

One episode in the same shape plus `events`, oldest first:

```json
{"events": [{"id": "…", "kind": "raised", "actor": null, "at": "…", "payload": {},
  "sample": {"id": "…", "at": "…", "receipt_time": "…"}}]}
```

`sample` (U68 R5): for an event a source record caused (`raised`, `escalated`, `deescalated`,
`cleared` by an evaluation), the sample behind it (`id` and `receipt_time` `null` for catalog
monitoring, `at` and `receipt_time` as in `trigger`); `null` for people's actions.

`kind`: `raised | escalated | deescalated | acknowledged | assigned | unassigned | note |
handed_off | cleared | rule_changed` (`rule_changed`, #451: the rules in force on the alarm's
parameter changed while it was open; payload `from` and `to` digests, `rule_ids`, `policy_id`; the
episode itself is unchanged; a decoder that does not know it shows the server's text). `escalated` payload has `from`, `to`, `acknowledgement_cleared`; `cleared`
has `cause`, `unacknowledged`; notes carry the text in the payload.

Errors: `404 episode_not_found`.

## History (Investigate's History tab; owner: api)

Two reads for `ux/screens/Investigate.md` §History. The chart around an episode uses the point
reads (`GET /telemetry/points/:point_id/history`, `GET /limits/points/:point_id/intervals`);
there is no peak value server-side. Derive the peak from the decimated buckets over
`[opened_at, cleared_at || now]`, taking `min` when `direction` is `low` and `max` when it is
`high`; there is no peak when `direction` is null.

### `GET /spacecraft/:spacecraft_id/alarm-episodes?point_id=&before=&limit=`

The spacecraft's episodes in every state, opened in the last 90 days, newest opened first.
`point_id` narrows the items and counts to one point. `limit` is 1–200 (default 50); `before` is
a `next_before` from the previous page.

```json
{"counts": {"d7": 3, "d30": 4, "d90": 5}, "retention_days": null,
 "items": [occurrence], "next_before": "opaque" | null}
```

`counts` counts episodes opened in the last 7, 30 and 90 days. `retention_days` is how long
episodes are kept; it's null while they are never pruned.

### `GET /alarm-episodes/:episode_id/history?scope=alarm|point&before=&limit=`

The episode, and the same alarm's earlier episodes on this spacecraft. With `scope=alarm` (the
default) that means the same source and subject: point plus policy for catalog alarms, point
alone for ground limits. With `scope=point` it means the same point under any condition.

```json
{"episode": {episode, show shape}, "counts": {"d7": 2, "d30": 3, "d90": 4},
 "first_opened_at": "…", "median_duration_s": 210, "retention_days": null,
 "items": [occurrence], "next_before": "opaque" | null}
```

- `counts` include the episode itself.
- `items` are only the episodes opened before it, within 90 days.
- `first_opened_at` is the earliest occurrence, at any age.
- `median_duration_s` is over all cleared occurrences, including the episode itself once it has
  cleared.

**Occurrence**: a subset of the episode shape plus four fields:

```json
{"id": "…", "source": "ground_limit", "status": "cleared", "severity": "critical",
 "peak_severity": "critical", "condition": "red_low", "direction": "low",
 "point": {"id": "…", "name": "…", "unit": "V"}, "opened_at": "…", "cleared_at": "…",
 "duration_s": 60, "ended": "back_in_limits", "cleared_unacknowledged": false,
 "acknowledged_by": {"kind": "user", "id": "…", "name": "…"} | null,
 "first_value": 21.5, "last_value": 24.2}
```

- `condition` is the source state. For ground limits that's `yellow_low`, `yellow_high`,
  `red_low` or `red_high`; for catalog alarms it's `watch`, `warning`, `distress`, `critical` or
  `severe`.
- `direction` is `low`, `high`, or null for catalog states.
- `duration_s` is null while the episode is open.
- `ended` is how the episode ended:
  - `back_in_limits`;
  - `source_stopped`: the source stopped reporting the condition, so the episode was reconciled;
  - `rule_retired`: a generation dropped the rule that raised it, so nothing evaluates it any more
    and the episode was cleared when that generation was applied (#451);
  - null while the episode is open.

  Clears are always automatic. Acknowledgement is the human action, recorded in
  `acknowledged_by`.
- Values are bare scalars; the unit is on `point`.

Errors: `422 invalid_params` for `limit`, `before` or `scope`; `404 episode_not_found`.

## Commands

Each returns `200` with the updated episode **including `events`** (the show shape).

| Route | Body | Notes |
| --- | --- | --- |
| `POST /:episode_id/acknowledge` | `{"note": "…"?}` | Idempotent. |
| `POST /:episode_id/assign` | `{"user_id": "user_…" \| null, "note": "…"?}` | `user_id` must be present; `null` unassigns. Doesn't acknowledge. |
| `POST /:episode_id/hand-off` | `{"to": "user_…" \| null, "note": "…"}` | Note required. |
| `POST /:episode_id/notes` | `{"note": "…"}` | Also allowed on cleared episodes. |

- Notes are text up to 4,000 bytes; blank notes count as missing.
- Assignable people: any active member of the mission's organization. Use
  `GET /organizations/:organization_id/people` (visible to every member: `user_id`, `display_name`).

Errors: `404 episode_not_found`, `409 episode_cleared` (ack/assign/hand-off on a cleared episode),
`422 note_required`, `422 assignee_not_member`, `422 invalid_params` (`details.user_id` / `.to` /
`.note`), `403 forbidden`, `403 invalid_csrf`, `503 alarms_unavailable`.
