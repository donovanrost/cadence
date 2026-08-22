---
title: "ADR-007: First-Party Capability ABI"
aliases: [plugin abi, capability abi, first party plugin model]
tags: [adr, architecture, extensibility, plugin, capability, replay]
status: accepted
created: 2026-03-28
updated: 2026-03-28
---

# ADR-007: First-Party Capability ABI

## Status

Accepted

## Context

Cadence must support runtime extensibility for mission-varying protocol and
application needs such as:

- telemetry semantic handling
- `CFDP`
- mission-specific download applications
- projections
- transport-local extensions such as `COP-1`

At the same time, extensibility must not break the guarantees already established
by earlier decisions:

- [ADR-001](001-mission-scoped-runtime-and-selector-model.md): governed runtime
  activation and selector-based semantic routing
- [ADR-004](004-activation-authorization-and-approval-policy.md): capability
  activation is governed and attributable
- [ADR-005](005-runtime-partitioning-and-workload-isolation.md): partition
  ownership and workload isolation are platform concerns
- [ADR-006](006-contact-link-and-transport-runtime-model.md): transport-local
  behavior and mission semantic behavior are different runtime concerns

The main architectural risk is treating “plugins” as arbitrary executable hooks.
If Cadence allows arbitrary side effects or generic untyped callbacks in the
core record path, it loses:

- replay determinism
- approval boundaries
- partition placement guarantees
- clean auditability
- runtime safety and failure isolation

Cadence therefore needs a constrained first-party extensibility model.

## Decision

Cadence will model first-party plugins as registered capability families with
typed capability kinds, explicit descriptors, explicit context, typed action
requests, and canonical-record-log authority for stateful recovery.

Capabilities consume canonical records and context, and emit canonical records
plus typed action requests. Capability logic must not perform direct external
side effects.

### 1. First-Party Only In The Current Phase

Release one extensibility is limited to first-party capability families shipped
with Cadence.

Mission-supplied executable plugins are explicitly deferred.

This ADR defines the ABI shape that first-party capability families must follow.

### 2. Capabilities Are Registered Families, Not Ad Hoc Hooks

Each capability family is registered in the platform with a stable identity and
declared behavior.

Missions instantiate capability families as governed configuration data.

The platform owns:

- activation and approval
- placement and partition affinity
- selector resolution and routing
- runtime supervision
- persistence and replay context
- authorization and action execution

Capability families own:

- config validation within their declared schema
- domain-specific record handling logic
- state-machine behavior where applicable
- emitted canonical records and action requests

### 3. Capability Kinds

Cadence supports four first-party capability kinds:

- `SemanticHandler`
- `ManagedApplication`
- `Projection`
- `TransportExtension`

Cadence should not force these concerns through one generic universal callback
shape.

#### SemanticHandler

Consumes canonical protocol-stage records inside mission endpoint partitions and
emits canonical semantic domain records.

Examples:

- telemetry packet handling
- custom mission message decode

#### ManagedApplication

Long-lived, stateful mission- or endpoint-scoped application instance.

Examples:

- `CFDP`
- mission-specific file download applications

#### Projection

Consumes canonical records and produces read-model or projection writes.

Examples:

- latest-value projections
- fleet summary projections

#### TransportExtension

Path- or transport-local runtime extension under contact or path runtime.

Examples:

- `COP-1`
- provider session adapters
- continuity or transport monitors

### 4. Shared Capability Descriptor

Every capability family must expose a descriptor with at least:

```elixir
%CapabilityDescriptor{
  family_key: atom(),
  kind: :semantic_handler | :managed_application | :projection | :transport_extension,
  supported_scopes: [atom()],
  input_stages: [atom()],
  partition_affinity: atom(),
  config_schema: module(),
  emitted_record_kinds: [atom()],
  emitted_action_kinds: [atom()],
  replay_mode: :deterministic,
  state_mode: :stateless | :stateful
}
```

This descriptor is used by the platform to validate activation, placement, and
runtime compatibility before workers start.

### 5. Explicit Capability Context

Capability logic receives explicit runtime context rather than reading hidden
global state.

Capability context should include fields equivalent to:

```elixir
%CapabilityContext{
  organization_id: binary(),
  mission_id: binary(),
  mission_basis_ref: binary(),
  scope_ref: binary(),
  partition_key: term(),
  replay?: boolean(),
  clock_ref: term(),
  metadata: map()
}
```

Capability logic should not depend on hidden database reads, hidden process
dictionary state, or direct wall-clock calls.

### 6. No Direct External Side Effects

Capability logic must not perform direct external side effects in its core
record-handling path.

Capabilities must not directly:

- call provider APIs
- write arbitrary database state outside platform-owned persistence boundaries
- send commands directly
- call external services ad hoc
- read wall clock time directly for behavior decisions

Instead, capabilities emit:

- canonical records
- typed action requests

Platform-owned executors carry out side effects under policy and audit control.

### 7. Typed Action Requests

Capabilities may emit typed action requests such as:

- `uplink_request`
- `provider_request`
- `schedule_timer`
- `cancel_timer`
- `operator_alert_request`

Action requests must be declared in the capability descriptor and validated by
the platform before execution.

Action requests are subject to platform authorization, approval, routing, and
execution rules.

