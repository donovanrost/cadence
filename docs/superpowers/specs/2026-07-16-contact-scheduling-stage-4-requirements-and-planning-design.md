# Stage 4 Contact Requirements and Planning

- Status: implemented
- Created: 2026-07-16
- Parent design:
  [Contact Scheduling and External Ground Network Simulation](2026-07-12-contact-scheduling-and-ground-network-simulation-design.md)
- Predecessor:
  [Stage 3 Durable Provider Integration Semantics](2026-07-15-contact-scheduling-stage-3-durable-integration-semantics-design.md)
- Implementation plan:
  [Stage 4 Requirements and Planning](../plans/2026-07-16-contact-scheduling-stage-4-requirements-and-planning.md)

## Summary

Stage 4 adds the mission planning layer above the durable provider integration
completed in Stage 3. A mission operator describes an operational outcome as a
versioned Contact Requirement. Cadence searches every eligible provider route,
persists the outcome of each search and the exact opportunities returned,
explains which opportunities satisfy or violate the requirement, and lets an
operator assemble a versioned Contact Plan. Approval freezes one exact plan
version before any provider capacity is requested. Plan execution delegates
every provider mutation to the existing Stage 3 reservation saga.

Stage 4 does not make Cadence an orbital propagator. Provider adapters remain
authoritative for bookable opportunities. Ephemeris, station geometry, antenna
capacity, service compatibility, and provider policy are provider inputs to
opportunity generation. Cadence records provider search readiness and evidence,
then reasons over returned opportunity windows.

## Locked Product Decisions

1. Contact Requirements are mission-owned operational intent. They do not own
   Provider Account, Mission Provider, Transport, or routing configuration.
2. A Requirement expresses an outcome without selecting an opportunity.
3. Requirements are versioned. Editing content creates a new immutable version
   and never changes the meaning of a plan that references an older version.
4. The existing direct opportunity-booking journey remains available for ad hoc
   operations. Stage 4 does not manufacture hidden Requirements for direct
   bookings.
5. Provider adapters remain authoritative for opportunities. Cadence does not
   infer visibility windows from TLE, OEM, or state-vector data in Stage 4.
6. A provider search that returns zero opportunities is different from a search
   that could not run. Both are durable planning evidence.
7. Opportunity snapshots are immutable evidence, not provider capacity. A
   successful reservation remains authoritative.
8. Contact Plans are versioned commitment proposals. A plan version records all
   considered snapshots, selections, rejections, explanations, conflicts, and
   unsatisfied Requirement outcomes.
9. Requirement-specific policy can narrow the exact Mission Provider delivery
   policy and account guardrails, but can never widen them.
10. Approval before initial reservation is a Plan decision. Creating a
    Requirement does not itself commit provider capacity.
11. Manual Plan approval initially requires an authenticated organization
    administrator. This matches Stage 3's authority for material provider
    commitments and produces named actor evidence.
12. Plan approval and provider mutation are separate durable steps. Approval is
    atomic database state; execution is a restart-safe saga.
13. Every Plan reservation uses an idempotency key derived from the exact plan
    version and opportunity snapshot. Retrying execution cannot create another
    provider Contact.
14. Partial success is first-class. A plan can reserve some selections, fail or
    remain ambiguous on others, and report its resulting Requirement coverage.
15. The product surface lives in the authenticated mission `:ops` LiveView
    session. Requirements and Plans are operational work, not Comms setup.
16. Stage 4 supports the existing provider-managed downlink execution path.
    Other directions may be represented as intent but remain explicitly
    unsupported for opportunity planning until their runtime exists.

## User Journey

### Create the need

The primary action is **Plan a contact**. The first prompt is **What does the
mission need?** The UI progressively captures:

- spacecraft
- service direction and operational intent
- earliest acceptable start and latest acceptable end
- success measure: usable contact, duration, volume, or contact count
- minimum and preferred duration
- minimum expected data volume when known
- contact count and minimum separation
- acceptable or excluded providers and stations
- priority
- plan approval mode
- operator rationale

