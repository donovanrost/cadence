# Dashboard Feature Maturity Handoff

This document preserves the active goal context before starting a fresh session.
The goal remains: **bring the dashboard feature to full maturity**. This is not
done yet. The current codebase has made substantial progress, but several
capability areas are still intentionally marked partial in the maturity
checklist.

## Authoritative Context

Start the next session from these files:

- `docs/dashboard-feature-maturity-checklist.md` - current maturity ledger by
  product area.
- `docs/dashboards-visualization-engine-design.md` - long-term target
  architecture and evidence log.
- `docs/telemetry-data-management-design.md` - data-management semantics,
  correction/import/replay workflows, source watermarks, and deduplication
  thinking.
- `docs/events-design.md` - event spine design context, if present in the
  checkout.
- `apps/cadence_web/test/cadence_web/live/ops_dashboard_live_test.exs` - still
  the largest serial dashboard LiveView proof bucket.
- `apps/cadence_web/test/cadence_web/live/ops_dashboard_show_live/` -
  increasingly the preferred home for smaller dashboard-specific tests.

Treat the live checkout as authoritative. There are many modified files and a
large accumulated feature diff. Do not assume any memory summary is current
without inspecting the files and running focused tests.

## What Full Maturity Means

The dashboard feature is mature when these criteria are true and verified:

1. **Document and lifecycle model are stable.**
   Dashboard documents, versions, drafts, publish/revert/archive/restore flows,
   lifecycle events, conflict handling, and operator routing are first-class and
   no longer prototype-shaped.

2. **Engine contract owns runtime resolution.**
   Dashboard rendering goes through typed planning, source execution, frame
   materialization, widget-frame validation, degradation/warning contracts, and
   presenter paths. New source or widget families should plug into this contract
   instead of bypassing it.

3. **Runtime contexts are explicit and durable.**
   Time, scope, data, replay, source-binding, and limit contexts must round-trip
   through URL params, document defaults, action payloads, data links, copied
   URLs, evidence panels, cache keys, and operator handoffs.

4. **Logical sources are backed by real source contracts.**
   Telemetry, limits, events, and operational observables must expose capability
   metadata, product compatibility, freshness/watermark/source-health posture,
   timeout/circuit behavior, warnings, evidence, and DataLinks.

5. **TSDB paths are operationally credible.**
   Managed QuestDB and BYO TSDB flows must cover schema/write/read behavior,
   source binding, readiness/probe diagnostics, credential material policy,
   source health, source watermarks, deployment-run visibility, retry/requeue,
   and isolation expectations. Long-term physical isolation by organization or
   mission is still a design direction, not fully implemented.

6. **Events are a durable source of truth.**
   Runtime facts, source health, source watermark movement, data-management
   workflows, limit/catalog/source/dashboard changes, contact/link/RF facts, and
   operator decisions should be modeled as inspectable events or intervals where
   dashboards depend on them.

7. **Operational observables are not dictionary-bound.**
   Cadence-produced values such as connection state, antenna pointing state,
   transport bit rate, RF lock/frame sync, RF metrics, command queue depth, and
   ingress latency must resolve through operational-observable source contracts,
   not telemetry dictionary assumptions.

8. **Scope is product-general, not spacecraft-only.**
   Mission, spacecraft, contact, ground station, source endpoint, transport,
   link, and multi-entity scopes should validate correctly, fail closed when
   unsupported, preserve non-primary row identity, and keep DataLinks/evidence
   tied to the actual resource.

9. **Investigation workflows are guided and auditable.**
   Historical request/import/backfill/replay/comparison/correction/retry flows
   should preserve request groups, item identity, dashboard runtime context,
   job state, action outcomes, policy reasons, and latest-action evidence.

10. **Browser coverage proves wiring, not every permutation.**
    Full-stack LiveView/browser tests should prove user-visible contracts.
    Permutations belong in async engine/source/presenter/component tests where
    possible.

11. **The test suite remains usable.**
    The feature is not mature if every slice requires a 15-minute feedback loop.
    Test structure must keep focused local verification practical while
    preserving `mix precommit` as the final gate.

12. **Docs and implementation stay aligned.**
    The design docs are long-term vision documents, but the maturity checklist
    must continue to distinguish complete, partial, and future work accurately.

## Current Maturity Snapshot

Current status from `docs/dashboard-feature-maturity-checklist.md`:

- **Complete; monitor:** document model, engine contract, source registry/logical
  source contracts, managed QuestDB path, runtime cache/invalidation.
- **Partial:** runtime contexts, BYO TSDB path, data-management semantics,
  operational event dependency, limits over time, replay workflow, scope product
  surface, operational observables, widget coverage, DataLinks/evidence,
  investigation workflows, browser/UI verification.
- **Punted intentionally:** dashboard governance and permissions. There is no
  real RBAC model yet; continue using `todo(authz)` comments where appropriate.

Recent implemented/proven work includes:

- Managed QuestDB provisioning/deployment-run visibility, failed-run retry, and
  stuck-run requeue.
- BYO credential material resolution through env-profile and external
  secret-manager paths, with redacted audit events.
- Adapter capability discovery/materialization from probe results.
- Classified QuestDB probe diagnostics and operator remediation metadata.
- Dashboard context propagation through request, stage, correction, retry,
  recovery, stale/missing replacement inspection, and latest-action evidence.
- Replacement recovery controls for missing, failed, stale, requeue, and mixed
  recovery action queues.
- DataLink/evidence expansion across dashboard lifecycle, comparison review,
  workflow, source health, source watermark, operational-event, and
  operational-observable paths.
