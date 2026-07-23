---
title: "ADR-015: Management Plane, Control Plane, and Data Plane Architecture"
aliases:
  [management plane, control plane, data plane, three plane architecture]
tags:
  [adr, architecture, management-plane, control-plane, data-plane, runtime]
status: accepted
created: 2026-07-21
updated: 2026-07-21
---

# ADR-015: Management Plane, Control Plane, and Data Plane Architecture

## Status

Accepted

This ADR supersedes the plane definitions in
[ADR-013](013-control-plane-data-plane-and-reconciliation-patterns.md). The
durable-write, signaling, reconciliation, process-ownership, and recovery
patterns established there remain valid under the responsibilities assigned
here.

The target implementation shape and migration sequence are described in
[Management, Control, and Data Plane Target Architecture](../architecture/management-control-data-plane-target.md).

## Context

Cadence originally described itself as a control plane plus a reconciled data
plane. That distinction correctly separated durable intent from hot runtime
execution, but it combined two different architectural questions:

1. where state is stored and work is executed; and
2. which part of the system has authority to make a decision.

The resulting definition made the control plane responsible for configuration,
policy, workflow state, operational lifecycle state, and all durable intent. It
made the data plane responsible for supervised runtime work, timers, and ordered
lanes. That is too broad on both sides.

Cadence already contains three materially different kinds of authority:

- users and services author, validate, version, approve, and audit what may
  happen;
- schedulers, reconcilers, dispatchers, and provider clients decide what should
  happen now or next; and
- runtime processes move bytes, execute protocols, interpret live records, and
  maintain hot projections.

The distinction is visible in existing vertical workflows:

- a Contact Plan is authored and approved, then executed into provider
  reservations, then realized as Contact, Path, and Transport runtimes;
- a command is staged and approved, then queued and released, then encoded and
  transmitted through a live transport;
- a governed binding set is authored and activated, then reconciled into a
  mission runtime, then used to interpret live ingress.

Treating the first two stages as one control plane obscures authorization and
approval boundaries. Treating every OTP timer or process as data-plane behavior
misclassifies contact scheduling, command dispatch, activation reconciliation,
and provider reservation recovery.

Cadence therefore needs a management plane in addition to its control and data
planes.

## Decision

Cadence will use a management-plane, control-plane, and data-plane architecture
as the default authority model for operational features.

The planes describe responsibility and dependency direction. They are not
synonyms for UI, Postgres, OTP, ETS, archives, or deployable services.

### 1. Management Plane

The management plane answers:

> What is allowed, and what does an authorized actor want Cadence to do?

It owns:

- organization, mission, identity, membership, and service-identity
  administration;
- authorization policy and actor scope;
- configuration authoring, validation, versioning, and publication;
- approval, separation of duties, and policy decisions;
- durable operator intent and the evidence explaining who requested or approved
  it;
- audit and investigation entry points; and
- administration of provider accounts, credentials, data sources, and other
  managed resources.

Representative management-plane artifacts include:

- Spacecraft Profiles, Transports, Routing Rules, catalog revisions, and
  binding-set versions;
- Contact Requirements, planning policies, proposed Contact Plans, and their
  approvals;
- staged commands, command requests, command approvals, and command-safety
  policy;
- dashboard definitions, data-source definitions, and publish decisions; and
- activation requests and approval records.

Management-plane artifacts are durable, attributable, scoped, and versioned
where they can affect operations. Approval or publication does not directly
mutate live runtime workers.

### 2. Control Plane

The control plane answers:

> Given authorized intent and current observations, what should happen now or
> next?

It owns:

- activation execution and active-basis generations;
- planning execution and operational selection;
- provider opportunity, reservation, modification, cancellation, and recovery
  workflows;
- contact scheduling, realization, lifecycle reconciliation, and early
  termination;
- command queueing, target selection, release attempts, dispatch scheduling,
  and verification lifecycle;
- runtime placement, ownership, desired-state reconciliation, and convergence;
- durable operational state machines and idempotent external-effect sagas; and
- safety reconciliation after missed signals, crashes, or restarts.

The control plane may use Postgres, OTP processes, timers, queues, and external
HTTP APIs. None of those mechanisms determines the plane. A signal-driven
contact scheduler is control-plane behavior even though it is a GenServer with
timers. A provider REST client is a control-plane adapter even when it performs
external I/O.