Normal operation shows only the first few fields. Provider/station restrictions,
redundancy, separation, policy narrowing, and metadata live behind an advanced
constraints disclosure.

### Search and explain

Cadence resolves every ready provider-managed route for the Requirement's
spacecraft. It searches routes with bounded concurrency and persists one search
outcome per exact route:

- `succeeded_with_results`
- `succeeded_without_results`
- `not_ready`
- `failed`

Each successful result becomes an immutable normalized opportunity snapshot
with exact Mission Provider, Provider Account/grant, Transport, Routing Rule,
Service Profile, Delivery Profile, source endpoint, and provider evidence.

The UI must not label a Requirement unsatisfied when a provider could not
evaluate it. It presents provider-by-provider evidence such as:

```text
North network       8 opportunities       Search complete
Regional provider   0 opportunities       No matching availability
Backup network      Not evaluated         Spacecraft orbit data expired
```

When provider extensions expose orbit readiness, Cadence retains bounded
metadata such as ephemeris reference, source kind, epoch, validity interval,
and provider validation status. These fields remain evidence and do not become
a Cadence propagation contract.

### Compare and construct a plan

Every opportunity is evaluated against hard Requirement constraints. The
comparison explains:

- within or outside the time window
- minimum and preferred duration
- estimated-volume sufficiency or unavailable estimate
- provider and station restrictions
- opportunity expiry
- conflicts with selected opportunities
- minimum separation
- exact provider route readiness

Stage 4 provides deterministic explanation and manual selection, not a fleet
optimizer. It may sort eligible opportunities consistently, but automatic
multi-spacecraft scoring and optimization belong to Stage 5.

The operator selects one or more snapshots and creates a draft Contact Plan.
The Plan records selected and rejected snapshot identities, Requirement
coverage, warnings, conflicts, search failures, and unsatisfied reasons.

### Review, approve, and execute

The review page reads like a commitment manifest:

- exact Requirement versions
- selected provider windows and routes
- estimated coverage and volume
- policy and approval consequences
- provider searches that were unavailable or returned no results
- conflicts and unsatisfied outcomes
- opportunity expiration countdown

Approval locks and revalidates the current plan version. A stale version,
expired opportunity, changed Requirement, missing exact route, revoked grant,
or widened policy blocks approval.

After approval, an execution record is created for every selected opportunity.
The executor persists intent before calling a provider, invokes Stage 3 booking,
and stores the resulting Provider Reservation or bounded error. Restarting the
executor resumes incomplete items using the same idempotency keys.

## Domain Model

### Contact Requirement

`ContactRequirement` is the stable mission-owned identity and mutable current
projection:

```text
contact_requirement_id
organization_id
mission_id
current_version
lifecycle_state: active | closed | canceled
created_by
inserted_at
updated_at
```

`ContactRequirementVersion` is immutable:

```text
contact_requirement_id + version
spacecraft_id
service_direction
contact_intent
earliest_start
latest_end
success_measure
minimum_duration_seconds
preferred_duration_seconds
minimum_data_volume_bytes
contact_count
minimum_separation_seconds
priority
provider_constraints
station_constraints
policy_constraints
approval_policy
rationale
metadata
content_sha256
created_by
created_at
```

Only the stable row is transitioned when a Requirement is closed or canceled.
Content edits insert a new version and advance `current_version` in one locked
transaction.

### Planning Run

`ContactPlanningRun` captures one attempt to find options for an exact
Requirement version:

```text
contact_planning_run_id
organization_id
mission_id
contact_requirement_id + requirement_version
lifecycle_state: running | completed | partial | failed
requested_by
started_at
completed_at
summary_document
```

`ContactPlanningSearch` records every exact route considered, including
successful empty results and failures. Search errors are bounded documents and
must never contain credentials.

### Opportunity Snapshot

`ContactOpportunitySnapshot` is immutable and content-addressed within one
planning run. It records:

```text
contact_opportunity_snapshot_id
planning_run_id
Requirement identity/version
provider opportunity reference
opportunity start/end/expiry and availability
estimated capacity
exact route binding document
normalized opportunity document
provider evidence reference/hash
evaluation document
eligible
content_sha256
```

