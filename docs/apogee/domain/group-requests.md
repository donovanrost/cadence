# Group command requests (M16 · M18 · M20 · O4 · M19)

Owner: **api-ops** (design + build in the commanding context, DECISIONS #29). Reviewers:
**domain**, **director**; fe-ops for the screen fit. Status: **draft 2, approved** (2026-11-09;
DECISIONS #31). Draft 2 folds in the director's answers to §10 and fe-ops' comments
(`plans/ops.md`, "fe-ops comments on group-requests.md"). Domain's lock review (Q5) is still open.
Screens: J3 Command a group (`ux/screens/Command.md` C1–C5), C1 Compose, C2 Approve, C3 Uplink
(`ux/screens/CommandFlow.md`). Decisions: #7 (two-person, policy-driven), #8 (no waves/gates
yet), #4 (no umbra/propagation). `L` = `apps/cadence/lib/cadence`.

## 0. Summary

- A new **command group** is one operator intent: **N targets × K commands** sent as one reviewed,
  approved, abortable unit. Each (target, command) pair is still an ordinary `CommandRequest`, so
  the existing queue, release, encoding, verifier and history machinery runs unchanged per member.
- The group owns what's shared: **target-query evidence**, the **command stack**, the **release
  plan**, the **two-person decision** (one GO for the whole group, with exclusions), a **log entry
  and notes**, and **abort**.
- **Every console-authored request is a group**, including 1 × 1. One shape for Compose, J3,
  Approve and Uplink; notes (M19) and abort (M20) work the same for one target or 400.
- The 25-target cap (`WorkspaceSubmission`) is replaced for groups by explicit bounds:
  **N ≤ 1,000, K ≤ 16, N×K ≤ 5,000** (config), validated in bounded chunks under one locked basis.
- New operator actions the model lacks today: **cancel a request** and **abort a group**. Both only
  touch members that haven't started to radiate.

## 1. What exists (and what it means for the design)

From a full read of the pipeline (2026-11-09):

| Today | Consequence |
| --- | --- |
| `CommandRequest` states `draft · validated · approval_pending · approved · rejected · queued · released · canceled`; insert as `validated` or `approval_pending` (`RequestValidation.request_lifecycle_state`) | Members reuse these states. Group policy must be able to **force** `approval_pending` (fleet reach). |
| (Before #708) Approval was per request (`RequestStore.decide_request`: expected-review digest, human actor, no self-approval) and did **not** enqueue; enqueue was a separate step (`Control.Commanding.enqueue/3` with an `ApprovedCommand` guard). Both are gone: only a group is decided | Group approval decides all members in one transaction, then enqueues them in stack order. Members can't be decided one by one. |
| Queue lanes are **per target** (`queue_lane_key = source_endpoint_ref`), ordered `priority, queue_sequence`; one `release_pending` entry holds its lane | A target's K members share its lane, so the stack runs **in order at that target's contact**, back-to-back. |
| Release fires on contact facts / lane kicks; release re-validates the **exact revision** (`resolve_basis`) | A revision change after submit makes a member un-releasable. Today that entry **sits at the head of its lane forever** (no failure, no sweep). Abort/cancel fixes that by hand; the Uplink read flags it. |
| `canceled` is only set by release-resolution `not_sent`; **no operator cancel** exists; expired entries stay `pending` | M20 adds an operator cancel for not-yet-started members. |
| No group, batch or correlation id on requests (only `source_command_stage_id`, queue metadata) | New `command_groups` table + `command_group_id` on requests. |
| `:commanding_changed` read update, no per-request push | Uplink progress v1 = group read refetched on `commanding`; a `command_group:<id>` channel push later. |
| **Bug found:** REST commanding accepted client actor documents (`decided_by`, `requested_by`, `enqueued_by`, `released_by`, stage `owner`) | **Fixed** (DECISIONS #30, `d8de442f`): actors come only from the authenticated scope, and any actor field gets `422 actor_not_assignable`. Group writes follow the same rule. |

## 2. Model

```
command_groups
  command_group_id PK, organization_id, mission_id
  state            approval_pending | queued | rejected | sent_back | aborted
                   (progress after `queued` is derived from members, §6)
  title            short reason (headline on Approve)          NOT NULL
  log_entry        operator log text (M19); required when a second GO is required
  requested_by     actor doc (session user only), requested_at
  requested_approver_user_id  NULL = any eligible operator ("Second GO from")
  target_query     {chips: [{key, op, value}], explicit_ids: [...]}      -- what was asked
  targets          [{spacecraft_id, source_endpoint_id, name, scid, profile: {id, version},
                     plane, state_at_resolution, matched_by: ["plane 07", "state caution+"]}]
  resolved_at      when the query was resolved                         -- evidence
  commands         [{position, command_id, name, argument_values, significance, hazardous, critical}]
  release          {mode: next_contact | not_before, not_before, expires_at}
  basis            {activation_id, revision_id, authoring_token}
  policy           {second_go_required, reasons: [{key, …}], policy_version}   -- §4, frozen at submit
  preflight        last preflight result (checks + digest), §5
  member_count, decided_by, decided_at, decision {kind, excluded_spacecraft_ids, note}
  aborted_by, aborted_at, abort_reason, abort_result {canceled, already_started}
  sent_back_from   command_group_id NULL (the group this draft was cloned from after send back)
  operation_id     client idempotency key, unique per (mission, requested_by)
  inserted_at, updated_at

command_group_events   (append-only; the request log and notes, M19)
  event_id PK, command_group_id FK, organization_id, mission_id, kind, actor, at, payload
  kind: submitted | preflight | approved | approved_with_exclusions | sent_back | rejected
        | note | member_canceled | aborted | member_failed | completed

command_requests  (+ columns, nullable for existing requests)
  command_group_id FK NULL, group_target_index int NULL, group_position int NULL
  index (command_group_id), unique (command_group_id, group_target_index, group_position)
```

Members are the N×K cross product, ordered by `(group_target_index, group_position)`. A member
carries its group (`command_group_id`, `group_target_index`, `group_position`), all required and the
group a foreign key (#708: every request is a group's member; the group was also mirrored into
`metadata.group` before, which is gone). A member that ends without radiating reads an `end_reason` (`earlier_command_failed |
excluded_at_review | expired | aborted | not_sent | release_basis_changed`) and, for
`earlier_command_failed`, the triggering member id (`caused_by`).

## 3. Lifecycle

```
submit ──► approval_pending ──GO────────────────► queued ──► (members progress) ──► completed*
   │            │  ├─GO excluding S──► queued (S's members rejected "excluded at review")
   │            │  ├─send back───────► sent_back (members rejected; author clones into a new draft)
   │            │  └─NO-GO───────────► rejected (members rejected)
   └─(no second GO required)──────────► queued
queued / approval_pending ──abort──► aborted (not-started members canceled; started ones run on)
* completed is derived: every member terminal.
```

- **Submit** (one transaction, under `ActiveBasis.with_command_catalog`'s locked basis): re-resolve
  each target's basis (`ActiveBasis.for_target`), validate and create every member through the
  exact snapshot validation (`RequestValidation.validate_on_snapshot`), in chunks of 25 so each
  validation stays bounded; then either enqueue in stack order (no second GO) or leave members
  `approval_pending`. Read updates + lane kicks after commit.
  The submit carries the **preflight digest** it was shown; a changed basis or target set →
  `409 preflight_stale` (the UI re-runs preflight).
- **Decide** (approver, session actor only): `expected_review` = digest of the group + its last
  preflight. Not the requester (self-approval prohibited, as today). If `requested_approver_user_id`
  is set, only that user. One `command_approvals` row **per member** (bulk insert), so per-request
  audit and existing reads stay correct. Then enqueue all approved members per target lane in
  stack order. A note is required for exclusions, send back and NO-GO.
- **Members can't be decided individually**: `LifecyclePolicy` rejects `decide_request` for a
  request with a `command_group_id` (`:command_request_belongs_to_group`). The old per-request
  approval page shows the group link instead.
- **Stop on failure (per target)** (#31, no "continue" option in v1): when a member's release fails
  or its verification fails or times out, the target's remaining **not-yet-released** members are
  canceled (`member_failed` event; `end_reason: earlier_command_failed`, `caused_by`). Other
  targets continue. Fully sequential "verify k before k+1" is a gate, which is waves (#8, later).
- **Send back** (#31) closes the group (`sent_back`, members rejected). Compose clones it from
  `GET /command-groups/:id` (`M/commands/new?from=group:<id>`), and the new group records
  `sent_back_from` and shows the reviewer's note.

## 4. Two-person policy (#7) and O4 policy text

Pure module `Cadence.Commanding.CommandPolicy`, the single source for preflight, submit, Approve
and the O4 read:

```elixir
evaluate(%{commands: [binding], target_count: n, mission_policy: policy}) ::
  %{second_go_required: boolean, reasons: [reason]}
reason: %{key: :hazardous_command | :critical_command | :policy_hint, command_id, name} |
        %{key: :fleet_reach, targets: n, threshold: t}
# stable keys + facts; the UI words them (CommandFlow R05, Approve "why a second GO")
```

- Per command: `RequestValidation.approval_required?/4` (critical, hazardous, critical/hazardous
  significance, confirmation/approval policy hint). Same predicate as single requests today.
- Fleet reach: `n ≥ fleet_reach_threshold`. **10 targets** (DECISIONS #31).
  Mission-configurable later via settings, then Cedar (#2/#7). `policy_version` is stored on the group.
- Non-hazardous single-target commands need no second GO (#7).
- **O4** `GET /missions/:id/command-policies` → `{policies: [{key, title, sentence, parameters}]}`
  rendered from the same module (for example `fleet_reach`: "Requests reaching 10 or more
  spacecraft need a second operator's GO.").

## 5. Preflight (M18)

`POST /missions/:id/command-groups/preflight` with a **draft** (targets or query, stack, release)
and **no side effects**; also `GET /command-groups/:id/preflight` re-runs it for Approve (A2).

Each check: `{key, result: go | hold | no_go, sentence_facts, per_target: [{spacecraft_id, result,
reason}], evidence}`. The server computes facts; the UI writes the sentences. Checks the backend
can't compute are **absent**, never `go`.

| key | NO-GO when | HOLD when | Source |
| --- | --- | --- | --- |
| `identity` | a target has no SCID, no source endpoint, or commanding isn't enabled | — | spacecraft + source endpoints + spacecraft model bindings |
| `catalog` | a command isn't in a target's plan, an argument is invalid/out of range, or targets are on different revisions than the group basis | — | per-target `ActiveBasis.for_target` + exact preview |
| `size` | N, K or N×K over the bounds | — | config; `evidence: {max_targets, max_commands, max_members}` |
| `conflicts` | — | other requests are queued/approval-pending on the same lanes (count + ids) | queue |
| `contact` | — | a target has no booked contact before `expires_at` (or within 6 h) | passes (M7); `per_target[].next_contact: {station_code, aos, los} \| null` (C4 draws from it) |
| `two_person` | — | a second GO is required (with reasons) | `CommandPolicy` |
| `query_drift` (review only) | — | the query now resolves differently (joined/left, with names) | re-resolve `target_query` |

Plan impact and umbra margin are **omitted** (no plan coupling yet; #4). The result has a `digest`
(stable hash of inputs + facts) used by submit and decide.

## 6. Reads and composition with the uplink lifecycle

- `GET /command-groups?state&mine&awaiting_me&operation_id` (Approve queue Q: `awaiting_me` =
  approval_pending, not requested by me, and `requested_approver_user_id` is null or me).
  `operation_id` resolves an unclear submit (ux U20); a replayed submit with a known `operation_id`
  answers `409 duplicate_operation` with the existing group id.
- `GET /command-groups/:id` → group (every input Compose needs to clone it) + `events` + `targets`:
  `[{spacecraft_id, name, scid, stage, members: [{position, request_id, stage, end_reason,
  caused_by, verify_by}], last_event_at, blocked: {reason} | null}]`. A member's `stage` comes from
  the existing `Reads.Commands` status and verification state. `verify_by` is the verifier window
  end, for "verifier window open".
- **Progress** (Uplink h1 and pipeline): counts per derived stage per target:
  `queued_for_contact` (pending entry) → `radiating` (release_pending) → `executed` (released,
  verifier pending) → `verified` | `verify_failed` | `no_verifier` (released, not_required) |
  `indeterminate` (release_uncertain) | `canceled` | `excluded`. Plus a `blocked` flag on a pending
  head entry whose release keeps failing basis re-validation ("catalog revision changed since
  submit"), so it shows in **Needs you** instead of waiting silently.
- Fleet `commands` counts, the action queue (approvals awaiting me, failed) and `/counts` count
  **groups** for approvals ("3 groups await your GO", using the same `awaiting_me` rule) and
  members for queue sizes.
- Live: `invalidate commanding` (as today). Then the **uplink lifecycle channel**:
  `command_group:<id>`, which pushes the progress delta and new events (separate milestone).

## 7. Cancel and abort (M20)

- `Commanding.cancel_request(scope, mission, request_id, reason)` (new, control plane): allowed
  when the request is `validated | approval_pending | approved`, or `queued` **with its queue
  entry `pending`**. Request → `canceled`; entry → `canceled`; lane kicked (which unblocks a lane
  stuck behind a basis mismatch or an expired head). Refused once `release_pending`/`released`
  (`:command_request_already_started`); in-flight attempts keep the existing release-resolution path.
- `abort_group`: cancels every member that's still cancelable in one transaction, and returns
  `{canceled: n, already_started: [ids]}` ("ABORT AVAILABLE UNTIL EACH UPLINK STARTS"). Allowed to
  any operator who can operate the mission (#31). Abort is a safing action, so it's not two-person.
  A reason is required and audited (`aborted` event, `abort_reason`).
- **Expired** members (past `expires_at`, still pending) are canceled by a periodic sweep with
  reason `expired`. This fixes today's silent leftovers (`member_canceled` event).
- **Stuck lane head** (#31): a pending head entry whose basis no longer resolves (revision changed
  since submit) **fails closed**. The release path marks it `release_basis_changed`: the request
  becomes `canceled` with that reason, the queue entry `canceled`, and the lane moves on. This applies to
  all requests, grouped or not, and replaces the silent indefinite hold.

## 8. API surface (contracts in `docs/apogee/api/commanding.md`)

| Method | Path | Ask |
| --- | --- | --- |
| POST | `/command-groups/preflight` | M18 |
| POST | `/command-groups` `{draft, preflight_digest, operation_id}` | M16 |
| GET | `/command-groups`, `/command-groups/:id`, `/command-groups/:id/preflight` | M16 · M18 |
| POST | `/command-groups/:id/decision` `{kind: go | go_excluding | send_back | no_go, excluded, note, expected_review}` | M16 |
| POST | `/command-groups/:id/notes` `{note}` | M19 |
| POST | `/command-groups/:id/abort` `{note}` · `/command-requests/:id/cancel` | M20 |
| GET | `/command-policies` | O4 |

Writes are idempotent on a client `operation_id` (stored on the group / event), CSRF, session actor only.

## 9. Placement, migration, rollout

- `L/commanding/command_group.ex` (struct), `command_group_row.ex`, `group_store.ex` (Repo),
  `command_policy.ex` (pure), `L/control/commanding/group_submission.ex` (submit / decide / abort,
  following `WorkspaceSubmission`), `L/reads/command_groups.ex`, `L/reads/command_preflight.ex`.
  Web: `CadenceWeb.Console.CommandGroupController` + JSON. All in commanding / control / reads;
  no cross-context row access (`mix cadence.architecture.check`).
- Migrations: create `command_groups`, `command_group_events`; add the three nullable columns +
  index to `command_requests` (mission trigger fills `organization_id` like other mission tables).
  Existing requests are untouched (`command_group_id NULL`) and keep working as today.
- Build order: (1) model + policy + submit/decide for N×K, (2) preflight, (3) cancel/abort +
  expiry sweep, (4) reads/progress, (5) O4 and notes, (6) uplink channel.

## 10. Decisions (DECISIONS #31) and open items

1. Fleet-reach threshold: **10 targets**.
2. Abort: **any mission operator**, reason required, audited.
3. Stop on failure per target; **no "continue"** in v1.
4. Send back = **a new group** prefilled (`sent_back_from`).
5. Bounds N ≤ 1,000 / K ≤ 16 / N×K ≤ 5,000: OK **pending domain's lock-duration review**.
6. `decided_by` and the other actor fields: fixed in `d8de442f` (#30).
7. Stuck lane head: fail closed with `release_basis_changed` (in M20).
