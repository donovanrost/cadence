# Stage 5 Fleet Planning and Automation

- Status: implemented
- Implemented: 2026-07-17

- Status: implementation in progress
- Created: 2026-07-16
- Parent design:
  [Contact Scheduling and External Ground Network Simulation](2026-07-12-contact-scheduling-and-ground-network-simulation-design.md)
- Predecessor:
  [Stage 4 Contact Requirements and Planning](2026-07-16-contact-scheduling-stage-4-requirements-and-planning-design.md)
- Implementation plan:
  [Stage 5 Fleet Planning and Automation](../plans/2026-07-16-contact-scheduling-stage-5-fleet-planning-and-automation.md)

## Summary

Stage 5 turns the Stage 4 planning workflow into a mission-scale scheduling
system. A mission operator can generate recurring Contact Requirements, start a
Fleet Planning Run over hundreds of exact Requirement versions, and receive one
explainable candidate Contact Plan. Cadence searches provider-owned
opportunities through the existing Stage 4 boundary, applies hard constraints,
scores feasible alternatives, snapshots policy and budget inputs, and explains
selected, displaced, and unsatisfied work.

Stage 5 does not add a second booking workflow. A candidate is an ordinary
versioned Contact Plan. Approval remains an exact-version decision, and
execution continues through the Stage 3 reservation saga. Repair planning
creates a new Fleet Planning Run and Contact Plan version for remaining work;
it never rewrites confirmed reservations or Scheduled Contacts.

Providers remain authoritative for orbit propagation, station geometry,
inventory, and bookable opportunities. Cadence is the scheduler over
provider-supplied candidate windows, not an orbital dynamics engine.

## Locked Product Decisions

1. Fleet Planning Runs are mission-owned. The first implementation never
   combines Requirements from different missions.
2. Every run snapshots exact Requirement versions and one exact Fleet Planning
   Policy version before provider search begins.
3. A run composes ordinary Stage 4 Contact Planning Runs. Provider adapters and
   opportunity snapshots are not bypassed or reimplemented.
4. One completed run may materialize one draft Contact Plan. That plan uses the
   existing immutable Plan, approval, execution-item, reservation, and
   Scheduled Contact semantics.
5. The optimizer is deterministic and explainable. Identical normalized inputs,
   policy version, and algorithm version produce the same selections and
   explanations.
6. “Optimal” means best under the declared bounded scoring policy and algorithm,
   not an unsupported claim of mathematical global optimality.
7. Hard constraints can never be traded for score. Scoring only ranks feasible
   alternatives.
8. Provider opportunities remain ephemeral. A selected snapshot is planning
   evidence, not capacity.
9. Repair planning preserves successful and uncertain execution items as locked
   commitments. It only plans unmet work around them.
10. Automatic execution is opt-in and requires an active, administrator-approved
    Automation Grant tied to exact policy bounds. A service actor never
    manufactures user approval.
11. Automation stops closed when a policy, grant, Requirement version, route,
    opportunity, quota, or budget input becomes stale.
12. Manual Stage 4 planning and direct ad hoc booking remain supported.
13. Fleet scale must come from bounded concurrency and durable checkpoints, not
    unbounded tasks or LiveView-held collections.

## Operator Journeys

### Define recurring mission demand

The operator creates a Requirement Template for one spacecraft and service
intent. A template contains:

- a fixed-interval or daily cadence
- an anchor and optional active interval
- a window offset and duration
- the Contact Requirement content to instantiate
- catch-up bounds
- lifecycle and operator rationale

Materialization is idempotent by template version and occurrence. Editing a
template creates a new immutable version. Previously generated Requirements
retain the version that produced them.

Templates generate ordinary Contact Requirements. Operators can inspect,
version, close, or cancel those Requirements through the Stage 4 journey.

### Configure fleet planning policy

A mission administrator configures a versioned Fleet Planning Policy:

- planning horizon and search concurrency
- scoring weights and deterministic tie-breaks
- provider, station, and resource concurrency assumptions
- per-provider and total contact, capacity, and cost ceilings
- redundancy and provider-diversity policy
- reserved budget for high-priority work
- maximum automatic-repair attempts and repair horizon
- automation mode and execution concurrency

Policy can narrow Provider Account and Mission Provider guardrails but cannot
widen them. Unknown or provider-specific commercial evidence remains bounded
metadata and cannot silently count as known cost.

### Run fleet planning

The operator opens **Ops → Planning**, chooses a horizon and Requirement scope,
and starts a Fleet Planning Run. The scope defaults to every active Requirement
whose window intersects the horizon.

The run progresses through durable phases:

```text
queued -> materializing -> searching -> optimizing -> materializing_plan
   |            |             |            |              |
   +----------> failed <-------+------------+--------------+
                                             |
                                             +-> completed
                                             +-> partial
                                             +-> canceled
```

The run page shows:

- Requirement and spacecraft counts
- provider-search progress and readiness
- eligible, selected, displaced, and unsatisfied counts
- quota, budget, redundancy, and resource pressure
- algorithm and policy versions
- bounded warnings and failures

### Review the fleet proposal

The completed run presents an operational coverage board:

