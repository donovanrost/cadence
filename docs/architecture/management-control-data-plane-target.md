---
title: Management, Control, and Data Plane Target Architecture
tags:
  [developer, architecture, management-plane, control-plane, data-plane, target]
status: active
created: 2026-07-21
updated: 2026-07-21
owner: Cadence core architecture
---

# Management, Control, and Data Plane Target Architecture

## Purpose

This document turns
[ADR-015](../decisions/015-management-control-data-plane-architecture.md) into
an end-state design for Cadence. It describes what the system should look like
after the plane boundaries are fully expressed in application services, state
ownership, process supervision, and dependency rules.

This is a target, not a claim about the current checkout. The migration is
incremental, but each slice should make the final shape more visible rather
than add a compatibility layer around the current one.

The architecture has three authority planes and two cross-cutting structures:

```text
                          OPERATOR AND SERVICE ADAPTERS
                                      |
                    +-----------------+-----------------+
                    |                                   |
                    v                                   v
          +--------------------+              +--------------------+
          |  MANAGEMENT PLANE  |              | READ / QUERY SIDE  |
          | intent, policy,     |              | projections across |
          | approval, audit     |              | all three planes   |
          +----------+---------+              +----------+---------+
                     | approved intent                    ^
                     v                                    |
          +--------------------+                           |
          |   CONTROL PLANE    |---------------------------+
          | schedule, select,  | lifecycle and audit facts
          | reconcile, dispatch|
          +----------+---------+
                     | exact runtime spec or action
                     v
          +--------------------+
          |     DATA PLANE     |---------------------------+
          | bytes, protocols,  | observations and evidence
          | live execution     |                           |
          +--------------------+                           v
                                                    ARCHIVE / HISTORY
```

Read models and archives support the planes; they do not acquire decision
authority of their own.

## Design Principles

### Plane And Bounded Context Are Different Axes

The existing
[context dependency policy](context-dependency-policy.md) describes business
ownership such as Catalog, Comms, Contact Planning, Contacts, Commanding,
Runtime, Telemetry, and Dashboards.

The plane model describes authority within and between those business areas.
A current context may need to split because it owns transitions in more than one
plane. For example:

- Commanding contains management-plane approval, control-plane release, and
  data-plane transmission behavior;
- Contacts contains management-owned setup compatibility, control-plane
  scheduling, and data-plane realized runtime handoff; and
- Runtime contains both mission control reconciliation and data-plane execution.

A correct end-state module satisfies both axes:

- its domain ownership is clear; and
- its plane authority is singular.

### Authority Follows State Transitions

The owner of a state transition owns the use case, transaction, invariants, and
public result. Storage location does not change that ownership.

Examples:

- approval of a Contact Plan is management-owned;
- transition of a provider reservation from pending to confirmed is
  control-owned;
- transition of a TCP receiver from disconnected to connected is data-owned.

### Handoffs Are Durable At Correctness Boundaries

When losing a handoff could lose an approved operation, the sending plane first
records authoritative state, then signals the receiving owner. The receiving
plane handles the request idempotently. Reconciliation repairs a lost signal.

No design relies on a PubSub message, GenServer call, or in-memory queue as the
only record that an approved operational action must occur.

### Read Models Do Not Become Write Backdoors

Dashboards, status pages, search indexes, health snapshots, and timelines may
combine facts from all planes. They remain read-side projections.

A button rendered beside a projection invokes the owning management or control
application service. It does not update the projection row and infer that the
authoritative operation occurred.

## End-State State Model

The system should make state ownership obvious from its type and storage API.

