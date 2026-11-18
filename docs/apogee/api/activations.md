# Activation approvals (§11 L10)

Conventions: [README.md](README.md). Proposal: `docs/apogee/plans/activations.md` (fe-setup). Owner:
api. Domain: `Management.Activations` (requests and decisions), `Control.Activations` (execute,
resume; domain 9b8456132, 8f30aac21). Replaces the LiveView `/ops/activations`.

Base: `/api/console/v1/missions/:mission_id/activations`. Every call checks the request belongs to
this mission (`404 activation_request_not_found` otherwise). Refetch on `invalidate` with
`activations` (new topic, sent when this API decides or resumes a request) and `attention` (an apply
that fails or stalls shows on Now).

## `<row>`

```json
{"id": "activation_request_…", "kind": "telemetry_decom", "app": {"key": "telemetry_decom", "name": "Telemetry Decom"},
 "summary": "Decom composition for 3 spacecraft",
 "binding_set": {"id": "…", "version": 4},
 "requested_by": {"kind": "user", "id": "…", "name": "Mira K."}, "requested_at": "…Z",
 "state": "approval_pending",
 "decision": null,
 "execution": null,
 "can_decide": true}
```

- `kind`: `telemetry_decom | spacecraft_configuration | null` (null: a mission activation with
  neither). `app` is null except for decom. `summary` is the same sentence the Now item shows
  (`Control.Activations.Description`).
