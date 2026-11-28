# Commanding endpoints (Compose, Command, Approve, Uplink)

Owner: **api-ops**. Conventions: [README.md](README.md). Asks are tracked by their IDs in
`docs/apogee/plans/ops.md`.

| Ask | Endpoint | Status |
| --- | --- | --- |
| M17 | `GET /missions/:mission_id/commands`, `GET /missions/:mission_id/commands/:command_id` | **implemented** |
| M16 M18 M20 O4 | command groups: preflight, submit, list/show, decision, abort, cancel, policies | **implemented** |
| M24 | `GET /missions/:mission_id/command-requests/:id/encoding` (owner: api) | **implemented** |
| A1 | `GET /missions/:mission_id/command-requests/:id/brief` (owner: api) | **implemented** |

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

## `GET /api/v1/missions/:mission_id/commands`

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

## `GET /api/v1/missions/:mission_id/commands/:command_id`

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

- `arguments[].current_point: {id, name, unit} | null` (Compose B2's "Now" column): the point
  whose value is this argument's current setting. It comes from a verifier that checks the point
  equals the value sent (e.g. SET_MODE's `HK.sc_mode == mode`); the first such verifier wins.
  It's null when no verifier ties the argument to a point. Read values with `POST
  …/telemetry/latest` (ops.md).

## Command groups (M16 · M18 · M20 · O4)

Design: [`domain/group-requests.md`](../domain/group-requests.md) (DECISIONS #29–#31). A group is
N targets × K commands, decided and aborted as one unit. Every console-authored request is a
group (1 × 1 included). Writes need `x-csrf-token`. The requester, approver and aborting
operator are always the session user (DECISIONS #30). Any mission operator (`Policy
:operate_mission`, an active member of the organization) may request, GO, NO-GO, send back, abort
and add notes (DECISIONS #42, #62). Self-approval and the two-person rule are unchanged: the
requester can't give a group's second GO. The session's `command.request`, `command.approve` and
`command.abort` capabilities are that same check, held when the user can operate at least one of
the organization's missions (#38), so an organization with no missions reports none. Refetch on
`invalidate` with `commanding`.

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
- `commands[].per_target` (optional, Compose "Per target"): `[{spacecraft_id,
  argument_values_json}]`, which overrides the command's `argument_values_json` for those targets.
  Each member is validated with its own values, and the preflight digest covers them, so changing
  one needs a new preflight. A spacecraft named twice is `422`. The show read echoes it on each
  command (`per_target: []` when none), and so does the resend clone.
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
    {"key": "size", "result": "go", "per_target": [], "evidence": {"max_targets": 5000, "max_commands": 16, "max_members": 20000, "targets": 2, "commands": 3}},
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
  | `model_approval_withdrawn` | yes | A target's active generation runs a revision whose approval was withdrawn (E2, #546). Commanding it is still possible, but a person says so. |
  | `changed_since_submit` (review only) | no | The validated group no longer matches what was submitted. GO is refused; send it back. |

- `contact`: the target's first `confirmed`/`active` booking whose uplink leg the provider
  confirmed (it carries the command window). It must overlap the release window, which runs from
  `not_before` (or now) to `expires_at` (or 6 h after that start). A HOLD has per-target
  `reason: "no_commandable_contact"` and `next_contact: null`. C4 draws from it. Evidence
  `{from, until}` is the window.
- `model_approval_withdrawn` (E2c, #546; label "Composition"): a target whose **active** generation
  (what a command is encoded and verified against, not the profile's pin) runs a revision whose
  approval was withdrawn. An ackable HOLD, never a NO-GO: the craft keeps its last generation and
  telemetry keeps flowing. One `per_target` row per target; a held one has `reason:
  "model_approval_withdrawn"` and `revision_id`, `kind` (`"withdrawn"`), `decided_by` (`{id, name}`,
  a member by their current name, never an email), `decided_at`, `reason_text` (the reason the deciding
  person gave) and `composition` (the shared composition object). Evidence `{count, composed}`:
  how many are held, and whether a held target's composition has more than one catalog.
  `hold_basis` names exactly those craft on exactly those decisions (a hash of each held craft's
  `"<revision_id>:withdrawn:<decided_at>"`), so an acknowledgement doesn't cover another craft on
  the same revision, or a later withdrawal. Acknowledged like any HOLD (DECISIONS #60/#61): the
  group event `hold_acknowledged` records its evidence. Review re-runs it, so an approver
  acknowledges a withdrawal that is new since submit.
  **What a GO records.** A group is armed by a GO, or by its submit when no second GO is needed.
  That arming checks (under its lock) that the acknowledgement it carries covers exactly the
  withdrawals now (a withdrawal since the preflight is `409 preflight_stale` at submit,
  `409 command_group_review_stale` at GO) and records, in each armed member's own approval row
  (append-only, same transaction), the basis of its craft's withdrawal it knew of, or none. An
  unattended release (a lane draining itself) refuses a craft whose current withdrawal isn't the
  recorded one, and a member whose row lacks the record fails closed (end_reason
  `model_approval_withdrawn_after_go`, below).
- `two_person` is **not a HOLD** (DECISIONS #61): it never blocks submit. Its `result` is
  `second_go` ("needs a second GO") while a second GO is required and not yet given, else `go`.
  `evidence.reasons` and top-level `second_go_required` say why the group goes to approval.
- `two_person` reason keys: `hazardous_command | critical_command | policy_hint | fleet_reach`.
- Plan impact and umbra margin are absent (no data, DECISIONS #4).
- Oversize drafts return only `size` (`no_go`, with the bounds) and `digest: null`.
  **The size bounds are a guard (#795), not a product limit:** `max_targets` 5,000, `max_commands`
  16, `max_members` (targets x commands) 20,000. Preflight and submit validate every member in one
  transaction; measured at about 0.2 ms a member for preflight and 0.3 ms for submit (5,000 x 4 =
  20,000 members: 3.3 s and 6 s; 500 x 16: 1.7 s and 2.7 s), so the defaults leave more than 2x
  headroom under the 15 s transaction timeout. A deployment (never an organization, mission or
  request) changes them with `config :cadence, :command_group_bounds`; past about 50,000 members
  the Repo's transaction timeout needs raising too. Over a bound is always loud: `size` `no_go` in
  preflight, `422 command_group_too_large` (the bounds and the draft's `targets` and `commands`
  in `details`) on create.

- **U51 (per-target verifiers).** Each target's commands are validated against its own pinned
  mission model (a fleet activation can pin spacecraft to different catalog revisions), so:
  - `targets[].catalog_revision`: `{number, label} | null`, the catalog revision its commands
    resolve to (show `rev <number>`, the label only without a number). `null` when no command
    validated for that target, which is then a Catalog NO-GO in `checks`.
  - `commands: [{position, command_id, verifier_groups: [{verifiers: [{id, name, description,
    phase, timeout_ms, delay_ms, severity}], catalog_revisions: [{number, label}], spacecraft_ids}]}]`:
    one group per distinct verifier set, compared without ids (two revisions give the same verifier
    different ids), largest first, then by first spacecraft id. `verifiers: []` is "No verifier:
    can't turn green". Targets with a NO-GO for that command are in no group.
  - U68 R1 `commands[].resolved_arguments: [{name, entered_value_json | null, resolved_value_json,
    sent_value_json | null, unit | null, source: entered | default | fixed | catalog,
    spacecraft_ids: null | [id]}]`: only where the server's value differs from what was entered.
    The server changes two things: a blank argument takes the catalog `default` or `fixed` value
    (`entered_value_json: null`), and a float encoded as 32-bit IEEE 754 radiates the nearest
    single-precision value (`sent_value_json`, else `null`). No unit conversion, no rounding of the
    stored value. `spacecraft_ids: null` = every validated target of that command; a list = only
    those (per-target values make rows differ). `catalog` = a filled value whose pinned definition
    couldn't be read to say default or fixed. `[]` when nothing differs.
  - The group's policy classifies each command by the strictest of its targets' revisions
    (critical/hazardous if any is, the highest significance, the strictest release hint), not by
    whichever target came first.

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
  U69 A5 (parity ops (C)): `q` (≤100 chars, case-insensitive substring of the title, log entry,
  group id, operation id, or a stacked command's id or name), `withdrawn_revision=<revision_id>` (E2, #546: groups with a target that runs that mission-model
  revision, resolved on the server for the authorized mission, so another mission's revision, or
  one no craft runs, is an empty page; with `state=queued&stage=queued_for_contact` it is the
  withdraw sheet's "the rest"; `422 invalid_params` with `target`; no id list ever goes in the URL),
  `target=<spacecraft_id>` (groups with
  it among their targets), `stage=` (comma list of `release_failed | verify_failed | indeterminate
  | in_flight | queued_for_contact`: groups where ANY target is at one; `in_flight` = `radiating`
  or `executed`; queued groups only; decided by the same progress the row shows, so the filter
  and the badge agree), `limit` (1..200, default 100), `cursor` (opaque, from `meta.next_cursor`;
  `null` = no more). Newest first (`requested_at`, then id). `awaiting_me` and `mine` filter in the
  database, so a page is exact. The response gains `meta: {next_cursor}`. With `stage=` a page
  can hold fewer than `limit` while `next_cursor` is set; keep following it. Bad `state`, `stage`,
  `limit`, `q` or `cursor` → `422 invalid_params` naming the field (an unknown `state` used to be
  ignored).
  Rows: `{id, state, title, requested_by, requested_at, requested_approver_user_id, member_count,
  target_count, command_count, second_go_required, awaiting_me, operation_id, priority, progress,
  finished}`. `priority` (U68): the group's release priority, 0..9 (default 3); lower releases
  sooner, only within one target's queue lane.
- `state` is the approval lifecycle only. A group stays `queued` after delivery. Delivery is in
  `progress` (`{stage: target count}`, same as show) and `finished` (`true` when every target is at
  a final stage: `verified | no_verifier | verify_failed | release_failed | canceled | rejected |
  excluded`; `indeterminate` isn't final, since an operator must resolve the uncertain release). `finished` doesn't mean success; read `progress` for the outcome.
  Both are `null` on rows whose state isn't `queued` (the state already says how they ended).
  Released tab = `queued` and not `finished` (qa #28).
- Show adds `review_token` (send it back on decisions), `log_entry`, `sent_back_from`,
  `target_query`, `commands[] {position, command_id, name, significance, critical, hazardous,
  argument_values_json, verifier_groups, resolved_arguments}` (`verifier_groups` as preflight's
  U51 and `resolved_arguments` as preflight's U68 R1, from each member's stored values and pinned
  revision; rejected or excluded members in no group or row), `release`,
  `policy`, `decision`, `decided_by/at`, `aborted_by/at`,
  `abort_reason`, `abort_result`, `progress` (`{stage: target count}`), `finished` (always a
  boolean on show), `events[] {id, kind, actor, at, payload}` (see Timeline events below),
  and `targets[]`:
  `{spacecraft_id, name, scid, stage, members: [{position, request_id, command_id, command_name, stage,
  end_reason, caused_by, verify_by, verified_at, timed_out_at, failed_at, occurred_at,
  release_refusal}], last_event_at, blocked: null}`. U69 A4a: `verified_at` = once every verifier
  instance is satisfied, the latest match; `timed_out_at` = the earliest deadline among instances
  that timed out; `failed_at` = the earliest match among instances whose failure criteria
  matched; each `null` when it doesn't apply (`verify_by` = the latest deadline, as before).
  U75: list rows and the group read carry `expiry: {expires_at, expired, sent, total} | null` (null
  unless a member ended `expired`): `expired` = members with `end_reason: expired`, `sent` =
  members that went out (radiating, executed, indeterminate, verified, no_verifier, verify_failed),
  `total` = `member_count`. Expired members keep stage `canceled` + `end_reason: expired`.
  `caused_by` is the earlier member whose failure stopped this one (`end_reason:
  earlier_command_failed`). `release_refusal` (U46): `null`, or `{code, details, at,
  realized_contact_id, booked}` while the member still waits and the latest named release that
  reached it stopped there (same codes as the release's `stopped`); a later release clears it. A
  member the stop closed says why in `end_reason` instead.
  `blocked`: `null`, or `{reason: "lane_release_uncertain", command_request_id}` when the target is
  waiting for its contact but its lane is held by a release whose outcome is unknown
  (`release_uncertain`). Nothing behind it releases until an operator resolves that attempt. Show
  it in "Needs you".
  `members_changed`, `submitted_member_count`, `current_member_count` (#120, ux U92 "Up front";
  show and the group channel push, not list rows): always present. While `state` is
  `approval_pending`: `members_changed` is `true` when the group's member rows no longer match the
  count it was submitted with (the GO refusal's own test, `Commanding.Groups.MemberCheck`, so the
  two never disagree), with both counts as integers (the `409 command_group_members_changed`
  details' names). In any other state all three are `null`. When it's `true` a GO answers that
  409, so disable GO up front; NO-GO, send back and abort stay allowed.
- **`withdrawn_after_go` (E2, #546; the release panel's caution).** Each target row, on the show's
  first page and on every `GET …/targets` page, carries `withdrawn_after_go`: `null`, or
  `{revision_id, decision: {kind, by: {id, name}, at, reason}}` when the target's craft runs a
  withdrawn revision and a member still waiting for its contact has an approval row that recorded
  a different withdrawal (or none, or predates the record), which is the comparison an unattended
  release refuses on. The show also carries the group's own `withdrawn_after_go`: `null`, or
  `{count, latest}`, `count` being the targets flagged across the **whole group** (not the page)
  and `latest` the newest decision by `at`, in the same shape. Both come from one batched
  withdrawal read over the group's craft and one read of the waiting members' approval rows, so
  the query count doesn't depend on the number of targets. A person naming the contact is not
  refused, so this is a caution for them, not a block.
- **Paged targets and events (#795).** Show also carries `targets_page: {total, revision,
  next_cursor}` and `events_page: {total, next_cursor}`: how many there are, and `revision` changes
  whenever any target's stage does (a live client refetches its pages then, or when
  `events_page.total` moves). Each target also carries its `index`. Today show still lists every
  target and event (`next_cursor: null`); the console moves to the paged reads below, after which
  show carries only the first 100 targets and the latest 50 events, and the group push omits both.
  - `GET /command-groups/:id/targets?limit=&cursor=&stage=&q=`: a page of `targets[]` in target
    order, `{data: {targets}, meta: {total, next_cursor}}`. `limit` 1..500 (default 100). `stage`
    is a comma list of member stages (the target's own); `q` (≤ 100 chars) a case-insensitive
    substring of the name or spacecraft id. `meta.total` counts the filtered targets.
  - `GET /command-groups/:id/events?limit=&cursor=`: a page of `events[]`, chronological, the latest
    first; the cursor reads back to older ones. `limit` 1..200 (default 50).
  - A cursor is opaque and belongs to its mission, group and list: another group's, another
    mission's, the other list's or a malformed one is `422 invalid_params`
    (`details.cursor`); a bad `limit`, `stage` or `q` names its own field. Same authorization as
    show; an unknown group is `404 command_group_not_found`.
- Member `stage`: `awaiting_go | queued_for_contact | radiating | executed | verified | no_verifier
  | verify_failed | release_failed | indeterminate | canceled | rejected | excluded`. A target's stage
  is its first unfinished member's. `end_reason`: `aborted | release_basis_changed |
  earlier_command_failed | expired | catalog_changed | spacecraft_archived |
  model_approval_withdrawn_after_go | excluded_at_review | canceled | rejected` (or null). `catalog_changed` (DECISIONS #65): a catalog change set canceled
  it before release. `spacecraft_archived` (L22): its spacecraft was archived before it released,
  so it never went out. `model_approval_withdrawn_after_go` (E2, #546): the lane was about to send
  it unattended, and its craft's model approval had been withdrawn after the GO (a withdrawal the
  GO hadn't acknowledged): the member failed closed, and the group needs a new GO (resubmit; the
  new preflight carries the `model_approval_withdrawn` HOLD). A person naming the contact
  (`POST …/release`) is the decision, so that path is not refused.
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
    verify_timed_out, release_failed, canceled, catalog_changed, rejected: count}}` (only non-zero keys).
    Written right after the release, verification, halt or abort that finished the last member.
    A one-minute reconcile sweep backs it up. Each write invalidates `commanding`.
  - `expired` (ux U75, DECISIONS #97): once per group, when its deadline ended members that hadn't
    gone out. `at` = the group's `expires_at`, actor `{actor_kind: "system"}`, payload `{sent,
    not_sent}` (members out before the deadline / members it ended). Written by whichever path ended
    them first (lane dispatch, a named release, the sweep); never twice.
  - `released_on_contact` (U46): a named release that got past the group-level checks, even when
    its first member stopped. `actor` the user. Payload: `{released_by, realized_contact_id, booked,
    released_entry_ids, not_attempted_entry_ids, stopped: null | {command_queue_entry_id,
    command_request_id, reason: {code, details}}}`. The audit line reads actor, `at` and `booked`.

### `POST /contacts/:realized_contact_id/release` (U46 named release, DECISIONS #84; owner: api)

Sends armed groups over a contact the operator names: a booked pass, or a hand-started contact
after the danger sheet. Body `{command_group_ids: [id] (1–50, distinct, in release order),
confirm_unbooked: bool (default false)}`; `operate_mission`, a fresh human (GO/NO-GO's rule).

- Each group goes through domain's `release_group_to_contact`: only its members for that
  contact's spacecraft, in stack order, stopping at the first that doesn't release (what went out
  stays released). Later groups are still tried after a stop or a group-level refusal.
- `200 {realized_contact_id, booked, results: [{command_group_id, outcome: released | stopped |
  refused, released_entry_ids, not_attempted_entry_ids, stopped: null | {command_queue_entry_id,
  command_request_id, code, details}, refused: null | {code, details}}]}`, one per id, in order.
  - Group codes (`refused`): `command_group_not_found`, `command_group_not_armed {state}`,
    `release_contact_not_target_spacecraft {realized_contact_id}`, `command_group_nothing_to_release
    {realized_contact_id}`.
  - Stop codes (`stopped`), read as known text: `command_window_closed {realized_contact_id, why,
    starts_at, ends_at}`, `command_queue_entry_not_next_for_release {next_command_queue_entry_id}`,
    `command_queue_lane_release_pending {queue_lane_key}`, `command_release_refused
    {command_release_attempt_id, refusal: {code, details}}`, `command_release_outcome_uncertain
    {command_release_attempt_id, message}`, bare codes (`earlier_command_failed`,
    `release_basis_changed`, …) with `{}`, any other tag with `{message}`, else `unknown`.
- Whole-request refusals, only while nothing has gone out: `409 command_window_closed
  {realized_contact_id, why: outside_pass | uplink_leg_dropped, starts_at, ends_at}` (times null
  without a booked window), `409 unbooked_contact_unconfirmed {realized_contact_id}` (resend with
  `confirm_unbooked: true` from the danger sheet), `404 realized_contact_not_found`, `409
  realized_contact_not_releasable {realized_contact_id, state: stopped | completed}`, `403
  forbidden`, `422 invalid_params {command_group_ids | confirm_unbooked}`. Once something has gone
  out, the same no about the contact is a 200: that group and the rest are `refused` with it.
- Each release that got past the group checks writes `released_on_contact` on the group's timeline.

### `POST /command-groups/:id/decision`

`{"kind": "go" | "go_excluding" | "send_back" | "no_go", "excluded": [spacecraft_id], "note": "…",
"expected_review": "<review_token>"}`. Returns the group. A note is required except for `go`.
`go_excluding` rejects the named targets' members ("excluded at review").

Errors: `403 command_group_self_approval_not_allowed` (#622, #280: the requester counts as people,
as on a single request, so a service requester is its issuer and rotators; details
`{via_service: {id, name}}` when it came through a service you're accountable for, none when you
requested it yourself), `403 command_group_approver_authors_unknown` (details `{service}`: a service
nobody is recorded as accountable for requested it, so nobody can decide it; fail closed),
`403 not_the_requested_approver`,
`409 command_group_not_pending`, `409 command_group_review_stale`, `409 command_group_basis_changed`
(the active catalog changed since submit, so resubmit), `409 command_group_members_changed` (GO
only: the group's member rows no longer match what submission recorded; details
`submitted_member_count`, `current_member_count`; send back and NO-GO stay allowed; resubmit), `422 note_required`, `422 exclusions_required`,
`422 unknown_excluded_target`, `422 invalid_params` (an `excluded` list that repeats a target: `details.excluded`).

`expected_review` is **required on `go` and `go_excluding`** (#117 step 4a; fail closed: a GO without it
answers `409 command_group_review_stale`), and optional on `send_back` and `no_go`. The token covers
the group's state, preflight and member count, and **which requests are its members** (the members
digest: each member's id with its own review token). Swapping one member for another at the same
count makes it stale. GO recomputes it under the group lock.

**HOLDs at GO** (DECISIONS #61): `go` and `go_excluding` re-run the review preflight
(`GET …/preflight`) on a pending group.
- Hard HOLDs refuse: `changed_since_submit`, and `contact` (no commandable contact).
- An ackable HOLD whose `hold_basis` is unchanged since the submitter acknowledged it carries.
- A new or changed one needs the approver's own acknowledgement: the body takes
  `acknowledged_holds: [{key, hold_basis, note}]`, the same as submit. It's recorded as a
  `hold_acknowledged` event with the approver as actor and `payload.at_decision: true`.
- Otherwise `422 holds_unacknowledged`, with `details.holds` as for submit.
- `send_back` and `no_go` don't check HOLDs.

### M26 (Uplink U2 / N; DECISIONS #69)

**Verifier series**, `GET /command-groups/:id/verifier-series[?targets=<id,id,…>][&point=<point_id>]`:
what U2 plots.
- `points: [{point_id, name, verifier_name, position, spacecraft_ids}]` (U2, 11-14): every
  telemetry point the group's verifiers watch, each with the targets whose OWN verifiers watch it
  (targets pinned to different catalog revisions can differ), ordered by stack position, then the
  verifier's order on the command. `[]` when nothing is plottable. `?point=` plots that one; without
  it (or for an unknown id) the first. The plot (`targets`, `target_count`, `truncated`, `summary`)
  covers only that point's targets. U2 draws one plot per `points[]` entry.
Refetch on `invalidate` `commanding`, plus `telemetry` throttled to 10 s.
- `verifier: {position, command_id, command_name}`: the plotted command, the first in stack order
  whose verifier watches a telemetry point (from its catalog verifier plans, so it's known before
  release). Header: `02 SET_TEMP · 34 stepped to 8.0 · 1 did not`.
- `point: {id, name, unit, type: numeric | enum | text} | null`. `null` means nothing to plot:
  `reason` is `verified_by_uplink_acknowledgement` (transport-only verifiers, as for the demo
  catalog's NOOP / SET_MODE / RESET_COUNTERS) or `no_verifier`. Say "Not plottable: verified by
  uplink acknowledgement only".
- `commanded: {value_json, comparison} | null`: the expected value (the value sent, once released)
  and its comparison. `band: {min_json, max_json} | null` for range criteria.
- `window: {from, to} | null`: the first release to the last verifier timeout; `null` before
  release, when there's nothing to plot yet.
- `targets: [{spacecraft_id, name, verifier_state: pending | satisfied | failed | timed_out | null,
  verifier: {instance_id, verifier_id, severity, failure_code} | null, timeout_at | null,
  matched_at | null, samples: [{t, value_json}]}]`: `timeout_at` / `matched_at` (U69 A4a) are the
  instance's verify-by and matched times;
  `verifier` (U68 R4) is that target's verifier instance, null exactly when `verifier_state` is
  (`failure_code`: `timed_out | failure_criteria_matched | null`); per target, that spacecraft's own samples only (#38), at most 300
  per target, decimated.
  - At most 100 targets. `?targets=` picks which (100 max); `target_count` is the group's total,
    and `truncated` is true when not all are included.
- `summary: {met, not_met, pending}`, from the plotted command's verifiers.
- `telemetry: ok | degraded`: the history store didn't answer within 3 s, so `samples` are empty.
- Errors: `404 command_group_not_found`.

**No automatic retry** (DECISIONS #69): re-sending a command without a fresh GO is a safety
policy for the user to decide. `Re-send` is Compose's clone (`?from=group:<id>`) narrowed to the
failed targets, through the normal approval flow. N lists no automatic recoveries, and there's no
`Retry 1 of 3`.

### `POST /command-groups/:id/abort` · `POST /command-requests/:id/cancel` (M20)

`{"reason": "…"}` (required). Abort cancels every member that hasn't started to radiate and
returns the group with `abort_result: {canceled: <count>, already_started: [request ids]}`
(`canceled` is how many members were canceled; `already_started` lists the ones that kept running). Members already
releasing or released keep running ("ABORT AVAILABLE UNTIL EACH UPLINK STARTS"). Any mission
operator may abort or cancel (`Policy :operate_mission`, not two-person, DECISIONS #42), the same
check as requesting and approving (#62). The session's `command.abort` capability is held when the
user can operate at least one of the organization's missions. Cancel works on any request (grouped
or not) that hasn't started.

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

### `POST /command-endpoints` · `GET /command-endpoints?spacecraft_ids=a,b` (Compose's endpoint picker)

`POST` takes `{"spacecraft_ids": ["a", "b", …]}` (#795): a fleet's ids don't fit in a URL. Each id
counts once. More ids than the size guard's `max_targets` is `422 command_group_too_large`
(`details.max_targets`, `details.targets`), never a silent cut; a non-list or a non-text id is
`422 invalid_params`. Ask for the page of rows on screen, not every target at once. The `GET` with
a comma list answers the same, with the same 422, until the console moves off it (then it goes).

Per spacecraft: `{spacecraft_id, resolved_source_endpoint_id, failure, routes[],
endpoints: [{id, name, scid, managed}]}`. `resolved_source_endpoint_id` is what preflight will use
when you send no override; `failure` (`no_uplink_route | multiple_primary_uplink_routes`) says why
there's none. `endpoints` are the spacecraft's source endpoints to offer as an explicit override;
`managed` marks the one routes materialize on.

### `GET /command-policies` (O4)

`{"data": {"policies": [{"key": "command_classification", "parameters": {"classifications": ["hazardous", "critical"]}},
{"key": "policy_hint", …}, {"key": "fleet_reach", "parameters": {"threshold": 10}}, {"key": "no_self_approval", "parameters": {}}]}}`.
The UI writes the sentences (title + sentence per key).

### Not yet

Nothing outstanding from the design. Work past its `expires_at` is never released: the release
claim refuses it under the request and lane locks. It ends `end_reason: expired` as soon as
release reaches it: the lane's dispatch closes its expired entries first, and a named-contact
release ends its expired members and STOPS at the first one in stack order (`stopped.reason.code`
`command_queue_entry_expired`). A group's members share ONE `expires_at` (DECISIONS #97; admission
refuses a group whose members don't), so when a group expires every unreleased member of a target
expires at the same instant and ends `end_reason: expired` itself, on both paths: none is left
queued to go out at a later contact. Members released before the deadline stay released. A sweep on every dispatcher reconcile
(about a minute) cleans up the rest. Live progress: the `command_group:<mission_id>:<command_group_id>` channel
(realtime.md).

## `GET /api/v1/missions/:mission_id/command-requests/:command_request_id/encoding` (M24, owner: api)

The bytes release would send for one request (Approve A3), encoded exactly as release encodes
them: the request's **own** model revision basis and its resolved argument values. Nothing is
transmitted.

```json
{"data": {
  "command_request_id": "…", "command_id": "…", "mission_model_revision_id": "…",
  "scope": "command_payload", "size_bytes": 3, "hex": "0A0007", "base64": "CgAH",
  "arguments_json": "{\"counter\":7}"
}}
```

- `scope: "command_payload"`: the command packet payload, **before** transport framing (no TC
  frame, segment or CLTU). Say so next to the bytes.
- It never encodes against another revision. If the request's revision isn't the active one, the
  read fails closed like release does: `409 encode_unavailable` with `details: {reason:
  "revision_superseded" | "revision_not_active" | "basis_unavailable" | "encode_failed", detail}`.
  Show "These bytes can't be shown" with the reason; don't fall back to the current catalog.
- `arguments_json`: the resolved values as JSON text (64-bit safe, like `argument_values_json`).
- Access: anyone who may review the mission's requests (`operate_mission`); otherwise `403
  forbidden`. `404 command_request_not_found`.

## `GET /api/v1/missions/:mission_id/command-requests/:command_request_id/brief` (A1, owner: api)

Context for reviewing one request: each argument's value and that argument's **current value**
on the request's spacecraft, plus the command's prior requests to the same target.

```json
{"data": {
  "command_request_id": "…", "command_id": "…", "spacecraft_id": "spacecraft-earendil-004",
  "arguments": [{"argument_id": "…", "name": "mode", "value_json": "3",
                 "current": {"point": "/parameters/HK/sc_mode", "value_json": "1", "at": "…",
                             "reason": null} | null,
                 "current_basis": "state_effect" | "none" | "unavailable"}],
  "prior_requests": [{"command_request_id", "command_group_id", "arguments_json", "state",
                      "requested_at", "requested_by": {"kind", "id", "name"},
                      "reached_target": true | false | null}]
}}
```

- A current value exists only where the catalog links the argument to a telemetry point: a
  command `state_effect` with `operation: set` for that argument. Its point is read **for the
  request's spacecraft only**, never mission-wide (#38). Nothing is inferred from verifiers or
  names. `current_basis: "none"` means no such link: say "no current value known".
- `current.reason`: `no_sample` (linked, but no value received yet) or `no_target_spacecraft`.
  `current_basis: "unavailable"`: the request's revision isn't active, so the link can't be read.
- Values are JSON text (`value_json`, `arguments_json`).
- `prior_requests`: the same command to the same target, newest first, at most 5, excluding this
  one. Each has `reached_target`: `true` when its latest release went over a contact serving only
  the target (#38's check), `false` when it went elsewhere (it didn't set this spacecraft: say so,
  don't present its values as the spacecraft's state), `null` when it was never released.
- Bounds (`valid_range`, unit) stay on the command catalog read (`GET /commands/:id`).
- Access as for M24 (`403 forbidden`, `404 command_request_not_found`).
## `GET /api/v1/missions/:mission_id/command-requests/:command_request_id/history` (U68 R3/R4, owner: api)

One member's release attempts and verifiers with the record that matched each (parity A3, A4b/c).
A member is a command request (`targets[].members[].request_id` on the group read).

```json
{"data": {"request_id": "…", "spacecraft_id": "…",
  "attempts": [{"attempt_id": "…", "state": "released", "uncertain": false, "failure_reason": null,
    "contact": {"id": "…", "label": "EARENDIL-007 · PUQ 07:20Z pass"}, "path_id": "…",
    "transport_binding_id": "…", "encoded_size_bytes": 12, "attempted_at": "…", "released_at": "…"}],
  "attempts_next": null,
  "verifiers": [{"instance_id": "…", "attempt_id": "…", "verifier_id": "…", "name": "Mode applied",
    "phase": "completion", "severity": "warning", "state": "satisfied", "failure_code": null,
    "matched_at": "…", "timeout_at": "…", "evidence_status": "ready",
    "evidence": {"kind": "telemetry", "sample_id": "…", "point_id": "HK.sc_mode", "point_name": "…",
      "packet_id": "…", "evidence_id": "…", "quality": "good", "raw_value_json": "2",
      "engineering_value_json": "2", "received_at": "…", "generated_at": "…"}}],
  "verifiers_next": null}}
```

- `attempts`: newest first. `state`: `release_pending | released | release_failed |
  release_uncertain | canceled`; `uncertain` is `state == release_uncertain`. `failure_reason` is
  an internal inspected term: Technical details only, never worded. `failure` (U70) is what to
  word: `{kind: refused | resolved | uncertain, code: string | null, by: {kind, id, name} | null,
  at | null} | null`. `refused` = the uplink refused before sending; `code` is the same vocabulary as
  a named release's `stopped.reason.code`. `resolved` = an operator resolved an uncertain
  release; `code: not_sent | rejected`, with `by` and `at` from the resolution log. `uncertain` =
  the cause's code (e.g. `send_outcome_unknown`). `by`/`at` are null except for `resolved`.
  `by.kind`: `user` (name = display name, else email) | `service_identity` (an API credential;
  name = its display name). Never Cadence itself: an automatic timeout records outcome
  `unknown`, which isn't a resolved failure. `contact.label` names the spacecraft, station code and AOS for a booked pass ("… pass",
  the date when not the attempt's day), or "… contact" for a hand-started one.
- `verifiers`: oldest first. `phase`: `acceptance | start | completion | custom`; `severity`:
  `info | warning | error | critical | null`; `state`: `pending | satisfied | failed | timed_out |
  canceled`; `failure_code`: `timed_out | failure_criteria_matched | null`.
- `evidence_status`: `ready` (`evidence` set), `pending` (nothing matched yet, still pending),
  `unmatched` (ended with nothing matched), `unavailable` (a match is recorded but its record
  can't be read, or belongs to another attempt). `evidence` is null unless `ready`:
  - `{kind: "telemetry", sample_id, point_id, point_name, packet_id, evidence_id, quality: good |
    suspect | bad, raw_value_json, engineering_value_json, unit, received_at, generated_at}`
    (`unit`: the point's catalog unit, `null` when none);
  - `{kind: "transport", source: "action_request", record_id, action, signal_phase, at, recorded_at:
    null}` (`action` = its action kind: `uplink_request | provider_request`, the only kinds that
    carry a command attempt; `at` = requested);
  - `{kind: "transport", source: "capability_record", record_id, action, signal_phase, at,
    recorded_at}` (`action` = its event kind: `transport_event_handled | control_input_handled |
    timer_handled`; `signal_phase` as the verifier matched it: the record's own phase, else
    `acceptance` for the uplink gateway's handled input; `at` = `recorded_at`). Neither
    transport record has a separate event time.
  - `signal_phase`: `acceptance | start | completion | failure | custom | null`.
- Paging: 25 each. `?attempts_after=<attempts_next>`, `?verifiers_after=<verifiers_next>`; `null`
  = no more. An id that isn't on this request: `422 invalid_params` (`details.field: "cursor"`).
- `404 command_request_not_found`.

## Compose draft (owner: api; director, BACKLOG ac293f6c)

Each user has one current draft per mission. Autosave overwrites it; there is no list and no
number (ux 36cca988: the header reads `DRAFT · SAVED 02:44:31Z`). Only its author can see it. A
draft is **inert**: approvers never see it, and it is never queued or releasable. Submitting a
group revalidates the group body in full, so nothing is trusted from a draft. A draft idle for 30
days reads as gone and is deleted on the next read or write.

### `GET /command-draft`
The caller's draft, as `{draft: <below> | null}`; `null` when they have none (200, not an error:
qa a11y #6).

```json
{"revision": 3, "saved_at": "…", "document": {…},
 "catalog": {"revision_saved": "<mission model revision>" | null, "revision_now": "…" | null,
             "missing_command_ids": ["…"]}}
```

`missing_command_ids` lists stacked commands the active catalog no longer has. It's empty when no
catalog is active.

Errors: `404 mission_not_found` for an unknown mission only. Having no draft is `{draft: null}`.

### `PUT /command-draft`
Body `{document, expected_revision}`. `expected_revision` is the revision you last saved, or null
for a first save. The response is `{revision, saved_at}`. When the stored revision differs (another
tab or device saved), the response is `409 command_draft_changed` with `details: {revision,
saved_at}`. Reload, then save at that revision.

The document is the editor's state and is opaque to the server, apart from a shape check
(`schema_version: 1`, a `stack` of at most 500 items each with a `command_id`) and a 256 KB cap:

```json
{"schema_version": 1, "title": "…", "log_entry": "…",
 "origin": {"kind": "alarm" | "spacecraft" | "sent_back", "id": "…"} | null,
 "target_query": {"plane": 7, "profile": null, "states": [], "explicit": ["…"]},
 "endpoints": {"<spacecraft_id>": "<source_endpoint_id>"},
 "stack": [{"key": "…", "command_id": "…", "values": {"<arg_id>": "raw text"},
            "per_target": {"<arg_id>": {"<spacecraft_id>": "raw text"}}}],
 "release": {"mode": "next_contact" | "not_before", "not_before": "…" | null},
 "requested_approver_user_id": "…" | null, "sent_back_from": "…" | null}
```

Values are stored as raw text, so invalid input survives a reload. Only preflight validates.

Errors: `422 invalid_params` (`document`, `document.stack`, `expected_revision`).

### `DELETE /command-draft`
Discards the draft. The response is `204` (idempotent).

### Submitting from a draft
`POST /command-groups` takes an optional `draft_revision`. Once the group is created, the caller's
draft is deleted in the same transaction, **only if it is still at that revision**, so a newer
autosave from another tab survives.

## The command four-eyes record (#117 step 4b; rides the next reset)

Every row in `command_approvals` is a complete decision record (DECISIONS #112; the fields are
required, so this lands only on a fresh database at a reset):
- `subject_digest`: the request's review token at decision (`Commanding.RequestDigest.digest/1`).
  For a group member, that's its own token. For a release, it's the token at release. **Basis
  version 3 (#708, DECISIONS #112):** the member's group (`command_group_id`, `group_target_index`,
  `group_position`) is part of what's reviewed, so every digest differs from version 2's; a
  decision record carries the digest it was decided on, and the database is reseeded.
- `separated_from`: exactly the ids the separation check was given (the requester; a service by its
  own id). It's `[]` on a `not_required` row, since no check ran.
- `admin_mode`: whether the decider or releaser acted as a platform admin, from their scope. It
  has no default: a path that omits it fails, and never records `false` by default.
- `decision`: `approved | rejected | not_required`.
  - **`not_required`** is written only when a request is released without a second GO (its policy
    needs none): a group submitted under such a policy.
    It's written in the release's own transaction, with the releaser as actor.
  - A decision path never writes it.
  - **No existing read shows it** (api-ops on #639): the org audit's command approvals, REST
    `GET …/command_approvals` (and `/:id`, which answers `404` for one) and the console review's
    history leave it out, so `decision` there stays `approved | rejected`. The four-eyes record has
    it (#239's audit).
- **Two names on an automatic release, on purpose (api-ops):** the approved command's
  `approved_by` stays the safety policy (`cadence:command_safety_policy`), because the policy is
  what authorized it, while the `not_required` row's actor is the person who released it. The
  audit shows the person, and the approved command shows the authority.
- A group decision's `decision_document` also names `members_digest` (the members the GO's token
  covered) and `excluded_request_ids` (the requests a GO-excluding left out).

## REST: command requests are made and decided only through command groups (#708; breaking)

The pre-console REST API (`/api/organizations/:organization_id/missions/:mission_id`) no longer
creates, decides or queues a command request on its own. Every command request is a member of a
command group (DECISIONS #61, #62), and a group is the one way to command. **Breaking:** these
endpoints are removed, and a call to one is a `404`:

| Removed | Instead |
| --- | --- |
| `POST /command_requests` | Submit a group: `POST /api/v1/missions/:mission_id/command-groups` (after `…/preflight`). |
| `POST /command_requests/:id/approve` · `/reject` | Decide the group: `POST /api/v1/missions/:mission_id/command-groups/:id/decision` (GO, GO excluding, send back, NO-GO). |
| `POST /command_requests/:id/enqueue` | The group's GO queues its members (or its submission, when its policy needs no second GO). |
| `POST /command_stages/:id/submit` | Submit a group. A command stage no longer turns into requests. |
| `GET`, `POST /command_stages`; `GET`, `PATCH /command_stages/:id`; `GET`, `POST /command_stages/:id/items`; `GET`, `PATCH /staged_command_items/:id` | Nothing: the stage workbench is deleted. A shared batch is a command group; Compose's autosaved draft is private. |

Still there: the reads `GET /command_requests` (and `/:id`), `GET /command_approvals`,
`GET /command_queue_entries` and the release `POST /command_queue_entries/:id/release`.

The command pages of the pre-console host that could queue a command without a group preflight
(the command workspace's queue action, the stage queue and the single-request authoring page,
#707) are removed with them, so no path queues a command without the group's preflight and its
second-GO rule.

## REST commanding: actors (#465)

Every actor object the pre-console REST commanding API sends (a command
request's `requested_by`, an approval's `decided_by`, a queue entry's `enqueued_by`, a release
attempt's `released_by`, alone or inside the release answer) is `{kind, id,
name}` or `null`, never the stored actor document (#146, through #472's `ActorRef`):

- `kind`: `user`, `service` or `system`.
- A person is named, and keeps their `id`, only while they hold an active membership in the
  record's organization, checked at read time; `name` is null when they have no display name.
  Anyone else (someone who has left, a platform admin from another organization) is `{kind:
  "user", id: null, name: null}`.
- A service identity of the organization keeps its `id` and its live display name; another
  organization's is `{kind: "service", id: null, name: null}`.
- The system actor reads as stored (`{kind: "system", id, name}`).
- A stored document Cadence can't read makes the whole field `null`.
- Never an email: the rows written before #466 that hold one stay as they are (#116), and it never
  leaves the server. The stored keys (`actor_kind`, `user_id`, `service_identity_id`,
  `user_display_name`, …) are gone from the answer; read `kind` and `id`.

## REST command queue entries: group members (owner: api-ops; four-eyes P0, 2026-11-18)

The pre-console REST API under `/api/organizations/:organization_id/missions/:mission_id`
(the `:api` and `:authenticated_api` pipelines) keeps its own error body, `{"errors": [{"reason":
"<code>", "message": "…"}]}`, not the console envelope. Every command request is a command group's
member (#708), so a request is queued and released only through its group.

| Endpoint | Refusal | Meaning | Instead |
| --- | --- | --- | --- |
| `POST /command_queue_entries/:id/release` | `409 command_group_not_armed` | The entry's group isn't armed (`queued`, after its GO), judged from the server's group row. Nothing was released. | Give the group its GO; its release goes through the group. |

The `message` is ux U87's words: "This command's group hasn't been given its GO, so it can't be
sent." Membership is read from the server's group records. The console's named release already
refused an unarmed group (`command_group_not_armed` under `refused`, in the release section above).

**Service requesters (#280, ux U100).** A request made through a service identity counts as made by
the people accountable for it (its issuer and rotators, and anyone an org admin records). Approving
it as one of them is refused with the same reason as approving your own,
`command_request_self_approval_not_allowed`. Before, a service requester had no `user_id`, so
that check passed. This REST envelope carries no `details`, so the service isn't named here; the
console's refusals name it (`details.via_service`).