The control plane is the only plane allowed to translate approved management
intent into current operational intent or an executable runtime specification.
Approved intent includes bounded automation grants and safety policy. The
control plane may act automatically within those pre-authorized bounds when
runtime observations require a decision; it does not require a new human
approval for every scheduled or fault-response transition.

### 3. Data Plane

The data plane answers:

> How is the selected operation executed against live traffic and protocol
> state?

It owns:

- realized mission, Contact, Path, provider, and Transport runtime execution;
- live sockets, streams, byte movement, and provider-native data delivery;
- ordered ingress lanes, bounded queues, and backpressure;
- CCSDS framing, decoding, protocol state machines, and capability execution;
- telemetry extraction, current-value projections, derived evaluation, and
  limit evaluation on live records;
- command encoding, transfer-frame production, and transmission through the
  selected transport;
- process-local timers and state that are intrinsic to protocol execution; and
- raw evidence, protocol records, and runtime observations produced by live
  execution.

Data-plane processes receive exact, immutable runtime specifications or typed
action requests. They do not choose among mutable management drafts, perform
human authorization, or decide whether an operational request should be
released.

### 4. Classify Operations, Not Technologies Or Pages

A plane classification applies to an operation and its authoritative state
transition. It does not automatically classify an entire database, context,
LiveView, controller, or module.

Examples:

- authoring a Contact Plan is management-plane work;
- executing an approved Contact Plan is control-plane work;
- running the realized Contact's TCP downlink is data-plane work;
- authoring and approving a command is management-plane work;
- selecting a release target and creating a release attempt is control-plane
  work;
- encoding and transmitting the command is data-plane work;
- defining a dashboard is management-plane work, while resolving its telemetry
  frame reads data-plane and control-plane observations through read models.

The web boundary is not itself the management plane. A single operator page may
invoke separate management, control, and read-side services while preserving
their authority boundaries.

### 5. Planes, Bounded Contexts, And Vertical Slices

Planes and bounded contexts are different architectural axes:

- a plane defines authority, dependency direction, and runtime responsibility;
- a bounded context defines domain language, invariants, and ownership within a
  plane; and
- a vertical slice is the unit in which Cadence delivers or migrates an
  end-to-end capability across plane boundaries.

Cadence will not create one giant bounded context for each plane. It will also
not use a single domain facade to conceal management, control, and data-plane
implementations behind one dependency surface. A business capability may span
all three planes, but each plane owns a separate model and lifecycle for its
part of that capability.

The preferred logical namespace is plane-first and domain-focused within each
plane. For example:

```text
Cadence.Management.Activations
Cadence.Management.ContactPlanning
Cadence.Management.Commanding

Cadence.Control.Activations
Cadence.Control.Contacts
Cadence.Control.Commanding
Cadence.Control.Missions

Cadence.Runtime.Contacts
Cadence.Runtime.Transports
Cadence.Runtime.Commanding
Cadence.Runtime.Telemetry

Cadence.Projections.ActivationStatus
Cadence.Projections.ContactStatus
Cadence.Projections.CommandStatus
```

An existing context that is cohesive and belongs to one plane may retain its
domain-first namespace while the architecture is migrated. A context or facade
that owns state transitions from more than one plane must be split. Namespace
movement alone is not sufficient; the split must establish separate state
ownership and public contracts.

Vertical slices are the delivery and migration unit, not the primary dependency
boundary. An activation slice, for example, includes management request and
approval, control execution and reconciliation, an exact runtime apply
contract, runtime observation, and a read projection. Each part remains owned
by its plane and is tested at the adjacent handoffs.

### 6. Authority Flow And Compile-Time Dependency Direction

The default causal and authority flow is:

```text
Management --approved intent--> Control --runtime spec/action--> Data
                                    ^                         |
                                    +------ observations -----+

Management facts --------+
Control facts ------------+-------> Projections
Data facts ---------------+
```

Compile-time dependencies do not mirror every causal arrow. A caller depends
on the public contract owned by the receiver of a command or the producer of a
fact:

```text
Web/adapters -------> Management public API
       |------------> Control public API
       +------------> Projections

Control -----------> Management public facts and services
Control -----------> Data public commands and observations

Projections --------> public facts from Management, Control, and Data
```

