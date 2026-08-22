# Stage 5 Fleet Planning and Automation Implementation Plan

**Status:** implemented

**Goal:** Add explainable, mission-scale scheduling and guarded automation over
provider-owned opportunities while preserving the exact Stage 3 reservation and
Stage 4 Plan approval boundaries.

**Design source:**
[Stage 5 Fleet Planning and Automation](../specs/2026-07-16-contact-scheduling-stage-5-fleet-planning-and-automation-design.md)

**Implementation record:**
[Stage 5 Fleet Planning and Automation Implementation Record](2026-07-17-contact-scheduling-stage-5-implementation-record.md)

## Locked Implementation Order

1. Recurring Requirement Templates and idempotent occurrences.
2. Versioned Fleet Planning Policy and approval.
3. Durable Fleet Planning Runs, exact inputs, and phase checkpoints.
4. Pure deterministic optimizer and decision evidence.
5. Stage 4 search composition and candidate Plan materialization.
6. Automation Grants, bounded execution, and repair planning.
7. Authenticated fleet planning workspace.
8. Simulator fleet/chaos proof, migrations, documentation, and final gates.

Each task preserves direct booking, Stage 4 manual planning, provider-owned
ephemeris, immutable Plan approval, reconciliation, and ordinary TCP/CCSDS
telemetry.

## Task 1: Requirement Templates

Create migrations, domain structs, persistence rows, and an authorized context
for:

- stable `contact_requirement_templates`
- immutable `contact_requirement_template_versions`
- idempotent `contact_requirement_occurrences`

Implement create, version, activate, pause, close, occurrence calculation, and
bounded materialization. Generated Contact Requirements record template
provenance in bounded metadata and use an exact unique occurrence key.

Focused proof covers immutable history, stale edits, schedule validation,
cross-organization failure, concurrent materialization, catch-up bounds, and
exactly-once Requirement creation.

## Task 2: Fleet Planning Policy

Create stable/version policy tables with exact current and active-version
foreign keys, content hashes, normalized documents, and approval evidence.

Implement draft versioning, validation, organization-admin approval, activation,
retirement, and policy narrowing. Validate scoring bounds, concurrency limits,
resource capacity, quotas, budgets, redundancy, automation, and repair policy.

Focused proof covers invalid/unknown fields, stale approval, concurrent
activation, content hashes, non-widening provider/account constraints, and
immutable active history.

## Task 3: Fleet Planning Runs and Inputs

Create:

- `fleet_planning_runs`
- `fleet_planning_run_requirement_refs`
- `fleet_planning_decisions`

Persist lifecycle/phase, exact policy and Requirement versions, algorithm
identity, horizon, trigger, repair source, progress, candidate Plan reference,
bounded failure, and actor evidence.

Implement scoped create/list/fetch/cancel and restart-safe phase transitions.
Use row locks or compare-and-swap transitions so only one worker owns a phase.

Focused proof covers horizon selection, exact input snapshots, drift detection,
phase idempotency, cancellation, recovery, and cross-scope failure.

## Task 4: Deterministic Optimizer

Implement a pure optimizer module with normalized input/output structs:

- hard-constraint evaluator
- resource calendar
- quota/budget ledger
- redundancy tracker
- bounded score calculator
- stable demand/candidate ordering
- deterministic bounded local improvement
- one explanation per considered snapshot

Use integer or decimal-safe normalized score components; never persist
non-deterministic floating-point ordering as a decision authority.

Focused proof covers identical-input determinism, hard constraints, stable
tie-breaks, scarcity, priority protection, overlap, separation, resource
capacity, quotas, budgets, redundancy, locked commitments, and bounded runtime.

## Task 5: Fleet Orchestrator and Candidate Plan

Compose Stage 4 Planner runs using `Task.async_stream/3` with policy-bounded
concurrency. Persist progress after each Requirement result. Reuse successful
current runs only when their exact inputs, route evidence, and freshness policy
permit it; otherwise create new Stage 4 runs.

