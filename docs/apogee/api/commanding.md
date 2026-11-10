# Commanding endpoints (Compose, Command, Approve, Uplink)

Owner: **api-ops**. Conventions: [README.md](README.md). Asks are tracked by their IDs in
`docs/apogee/plans/ops.md`.

| Ask | Endpoint | Status |
| --- | --- | --- |
| M17 | `GET /missions/:mission_id/commands`, `GET /missions/:mission_id/commands/:command_id` | **implemented** |
| M16 M18 M20 O4 | command groups: preflight, submit, list/show, decision, abort, cancel, policies | **implemented** |

## The active catalog

Both reads use the mission's **active generation** under the same read lock request authoring
uses, so the catalog matches what a request is validated against. Refetch on `invalidate` with
`catalog` or `configuration` (a new activation changes the revision).

When nothing is active (no promoted mission model, or no command plan), both answer `200` with
`state: "not_active"` and an empty result. Show "No active command catalog" with a link to Setup.

Every response has the basis: `state` (`active | not_active`), `revision_id`, `catalog_revision`,
`plan_id` and `activation_id` (all `null` when not active). `catalog_revision` is
`{id, number, label}`, the human catalog revision ("CATALOG rev 14") that produced the active
model revision, or `null` when no catalog revision records it (for example a model composed by
hand). The group show response has the same `catalog_revision` for its members' revision.

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

## Command groups (M16 · M18 · M20 · O4)