- coverage by spacecraft and Requirement
- selected contacts on a shared horizon
- conflicts avoided
- alternatives displaced by higher-value work
- unsatisfied hard constraints
- provider-search failures
- budget or quota exhaustion
- redundancy and provider-diversity results

Every decision answers “why selected?” or “why not selected?” without requiring
operators to interpret optimizer internals.

The candidate opens as the ordinary Stage 4 Plan commitment manifest for exact
review, submission, approval, and execution.

### Repair partial execution

When execution is partial, failed, rejected, or cannot converge from an
uncertain provider outcome, the operator can start a repair run.

The repair run snapshots:

- the source Fleet Planning Run and Plan version
- successful and uncertain execution items as locked commitments
- still-current unmet Requirement versions
- current provider opportunities and policy

The repair result is a new draft Contact Plan version. Existing Provider
Reservations and Scheduled Contacts are never canceled or replaced implicitly.
Compensation remains an explicit operator action.

## Domain Model

### Contact Requirement Template

Stable resource:

```text
contact_requirement_template_id
organization_id
mission_id
current_version
lifecycle_state
created_by
lifecycle_changed_by / at / reason
```

Immutable version:

```text
contact_requirement_template_version_id
contact_requirement_template_id
organization_id
mission_id
version
spacecraft_id
schedule_document
requirement_document
catch_up_policy_document
content_sha256
created_by / at
```

Generated-occurrence evidence:

```text
contact_requirement_occurrence_id
template id and exact version
occurrence_at
generated_requirement id and version
generation_state and bounded error
unique(template id, template version, occurrence_at)
```

### Fleet Planning Policy

Stable resource plus immutable versions. A version owns normalized documents
for:

- horizon and concurrency
- scoring
- capacity and resource constraints
- budgets and quotas
- redundancy
- automation and repair

It records a content hash and administrator approval evidence. Editing creates a
new draft version. Only one exact approved version may be active for new runs.

### Fleet Planning Run

```text
fleet_planning_run_id
organization_id
mission_id
lifecycle_state and phase
trigger_kind: manual | scheduled | repair
policy id and exact version
algorithm key and version
horizon start / end
source run and source plan refs for repair
candidate plan id and exact version
input / progress / result summary documents
failure document
triggered_by actor evidence
started_at / completed_at
```

Run Requirement references preserve the exact input versions and disposition:

```text
fleet_planning_run_requirement_ref_id
fleet_planning_run_id
contact_requirement_id and exact version
contact_planning_run_id
input_state
result_state
explanation_document
```

Optimization decisions preserve every considered snapshot:

```text
fleet_planning_decision_id
fleet_planning_run_id
contact_opportunity_snapshot_id
disposition: selected | displaced | ineligible | locked
score
rank
hard_constraint_document
score_document
explanation_document
```

### Automation Grant

An Automation Grant is an administrator-approved authorization envelope, not a
replacement user:

```text
automation_grant_id
organization_id
mission_id
fleet_planning_policy_id and exact version
allowed actions
maximum horizon / contacts / cost / execution concurrency
valid_from / valid_until
lifecycle_state
approved_by / at / reason
content_sha256
```

Automatic submission, approval, or execution evidence references this exact
grant. Expiry or policy drift stops new automated actions.

## Optimizer Contract

The optimizer receives only normalized immutable inputs:

```text
exact Requirement versions
immutable opportunity snapshots
locked commitments
exact Fleet Planning Policy version
algorithm key and version
```

It returns:

```text
selected snapshot IDs in deterministic order
one decision record per considered snapshot
coverage and unsatisfied outcomes per Requirement
resource, quota, budget, and redundancy summaries
quality and termination evidence
```

### Hard constraints

- Stage 4 opportunity eligibility
- Requirement window, duration, volume, count, and separation
- same-spacecraft temporal overlap
- declared exclusive provider resource overlap
- active provider route and grant
- opportunity expiry
- provider/station allow and exclude lists
- known hard contact, volume, or cost ceilings
- locked commitment conflicts

Unknown cost or capacity cannot satisfy a hard minimum or maximum that requires
known evidence.

### Scoring

The first algorithm is a deterministic bounded greedy allocator with
deterministic local improvement. It orders demand by:

1. hard deadline
2. Requirement priority
3. scarcity of feasible alternatives
4. stable Requirement identity and version

Candidate score may include:

- preferred-duration and volume coverage
- earlier deadline protection
- provider and station preference
- opportunity confidence
- cost efficiency when cost is known
- provider diversity and redundancy
- schedule fragmentation
- expiry risk

Every component is normalized, bounded, and recorded. Stable IDs break final
ties.

Local improvement may replace a bounded selection set only when it increases
the declared score without violating hard constraints or reducing protected
priority coverage.

## Budgets, Quotas, and Redundancy

- Provider-native quotas and account limits remain provider authority.
- Cadence policy provides planning ceilings, not a claim of provider inventory.
- A run snapshots both Cadence policy and bounded provider evidence.
- Known cost accumulates in the declared currency. Mixed or unknown currencies
  cannot be combined.