Control is the deliberate integration point. It may depend on the public
boundaries of Management and Data because it translates approved intent into
exact runtime actions and evaluates runtime observations. Management and Data
remain independent of each other and of Control implementation.

Web modules compose public services and read models but do not orchestrate a
multi-plane state machine. Projections are downstream consumers: no
authoritative plane depends on a projection for correctness. All planes may
depend on explicitly approved, lower-level platform or protocol libraries;
those libraries must not depend back on a plane.

The following rules are mandatory:

1. Management-plane code must not depend on Control or Data implementation and
   must not directly start, stop, reconfigure, or message data-plane workers.
2. Data-plane code must not depend on Management or Control and must not query
   mutable management drafts or choose which configuration, policy, plan, or
   command request becomes active.
3. Control-plane code may depend only on public Management services and facts,
   and public Data commands and observations. It must not depend on their
   schemas, repositories, process names, or implementation modules.
4. Control-plane code must consume an authorized, immutable management artifact
   or an explicit system recovery basis before creating operational intent.
5. Data-plane execution must be driven by an exact runtime specification,
   generation, or typed action request produced by the control plane.
6. Data-plane observations may inform control decisions, but observations do
   not silently rewrite management intent.
7. Cross-plane reads use public services, immutable value types, events, or
   read models. They do not use another plane's Ecto schemas as an API.
8. Web controllers and LiveViews must not implement multi-plane orchestration.
9. Management, Control, and Data must not depend on projections for
   authoritative decisions.
10. A transaction must not be stretched across a plane boundary or an external
    system. Durable handoff plus idempotent execution and reconciliation is the
    correctness model.

### 7. Cross-Plane Contracts

Every state-changing management-to-control or control-to-data contract, and
every data-to-control observation, must carry enough identity to make execution
attributable, exact, and idempotent.

The typed contract must include, as applicable:

- unique message or request identity;
- correlation and causation identity;
- organization and mission scope;
- immutable artifact identity, version, and content hash;
- actor and policy-decision references;
- target resource and ownership key;
- generation or expected prior version;
- idempotency key;
- requested or effective time; and
- bounded metadata safe for audit.

Cadence should use domain-specific types such as `ApprovedContactPlan`,
`ActivationExecutionRequest`, `MissionRuntimeSpec`, or
`TransmitCommandRequest`. It should not replace clear domain contracts with one
unbounded generic plane message or a general-purpose `Cadence.Contracts`
package.

Contract ownership follows two rules:

- a command or request type is owned by its receiver; and
- a fact, event, or observation type is owned by its producer.

For example, Management owns an `ActivationApproved` fact, Data owns the
`MissionRuntimeSpec` accepted by its apply API and the `GenerationApplied`
observation it produces, and Control depends on those public types while
coordinating the handoff. Management does not construct runtime state, and Data
does not fetch the approval record.

### 8. State Ownership

Cadence distinguishes four kinds of truth:

| Kind | Owner | Examples |
| --- | --- | --- |
| Governed intent | Management | configuration versions, policies, approvals, proposed plans, approved command requests |
| Operational intent and lifecycle | Control | active-basis generation, provider reservation, scheduled Contact, command queue entry, release attempt |
| Execution state and evidence | Data | live process state, protocol state, raw ingress, telemetry samples, transport observations |
| Read projection | Derived, cross-cutting | dashboard frames, health summaries, audit timelines, operator lists |

Read projections do not acquire authority merely because they are persisted or
shown to an operator. They are rebuildable views over one or more authoritative
sources.

### 9. Reconciliation Belongs To The Control Plane

Level-triggered reconciliation, edge-triggered notification, process-owned
schedules, durable queues, and safety polling remain approved patterns from
ADR-013.

Under this ADR:

- reconciliation is a control-plane responsibility;
- the control plane compares durable operational intent with observed runtime
  state;
- the control plane sends idempotent apply, start, stop, or action requests to
  the data plane; and
- the data plane reports applied generations and execution observations.

A protocol timer inside COP-1 remains data-plane state because it executes the
selected protocol. A timer deciding when a Contact should be realized remains
control-plane state because it decides operational lifecycle.

### 10. Authentication And Actor Context

User and service actor authorization is evaluated at management and externally
invoked control-plane boundaries through `Cadence.Auth.Scope` and policy.