| State family | Plane owner | Durable authority | Typical runtime representation |
| --- | --- | --- | --- |
| Organization, identity, membership, mission | Management | Postgres | request-scoped `Scope` |
| Catalog, profile, Transport, Routing Rule versions | Management | immutable/versioned Postgres rows and events | validated value objects |
| Approval and policy decisions | Management | append-only decision records plus workflow projection | none required |
| Contact Requirement and proposed Plan | Management | immutable versions plus current workflow projection | planning inputs/results |
| Approved command intent | Management | immutable request, items, approval evidence | encoded-independent command model |
| Active basis | Control | generation record pointing to exact management versions | mission-control projection |
| Provider reservation and scheduled Contact | Control | durable lifecycle and attempt records | scheduler projection and timers |
| Command queue and release attempt | Control | durable queue/lifecycle records | lane projection and timers |
| Runtime placement and applied generation | Control | desired/applied generation and ownership records | reconciler state |
| Contact, Path, and Transport execution | Data | observations and retained execution evidence | supervised processes |
| Protocol and capability state | Data | snapshots only when required for recovery or evidence | process state |
| Raw ingress and protocol records | Data | archive | ordered queues and bounded batches |
| Current telemetry and live health | Data | rebuildable or bounded projection | ETS/process state |
| Operator views and dashboard frames | Read side | rebuildable projection or query result | caches keyed by source revisions |

Three similarly named things must remain distinct:

- **desired generation**: the control plane's exact runtime target;
- **applied generation**: the data plane's acknowledgement of the target it is
  executing; and
- **observed health**: current evidence about execution, which may be healthy,
  degraded, stale, or absent.

Health does not silently change desired generation. A failed apply does not
rewrite the approved management artifact.

## End-State Plane Responsibilities

### Management Plane

The management plane is organized around governed product nouns rather than a
generic configuration service.

Target capability groups:

```text
Cadence.Management.Identity
Cadence.Management.Missions
Cadence.Management.Catalog
Cadence.Management.Spacecraft
Cadence.Management.Comms
Cadence.Management.GroundNetworkAdministration
Cadence.Management.ContactPlanning
Cadence.Management.CommandGovernance
Cadence.Management.DashboardManagement
Cadence.Management.ActivationGovernance
```

The names are illustrative namespace destinations. Existing domain names may
remain when their ownership is already unambiguous. The important endpoint is
that every management mutation:

- accepts `Cadence.Auth.Scope` as its first argument;
- authorizes within organization and optional mission scope;
- produces immutable versions or explicit lifecycle transitions;
- records actor and policy evidence;
- never messages runtime processes directly; and
- exposes domain structs, not Ecto rows.

Management workflows may emit an approved-intent fact after the approving
transaction commits. A control-plane caller may also explicitly execute an
approved intent through a control service. Both paths resolve to the same
idempotent control operation.

### Control Plane

The control plane owns durable operational state and the active processes that
converge it.

Target capability groups:

```text
Cadence.Control.Activation
Cadence.Control.Missions
Cadence.Control.ProviderOperations
Cadence.Control.ContactPlans
Cadence.Control.Contacts
Cadence.Control.Commanding
Cadence.Control.RuntimePlacement
Cadence.Control.Jobs
```

The control plane contains two kinds of component:

1. application services and stores that make durable operational transitions;
2. supervised owners that schedule, reconcile, dispatch, and recover those
   transitions.

Control services accept either:

- a currently authorized `Scope` for an externally invoked operational action;
  or
- a typed approved intent containing persisted actor and policy evidence for
  asynchronous execution.

The control plane owns external provider scheduling APIs because they allocate
capacity and alter operational lifecycle. It does not own provider-delivered
telemetry sockets or protocol execution.

An approved management basis may authorize bounded automation, failover, and
safety response. Control owners can make those operational decisions from live
observations without returning to a human for each transition, but they must
remain inside the recorded policy and preserve the causation chain.

### Data Plane

The existing `Cadence.Runtime` vocabulary is a strong base for the data plane.
The target does not require a mechanical rename to `Cadence.DataPlane`.

Target capability groups:

```text
Cadence.Runtime.Missions
Cadence.Runtime.Partitions
Cadence.Runtime.Contacts
Cadence.Runtime.Paths
Cadence.Runtime.Transports
Cadence.Runtime.Ingress
Cadence.Runtime.Capabilities
Cadence.Runtime.CommandExecution
Cadence.Runtime.Telemetry
```

Data-plane entry points accept only typed runtime specifications, action
requests, ingress units, protocol events, or replay inputs. They do not accept a
controller params map or a user session.

