# Commanding endpoints (Compose, Command, Approve, Uplink)

Owner: **api-ops**. Conventions: [README.md](README.md). Asks are tracked by their IDs in
`docs/apogee/plans/ops.md`.

| Ask | Endpoint | Status |
| --- | --- | --- |
| M17 | `GET /missions/:mission_id/commands`, `GET /missions/:mission_id/commands/:command_id` | **implemented** |
| M16 M18 M20 | group requests, preflight, cancel/abort | planned |

## The active catalog

Both reads use the mission's **active generation** under the same read lock request authoring
uses, so the catalog matches what a request is validated against. Refetch on `invalidate` with
`catalog` or `configuration` (a new activation changes the revision).

When nothing is active (no promoted mission model, or no command plan), both answer `200` with
`state: "not_active"` and an empty result. Show "No active command catalog" with a link to Setup.

Every response has the basis: `state` (`active | not_active`), `revision_id`, `plan_id` and
`activation_id` (all `null` when not active).

## `GET /api/console/v1/missions/:mission_id/commands`

Query: `q` (case-insensitive substring of id, name, display name, description or subsystem),
`limit` 1–500 (default 100), `after` (the `meta.next_cursor` of the previous page). Sorted by
command id.

```json
{"data": {
   "state": "active", "revision_id": "…", "plan_id": "…", "activation_id": "…",
   "commands": [{
     "id": "cmd_…", "name": "SET_COUNTER", "display_name": null, "description": null,
     "subsystem": "EPS", "group": null,
     "significance": "hazardous", "critical": false, "hazardous": true,
     "second_go_required": true, "argument_count": 2
   }]},
 "meta": {"next_cursor": "cmd_…"}}
```

- `second_go_required`: the DECISIONS #7 policy for a **single-target** request of this command
  (critical, hazardous, critical/hazardous significance, or a confirmation/approval policy hint),
  computed by the same predicate request validation uses. Multi-target (fleet-wide) requests can
  need a second GO even when this is `false`; that comes with M16/M18.
- `significance`: `routine | warning | critical | hazardous | null`.

Errors: `422 invalid_params` (`details.limit`), `503 catalog_unavailable`, `404 mission_not_found`.

## `GET /api/console/v1/missions/:mission_id/commands/:command_id`

The list entry plus:

```json
{"data": {"state": "active", "revision_id": "…", "plan_id": "…", "activation_id": "…",
  "command": {
    "id": "cmd_…", "name": "SET_LEVEL", "…": "list entry fields",
    "opcode_json": "20", "apid": 42, "service_type": null, "service_subtype": null,
    "release_policy_hint": null,
    "arguments": [{
      "id": "…", "name": "level", "description": null, "type": "integer", "required": true,
      "default_value_json": null, "fixed_value_json": null, "hazardous_values_json": [],
      "choices": [{"label": "ON", "value_json": "1"}],
      "valid_range": {"minimum_json": "0", "maximum_json": "100"},
      "unit": "%"
    }],
    "verifiers": [{"id": "…", "name": "…", "description": null, "phase": "completion",
                   "timeout_ms": 5000, "delay_ms": null, "severity": null}],
    "constraints": [{"id": "…", "name": "…", "description": null, "type": "precondition",
                     "blocking": true, "timeout_ms": 2000}]
  }}}
```

- **Values are JSON strings** (`*_json`): `default_value_json`, `fixed_value_json`,
  `hazardous_values_json[]`, `choices[].value_json`, `valid_range.minimum_json/maximum_json` and
  `opcode_json`. Arguments can be 64-bit integers that a JS number can't hold exactly; parse them
  with a big-int-aware decoder (or keep the string). `null` means "not set".
- `type`: `integer | float | string | binary | boolean | enumerated`.
- `fixed_value_json` set: the operator can't change the argument. Show it read-only.
- `choices`: only for `enumerated` arguments; `[]` otherwise (or if the choices can't be read).
- `valid_range`: from the catalog argument type (XTCE `ValidRange`, YAML `min_value`/`max_value`).
  `null` when there's none; either bound can be `null` (half-open).
- `unit`: the argument type's display unit, `null` when the catalog has none. XTCE import doesn't
  carry argument units yet; YAML `units` does.
- `verifiers.phase`: `acceptance | start | completion | custom`; `severity`:
  `info | warning | error | critical | null`. `constraints.type`:
  `precondition | interlock | timing_window | custom`.
- Not yet: per-target compatibility (activations with per-spacecraft configurations can give a
  target a different plan; this read shows the mission-level plan), and an encoded-packet preview (M24).

Errors: `404 command_not_found`, `503 catalog_unavailable`, `404 mission_not_found`.