The route binding document contains only serializable identifiers and versions;
adapter modules and runtime processes are never persisted.

### Contact Plan

`ContactPlan` is the stable current projection:

```text
contact_plan_id
organization_id
mission_id
current_version
lifecycle_state:
  draft | pending_approval | approved | executing |
  partially_reserved | reserved | failed | canceled | superseded
created_by
approved_version
approved_at
approved_by
```

`ContactPlanVersion` is immutable:

```text
contact_plan_id + version
Requirement references with exact versions
planning run references
selected opportunity snapshot IDs
rejected opportunity snapshot IDs
coverage document
conflict document
unsatisfied document
policy snapshot document
rationale
content_sha256
created_by
created_at
```

Edits after approval create a new version, clear approval, and make the prior
approved version historical. An executing or reserved version is never edited.

### Approval and Execution

`ContactPlanApproval` is append-only actor evidence for an exact plan content
hash. It records approval or rejection, actor, reason, and time.

`ContactPlanExecutionItem` is one durable saga item per selected opportunity:

```text
plan identity/version
opportunity snapshot identity
idempotency key
state: pending | requesting | reserved | uncertain | rejected | failed
provider reservation identity
attempt count
last error document
started_at
completed_at
```

The provider reservation snapshots the Requirement, Plan, and opportunity
snapshot references. Direct bookings leave those optional fields empty.

## Requirement Evaluation

The evaluator returns data, not presentation strings alone:

```text
eligible
hard_failures[]
warnings[]
facts{
  duration_seconds
  expected_volume_bytes
  expected_volume_known
  provider_allowed
  station_allowed
  expires_at
}
```

Hard failures include an outside window, too-short duration, disallowed provider
or station, expired opportunity, and incompatible direction/service. Missing
estimated volume is a warning unless the Requirement explicitly makes a volume
estimate mandatory. The Plan-level evaluator additionally checks contact count,
aggregate estimated volume, redundancy, and minimum separation.

An unsatisfied document separates:

- hard constraint failure
- insufficient eligible opportunities
- insufficient aggregate duration or volume
- provider search unavailable
- opportunity expired
- exact route no longer ready

## Policy Narrowing

Requirement policy is an additional maximum restriction over the exact Mission
Provider delivery policy used by a selected route. It may reduce permitted
timing shifts, restrict station substitutions, disable automatic provider
changes, or require explicit approval. It cannot add a station, provider, or
automatic behavior forbidden by mission or organization policy.

The approved Plan snapshots the effective narrowed policy for each selection.
The Stage 3 Provider Reservation continues to snapshot the authoritative
Mission Provider policy. Plan policy is additional approval evidence; it does
not rewrite provider integration configuration.

## Authorization and Routing

New routes are placed inside the existing authenticated `live_session :ops`
because they require organization membership, mission loading, the Ops shell,
and mission-operational navigation:

```text
/missions/:mission_id/ops/requirements
/missions/:mission_id/ops/requirements/new
/missions/:mission_id/ops/requirements/:contact_requirement_id
/missions/:mission_id/ops/plans/:contact_plan_id
```

The browser pipeline supplies `current_scope`; `MissionAuth.load_mission`
proves the mission belongs to the selected organization. Public context writes
receive `current_scope` first. Requirement and draft-plan work requires an
authenticated organization member. Plan approval/rejection requires
organization-admin or platform-admin capability and a named user actor.

## Operational Presentation

The Requirements page uses an industrial planning-desk aesthetic consistent
with the existing Contacts HUD, with stronger temporal hierarchy:

- a horizon rail that shows requirements by deadline and fulfillment risk
- compact outcome sentences instead of schema-field titles
- a four-step status strip: `Need → Options → Plan → Reserved`
- provider search evidence separated from unsatisfied outcomes
- progressive advanced constraints
- comparison rows aligned by time, duration, provider, station, expected
  capacity, expiry, and eligibility explanation
- a Plan review manifest that clearly marks the exact version being approved