- Runtime context rail and related UI proof.
- Initial test-suite routing improvements in the root `mix test` alias so
  root-level `mix test apps/<child>/...` paths run only the owning child app.

## Testing State

The test suite is now a major feature-maturity concern.

Current evidence from this session:

- `mix test apps/cadence_web/test/cadence_web/live/ops_dashboard_show_live/historical_workflow_replacement_recovery_live_test.exs`
  passed: 2 tests in about 1 second.
- `mix test apps/cadence_web/test/cadence_web/live/ops_dashboard_live_test.exs`
  passed after the split: 117 tests in about 44.8 seconds.
- Before the split, the same monolithic file passed as 119 tests in about 47.2
  seconds.
- A full `mix precommit` before the split passed:
  - `cadence`: 1261 tests
  - `cadence_simulator`: 66 tests
  - `cadence_web`: 1663 tests in about 712.7 seconds
- After the split, focused tests passed, and the `cadence` child suite passed
  independently with 1261 tests.
- Full `mix precommit` was attempted again but did not finish cleanly before
  this handoff. Two attempts failed in unrelated `cadence` tests that passed
  when rerun in isolation:
  - `Cadence.Persistence.PersistTelemetryIngressTest` failed once because
    `Cadence.Repo` was not found.
  - `Cadence.Reads.MissionEventsTest` failed once with a runtime coordinator
    timeout.
- A final `mix precommit` attempt was running in `cadence_web` when the session
  was interrupted. The background `mix precommit` and child `mix test` processes
  were terminated intentionally before writing this handoff.

Do not claim the post-split full project gate is green until a new session runs
and completes `mix precommit`.

## Test-Suite Split Started

The first concrete split has been made:

- New file:
  `apps/cadence_web/test/cadence_web/live/ops_dashboard_show_live/historical_workflow_replacement_recovery_live_test.exs`
- Moved out of:
  `apps/cadence_web/test/cadence_web/live/ops_dashboard_live_test.exs`
- Coverage moved:
  - stale replacement inspect/requeue browser proof
  - mixed missing/failed/stale replacement recovery action queue browser proof

This is a model for future test cleanup:

- Keep one full-stack proof for product wiring.
- Move branch permutations into async command/presenter/component tests.
- Create workflow-specific LiveView files instead of growing
  `ops_dashboard_live_test.exs`.
- Preserve focused line/path test commands in docs or final handoffs.

## Current Worktree Warning

The worktree is very dirty. Many changes are part of the dashboard maturity
effort, and some may predate the latest slice. Do not revert broad changes.
Before editing, run:

```sh
git status --short
git diff --stat
```

Then inspect only the files relevant to the next slice.

New or recently relevant untracked files include:

- `apps/cadence/lib/cadence/dashboards/managed_questdb_provisioning_runs.ex`
- `apps/cadence/lib/cadence/dashboards/source_credentials/external_secret_backend.ex`
- `apps/cadence/lib/cadence/dashboards/tsdb_deployment_status.ex`
- `apps/cadence_web/lib/cadence_web/components/ops_context_rail.ex`
- `apps/cadence_web/lib/cadence_web/live/ops_dashboard_show_live/context_rail_sections.ex`
- `apps/cadence_web/lib/cadence_web/live/ops_dashboard_show_live/runtime_resolve_task.ex`
- `apps/cadence_web/test/cadence_web/components/ops_context_rail_test.exs`
- `apps/cadence_web/test/cadence_web/live/ops_dashboard_show_live/historical_workflow_replacement_recovery_live_test.exs`
- `apps/cadence_web/test/cadence_web/live/ops_dashboard_show_live/runtime_resolve_task_test.exs`

## Recommended Next Session Start

1. Confirm no leftover test processes:

   ```sh
   pgrep -fl "mix precommit|mix test|dashboard_viewport_smoke"
   ```

2. Inspect the current worktree:

   ```sh
   git status --short
   git diff --stat
   ```

3. Verify the split still passes:

   ```sh
   mix test apps/cadence_web/test/cadence_web/live/ops_dashboard_show_live/historical_workflow_replacement_recovery_live_test.exs
   mix test apps/cadence_web/test/cadence_web/live/ops_dashboard_live_test.exs
   ```

4. Run `mix precommit`. If it fails in unrelated `cadence` runtime tests, rerun
   the exact failing file/line once before changing code. If the same failure
   repeats, treat runtime lifecycle stability as the next slice.

5. Continue the test-suite maturity slice. Good next candidates:
   - move historical workflow request/stage/retry browser proofs out of
     `ops_dashboard_live_test.exs`;
   - split runtime invalidation browser proofs by source family;
   - move widget editing/lifecycle browser proofs into workflow-specific files;
   - keep the large monolithic file shrinking until focused dashboard work no
     longer requires a 45-second local run.

## Remaining Product Work After Test Health

Once the feedback loop is back under control, continue toward maturity in this
rough order:

1. Harden BYO and managed TSDB operations beyond first QuestDB paths:
   deployment isolation, probe policy, secret-manager production integration,
   and tenant/mission physical isolation planning.
2. Continue event-spine work for runtime/link/RF/source-watermark intervals so
   dashboard evidence points to durable facts instead of process snapshots.
3. Broaden replay and limit-over-time workflows, including replay-preserving
   operator handoffs.
4. Keep expanding operational observables where they replace telemetry-dictionary
   assumptions.
5. Finish data-management workflows around correction/import/replay policy,
   deduplication semantics, and audit trails.

Do not mark the dashboard maturity goal complete until the checklist no longer
has material partial areas, `mix precommit` passes from a clean start, and the
docs accurately distinguish future optional expansion from required maturity
work.