Design: [`domain/group-requests.md`](../domain/group-requests.md) (DECISIONS #29–#31). A group is
N targets × K commands, decided and aborted as one unit. Every console-authored request is a
group (1 × 1 included). Writes need `x-csrf-token`. The requester, approver and aborting
operator are always the session user (DECISIONS #30). Commanding needs organization admin today
(DECISIONS #38). Refetch on `invalidate` with `commanding`.

### Draft (the body of preflight and create)

```json
{"title": "Load shed after VBAT red on 312", "log_entry": "…",
 "targets": [{"spacecraft_id": "spacecraft-…", "source_endpoint_id": null}],
 "target_query": {"chips": [{"key": "plane", "value": 7}]},
 "commands": [{"command_id": "cmd_…", "argument_values_json": "{\"mode\":3}"}],
 "not_before": null, "expires_at": null, "priority": 3,
 "requested_approver_user_id": null, "sent_back_from": null}
```

- `targets[]`: leave `source_endpoint_id` null and the server resolves the uplink endpoint from the
  target's routes (DECISIONS #41): its **primary** active, enabled route with an outbound or
  bidirectional leg (counted per profile rule, so one rule across several stations is one route).
  Identity NO-GO reasons: `no_uplink_route` and `multiple_primary_uplink_routes`, with
  `per_target[].routes[] {id, name, direction, role, origin, transport_id, ground_station_id,
  profile_id, profile_rule_id}` naming the competing (or existing) routes, so you can link to the
  profile's routing. Setting `source_endpoint_id` is an explicit override, stored as evidence on the
  group target (`resolution.via: "override"`). `target_query` is stored as evidence too.
- `argument_values_json`: a JSON object string, the same rules as single requests (64-bit safe).
- Bounds: N ≤ 1,000, K ≤ 16, N×K ≤ 5,000.

### `POST /command-groups/preflight` (M18)

No side effects. Returns:

```json
{"data": {"valid": true, "digest": "…", "members": 6, "second_go_required": true,
  "targets": [{"index": 0, "spacecraft_id": "…", "source_endpoint_id": "…", "name": "SC-1", "scid": 7, "failure": null}],
  "checks": [
    {"key": "identity", "result": "go", "per_target": [], "evidence": {}},
    {"key": "catalog", "result": "no_go", "per_target": [{"spacecraft_id": "…", "result": "no_go",
       "reason": [{"position": 0, "command_id": "…", "reason": "invalid_command_argument"}]}], "evidence": {"count": 1}},
    {"key": "size", "result": "go", "per_target": [], "evidence": {"max_targets": 1000, "max_commands": 16, "max_members": 5000, "targets": 2, "commands": 3}},
    {"key": "conflicts", "result": "hold", "per_target": [], "evidence": {"count": 2, "command_request_ids": ["…"]}},
    {"key": "contact", "result": "hold", "per_target": [{"spacecraft_id": "…", "result": "go",
       "next_contact": {"station_code": "SVL", "aos": "…", "los": "…"}}], "evidence": {"until": "…"}},
    {"key": "two_person", "result": "hold", "per_target": [], "evidence": {"reasons": [
       {"key": "hazardous_command", "command_id": "…", "name": "SET_POWER_MODE"},
       {"key": "fleet_reach", "targets": 12, "threshold": 10}]}}
  ]}}
```

- `result`: `go | hold | no_go`. Any `no_go` blocks submit. **HOLDs hold** (DECISIONS #60): submit
  is refused while any HOLD in the current preflight is unacknowledged or not cleared (below).
- Every check also has `ackable` and `hold_basis`, both `null` unless `result` is `hold`.
  - `ackable: true`: the submitter may acknowledge the HOLD with a note.
  - `ackable: false`: the HOLD is hard and must clear.
  - `hold_basis`: a hash of that HOLD's facts. An acknowledgement names it, so it can't carry over
    to a changed HOLD.

  | HOLD | ackable | Why |
  | --- | --- | --- |
  | `conflicts` | yes | Other work on the same lanes is known and accepted; the group queues behind it. |
  | `contact` | **no** | No commandable contact in the release window: nothing can be sent. Book one, or change the window. |
  | `changed_since_submit` (review only) | no | The validated group no longer matches what was submitted. GO is refused; send it back. |

- `contact`: the target's first `confirmed`/`active` booking whose uplink leg the provider
  confirmed (it carries the command window). It must overlap the release window, which runs from
  `not_before` (or now) to `expires_at` (or 6 h after that start). A HOLD has per-target
  `reason: "no_commandable_contact"` and `next_contact: null`. C4 draws from it. Evidence
  `{from, until}` is the window.
- `two_person` is **not a HOLD** (DECISIONS #61): it never blocks submit. Its `result` is
  `second_go` ("needs a second GO") while a second GO is required and not yet given, else `go`.
  `evidence.reasons` and top-level `second_go_required` say why the group goes to approval.
- `two_person` reason keys: `hazardous_command | critical_command | policy_hint | fleet_reach`.
- Plan impact and umbra margin are absent (no data, DECISIONS #4).
- Oversize drafts return only `size` (`no_go`, with the bounds) and `digest: null`.

### `POST /command-groups` (M16)

Body: the draft plus `preflight_digest` (from the preflight the operator saw) and
`operation_id` (client idempotency key). `201` with the group (show shape).

- `acknowledged_holds: [{key, hold_basis, note}]` (DECISIONS #60). `note` is required, at most
  1000 characters; the actor is the session user.
  - Submit re-runs preflight. Each HOLD needs an acknowledgement with the same `key` and current
    `hold_basis`, and an `ackable` HOLD; hard HOLDs must clear.
  - Otherwise: `422 holds_unacknowledged`, `details.holds: [{key, ackable, hold_basis}]`, listing
    every unsatisfied HOLD, hard ones included. Re-run preflight and show them.
  - Malformed items or a blank note: `422 invalid_params` (`details.acknowledged_holds`).
  - Each accepted acknowledgement is a group event, `hold_acknowledged` (below).
  - A replay of a known `operation_id` skips the HOLD check and answers `409 duplicate_operation`.
- With no second GO required, members are **queued** at once, in stack order per target lane.
  Otherwise the group is `approval_pending`, and `log_entry` is required.
- `409 preflight_stale`: something changed since that preflight. Re-run it.
- `409 duplicate_operation` (`details.command_group_id`): this `operation_id` was already
  submitted. To resolve an unclear submit (ux U20), use `GET /command-groups?operation_id=`.
- `422 preflight_no_go` (`details.identity[]`, `details.catalog[]`), `422 title_required`,
  `422 log_entry_required`, `422 command_group_too_large`, `409 command_catalog_not_active`.

### `GET /command-groups` · `GET /command-groups/:id` · `GET /command-groups/:id/preflight`

- List query: `state` (comma list of `approval_pending | queued | rejected | sent_back | aborted`),
  `awaiting_me=true` (Approve queue: pending, not mine, and I'm the named approver or none was
  named), `mine=true`, `operation_id=` (returns 0 or 1 groups).
  Rows: `{id, state, title, requested_by, requested_at, requested_approver_user_id, member_count,
  target_count, command_count, second_go_required, awaiting_me, operation_id, progress, finished}`.
- `state` is the approval lifecycle only. A group stays `queued` after delivery. Delivery is in
  `progress` (`{stage: target count}`, same as show) and `finished` (`true` when every target is at
  a final stage: `verified | no_verifier | verify_failed | release_failed | canceled | rejected |
  excluded`; `indeterminate` isn't final, since an operator must resolve the uncertain release). `finished` doesn't mean success; read `progress` for the outcome.
  Both are `null` on rows whose state isn't `queued` (the state already says how they ended).
  Released tab = `queued` and not `finished` (qa #28).
- Show adds `review_token` (send it back on decisions), `log_entry`, `sent_back_from`,
  `target_query`, `commands[] {position, command_id, name, significance, critical, hazardous,
  argument_values_json}`, `release`, `policy`, `decision`, `decided_by/at`, `aborted_by/at`,
  `abort_reason`, `abort_result`, `progress` (`{stage: target count}`), `finished` (always a
  boolean on show), `events[] {id, kind, actor, at, payload}` (see Timeline events below),
  and `targets[]`:
  `{spacecraft_id, name, scid, stage, members: [{position, request_id, command_id, command_name, stage,
  end_reason, caused_by, verify_by, occurred_at}], last_event_at, blocked: null}`. `caused_by` is the
  earlier member whose failure stopped this one (`end_reason: earlier_command_failed`).
  `blocked`: `null`, or `{reason: "lane_release_uncertain", command_request_id}` when the target is
  waiting for its contact but its lane is held by a release whose outcome is unknown
  (`release_uncertain`). Nothing behind it releases until an operator resolves that attempt. Show
  it in "Needs you".
- Member `stage`: `awaiting_go | queued_for_contact | radiating | executed | verified | no_verifier
  | verify_failed | release_failed | indeterminate | canceled | rejected | excluded`. A target's stage
  is its first unfinished member's. `end_reason`: `aborted | release_basis_changed |
  earlier_command_failed | expired | excluded_at_review | canceled | rejected` (or null).
- `…/preflight` re-runs preflight on the submitted inputs for Approve (A2) and adds
  `changed_since_submit` (`hold` when the result no longer matches what was submitted). Its
  `conflicts` check leaves out the group's own members, so only other work on the lanes counts.
- Compose "send back" clone: everything a new draft needs is in the show response.
- **Timeline events** (`events[]`, oldest first), the group's audit record. `actor` is one of
  two shapes, told apart by `actor_kind`. Decode it as a variant on that key; a system actor has no
  `user_id` key, since no user is invented for it:
  - `{actor_kind: "user", user_id}`: a person did it;
  - `{actor_kind: "system"}`: Cadence recorded an outcome (`member_failed`, `completed`).
  - `submitted`, `approved`, `approved_with_exclusions`, `sent_back`, `rejected`, `note`,
    `member_canceled`, `aborted`: written by the operator action, with `actor` the user.
  - `hold_acknowledged` (DECISIONS #60): written at submit, one per acknowledged HOLD, with
    `actor` the submitter. Payload: `{key, note, hold_basis, preflight_digest, evidence}` (the
    HOLD's facts when acknowledged).
  - `member_failed` (DECISIONS #51): once per member whose release failed or whose
    verification failed or timed out. `actor: {actor_kind: "system"}`. Payload:
    `{command_request_id, command_id, spacecraft_id, target_index, position, reason:
    release_failed | verify_failed | verify_timed_out, later_members_stopped}`. The last field
    counts the later members of that target that won't release (stop on failure, #31).
  - `completed` (#51): once, when every member of a `queued` or `aborted` group is final.
    `actor: {actor_kind: "system"}`. Payload: `{members: {verified, no_verifier, verify_failed,
    verify_timed_out, release_failed, canceled, rejected: count}}` (only non-zero keys).
    Written right after the release, verification, halt or abort that finished the last member.
    A one-minute reconcile sweep backs it up. Each write invalidates `commanding`.

### `POST /command-groups/:id/decision`

`{"kind": "go" | "go_excluding" | "send_back" | "no_go", "excluded": [spacecraft_id], "note": "…",
"expected_review": "<review_token>"}`. Returns the group. A note is required except for `go`.
`go_excluding` rejects the named targets' members ("excluded at review").

Errors: `403 command_group_self_approval_not_allowed`, `403 not_the_requested_approver`,
`409 command_group_not_pending`, `409 command_group_review_stale`, `409 command_group_basis_changed`
(the active catalog changed since submit, so resubmit), `422 note_required`, `422 exclusions_required`,
`422 unknown_excluded_target`, `422 invalid_params`.

**HOLDs at GO** (DECISIONS #61): `go` and `go_excluding` re-run the review preflight
(`GET …/preflight`) on a pending group.
- Hard HOLDs refuse: `changed_since_submit`, and `contact` (no commandable contact).
- An ackable HOLD whose `hold_basis` is unchanged since the submitter acknowledged it carries.
- A new or changed one needs the approver's own acknowledgement: the body takes
  `acknowledged_holds: [{key, hold_basis, note}]`, the same as submit. It's recorded as a
  `hold_acknowledged` event with the approver as actor and `payload.at_decision: true`.
- Otherwise `422 holds_unacknowledged`, with `details.holds` as for submit.
- `send_back` and `no_go` don't check HOLDs.

### `POST /command-groups/:id/abort` · `POST /command-requests/:id/cancel` (M20)

`{"reason": "…"}` (required). Abort cancels every member that hasn't started to radiate and
returns the group with `abort_result: {canceled: <count>, already_started: [request ids]}`
(`canceled` is how many members were canceled; `already_started` lists the ones that kept running). Members already
releasing or released keep running ("ABORT AVAILABLE UNTIL EACH UPLINK STARTS"). Any mission
operator may abort or cancel (`Policy :operate_mission`, not two-person, DECISIONS #42), so this
works for plain members even though requesting and approving need organization admin today. The
session's `command.abort` capability is that same check: held when the user can operate at least one
of the organization's missions. Cancel works on any request (grouped or not) that hasn't started.

Errors: `422 reason_required`, `409 command_group_not_abortable`, `409 command_request_already_started`,
`404 command_request_not_found`, `404 command_group_not_found`.

Also new, at release time:
- A queued request whose model revision is no longer active **fails closed** (`canceled`,
  `end_reason: release_basis_changed`) instead of blocking its lane.
- **Stop on failure per target** (DECISIONS #31): a member doesn't release after an earlier member
  of the same target failed to release, failed or timed out verification, or was itself stopped.
  It's canceled with `end_reason: earlier_command_failed` and `caused_by`. Other targets continue.
  A verification failure that arrives after the next member already radiated can't stop it.
  That would need "verify before next" gates (waves, #8).

### `POST /command-groups/:id/notes` (M19)

`{"note": "…"}` (≤ 4,000 bytes, required). Appends a `note` event by the session operator. Allowed in
any state, including finished groups. Returns the group. Errors: `422 note_required`,
`404 command_group_not_found`.

### `GET /command-endpoints?spacecraft_ids=a,b` (Compose's endpoint picker)

Per spacecraft (≤ 1,000): `{spacecraft_id, resolved_source_endpoint_id, failure, routes[],
endpoints: [{id, name, scid, managed}]}`. `resolved_source_endpoint_id` is what preflight will use
when you send no override; `failure` (`no_uplink_route | multiple_primary_uplink_routes`) says why
there's none. `endpoints` are the spacecraft's source endpoints to offer as an explicit override;
`managed` marks the one routes materialize on.

### `GET /command-policies` (O4)

`{"data": {"policies": [{"key": "command_classification", "parameters": {"classifications": ["hazardous", "critical"]}},
{"key": "policy_hint", …}, {"key": "fleet_reach", "parameters": {"threshold": 10}}, {"key": "no_self_approval", "parameters": {}}]}}`.
The UI writes the sentences (title + sentence per key).

### Not yet

Nothing outstanding from the design. Expired unstarted work is canceled by a sweep on every
dispatcher reconcile (about a minute), with `end_reason: expired`. Live progress: the `command_group:<mission_id>:<command_group_id>` channel
(realtime.md).