Healthy setup is quiet. Missing mappings, unavailable searches, expiring
opportunities, conflicts, and unmet outcomes receive explicit actionable copy.

## Failure and Recovery Semantics

- If one provider search fails, the planning run is `partial`; successful route
  results remain usable and the failure remains visible.
- If all route searches fail, the run is `failed`, not `completed` with no
  opportunities.
- Re-running planning creates a new run and new immutable snapshots.
- Approval always rechecks Requirement version, Plan hash, opportunity expiry,
  route exactness, grant activity, and policy narrowing.
- Execution persists each item before provider mutation.
- Ambiguous provider outcomes remain `uncertain` and rely on the Stage 3
  reconciliation path; execution never blindly retries a write.
- Partial reservation never rolls back already committed provider capacity.
  Operators see explicit compensation/cancellation choices.
- A repeated executor invocation converges on the same execution items and
  Stage 3 idempotency keys.

## Stage Boundary

### Included

- versioned mission Contact Requirements
- multi-provider bounded opportunity search
- durable provider-by-provider search outcomes
- immutable normalized opportunity snapshots
- deterministic eligibility and plan-coverage explanation
- versioned Contact Plans
- manual selection, review, approval, and rejection
- restart-safe plan execution through Stage 3 reservations
- partial-success and unsatisfied-requirement reporting
- authenticated mission Ops Requirements and Plan journeys
- simulator and fake-provider proofs for mixed search outcomes

### Excluded

- Cadence-owned orbit propagation
- automated several-hundred-spacecraft optimization
- cross-requirement resource optimization
- automatic partial replanning
- quotas, budgets, and commercial cost enforcement beyond bounded evidence
- recurring Requirement generation
- organization-wide approval framework
- real AWS, Leaf, or KSAT adapter implementation
- general plugin packaging
- uplink or bidirectional data-plane execution

These exclusions belong to Stage 5 or Stage 6. They must not be approximated by
silently treating provider opportunities as guaranteed capacity.

## Acceptance Criteria

- A mission member can create and version a valid Contact Requirement.
- Cross-organization Requirement and Plan reads/writes fail closed.
- Every planning run references one exact Requirement version.
- Every ready provider route is either searched or represented by a durable
  bounded failure outcome.
- Successful empty search and failed search are distinguishable.
- Opportunity snapshots preserve exact provider/routing/profile bindings and
  sanitized evidence.
- Requirement evaluation explains every ineligible opportunity.
- Plan coverage explains contact-count, duration, volume, separation, provider
  search, and expiry outcomes.
- Editing a Requirement never changes a historical Plan.
- Editing a Plan produces a new immutable version and invalidates stale
  approval.
- Approval rejects stale hash, stale version, expired opportunity, missing
  route, revoked grant, and widened policy.
- Approval evidence includes a named authenticated administrator and reason.
- Each selected opportunity has exactly one durable execution item and stable
  idempotency key.
- Repeated or restarted execution cannot create a duplicate Provider
  Reservation or Scheduled Contact.
- Partial provider success remains visible and recoverable.
- Direct ad hoc booking remains operational without a Requirement or Plan.
- Requirements and Plans render inside the authenticated mission `:ops` surface
  with stable DOM IDs and progressive constraints.
- Focused core, LiveView, migration, separate-app, and root `mix precommit`
  gates pass.

## Implementation Verification

Implemented on 2026-07-16. Current-state proof includes:

- 36 focused Contact Planning tests after the final static-analysis refactor
- 20 focused simulator provider and contact-scheduling boundary tests
- 17 focused authenticated Ops Contact Requirement, Plan, Schedule, and Contact
  LiveView tests
- the clean-database and populated-Stage-3 migration audit
- root `mix precommit`: 1,453 Cadence tests, 11 CCSDS tests, 102 simulator
  tests, and 1,623 web tests passed; 93 browser-tagged tests were excluded by
  the repository's normal precommit configuration

The local application was running for final verification, but the attached
browser automation bridge was unavailable. No manual or screenshot-level proof
is claimed; the authenticated journeys are covered through LiveView interaction
tests and stable DOM selectors.