The data plane may retain evidence and recovery state, but durable persistence
must stay off ordered hot paths unless correctness explicitly requires the
write. Archive and projector lanes remain the preferred destination for
high-rate history.

## Cross-Plane Contract Model

Cadence should use a small family of domain-specific contracts with consistent
metadata. It should not introduce a universal untyped envelope.

### Management To Control

Representative contracts:

- `ApprovedActivation`
- `ApprovedContactPlan`
- `ApprovedCommand`
- `ApprovedProviderConfigurationChange`
- `ApprovedDataSourceLifecycleChange`

Every contract identifies:

```text
request identity
correlation and causation identity
organization and mission scope
artifact identity, version, and content hash
requesting and approving actor references
policy decision and change class
idempotency key
approval and effective timestamps
```

The control plane verifies that the referenced artifact and approval still form
a valid immutable basis. It does not re-run management authoring logic against a
mutable draft.

### Control To Data

Representative contracts:

- `MissionRuntimeSpec`
- `RealizedContactRuntimeSpec`
- `ApplyRuntimeGeneration`
- `StartPath`
- `StopPath`
- `TransmitCommand`

Every runtime specification contains exact versions and fully resolved runtime
inputs. For example, a realized Contact runtime spec should contain selected
Routing Rule, Transport, provider delivery, profile, source-endpoint, and
capability configuration references. A data-plane worker should not query the
latest Transport or Routing Rule while starting.

Runtime apply commands identify the desired generation and expected prior
generation. Duplicate application is harmless. Applying an older generation
after a newer one is rejected.

### Data To Control

Representative observations:

- `RuntimeGenerationApplied`
- `RuntimeGenerationRejected`
- `ContactRuntimeStarted`
- `PathStateChanged`
- `TransportDeliveryChanged`
- `CommandAcceptedForTransmission`
- `CommandTransmitted`
- `CommandProtocolOutcomeObserved`
- `RuntimeCapacityChanged`

Observations identify the runtime owner, generation, correlation, evidence
references, and observed time. The control plane decides whether an observation
advances operational lifecycle.

For example, a transport observation does not directly mark a command verified.
The command control workflow correlates the observation and verifier policy,
then writes the authoritative verification transition.

### Facts To Read Models

Each plane publishes attributable facts after authoritative transitions. Read
models consume those facts or public query services and build:

- mission and Contact timelines;
- command narratives;
- runtime health summaries;
- audit history;
- dashboard operational frames; and
- notification projections.

Projection lag and source revision are explicit. A read model never pretends to
be the authoritative write model.

## Target Supervision Topology

The current `Cadence.Application` starts runtime, command dispatch, contact
scheduling, provider reconciliation, dashboard runtime services, projections,
archives, and jobs as peers. The target makes restart and authority domains
visible.

```text
Cadence.Supervisor
|
+-- Cadence.Platform.Supervisor
|   +-- Repo
|   +-- PubSub
|   +-- observability exporters
|   +-- shared registries and secret clients
|
+-- Cadence.Management.Supervisor
|   +-- management workflow jobs
|   +-- approval/notification delivery workers
|   +-- managed-resource lifecycle request dispatch
|
+-- Cadence.Control.Supervisor
|   +-- organization/provider control owners
|   +-- mission control dynamic supervisor
|   |   +-- ActiveBasisController
|   |   +-- MissionRuntimeReconciler
|   |   +-- ContactScheduler
|   |   +-- mission command dispatch supervision
|   +-- provider reservation reconcilers
|   +-- control-plane job dispatch
|
+-- Cadence.Runtime.Supervisor
|   +-- capability registry
|   +-- mission data-plane dynamic supervisor
|       +-- partition runtimes
|       +-- realized Contact runtimes
|           +-- Path runtimes
|               +-- provider delivery adapters
|               +-- Transport runtimes
|               +-- ingress executor and projector
|
+-- Cadence.Projections.Supervisor
    +-- durable event projectors
    +-- dashboard/runtime read caches
    +-- health and notification projections
```

The critical change is that a mission control owner is not a child of the
mission data-plane supervisor. Control-plane failure and restart should rebuild
desired state and reconcile the data plane. Data-plane failure should restart
execution and report observed state without taking down the authoritative
control owner.