- High-priority budget reserves cannot be consumed by lower-priority work.
- Requirement contact count remains the minimum coverage target.
- Redundancy can require distinct providers, stations, or service pools.
- If redundancy cannot be achieved, the Requirement is explicitly partial or
  unsatisfied; duplicate contacts are never mislabeled as diverse.

## Concurrency and Checkpointing

- Requirement generation uses bounded batches and idempotent occurrence keys.
- Provider search reuses Stage 4 planning runs and bounded adapter concurrency.
- Fleet orchestration checkpoints after materialization, search, optimization,
  Plan creation, and each automated action.
- Reservation execution reuses durable Stage 4 items and adds a policy-bounded
  execution concurrency limit.
- Restart resumes from durable phase state and never repeats completed provider
  mutations.

## Authorization

- Mission members may list runs, start manual runs, and inspect decisions.
- Organization administrators may manage templates and draft policy versions;
  Cadence does not yet expose a separate mission-administrator membership role.
- Organization administrators approve Fleet Planning Policy versions and
  Automation Grants.
- Existing Stage 4 manual Plan approval remains organization-admin scoped.
- Automated decisions use a service identity plus an exact active Automation
  Grant and record both the service actor and approving administrator.
- Every public write receives `current_scope` first.

## Operational Presentation

The Fleet Planning workspace extends the existing industrial planning-desk
language into a dense temporal control surface:

- a mission-horizon rail with contacts and locked commitments
- a spacecraft coverage matrix rather than card grids
- a pressure rail for scarce provider resources, quotas, and budgets
- an exception queue for unsatisfied or provider-blocked Requirements
- a run phase strip with durable checkpoint counts
- a decision inspector that reads as operational rationale

Healthy work stays visually quiet. The page emphasizes deadlines, coverage
gaps, contested capacity, expiring evidence, and actions requiring judgment.
Collections use LiveView streams and stable DOM IDs.

Routes live in the authenticated mission `:ops` LiveSession because fleet
planning is mission operations. Organization-level Provider Account guardrails
remain in the organization-admin surface.

## Failure and Recovery Semantics

- One failed provider search makes the run partial when useful alternatives
  remain.
- A failed search never becomes empty availability.
- A run with no feasible selection may complete with an explainable unsatisfied
  result; infrastructure or persistence failures produce `failed`.
- Requirement or policy drift before Plan materialization stops closed.
- Opportunity expiry before approval remains a Stage 4 approval failure.
- Provider rejection after approval becomes partial execution evidence.
- Repair runs do not treat uncertain reservations as free capacity.
- Cancellation is explicit and does not delete run, decision, Plan, or
  reservation history.

## Stage Boundary

### Included

- recurring Requirement templates and idempotent generation
- mission-scoped Fleet Planning Policies
- batched several-hundred-spacecraft planning
- deterministic scoring and hard constraints
- quotas, budgets, and redundancy planning policy
- candidate Contact Plan materialization
- bounded automatic submission/execution under exact grants
- partial repair planning around locked commitments
- authenticated fleet planning workspace
- simulator scale, fault, restart, and convergence qualification

### Excluded

- Cadence-owned orbit propagation
- cross-mission or organization-wide optimization
- a claim of mathematically global optimality
- real AWS, Leaf, or KSAT adapter implementation
- general adapter plugin packaging
- commercial billing or invoice reconciliation
- provider inventory ownership
- uplink or bidirectional data-plane implementation

Commercial provider proof and any plugin-model changes remain Stage 6.

## Acceptance Criteria

- A mission administrator can create and version a recurring Requirement
  Template.
- Materializing the same occurrence repeatedly creates exactly one Requirement.
- A Fleet Planning Run snapshots exact Requirement and policy versions.
- Several hundred Requirements can be searched with bounded concurrency and
  durable progress.
- Every eligible provider route has successful-empty, successful-result,
  excluded, not-ready, or bounded-failure evidence through Stage 4 runs.
- Identical normalized inputs produce identical selected IDs and decision
  explanations.
- Hard constraints are never traded for score.
- Same-spacecraft, exclusive-resource, separation, quota, budget, and locked
  commitment conflicts are enforced.
- Every considered snapshot has one durable selected, displaced, ineligible, or
  locked decision.
- Coverage explains unsatisfied count, duration, volume, redundancy, quota,
  budget, provider, and expiry outcomes.
- A completed run materializes an ordinary draft Contact Plan with exact input
  references.
- Manual Plan approval and execution continue to use Stage 4 semantics.
- Automatic actions require an active exact-policy Automation Grant and retain
  named administrator evidence.
- Bounded parallel execution cannot duplicate reservations or Scheduled
  Contacts.
- Repair planning preserves successful and uncertain commitments and only
  schedules unmet work.
- Restarting orchestration resumes from durable checkpoints.
- Direct ad hoc booking and Stage 4 single-Requirement planning remain green.
- Fleet UI renders in authenticated mission Ops with streams, stable selectors,
  and progressive decision evidence.
- Scale tests cover at least 300 spacecraft and deterministic provider faults.
- Clean/upgrade migration audits, focused suites, browser verification when
  available, and root `mix precommit` pass.
