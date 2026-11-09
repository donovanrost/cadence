# Scheduling endpoints (S2–S6, S8)

Owner: **api** (DECISIONS #26). Consumer: **lead** (K1 Plan, K2 Re-plan). S1 passes and S10 push
are api-ops'. Base: `/api/console/v1/missions/:mission_id`. Conventions: [README.md](README.md).

Status: **design for agreement** (2026-11-09). The reads (S2, S6, S3 read) are being built now.
The async actions wait for the decisions in §2.

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