The control plane may intentionally restart a data-plane scope to apply a new
generation. The data plane must never terminate its control owner as an
incidental consequence of a path or protocol crash.

## Target Vertical Workflows

### Activation

End-state flow:

```text
author version -> validate -> request -> approve
    -> ApprovedActivation
    -> ActivationExecutor writes ActiveBasis generation N
    -> MissionRuntimeReconciler builds MissionRuntimeSpec generation N
    -> data plane applies N
    -> RuntimeGenerationApplied N
    -> control records convergence
```

Target ownership:

- management owns authoring, validation, request, approval, and audit;
- control owns activation execution, active generation, and convergence;
- data owns execution of the applied generation.

The current direct `activate_binding_set/5` path should become an internal
control operation that is reachable only with an approved activation basis or
an explicit development fixture boundary.

### Contact Planning And Execution

End-state flow:

```text
Requirement -> search evidence -> Plan version -> approval
    -> ApprovedContactPlan
    -> plan execution items
    -> provider reservations and recovery
    -> Scheduled Contact lifecycle
    -> RealizedContactRuntimeSpec
    -> Contact / Path / Transport runtime
```

Target ownership:

- management owns Requirements, policies, search evidence retained for
  decision-making, proposed Plan versions, approvals, and automation grants;
- control owns execution items, provider capacity mutations, reservations,
  scheduled Contacts, realization, and early termination;
- data owns realized Contact, Path, provider delivery, and Transport execution.

Provider opportunity search is operational control even when initiated while
authoring a Plan. The management plane retains the bounded search result as
decision evidence; it does not own the vendor control API.

### Commanding

End-state flow:

```text
stage -> request -> validate -> approve
    -> ApprovedCommand
    -> queue entry -> release target selection -> release attempt
    -> TransmitCommand
    -> encode / frame / protocol / provider delivery
    -> transmission and telemetry observations
    -> control-owned verification lifecycle
```

Target ownership:

- management owns command definition selection, arguments, staging, request,
  validation, approval, and safety policy;
- control owns queue lanes, priority, `not_before`, release constraints, target
  selection, attempts, retry, and verifier lifecycle;
- data owns exact encoding, framing, COP-1 state, transport action execution,
  and correlated live observations.

The final bytes are derived from the approved immutable command basis. A
control-plane release must not re-read a mutable stage and a data-plane encoder
must not decide whether approval is adequate.

### Provider Integration

End-state flow:

```text
Provider Account / credential / grant / Mission Provider configuration
    -> approved provider operational basis
    -> capability and inventory control APIs
    -> opportunity and reservation control APIs
    -> exact delivery configuration in RealizedContactRuntimeSpec
    -> path-local provider data adapter
```

The three responsibilities should have separate registries and contracts:

- provider administration registry for account/configuration kinds;
- Provider Client registry for control-plane behavior;
- provider delivery adapter registry for data-plane wire behavior.

A provider implementation may supply both a client and a delivery adapter, but
those modules do not call each other through hidden provider-specific state.
They meet through durable provider references and exact runtime specifications.

### Telemetry Ingress

End-state flow:

```text
provider bytes -> path-local ordered ingress -> protocol decode
    -> mission partition and capability execution
    -> current-value / live projections
    -> async archive and durable projectors
```

This is almost entirely data-plane work. The control plane observes capacity,
delivery, ownership, and lifecycle signals. The management plane defines and
approves the catalog, selectors, and capability basis used by the applied
runtime generation.

### Dashboards And Operator Experience

Dashboard definition, versioning, publication, data-source administration, and
credential policy are management-plane operations.

Dashboard resolution is a read-side operation. It may query:

- management facts such as exact configuration revisions;
- control facts such as Contact phase, command queue depth, reservation status,
  or applied generation; and
- data facts such as telemetry, transport bitrate, connection state, or runtime
  activity.

Data-source provisioning and deprovisioning follow the normal split:

- management authorizes and records the desired lifecycle change;
- control executes and reconciles the infrastructure operation; and
- the read side presents desired, actual, and observed health separately.