An approved handoff preserves actor and policy evidence, but data-plane workers
do not receive a live user session or independently reinterpret actor roles.
Internal automation uses service-backed scope at the management or control
boundary and does not gain a hidden bypass.

### 11. Provider Boundaries

Cadence distinguishes three provider responsibilities:

- Provider Account, grant, credential reference, and mission-provider
  configuration are management-plane concerns;
- provider capabilities, inventory synchronization, opportunity search,
  reservation, modification, cancellation, event recovery, and reconciliation
  are control-plane concerns; and
- path-local TCP, UDP, SLE, object-delivery, or other live delivery adapters are
  data-plane concerns.

An external vendor may call its API a control plane. Cadence's Provider Client
is the Cadence control-plane adapter to that external control plane. It remains
separate from the data-delivery adapter.

### 12. Observability, Archives, Jobs, And Read Models Are Cross-Cutting

These mechanisms do not define additional planes:

- every plane emits telemetry and attributable events;
- archives store data-plane evidence and other append-only history;
- read models project management, control, and data facts for operators;
- a background job belongs to the plane whose operation it executes; and
- dashboards consume read contracts without becoming the source of operational
  truth.

### 13. Logical Boundary And Enforcement Before Deployment Boundary

Cadence will enforce the plane model inside the existing umbrella before
requiring separate releases, databases, or nodes.

The architecture boundary must become executable before broad module movement.
Cadence's dependency checks will:

- classify modules by plane namespace or an explicit temporary ownership map;
- default-deny cross-plane references except for named public APIs, commands,
  facts, observations, and immutable value types;
- continue to prohibit cross-context Ecto-schema dependencies;
- prohibit references to another plane's process implementation or registered
  process name; and
- baseline existing violations with an owner and removal phase while rejecting
  new violations.

The adoption order is:

1. plane classification and executable dependency rules;
2. explicit application-service, command, fact, and value-type contracts;
3. plane-specific test harnesses and boot-isolation fitness checks;
4. namespace and state ownership;
5. separate internal supervisors and restart domains; and
6. optional OTP application or deployment extraction when the dependency graph
   is one-way and an operational need justifies it.

The target is not a distributed system by default. A module move or service
split that does not improve authority, dependency direction, restart behavior,
or testability is not progress toward this ADR.

### 14. Test Isolation Is An Architectural Property

A plane boundary is not complete unless its focused tests can exercise that
plane without starting unrelated planes. Compiling all modules in the current
umbrella application is temporarily acceptable; booting Management or Control
to test Data behavior, or booting Data to test Management behavior, is not the
target test architecture.

Cadence uses four test tiers:

| Tier | Processes and resources started | Purpose |
| --- | --- | --- |
| Pure contract or domain | None | Value construction, validation, hashes, invariants, and deterministic transformations |
| Plane component | The smallest supervisor or process owned by the plane under test | Plane behavior with other planes represented by public-contract fixtures or fakes |
| Adjacent integration | Exactly the two adjacent planes involved in a handoff | Contract compatibility, idempotency, causation, and recovery across one boundary |
| End to end | All required planes, web boundaries, and adapters | A small set of critical operational workflows and audit chains |

The following testability rules are mandatory:

1. Management, Control, and Data each have a focused suite that runs without
   starting either unrelated plane.
2. Data-plane tests construct exact runtime specifications and typed actions
   directly. They do not invoke Control merely to manufacture test setup.
3. Plane-component tests start the smallest owned supervised subtree. Starting
   the root Cadence application is reserved for tests whose subject is full
   application startup or an end-to-end workflow.
4. Repo, PubSub, archives, sockets, and external adapters start only when the
   behavior under test requires them. Persistence-backed data-plane components
   may use the Repo without booting Management or Control.
5. Contract test data follows contract ownership: producers provide canonical
   fact and observation fixtures; receivers provide command and request
   constructors. Tests do not exchange another plane's Ecto rows or mock its
   implementation modules.
6. Clocks, retry triggers, external adapters, event sinks, and process names are
   explicit dependencies where they affect behavior. Routine component tests
   do not depend on wall-clock sleeps, network availability, global application
   configuration, or globally registered processes.
7. Tests that do not own a global resource are parallel-safe by default.
8. Adjacent integration tests prove one typed handoff. Cross-plane workflow
   orchestration and browser behavior do not belong in a plane-component suite.
