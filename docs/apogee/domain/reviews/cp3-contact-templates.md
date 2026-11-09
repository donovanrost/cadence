# Review · CP3 contact templates (42d62c5a, with fd0ca7bc)

Reviewer: **domain** (2026-11-09). Author: api. Line numbers are from the working tree, which
includes fd0ca7bc (the configurable cap).

Status: **changes requested**. Finding 1 blocks the shared tree's architecture check. Findings 2
and 3 can lose or duplicate demand.

## Must fix

1. **The architecture check fails** with 2 new cross-context row edges:
   `contact_planning/template_supersession.ex` reads `ContactPlanRequirementRefRow` and
   `ContactPlanRow` directly (`planned/2`, around lines 76–92).
   - Fix: move "requirements taken up by a plan in pending_approval or later" into
     `ContactPlans`, which owns those rows, and do it together with finding 3.
2. **A fleet start from the ops console never supersedes, so the same slot is planned twice.**
   - Only `Control.Scheduling.create_draft` (scheduling.ex:321) calls `supersede_stale/3`. The
     ops-console path (`ops_console/actions/fleet_planning.ex`, then
     `FleetPlanningStarts.preview`/`create`) materializes with `supersede: false`
     (fleet_planning_starts.ex:158).
   - Scenario: v1 materialized, then v2 saved, then an operator starts a run from the console.
     The reviewed inputs list v1's active future requirements, and v2 generates the same
     (occurrence, spacecraft) slots. Your own test's "8 active" shows both survive.
   - Preferred fix: keep preview read-only. Have `FleetStartInputs` leave out requirements that
     `TemplateSupersession.cause/3` would cancel, then supersede inside `claim` after
     materializing. Minimum fix: call `supersede_stale` from `FleetPlanningStarts` so every
     caller gets it.
3. **Supersession can cancel a requirement that a plan takes up between the check and the
   cancel.**
   - `supersede/4` reads the planned set in one unlocked query, then `ContactRequirements.cancel`
     runs one transaction per requirement and never re-checks plan references.
     `ContactPlans.submit` locks only the plan row.
   - Scenario: draft P references R, so R isn't "planned". P is submitted (pending_approval),
     then supersession cancels R. Approval then fails safe with
     `contact_plan_requirement_not_active`, but the plan is stuck and needs a replan, which the
     design says doesn't happen to planned requirements.
   - Fix: re-check inside the cancel transaction after locking the requirement, joining the refs
     to their plans `FOR SHARE OF plan` (submit holds `FOR UPDATE` on the plan, so they
     serialize). Add a test for the "planned requirement is kept" branch; none exists.
4. **`supersede_stale` cancels before anything has materialized.** scheduling.ex runs it before
   the `with`, so it also runs when preview or create fails.
   - Scenario: v2 widens the target past the fan-out cap. v1's future requirements get canceled
     ("template_versioned"), then materialization fails with the occurrence limit. Coverage is
     lost silently, which contradicts "superseded when a newer version materializes".
   - Fix: supersede only after the current version materializes (this falls out of the finding 2
     fix).

## Should fix

5. **The fleet-start review hash can change on its own.** `existing_occurrences/2`
   (fleet_start_inputs.ex:185) orders by `occurrence_at` only. With fan-out, several rows share
   one occurrence, so their order is unspecified and the hash differs between preview and
   create, giving spurious `fleet_planning_review_changed`.
   - Fix: add `asc: r.spacecraft_id`.
   - Also sort the resolved profile targets by `spacecraft_id`, not `display_name`, before
     hashing, so a rename doesn't change the hash.
6. **Preview and summary counts are wrong for long windows and dense cadences.**
   `PlanningTemplates.effect/5` uses `preview_occurrences`, which applies catch-up bounds:
   - the 7-day lookback means a 31-day preview counts only the last 7 days, then divides by 31
     for contacts per day;
   - the 100-occurrence cap means a 10-minute cadence shows at most 100.

   Fix: use `RequirementSchedule.occurrences_between` with an explicit limit.
7. **Supersession is O(templates × all active requirements) inside the draft request.** `stale/3`
   lists every active requirement for each template. At fd0ca7bc's sizing (about 42k generated
   requirements) with tens of templates, that's millions of rows per draft.
   - Fix: list once and group by `metadata.generation.contact_requirement_template_id`, or
     filter in SQL (jsonb plus `earliest_start > now`).
8. **Reviewed start gap.** `reviewed_materialization?/2` accepts `{:created, nil}` for any
   spacecraft, and targets are re-resolved inside the claim without locking spacecraft rows. A
   pin change in between can generate a requirement for a spacecraft that wasn't reviewed.
   - Fix: require `occurrence.spacecraft_id in reviewed_ids`, or pass the reviewed targets
     into `materialize`.

## Low / note

9. **`down/0` of 20261110100000 fails once fan-out data exists:**
   - the old unique index can't be recreated;
   - `spacecraft_id SET NOT NULL` fails for multi-target versions.

   Collapse that data explicitly, or make the migration irreversible.
10. **Migration locking is fine at current sizes.** If the tables grow, add the
    `mission_spacecraft` FK `NOT VALID`, then `VALIDATE` it.
11. **Decision needed: duplicate demand when the old version's requirement is already planned.**
    v1's requirement is kept (it's planned) and v2 still generates the same slot, so the slot is
    demanded twice. Either skip generating slots that a kept requirement covers, or document that
    the planner dedupes them.
12. **The supersession cause is free text only** (`lifecycle_reason`). If the UI filters by
    cause, store it as a structured field.