The page remains telemetry-first. Plane provenance is available for diagnosis,
but generic plane labels do not become primary dashboard chrome.

## Target Code And Application Shape

### Inside The Existing `:cadence` Application

The first complete logical shape can exist without an umbrella split:

```text
Cadence.Management.*
Cadence.Control.*
Cadence.Runtime.*
Cadence.Projections.*
Cadence.Platform.*
```

Existing cohesive namespaces such as `Cadence.Catalog` or
`Cadence.ContactPlanning` do not need a mechanical rename if their public API is
unambiguously management-owned and architecture policy classifies them as such.
Mixed facades such as `Cadence.Commanding`, `Cadence.Contacts`, and
`Cadence.Runtime` should shrink toward explicit plane-owned application
services.

The root `Cadence` facade and `CadenceWeb.ControlPlane*` catch-all modules are
transitional. Web code should call resource- and plane-specific boundaries such
as management command parsing, control Contact execution, or telemetry query
serialization rather than one API namespace that implies every endpoint is
control-plane work.

### Possible Umbrella End State

If internal dependency direction becomes clean and separate restart or release
behavior is operationally useful, the likely application topology is:

```text
cadence_web
  |---> cadence_management ---> cadence_catalog
  |---> cadence_control -------> cadence_management
  |              |------------> cadence_runtime
  |---> cadence_projections ---> management/control/runtime public facts

cadence_runtime ---------------> cadence_catalog
  |----------------------------> cadence_ccsds

cadence_simulator -------------> cadence_ccsds
```

Shared platform infrastructure remains narrow: Repo process, PubSub/event
transport, identifiers, clocks, observability, secrets, and low-level tenant
scoping. Each plane still owns its schemas, stores, transactions, and domain
types. A shared platform application must not become a new horizontal business
logic layer.

Application extraction is justified only when:

- production dependencies are one-way;
- cross-plane calls use stable public contracts;
- Ecto schemas do not cross the boundary;
- each application's tests can run without booting unrelated planes;
- startup and restart behavior is explicit; and
- independent deployment, scaling, or fault isolation has a concrete benefit.

Separate databases are not an assumed target. State ownership and schema
ownership come first. Physical stores can remain shared while transactions and
queries respect plane boundaries.

## Dependency Rules And Fitness Functions

The target should become executable through architecture checks.

Required rules:

1. management production code cannot depend on `Cadence.Runtime` or call
   control implementation modules;
2. data-plane production code cannot depend on management stores, policy,
   approvals, controller params, or Ecto rows;
3. control code may depend only on management public services/value types and
   runtime public commands/observations;
4. no cross-plane caller depends on another plane's schema module;
5. `Cadence.Auth.Scope` appears at management and external control boundaries,
   not in data-plane worker state;
6. data-plane runtime specs contain no unresolved `latest` references;
7. direct process messaging across planes is hidden behind a public service;
8. new cross-plane mutations include correlation, exact basis, and idempotency;
9. plane supervisors have independent restart tests; and
10. every reconciler documents desired source, observed source, ownership key,
    idempotency, and missed-signal recovery.

Useful test layers:

- pure contract tests for version, hash, and invariant validation;
- management workflow tests proving authorization and approval evidence;
- control state-machine tests proving idempotency and reconciliation;
- data-plane contract tests proving exact-generation application;
- vertical integration tests proving one handoff between adjacent planes; and
- a small number of end-to-end workflows proving full causation and audit.

## Migration Sequence

### Phase 0: Publish And Guard The Model

- Accept ADR-015 and this target architecture.
- Classify existing namespaces and supervised children by plane role.
- Add an initial architecture check that prevents new management-to-runtime
  dependencies and new data-to-management dependencies.
- Treat existing exceptions as named, reviewable debt rather than permission
  for growth.

### Phase 1: Activation Reference Slice

- Add governed activation request, approval, and execution records.
- Introduce an `ApprovedActivation` handoff.
- Move active-basis mutation behind a control-plane executor.
- Give active basis a monotonic generation and immutable content basis.
- Have mission control reconcile that generation into runtime.
- Expose desired, applied, and observed activation state separately.

This is the reference implementation because it exercises every plane without
requiring a broad product rewrite.

