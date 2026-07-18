# Stage 4 Contact Requirements and Planning Implementation Plan

**Status:** implemented

**Goal:** Add mission-owned Contact Requirements and versioned Contact Plans,
search and explain opportunities across every eligible provider route, and
execute one exact approved plan version through the durable Stage 3 reservation
boundary.

**Design source:**
[Stage 4 Contact Requirements and Planning](../specs/2026-07-16-contact-scheduling-stage-4-requirements-and-planning-design.md)

## Locked Implementation Order

1. Persistence and versioned Requirement domain.
2. Planning runs, route-search outcomes, opportunity snapshots, and evaluators.
3. Versioned Plans and approval evidence.
4. Restart-safe plan execution through Provider Booking.
5. Authenticated Ops Requirements and Plans UI.
6. Separate-app, migration, browser, and final gates.

Each task must retain direct ad hoc booking and all Stage 3 reconciliation,
event, approval, audit, and TCP/CCSDS proofs.

## Task 1: Contact Requirement Domain

Create migrations for stable `contact_requirements` and immutable
`contact_requirement_versions` with organization/mission foreign keys,
positive-version constraints, exact current-version foreign key, scoped
indexes, and content hashes.

Add:

- `Cadence.ContactPlanning.ContactRequirement`
- `Cadence.ContactPlanning.ContactRequirementVersion`
- `Cadence.ContactPlanning.ContactRequirements`
- persistence rows for stable and version records

Implement authenticated member create/version/close/cancel operations,
organization and mission scoping, spacecraft existence validation, time-window
validation, bounded documents/text, success-measure validation, and immutable
history. Public writes receive `current_scope` first.

Focused proof:

- create and fetch current Requirement
- every edit creates exactly one next version
- concurrent edits converge or return stale-version conflict
- historical versions remain unchanged
- invalid windows and success measures fail
- foreign spacecraft and cross-organization access fail
- close/cancel blocks new planning without deleting history

## Task 2: Planning Evidence and Multi-Provider Search

Create migrations and domains for:

- `contact_planning_runs`
- `contact_planning_searches`
- `contact_opportunity_snapshots`

Implement a planning coordinator that loads one exact active Requirement
version, resolves every ready downlink provider route for its spacecraft, and
uses `Task.async_stream/3` with bounded concurrency and `timeout: :infinity`.
Persist one route-search outcome even for empty results and bounded failures.

Snapshot exact serializable route bindings and normalized opportunities.
Sanitize and content-hash evidence. Never persist adapter modules, credentials,
or raw unbounded provider errors.

Focused proof:

- fan-out across multiple Mission Providers/routes
- deterministic route ordering
- successful results and successful empty result remain distinct
- partial provider failure produces a partial run with usable results
- all provider failures produce a failed run
- duplicate provider opportunity payload converges within one run
- provider error and ephemeris/readiness evidence are bounded and secret-free
- stale/closed Requirement cannot start planning

## Task 3: Requirement and Plan Evaluation

Add pure evaluators for individual opportunities and selected collections.
Return stable reason codes plus bounded operator explanations.

Evaluate:

- time window
- minimum/preferred duration
- expected volume and estimate availability
- allowed/excluded providers and stations
- expiry
- contact count
- minimum separation
- aggregate duration/volume
- route-search failures and missing coverage

Missing estimates produce warnings unless the Requirement explicitly requires a
known estimate. Never call a failed provider search “no availability.”

Focused proof includes equality boundaries, unknown capacity, expired windows,
provider/station restrictions, separation, aggregation, partial searches, and
deterministic reason ordering.

## Task 4: Versioned Contact Plans

Create stable `contact_plans`, immutable `contact_plan_versions`, and append-only
`contact_plan_approvals`.

Implement draft creation from exact Requirement versions and one or more
planning runs. Selected snapshot IDs must belong to referenced runs and
Requirements. Persist considered, selected, and rejected identities, coverage,
conflicts, unsatisfied reasons, effective policy snapshots, rationale, and
content hash.

Plan edits create a new version under a row lock and clear prior approval from
the current projection without rewriting historical versions.

Focused proof:

- exact Requirement/run/snapshot linkage
- no cross-mission selection
- deterministic plan hash
- immutable version history
- stale concurrent edit rejection
- eligible selections only
- unsatisfied Plan allowed but explicit
- approved/executing Plan cannot be edited in place

## Task 5: Plan Approval

Implement authenticated organization-admin approve/reject commands. Approval
locks the stable Plan, re-fetches the exact current version, and revalidates:

- proposal hash and current version
- referenced Requirement versions and lifecycle
- opportunity expiry
- exact provider route readiness and route snapshot equality
- active Provider Account grant
- Requirement policy narrowing
- Plan-level conflicts and approval policy

Approval inserts append-only actor evidence and transitions only the exact
version reviewed. Rejection records a required reason without deleting the
draft.

