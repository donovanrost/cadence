# Alarm episodes: console endpoints

Owner: **api-ops** (DECISIONS #22). Conventions: [README.md](README.md). Domain facade and
semantics: [alarms.md](alarms.md) (domain), design `docs/apogee/domain/alarm-lifecycle.md`.

Base: `/api/console/v1/missions/:mission_id/alarm-episodes`. Writes need `x-csrf-token`.
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
- `summary` counts all active episodes in the mission, ignoring filters.
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

## `GET /alarm-episodes/:episode_id`

One episode in the same shape plus `events`, oldest first:

```json
{"events": [{"id": "…", "kind": "raised", "actor": null, "at": "…", "payload": {}}]}
```

`kind`: `raised | escalated | deescalated | acknowledged | assigned | unassigned | note |
handed_off | cleared`. `escalated` payload has `from`, `to`, `acknowledgement_cleared`; `cleared`
has `cause`, `unacknowledged`; notes carry the text in the payload.

Errors: `404 episode_not_found`.

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