### Phase 2: Separate Mission Control From Mission Runtime

- Introduce a mission control supervisor and runtime reconciler.
- Move active-basis ownership and Contact scheduling out of the data-plane
  mission supervisor.
- Define `MissionRuntimeSpec` and applied-generation observations.
- Keep runtime partition and realized Contact supervisors under the data plane.

### Phase 3: Contact Vertical Split

- Keep Contact Requirements, planning policy, Plan versions, and approvals in
  management.
- Move Plan execution, Provider Reservation, scheduled Contact, and lifecycle
  reconciliation under control.
- Build `RealizedContactRuntimeSpec` as the only start input for data-plane
  Contact execution.
- Remove data-plane reads of mutable Routing Rule, Transport, or provider setup.

### Phase 4: Commanding Vertical Split

- Separate command authoring/approval from queue/release control.
- Make an approved immutable command the queue input.
- Create a typed control-to-data transmit request.
- Feed transport and telemetry observations back to the control-owned verifier
  workflow.

### Phase 5: Provider And Managed Resource Split

- Separate provider administration from Provider Client control behavior and
  live delivery adapters.
- Apply the same request/execution/observation model to data-source and TSDB
  lifecycle operations.

### Phase 6: Read Side And Web Boundaries

- Replace catch-all control-plane params and JSON modules with resource-owned
  boundary modules.
- Make dashboard and operator pages consume explicit read models.
- Show desired, operational, applied, and observed state without conflating
  them.
- Keep existing authenticated router scopes and product navigation unless a
  product requirement—not the internal plane model—justifies a route change.

### Phase 7: Physical Extraction

- Group processes under independent plane supervisors.
- Measure xref direction, boot coupling, failure isolation, and test startup.
- Extract an umbrella application only when its API is already a one-way
  dependency leaf and the extraction improves an operational property.

## End-State Completion Criteria

The rearchitecture is complete when:

- every authoritative mutation has one documented plane owner;
- activation, Contact, Commanding, provider, and managed-resource flows use
  typed adjacent-plane handoffs;
- management cannot directly manipulate runtime processes;
- data-plane workers start from exact runtime specs and do not select mutable
  management state;
- desired, applied, and observed state are independently visible;
- mission control and mission data-plane supervision are separate restart
  domains;
- cross-plane Ecto-schema dependencies are zero;
- architecture checks reject reverse dependencies;
- focused tests can boot and exercise each plane without unrelated runtime
  setup; and
- any application/deployment split follows the documented dependency graph
  rather than compensating for cycles.

## Explicit Non-Goals

- No generic management-plane or control-plane user navigation.
- No immediate microservice decomposition.
- No database-per-plane requirement.
- No replacement of aerospace product nouns with infrastructure terminology.
- No event sourcing requirement for every aggregate.
- No mandate that all cross-plane interactions be asynchronous.
- No persistence of every runtime snapshot merely to make it visible.
- No new compatibility facade that preserves mixed-plane APIs indefinitely.

## Open Design Work

The ADR decides the authority model. These details should be resolved in the
first implementation slices:

1. the exact activation request and approval schemas;
2. generation and compare-and-set semantics for active and applied runtime
   bases;
3. whether control-to-data handoffs use direct calls plus durable desired state,
   a transactional outbox, or a combination;
4. the multi-node ownership and placement mechanism for mission control and
   data-plane scopes;
5. the minimum runtime-spec snapshot needed for deterministic restart and
   replay;
6. event retention and projection rebuild strategy for cross-plane operator
   timelines; and
7. the first architecture dependency rules that can be enforced without
   freezing legitimate migration work.

## Related Documents

- [ADR-015: Management Plane, Control Plane, and Data Plane Architecture](../decisions/015-management-control-data-plane-architecture.md)
- [Cadence Context Dependency Policy](context-dependency-policy.md)
- [Cadence Architecture and Test Performance Review](../architecture-and-test-performance-review.md)
- [Developer Architecture Guide](../developer-architecture-guide.md)
- [Understand the Runtime Substrate and Capabilities](../how-to/understand-the-runtime-substrate-and-capabilities.md)