## Checked and fine

- **Migration data safety:**
  - existing FKs guarantee the backfills and the `SET NOT NULL`;
  - the new unique index is a superset of the old columns;
  - JSON wrapping and name length are compatible.
- **Fan-out cap:** in `materialize/6` it's enforced before any write, with a tagged error. The
  fleet-start inputs enforce the summed cap, but under `fleet_planning_occurrence_limit_exceeded`,
  which the console returns as a generic 422. Consider mapping it.
- **"Future" uses one `now` per call**, so started windows are untouched.
- **Profile targets** use the effective pin (any version). Spacecraft have no archived state.
- **Every new query is scoped by org and mission.** The routes sit behind `MissionScope`; writes
  are admin, materialize is operator, cancel is member.
- **The legacy `spacecraft_id`** is derived from the target, not taken from input.

## Re-review · 502d183c, 86fa159c (2026-11-09)

The touched tests pass: targeted_templates 9/9 and template_supersession 4/4.
`template_supersession.ex` no longer reads plan rows; the uptake query lives in `ContactPlans`.
The architecture check couldn't complete at review time, because untracked point-search files
were mid-write.

| # | Verdict |
| --- | --- |
| 1, 2, 4, 5, 6, 7, 8, 9 | Fixed. For 4, the cancels join the claim transaction and roll back with it, but no test covers that rollback. |
| 3 | **Partially fixed.** It works when the submit commits first; the concurrent case is still open (new A). |
| 11, 12 | Decided or noted in contact-templates.md. |
| U27 | **Partially correct** (new C, D, F). |

### New, ranked

- **A. High: the FOR SHARE re-check doesn't wait for an uncommitted submit.**
  `requirements_taken_up/4` (contact_plans.ex:120) filters `plan.lifecycle_state in @taken_up`
  in the locking query's WHERE.
  - Under READ COMMITTED, a plan whose submit is in flight is still `draft` in the statement
    snapshot. It is never a lock candidate, so supersession doesn't wait for it.
  - Submit locks only the plan row.
  - Result: R is cancelled, then the submit commits, and approval later fails with
    `contact_plan_requirement_not_active`.
  - Fix: share-lock every plan referencing R with no state filter, filter the states in Elixir
    afterwards, and do it before locking R (this also fixes B).
- **B. Medium: lock-order inversion with approval.**
  - Approval locks the plan `FOR UPDATE`, then the requirements.
  - Supersession locks R `FOR UPDATE`, then the plans `FOR SHARE`.
  - The claim locks R `FOR SHARE` (fleet_start_inputs.ex:124), then the plans.

  The result is a deadlock, raised as `Postgrex.Error`, which `cancel_unless_taken_up` doesn't
  catch: it becomes a 500 from fleet start, or a worker exit in `materialize_active`. Use one
  order everywhere (plans first). Also consider a mission-level lock for concurrent starts.
- **C. High: U27's read rule is wider than the supersession rule.** `overtaken?`
  (plan_supersession.ex:143) uses `TemplateSupersession.cause/3` with no "future" or
  active-template filter. Supersession only cancels future requirements of active templates.
  - Scenario: a template is bumped at noon. The re-drafted day still references v1's morning
    requirements (kept because they aren't future), so it reads `superseded`, and every submit
    returns 409.
  - Fix: apply the same future and active-template conditions in `overtaken?`.
- **D. Medium: the 409 is unlocked and enforced on one surface only.**
  - `current/4` runs before the submit transaction (scheduling.ex:108-129), so it can race.
  - The ops console (`plan_decisions.ex:13`) and fleet automation (`fleet_automation.ex:246`)
    submit without checking.

  Move the check into `submit_transaction` (and approval) under the plan lock, or document it as
  a console-only hint.
- **E. Medium: supersession can cancel beyond what v2 materialized.** It cancels every future
  stale requirement of the template, while v2 only covered the horizon and catch-up window.
  Requirements past it are left with no replacement. Limit cancels to the slots, or at least the
  window, that v2 covered.
- **F. Medium (cost): the read-time check in `ContactPlanOverview.list`** (up to 100 plans) does
  per-plan, per-ref requirement fetches plus template and target resolution. That's on the order
  of 10^5 or more queries per list at fleet scale. Batch the fetches, and cache templates and
  targets per call.
- **G. Low:**
  - the review hash depends on wall-clock time (`without_superseded` uses `utc_now`), so a
    requirement that starts between preview and create flips the hash;
  - an inner `Repo.rollback` in `ContactRequirements.cancel` poisons the claim transaction, but
    the warning path continues as if the start succeeded;
  - a `pending_approval` plan reads as superseded through `except_plan_id`, so the console
    approve returns 409 while the ops console approves.

## Second re-review · 21d37913 (2026-11-09)

A–F are addressed, and I spot-checked A and C in the code:

- `requirements_taken_up` share-locks every referencing plan with no state filter in the
  query, then filters in Elixir. Plans are locked before requirements everywhere.
- `stale_template?` applies the supersession rule: only a future requirement of an active
  template.

G1 (the review hash depends on wall-clock time) is still open and low; it's fine to defer.
**Status: approved.**

**G1 closed (4b6eeb93).** `FleetStartInputs.load` takes `as_of`, which is part of the hashed
evidence. The claim reloads at that `as_of`, and supersession uses it as `now`. An `as_of` older
than 15 minutes, or in the future, returns `fleet_planning_review_changed`. Every CP3 finding is
now closed.