### 8. SemanticHandler Contract

`SemanticHandler` families should implement a stateless or lightly stateful
record handler contract equivalent to:

```elixir
handle_record(record, ctx) ::
  {:ok, %{
    records: [canonical_record],
    action_requests: [action_request],
    anomalies: [canonical_record]
  }} | {:error, term()}
```

These handlers are normally invoked within mission endpoint partitions and are
expected to be deterministic given the input record, active basis, and context.

### 9. ManagedApplication Contract

`ManagedApplication` families implement long-lived state-machine behavior with a
contract equivalent to:

```elixir
init_instance(ctx) ::
  {:ok, app_state}

handle_record(record, app_state, ctx) ::
  {:ok, %{state: app_state, records: [...], action_requests: [...]}}

handle_timer(timer_ref, app_state, ctx) ::
  {:ok, %{state: app_state, records: [...], action_requests: [...]}}

snapshot_state(app_state, ctx) ::
  {:ok, snapshot}
```

Managed applications do not own scheduling primitives directly. Timer requests
go through the platform as action requests.

### 10. Projection Contract

`Projection` families implement read-model update behavior with a contract
equivalent to:

```elixir
project(record, projection_state, ctx) ::
  {:ok, %{state: projection_state, writes: [projection_write]}}

rebuild(source_stream, ctx) ::
  {:ok, rebuild_result}
```

Projections consume canonical records and emit projection writes only. They do
not perform arbitrary side effects.

### 11. TransportExtension Contract

`TransportExtension` families implement path- or transport-local operational
behavior with a contract equivalent to:

```elixir
init_transport(ctx) ::
  {:ok, transport_state}

handle_transport_event(event, transport_state, ctx) ::
  {:ok, %{state: transport_state, records: [...], action_requests: [...]} }

handle_control_input(control, transport_state, ctx) ::
  {:ok, %{state: transport_state, records: [...], action_requests: [...]} }

handle_timer(timer_ref, transport_state, ctx) ::
  {:ok, %{state: transport_state, records: [...], action_requests: [...]} }
```

This is the appropriate home for transport-local protocol behavior such as
`COP-1`.

### 12. Timer And Clock Control

Capabilities must not call wall-clock APIs directly for behavior that affects
runtime semantics.

Time enters capability logic only through:

- explicit context
- typed timer action requests
- timer firing callbacks invoked by the platform

This is required for replay determinism and controlled simulation.

### 13. Canonical Record Log Is Authoritative

For stateful capabilities, the canonical record log is the authoritative source
of truth.

Snapshots are optional acceleration aids for:

- recovery
- restart speed
- replay checkpointing

Snapshots are not the canonical source of truth and must not replace the ability
to reconstruct state from canonical records plus active basis.

### 14. Runtime Validation Rules

Before activation or instance start, the platform must validate that:

- the capability kind matches the configured runtime location
- the declared scope is compatible with the target scope
- the declared input stages are available at the binding point
- emitted record and action kinds are declared
- partition affinity is compatible with placement rules

Invalid capability placement or activation must fail before runtime start.

### 15. Replay Contract

First-party capabilities must support replay under the same capability ABI used
for live processing.

Replay should change only:

- runtime context, such as `replay?: true`
- time-driving mechanics
- action-request execution mode where necessary

Replay must not require a separate plugin path with different core logic.

### 16. Anti-Decisions

Cadence should not treat release-one plugins as:

- arbitrary code hooks with unrestricted runtime power
- direct database or network actors in the record-processing path
- timer-owning black boxes with hidden wall-clock behavior
- untyped emitters of arbitrary side effects
- components whose state exists only in snapshots

## Consequences

### Positive

- Extensibility remains compatible with governed activation, replay, and
  partition ownership.
- Different runtime concerns get different ABI shapes instead of one distorted
  generic callback interface.
- Side effects remain under platform policy and audit control.
- Stateful capabilities can recover deterministically because canonical records
  remain authoritative.
- The platform can validate capability placement and compatibility before live
  runtime impact.

### Negative

- The ABI is more structured and restrictive than a generic plugin system.
- Capability authors must fit behavior into typed record and action-request
  contracts.
- Platform-owned executors and timer services become more important because
  capabilities cannot bypass them.
- Some capabilities may require more upfront design to fit the deterministic
  model.

### Constraints Introduced

- Capability logic cannot perform direct external side effects.
- Stateful capability snapshots are optional acceleration only.
- Capability families must declare their emitted records and action requests.
- Replay and live processing must share the same core capability logic.

## Open Questions

1. What exact record and action-request families should release one expose as
   stable platform primitives?
2. Which scopes should release one permit for each capability kind?
3. How should capability descriptors be registered and versioned within Cadence?
4. What future additional constraints are needed before mission-supplied plugin
   execution, such as `WASM`, could be considered safe?

## See Also

- [Architecture Decision Records](./_index.md)
- [ADR-001: Mission-Scoped Runtime and Selector Model](001-mission-scoped-runtime-and-selector-model.md)
- [ADR-005: Runtime Partitioning and Workload Isolation](005-runtime-partitioning-and-workload-isolation.md)
- [ADR-006: Contact, Link, and Transport Runtime Model](006-contact-link-and-transport-runtime-model.md)