- `state`: `approval_pending | approved | rejected | withdrawn | superseded` (domain 444c6126b).
  `superseded`: a newer request for the same binding set (or, for spacecraft configuration, the
  same reviewed spacecraft) arrived. `superseded_by` (that request's id) and `superseded_at` are set
  then, else null.
- `decision`: the latest human decision, `{state: approved | rejected | withdrawn, by {kind, id,
  name}, at, reason}`, or null. A request approved by policy alone (no reviewer) is `approved`
  with a null decision. A superseded one has no decision (the system did it).
  - **From the dev reset (DECISIONS #112, P3 step 3; it rides the dev reset slot, ~11-21):** every
    decision is recorded, including one no second person was needed for. A request activated
    directly under a `direct` policy is `approved` with `decision: {state: not_required, by` (the
    submitter)`, at, reason: null, source, subject, separated_from, admin_mode}`, never a null
    decision. Every decision gains `source {kind: change_set_review | spacecraft_configuration |
    …, id}` (read `kind` as open text), `subject {kind, id, version, digest}`, `separated_from`
    (actor ids) and `admin_mode` (boolean), and `reason` may be null (approve comments are
    optional). Until the reset, read these keys as optional and a null decision as today's
    policy-only form.
- `execution`: null until an apply starts, then `{state: in_progress | succeeded | failed, since,
  finished_at, error_code, error, retryable}`.
  - `finished_at` (ux #227, added 11-18; read it as optional): when the apply succeeded or failed;
    null while it runs, including after a resume until it finishes again. It's never the
    decision's time: a held apply that resumes later reads its own finish time.
  - `error_code` (closed set): `activation_execution_interrupted |
    spacecraft_configuration_review_stale | approved_activation_content_mismatch`, or another
    domain code (word it as the generic failure). It's null unless `failed`.
  - `error`: the server's sentence (ux U41, the same as the Now item), never the raw reason. It's
    set when the execution failed or has **stalled** (in progress over 10 min with nothing working
    on it), else null.
  - `retryable`: `Retry apply` can succeed. It's true for a stalled execution and for a failure
    other than `spacecraft_configuration_review_stale` / `approved_activation_content_mismatch`.
    Otherwise the next step is a new request ("Request activation again so the current version
    can be approved.").
- `can_decide`: pending, you may approve (`activations.approve`), and you didn't request it.
- `spacecraft` and `spacecraft_total` (detail only; #235, lead 11-18): a spacecraft configuration
  request's reviewed craft, `[{id, name}]` (at most 100, in the request's order) and their count,
  on every state; both `null` for other kinds.
- `configuration_changes` (detail only; #235, lead's final shape 11-18): what a PENDING spacecraft
  configuration request changes, grouped by identical change; `null` for other kinds and once
  decided (after an apply, what runs is its content). `{groups: [{rows: [{field, label, before,
  after}], first_start, telemetry_enabled, count, spacecraft: [{spacecraft_id, name}]}], total}`.
  - A group is the craft whose `rows`, `first_start` and `telemetry_enabled` are equal; every
    group is sent. Changed groups come first, in the request's order; the no-change group (`rows:
    []`) last. `spacecraft` names at most 100; `count` is exact. `total` counts every reviewed
    craft; one whose reviewed version can't be read (or that was saved again since the review, so the
    request is stale) is in `total` but in no group.
  - `rows` compare the reviewed version with what runs now. `first_start`: nothing is active for
    the craft, so every set field is a row with `before: null`. Fields, in this order:
    `catalog_revision {id, number|null}`, `telemetry_source {id, name}`, `handled_apids [int]`,
    `downlink`, `uplink` (the protocol word), `frame_size`, `secondary_header_length`,
    `insert_zone_length`, `ocf_length` (int), `truncated_primary_header` (bool); a missing value
    is `null` ("Not set"). `label` is the fallback word. The switches are never rows (#109);
    `telemetry_enabled` is the value the craft will run with.

## Endpoints

- `GET /?state=pending|decided&before=` → `{requests: [<row>], next, permissions}`. `pending` (the
  default) is `approval_pending`; `decided` is the rest. Newest first, 25 a page; pass
  `next` back as `before` (null on the last page). `permissions`: `["activations.approve"]` for
  people who may approve, decide and retry, else `[]`. `422 invalid_params` for an unknown `state`
  or a bad cursor.
- `GET /:id` → `<row>` plus `details: [{label, value}]` (server-made facts: what it activates, the
  binding set, the spacecraft, up to 5 named then "and N more", and the content hash), `comparison:
  {report_id, label} | null` (decom's mission-model comparison), `configuration_changes` (above)
  and `permissions` (as above).
- `GET /:id/configuration-changes?group=N&offset=K` → `{spacecraft: [{spacecraft_id, name}],
  next_offset}`: 100 names of the group at index `N` of `configuration_changes.groups` (as the
  detail sent them), from `offset` (default 0); `next_offset` is null on the last page. `404
  configuration_changes_group_not_found` for a group the request doesn't have (or a request that
  isn't a pending configuration review); `422 invalid_params` for a bad `group` or `offset`.
- `POST /:id/approve {reason}` → `200 {request: <row>, outcome: applied | needs_review}`. Approving
  applies at once. `needs_review`: approved, but the apply didn't finish; the row's
  `execution.error` says why, and `retryable` says whether `Retry apply` can help.
- `POST /:id/reject {reason}` → `200 {request: <row>}`.
- `POST /:id/withdraw {reason}` (the requester only) → `200 {request: <row>}`.
- `POST /:id/resume` (empty body, **Retry apply**) → `200 {request: <row>, outcome: applied |
  needs_review}`. Same permission as approve; audited (`activation_resumed`).

Errors:
- `422 invalid_params {reason: "Say why."}`: approve, reject and withdraw need a reason (1–4096
  bytes).
- `403 not_requester` (withdraw): "Only the person who requested it can withdraw it."
- `409 not_pending {state}`: already decided (`state` is the request's state, or null when it
  changed under you).
- `403 self_approval_forbidden`: you requested it.
- `409 activation_policy_changed` (approve only; reject always works): the activation policy
  changed since the request; request it again. (It's not `policy_changed`, which is the planning policy's code.)
- `409 nothing_to_resume {state}` (resume): `succeeded` ("It already applied."), `in_progress`
  ("It's applying now.", not stalled yet), or the request's state when it isn't approved
  (`approval_pending | rejected`): "There's nothing to retry."
- `409 not_resumable {error_code}` (resume): a stale review or content mismatch can't apply on a
  retry. Refetch, since the row is then `retryable: false`.
- `409 activation_execution_in_progress` (resume): something is applying it right now.
- `403 forbidden`, `404 activation_request_not_found`.

todo(authz): reads are open to the mission's console members. Approve, reject and resume use
`:approve_activation` (today `:operate_mission`); the rule is with the user and director for Cedar.