9. Each plane has an executable boot-isolation fitness test proving that its
   focused suite does not start unrelated plane supervisors or services.

Each plane will have a named focused test entry point. Warm startup and
execution time are measured as architecture fitness signals, with budgets
recorded in the target architecture or developer testing guide. The root
precommit suite remains the final repository gate, not the required inner loop
for a plane-local change.

Logical test isolation comes before OTP application extraction. If compilation
of unrelated plane code remains the dominant cost after boot and fixture
isolation, extracting a plane into an umbrella application is justified by the
test-performance and dependency benefit even when separate deployment is not
needed.

### 15. Product Vocabulary Remains Domain-Specific

Management plane, control plane, and data plane are architectural terms.

Cadence's primary UI and API vocabulary remains domain-specific: Spacecraft
Profile, Transport, Routing Rule, Contact Requirement, Contact Plan, Contact,
Command, Dashboard, and related aerospace nouns. Cadence will not add generic
"Management Plane" or "Control Plane" navigation merely to mirror the code
architecture.

## Consequences

### Positive

- Authorization and approval are separated from operational execution.
- Schedulers and reconcilers have a clear home outside the byte-processing data
  plane.
- Runtime workers receive exact configuration rather than reaching back into
  mutable authoring state.
- Contact, Commanding, Activation, Ground Networks, and Dashboards gain
  repeatable responsibility seams.
- Future process, node, or application separation can follow dependency
  direction instead of inventing it during deployment work.
- Audit and incident reconstruction can follow causation across all three
  planes.
- Plane-local changes gain a focused, deterministic test loop that does not
  require unrelated operational infrastructure.

### Negative

- Several existing contexts and facades span more than one plane and must be
  decomposed.
- More explicit handoff types, generations, events, and idempotency behavior
  are required.
- Some workflows that are currently one function call will become durable,
  multi-stage state machines.
- Read models and operational APIs must distinguish authoritative state from
  derived presentation state.
- The architecture has more concepts and requires executable dependency
  guardrails to remain useful.
- Test fixtures, process names, clocks, and adapters require explicit ownership
  instead of relying on globally started application state.

### Constraints Introduced

- Management may not directly mutate data-plane workers.
- Data-plane code may not authorize users or select mutable management state.
- Control is the exclusive authority for realizing approved intent into
  operational state.
- Cross-plane mutations are typed, attributable, versioned, and idempotent.
- Reconciliation is control-plane behavior.
- Plane boundaries are not inferred from storage technology, OTP usage, route
  location, or UI placement.
- A focused plane suite may not require unrelated plane supervisors or services
  to be running.

## Initial Adoption Priorities

1. Introduce plane-specific test entry points, minimal plane test supervisors,
   and boot-isolation checks.
2. Replace direct binding-set activation with a governed activation request,
   approval, execution, and active-generation handoff.
3. Separate mission control ownership from mission data-plane supervision.
4. Split Contact planning/governance, Contact lifecycle control, and realized
   Contact runtime execution.
5. Split Command authoring/approval, queue/release control, and live command
   execution.
6. Separate provider administration, provider control APIs, and live delivery
   adapters.
7. Recast dashboards and operational APIs as management/read-side consumers of
   explicit plane contracts.

## See Also

- [Management, Control, and Data Plane Target Architecture](../architecture/management-control-data-plane-target.md)
- [Cadence Context Dependency Policy](../architecture/context-dependency-policy.md)
- [ADR-001: Mission-Scoped Runtime and Selector Model](001-mission-scoped-runtime-and-selector-model.md)
- [ADR-003: Authorization Context and Policy Evaluation Model](003-authorization-context-and-policy-evaluation-model.md)
- [ADR-004: Activation Authorization and Approval Policy](004-activation-authorization-and-approval-policy.md)
- [ADR-006: Contact, Link, and Transport Runtime Model](006-contact-link-and-transport-runtime-model.md)
- [ADR-011: Command Staging, Queueing, and Release Lifecycle](011-command-staging-queueing-and-release-lifecycle.md)
- [ADR-012: Provider Adapter and Ground Station Simulator Model](012-provider-adapter-and-ground-station-simulator-model.md)
- [ADR-013: Control Plane, Data Plane, and Reconciliation Patterns](013-control-plane-data-plane-and-reconciliation-patterns.md)
