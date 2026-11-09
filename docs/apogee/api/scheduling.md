# Scheduling endpoints (S2–S6, S8)

Owner: **api** (DECISIONS #26). Consumer: **lead** (K1 Plan, K2 Re-plan). S1 passes and S10 push
are api-ops'. Base: `/api/console/v1/missions/:mission_id`. Conventions: [README.md](README.md).

Status: decisions agreed (DECISIONS #27, #28). **Implemented:** S6 list, plan detail with S2 demand,
S3 drafts (start/read/continue) and S5 submit/execute with acknowledged exceptions. Planning setup, day demand
and S4 edits/alternatives are also in. **Next:** S8 re-plan.

## 1. What the domain actually does (survey)

| Need | Domain today | Consequence |
| --- | --- | --- |
| Draft a day (S3) | `FleetPlanningStarts.preview/create` (evidence pattern) creates a *queued* fleet run; `FleetPlanner.run` executes it **synchronously**: provider searches per requirement (slow, real I/O), optimize, then materialize a candidate `ContactPlan` (draft). | Must run outside the request; no progress events exist. |
| Edit the draft (S4) | No add/remove inside a run. The only edit is `version_plan(plan, expected_version, selected_snapshot_ids/locked_snapshot_ids)` on the **candidate plan**. Only snapshots found by the run's searches are eligible. Coverage, conflicts and unsatisfied are recomputed and **persisted** as a new plan version (no dry run). | "Add a pass" = pick from the run's unselected opportunities. Each edit is a plan version (gives r41 → r42 for free). |
| Alternatives + effect (S4) | Nothing. Pure building block: `RequirementEvaluator.evaluate_selection/3`. | I compute effects in the read, with no persistence. |
| Demand (S2) | Pure evaluator per **requirement version** (spacecraft + window); persisted coverage on plan versions and run results. | Group by spacecraft for the "2 / 3" view. |
| Submit (S5) | `submit_plan` (draft → pending_approval), then `approve` (**organization_admin only**; requires **no conflicts, no unsatisfied requirements**, ≥ 1 selection), then `execute_approved_plan` (books with providers **synchronously**; idempotent per item). | A partial plan can't be submitted; members can only request approval. |
| Plans list (S6) | `list_plans` is unbounded. | Filter by day/state in the read and cap at 100. |
| Re-plan (S8) | A repair creates a **successor run** with a **new candidate plan** (not a version), locking committed passes. There is no diff and no apply. | I compute moved/dropped by diffing selections; apply = submit → approve → execute on the new plan. |

## 2. Decisions needed (lead + director)

1. **Async execution for S3 (draft) and S5/S8 (execute).** Proposal: run them under a supervised
   task (`Task.Supervisor`) in the web node. Return `202` with the run or plan id, and push
   `scheduling_progress {kind: draft|execute, id, phase, state, at}` on `mission:<id>`. The run and
   plan rows are the durable state, so a client that reconnects reads them. If the node dies
   mid-run, the run stays `running`/the plan stays `executing`. "Continue" recovers a run
   (`FleetRunActions :continue`), and execution items are idempotent, so re-execute is safe.
   **No new tables or migrations.** The alternative (a durable job type + journal table like
   the workspace's) is more robust, but it needs domain work and a migration. *Recommend the
   supervised task for v1.*
2. **Idempotency (`operation_id`).** Draft creation is already guarded by the evidence pattern
   (preview → create with the same evidence sha), and execution is idempotent per item. Proposal:
   accept `operation_id` and keep an in-memory node-local map (operation → result) for replays
   within 15 min. No durable journal in v1. *Recommend.*
3. **Approval (ux Q9).** The domain requires an org admin to approve, and approval requires a
   fully satisfied, conflict-free plan. Proposal for "Submit N requests": an org admin's submit
   does submit + approve + execute in one action; a member's submit moves the plan to
   `pending_approval` and returns `state: pending_approval` (the UI shows "waiting for an admin").
   Unsatisfied or conflicting drafts return `422 plan_not_ready` with the coverage, so K1 can show
   what blocks submit. Relaxing either rule is a domain/director call.
4. **Policy prerequisite.** Drafting needs an active fleet planning policy and at least one active
   requirement in the window. Missing either → `422 planning_not_set_up` (`details.missing`), and
   readiness should surface it. There's no console setup for policies yet. Is that a Setup gap
   to schedule?

## 3. Proposed endpoints

- **S6** `GET /contact-plans?day=YYYY-MM-DD&state=` → `{plans: [{id, version, state, day_start, day_end,
  author, counts: {selected, conflicts, unsatisfied}, updated_at}]}` (≤ 100, newest first).
- **S3** `POST /contact-plans/drafts {day, operation_id}` → `202 {run_id, state: queued}`. It runs
  preview + create + run in the task. `GET /contact-plans/drafts/:run_id` → `{run: {id, state, phase,
  horizon, failure}, plan: {id, version, state} | null, totals: {passes, minutes, rule_met, rule_total,
  conflicts}, passes: [{snapshot_id, spacecraft_id, station, starts_at, ends_at, disposition, score}]}`.
- **S2** `GET /demand?plan_id=&version=` (or `?run_id=`) → per spacecraft `{spacecraft_id, rule_met,
  contacts: {have, need}, reasons: [...]}` + `rules: [{requirement_id, version, text, source}]`. The
  `day=` form reads the latest plan for that day.
- **S4** `POST /contact-plans/:plan_id/versions {expected_version, add: [snapshot_id], remove:
  [snapshot_id]}` → the new version + totals + per-spacecraft effect.
  `GET /contact-plans/:plan_id/alternatives?spacecraft_id=` → unselected opportunities of the
  plan's runs for that spacecraft, each with `effect: {rule_met_after, contacts_after,
  clashes_with: [snapshot_id]}`.
- **S5** `POST /contact-plans/:plan_id/submit {expected_version, reason, operation_id}` → as in
  §2.3; when executing, `202 {state: executing}` and the per-item state arrives via S1/S10.
- **S8** `POST /contact-plans/:plan_id/repairs {from, to, operation_id}` → `202 {run_id}`;
  `GET /contact-plans/repairs/:run_id` → `{source_plan, plan (new), moved: [...], dropped: [...],
  added: [...], totals}`; apply = S5 submit on the new plan.

## 4. Implemented contracts

### Live: `scheduling_progress` on `mission:<id>`

`{kind: "draft" | "execute", id, state: "running" | "finished" | "failed", reason, at}`, sent when
off-request work starts and ends. It also emits `invalidate` with `contacts`. Treat it as a hint and
refetch the read. The read is the truth.

### `GET /contact-plans?day=YYYY-MM-DD&state=` (S6)

`{plans: [{id, version, state, window: {from, to}, author, counts: {passes, minutes, conflicts,
unsatisfied}, ready_to_approve, updated_at}]}`, newest first, capped at 100. `window` spans the
selected passes (`null` for an empty plan); `day` matches the window's start date (UTC). `state` is
one of `draft, pending_approval, approved, executing, partially_reserved, reserved, failed,
canceled, superseded`.

### `GET /contact-plans/:plan_id[?version=n]`

The list row, plus:
- `passes: [{snapshot_id, spacecraft_id, station, starts_at, ends_at, synthetic, locked}]`
- `demand: {rule_met, rule_total, spacecraft: [{spacecraft_id, rule_met, contacts: {have, need},
  reasons: [code]}], rules: [{requirement_id, version, spacecraft_id, text, source: "requirement",
  window}]}` (S2, from the version's persisted coverage)
- `unmet: [{requirement_id, requirement_version, spacecraft_id, why: [code]}]`: what an approver
  must acknowledge (DECISIONS #28)
- `conflicts: [{code, spacecraft_id, snapshot_ids}]`: overlapping passes for one spacecraft, which
  always block approval

`station` is the provider's ground-station ref. Errors: `404 plan_not_found`.

### `POST /contact-plans/drafts` (S3)

Body `{day: "YYYY-MM-DD", operation_id}`. It plans 00:00–24:00 UTC of that day with the mission's
active fleet planning policy and the active requirements (including recurring templates), then
runs the plan **off the request**.

- `202 {run_id, outcome: "created" | "replayed", state}`. The same `operation_id` returns the same
  run (persisted, so it works on any node).
- `422 planning_not_set_up` with `details.missing`: `["fleet_planning_policy"]` or
  `["contact_requirements"]`. `422 horizon_exceeds_policy`. `409 inputs_changed` (retry).

### `GET /contact-plans/drafts/:run_id`

`{run: {id, state, phase, horizon: {from, to}, failure, started_at, updated_at}, plan: <plan detail>
| null}`.

- `state`: `queued | running | completed | partial | failed | canceled | interrupted`.
  **`interrupted`** means the run is queued/running but nothing is executing it (no session holds
  its lock, checked cluster-wide), so offer Continue. A queued run gets 60 s to start before it
  counts as interrupted.
- `plan` is the candidate plan (draft) once the run materializes it.
- `404 draft_not_found`.

### `POST /contact-plans/drafts/:run_id/continue`

Resumes an interrupted run off the request and returns `202 {run_id, state: "running"}`.
`409 draft_not_interrupted` otherwise.

### `POST /contact-plans/:plan_id/submit` (S5)

Body `{expected_version, operation_id, reason?, acknowledgements?: [{requirement_id,
requirement_version?, reason}]}`. `reason` defaults to a console note; acknowledgement reasons are
10–2000 characters. `requirement_version` is accepted and ignored, because the server pins the
version from the plan.

| Caller | What happens | Response |
| --- | --- | --- |
| member | draft → `pending_approval` (an admin reviews it) | `200 {plan_id, state: "pending_approval", outcome: "pending_approval"}` |
| org admin | submit (if draft) → approve with the acknowledgements → execute **off the request** | `202 {plan_id, state: "executing", outcome: "executing"}`, then `scheduling_progress {kind: "execute"}` |
| replay (same `operation_id` on this plan) | nothing | `200 {plan_id, state, outcome: "replayed"}` |

An admin calling submit on a member's `pending_approval` plan is the review: it approves and
executes. Per-item booking states show up in S1 passes and the plan detail.

Errors:
- `422 plan_not_ready`: unmet requirements without acknowledgements, any conflict, or an empty plan.
  `details: {unmet, conflicts}`, as in the plan detail.
- `422 acknowledgements_required` (`details.missing: [requirement_id]`): some, not all, unmet
  requirements were acknowledged.
- `422 invalid_params`: body shape, a reason outside 10–2000, or an acknowledgement for a
  requirement that isn't unmet.
- `409 plan_changed` (stale `expected_version`), `409 plan_not_submittable`,
  `409 operation_conflict` (operation id used on another plan), `404 plan_not_found`.

Acknowledgements are stored on the approval (`approval.exceptions`) with its actor and time
(DECISIONS #28).

### `POST /contact-plans/:plan_id/execute`

Re-executes an approved plan whose execution was **interrupted**, or that was approved and never
started. Items are idempotent, so booked passes aren't rebooked. Returns `202 {plan_id, state:
"executing"}`, or `409 plan_not_resumable`.

### Plan state `interrupted`

List rows and plan detail report `state: "interrupted"` for a plan whose lifecycle is `executing`
when no session holds its execution lock (cluster-wide). Offer Execute.

### `GET /contact-plans/setup`

`{setup: {ready, missing: ["fleet_planning_policy" | "contact_requirements"], policy: {id, version} |
null, requirements: n, templates: n}}`. `ready` means drafting can start (an active policy plus at
least one active requirement or template). Readiness reports the same condition as finding
`planning_not_set_up` (fix kind `contact_planning`, which has no area tile).

### `GET /contact-plans/demand?day=YYYY-MM-DD` (S2, no plan needed)

`{day, spacecraft_with_rules, contacts_needed, without_rule, spacecraft_total}`. It counts active
requirements whose window overlaps the UTC day, plus template occurrences due that day (previewed;
nothing is materialized). Each one contributes its `contact_count`.

### `POST /contact-plans/:plan_id/versions` (S4 edit)

Body `{expected_version, add?: [snapshot_id], remove?: [snapshot_id]}`. Creates the next plan
version with the selection changed, and the domain recomputes coverage, conflicts and unmet. It
returns the new plan detail. Only passes the plan's planning runs found can be added (pick them
from alternatives). Editing a plan in review returns it to draft (the domain's rule). Errors:
`409 plan_changed`, `404 plan_not_found`, `422 plan_not_editable` (`details.reason` is the domain
code, e.g. a snapshot that doesn't belong to the plan's runs), `422 invalid_params`.

### `GET /contact-plans/:plan_id/alternatives?spacecraft_id=` (S4)

`{plan_id, version, spacecraft_id, rule_met, contacts, alternatives: [{snapshot_id,
requirement_id, station, starts_at, ends_at, synthetic, effect: {rule_met_after, contacts_after,
clashes_with: [snapshot_id]}}]}`: eligible opportunities the plan's runs found for that
spacecraft but didn't select, oldest first. Effects come from the same requirement evaluator the
plan uses, and nothing is written. The "closes gap to 6h10" phrasing isn't computed (the rules
have no gap measure); `rule_met_after` and `clashes_with` are.