Feed immutable snapshots to the optimizer, persist every decision, and
materialize the result through `ContactPlans.create/4`. Link the exact candidate
Plan version to the Fleet Planning Run.

Focused proof covers mixed providers, partial search failure, successful empty,
deterministic selection, Requirement drift, policy drift, Plan linkage, and
restart from every checkpoint.

## Task 6: Automation and Repair

Create immutable, administrator-approved Automation Grants. Implement:

- manual advisory mode
- approval-required automatic submission
- grant-bounded automatic approval evidence
- policy-bounded execution concurrency
- repair-run creation from partial execution
- locked successful and uncertain commitments

Do not impersonate a user. Automated evidence includes service identity, exact
grant, policy, approving administrator, and reason.

Focused proof covers expiry, revocation, stale policy, cap enforcement,
concurrent triggers, duplicate prevention, uncertain outcomes, partial success,
and repair convergence.

## Task 7: Fleet Planning Workspace

Add authenticated mission Ops routes:

```text
/missions/:mission_id/ops/planning
/missions/:mission_id/ops/planning/new
/missions/:mission_id/ops/planning/runs/:fleet_planning_run_id
/missions/:mission_id/ops/planning/policy
/missions/:mission_id/ops/requirement-templates
```

Build:

- run horizon and scope form with progressive policy details
- streamed run history
- durable phase/progress strip
- horizon rail and spacecraft coverage matrix
- provider/resource pressure rail
- exception queue
- streamed decision inspector
- links to exact Stage 4 Requirement, Plan, reservation, and Contact records
- template and policy management appropriate to role

LiveView proof covers authentication, mission scoping, member/admin actions,
progress refresh, stable selectors, empty/partial/failed/completed runs,
decision inspection, automation grant state, and repair action.

## Task 8: Simulator Scale and Chaos

Extend the separate simulator with deterministic fleet scenarios:

- at least 300 spacecraft
- multiple stations and exclusive service pools
- route-specific latency and rate limits
- missing, expired, and processing orbit readiness
- successful empty availability
- overlapping opportunities and expiring windows
- partial reservation rejection
- ambiguous commit response
- provider restart and event replay

Prove Requirement generation through Fleet Planning Run, candidate Plan,
approval/automation, bounded reservations, repair, Scheduled Contacts, and
ordinary TCP/CCSDS telemetry. Cadence must not call simulator administrator APIs
or perform orbit propagation.

## Task 9: Migration and Final Gates

Extend the provider/planning migration audit with:

- clean Stage 5 database
- populated Stage 4 database upgrade
- retained Requirements, Plans, reservations, and Scheduled Contacts
- null fleet refs for historical Stage 4 records
- exact current-version, active-policy, candidate-Plan, repair-source, and
  decision foreign keys

Update parent design, simulator/provider guides, operator guide, and an
implementation record with exact verification counts.

Run owning-app focused suites, simulator boundary/scale suites, browser
verification against the live authenticated workspace when available, then:

```bash
mix precommit
```

## Definition of Done

- Every acceptance criterion in the Stage 5 design has direct current-state
  evidence.
- All schema-visible references have migrations, schemas, domain conversion,
  and focused persistence proof.
- Every public write is scoped and authorized.
- Requirement generation and orchestration are restart-safe and idempotent.
- Optimizer output is deterministic, bounded, and explainable.
- Hard constraints cannot be traded for score.
- Candidate Plans, approvals, and reservations preserve exact versions.
- Automation requires exact active grant evidence and stops closed.
- Repair preserves successful and uncertain commitments.
- The 300-spacecraft simulator scale/chaos proof passes.
- Direct booking and all Stage 4 proofs remain green.
- Ops journeys are functional and covered by stable selectors.
- Clean/upgrade migration audits, focused suites, and root `mix precommit` pass.