Focused proof includes unauthorized actor, stale hash/version, expired
opportunity, changed Requirement, revoked grant, missing route, policy widening,
named actor evidence, rejection, and concurrent approval.

## Task 6: Restart-Safe Plan Execution

Create `contact_plan_execution_items` and add optional exact Requirement, Plan,
and opportunity-snapshot references to `provider_reservations`.

Approval creates one execution item per selected opportunity with a stable
idempotency key. Execution re-resolves exact route bindings, persists
`requesting`, and invokes `ProviderBooking.reserve/5`. Record confirmed,
pending/uncertain, rejected, or failed outcomes without rolling back other
provider commitments.

Repeated execution must resume incomplete items and reuse Stage 3 correlation
references. Reconciliation remains authoritative for ambiguous writes.

Focused proof:

- one selection produces one item and linked reservation
- multiple providers can partially succeed
- response loss after commit remains uncertain and recoverable
- executor restart reuses idempotency
- repeated execution creates no duplicate reservation/contact
- Plan projection becomes executing, partially reserved, reserved, or failed
- direct bookings continue with empty Plan references

## Task 7: Requirements Ops Journey

Place routes in the existing authenticated `live_session :ops`:

```text
/missions/:mission_id/ops/requirements
/missions/:mission_id/ops/requirements/new
/missions/:mission_id/ops/requirements/:contact_requirement_id
```

This session is required because the journey is mission-operational, must load
organization and mission scope before rendering, and belongs in the Ops shell.

Build:

- horizon-oriented Requirement list and fulfillment strip
- outcome-first progressive Requirement form using `to_form/2` and `<.input>`
- Requirement detail with immutable version history
- provider-by-provider planning evidence
- streamed opportunity comparison with explicit eligibility reasons
- snapshot selection and draft-Plan creation

Use stable DOM IDs for pages, forms, disclosures, search outcomes, opportunity
rows, version rows, and plan actions. Use LiveView streams for collections.

## Task 8: Plan Review and Approval Journey

Add:

```text
/missions/:mission_id/ops/plans/:contact_plan_id
```

Render the exact Plan version as a commitment manifest with Requirement intent,
selected windows, rejected alternatives, coverage, warnings, conflicts,
unsatisfied outcomes, route bindings, policy, expiry, and approval evidence.

Organization administrators can approve/reject with a required reason. Approval
and execution state must remain distinct. Show every execution item and link
successful items to the existing Contact detail.

LiveView proof covers router authentication, organization membership, member
versus admin actions, stale version, progressive constraints, mixed provider
searches, plan construction, approval, partial execution, and stable selectors.

## Task 9: Simulator and Boundary Proof

Extend simulator/fake-provider fixtures so one Requirement can encounter:

- eligible opportunities from multiple providers/routes
- successful empty availability
- provider failure
- missing/expired orbit-readiness evidence
- expiring opportunities
- partial reservation success
- ambiguous response loss after commit

Prove the full boundary from Requirement through approved Plan, Provider
Reservations, Scheduled Contacts, and ordinary TCP/CCSDS telemetry. Cadence must
not call simulator administrator APIs or perform orbit propagation.

## Task 10: Migration, Documentation, and Final Gates

Extend the migration audit with:

- clean Stage 4 database
- populated Stage 3 database upgrade
- existing direct reservations retained with null Plan references
- all new exact current-version and execution foreign keys valid

Update the parent design, simulator guide, provider-adapter guide, and operator
flow. Document orbit/ephemeris ownership, provider search failure semantics,
Requirement versioning, Plan approval, partial execution, and recovery.

Run focused suites from their owning applications and then from the umbrella
root:

```bash
mix precommit
```

Record exact counts and browser exclusions. Use the browser against the live
authenticated Requirements and Plan journeys when browser automation is
available; otherwise state the limitation without claiming manual proof.

## Definition of Done

- All acceptance criteria in the Stage 4 design have direct current-state
  evidence.
- Every schema-visible reference has migration, Ecto schema, domain conversion,
  and focused persistence proof.
- Every public write is scoped and authorized.
- Provider search errors and empty availability remain distinct.
- Requirement and Plan history is immutable and exact-versioned.
- Plan approval cannot authorize stale, expired, widened, or unavailable work.
- Plan execution is restart-safe, partially recoverable, and idempotent.
- Existing direct booking and all Stage 3 proofs remain green.
- The Ops journey is functional, progressively rendered, and covered through
  stable DOM selectors.
- Clean/upgrade migration audits, focused tests, and root `mix precommit` pass.

## Completion Record

Completed on 2026-07-16. The final root gate passed 1,453 Cadence tests, 11
CCSDS tests, 102 simulator tests, and 1,623 web tests. The normal precommit
configuration excluded 93 browser-tagged tests. The clean/populated migration
audit and focused core, simulator-boundary, and LiveView suites also passed.

The attached browser automation bridge was unavailable against the running
local application, so completion relies on the LiveView interaction tests and
stable selectors rather than claimed screenshot-level verification.
