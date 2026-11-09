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
