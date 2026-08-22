---
title: "ADR-001: Mission-Scoped Runtime and Selector Model"
aliases: [runtime selector model, mission scoped runtime, activation model]
tags: [adr, architecture, runtime, selector, activation, mission]
status: accepted
created: 2026-03-28
updated: 2026-07-21
---

# ADR-001: Mission-Scoped Runtime and Selector Model

## Status

Accepted

## Context

Cadence is being rebuilt as a ground data system for large-scale constellation
operations, not as a single-mission telemetry pipeline.

Missions vary substantially:

- spacecraft may run different flight software distributions
- the same `APID` may mean different things on different spacecraft
- some spacecraft may enable new protocol/application families over time, such
  as `CFDP`
- some missions may introduce relay topologies where traffic is observed on one
  path but semantically belongs to another endpoint

Cadence must support runtime reconfiguration without application redeploy. A
user should be able to:

- add a new spacecraft
- activate new telemetry bindings
- enable a new first-party application family such as `CFDP`

and have Cadence converge its running system to the new desired state
automatically.

We also need clear runtime behavior for:

- how configuration becomes active
- how running processes are scoped
- how traffic is matched to application handlers
- what happens when traffic does not match any handler

## Decision

Cadence will use a mission-scoped reconciled runtime with explicit activation
and canonical-record-based selectors.

### 1. Root Runtime Scope

The top-level runtime scope is `mission`.

Cadence will run one reconciled mission runtime per active mission. Within a
mission runtime, Cadence may manage subordinate scopes such as:

- spacecraft
- relay endpoints
- contacts
- link sessions
- transport service instances

Telemetry meaning and application binding are mission-runtime concerns, not
contact-runtime concerns.

### 2. Runtime Behavior

Cadence behaves as a governed management plane, an operational control plane,
and a reconciled data-plane runtime, using the definitions in
[ADR-015](015-management-control-data-plane-architecture.md):

1. Users and services define desired state through management-plane APIs or UI.
2. Desired state is stored as governed, versioned configuration.
3. The control plane executes an approved activation and makes one exact
   configuration generation operational for a scope.
4. Control-plane reconcilers converge data-plane runtime instances to that
   active generation.
5. New live traffic is interpreted by the data plane against the applied
   generation for that mission.

Activation affects future live traffic only.

Historical traffic is never silently reinterpreted. Processing historical
traffic under a different basis requires an explicit replay or reprocessing job.

### 3. Capability Model

Cadence ships capability families in code. Missions instantiate those
capabilities as data.

Examples of capability families:

- telemetry packet handling
- derived telemetry evaluation
- limit evaluation
- `CFDP`
- file download applications
- projections and archive writers

Each managed runtime instance is a scoped instantiation of one capability
family.

Near-term plugin support is limited to first-party capability families shipped
with Cadence. Mission-supplied executable plugins are deferred.

### 4. Configuration and Activation Model

Cadence configuration is modeled as immutable, versioned activation sets.

An activation set contains the desired runtime configuration for a mission or a
sub-scope within that mission.

At minimum, activation-controlled configuration includes:

- source endpoint definitions
- spacecraft associations
- protocol/application selectors
- managed application instances
- handler configuration payloads

Configuration lifecycle states are:

- drafted
- validated
- active

Runtime-affecting changes require explicit activation.

### 5. Semantic Source Identity

Cadence will not interpret traffic using `APID` alone or `SCID` alone.

Traffic meaning is resolved using a semantic source identity:

- `source_endpoint_ref`

`source_endpoint_ref` may be derived from:

- `SCID`
- provider or path metadata
- relay context
- mission-governed source mapping

Observed transport context remains important, but it is not the primary semantic
meaning key.

### 6. Selector Inputs

Selectors match canonical records at explicit protocol stages, not raw byte
patterns.

Selectors may match on a canonical envelope shaped like:

```elixir
%{
  mission_id: ...,
  source_endpoint_ref: ...,
  spacecraft_id: ...,
  direction: :downlink | :uplink,
  protocol_stage: :raw_evidence | :transfer_frame | :space_packet | :encapsulation_packet | :app_pdu,
  protocol_family: :tm | :tc | :aos | :uslp | :cfdp | ...,
  contact_ref: ...,
  link_ref: ...,
  provider_path_ref: ...,
  scid: ...,
  vcid: ...,
  map_id: ...,
  apid: ...,
  packet_type: ...,
  service_type: ...,
  service_subtype: ...,
  app_kind: ...,
  metadata: %{...}
}
```

Release one may use only a subset of these fields, but this is the target
selector envelope.

### 7. Selector Resolution Model

Selector meaning is scoped by:

- `mission_id`
- `source_endpoint_ref`
- `protocol_stage`
- active configuration basis

This means an `APID` only has meaning within scoped mission configuration, not
globally across Cadence.

Selectors must support:

- mission-wide defaults
- more specific source-endpoint overrides
- optional context matching on protocol-layer fields

### 8. Dispatch Semantics

For a matched record, Cadence dispatches to:

- one primary handler that owns semantic interpretation
- zero or more observer handlers that may archive, project, or inspect

If multiple primary selectors match with equal precedence, activation validation
must reject the configuration as ambiguous.

### 9. Selector Matching Algorithm

Selector resolution follows this order:

1. Load selectors from the active configuration basis for the mission.
2. Keep only selectors whose scope and match fields are satisfied by the record
   envelope.
3. Rank by specificity:
   - `source_endpoint_ref` beats `spacecraft_id`
   - spacecraft-specific beats mission-default
   - more protocol-layer constraints beat fewer constraints
4. Rank remaining selectors by explicit priority.
5. Reject ambiguous equal-precedence primary matches.
6. Dispatch one primary handler plus any observers.

### 10. Unmatched Traffic

Unmatched traffic must never disappear.

If no selector matches, Cadence must:

- retain the original evidence
- emit a durable unmatched or anomaly record
- preserve enough context for later inspection or replay

### 11. Contact and Link Runtime

Contacts, links, and transport sessions are first-class operational scopes, but
they are not the root semantic runtime boundary.

Contact-scoped runtime is appropriate for short-lived operational state such as:

- provider session adapters
- active link-session state
- transport timers and queues
- contact lifecycle supervision
- path failover execution

Mission-scoped runtime remains responsible for long-lived semantic behavior such
as:

- telemetry meaning
- application bindings
- derived telemetry definitions
- limit definitions
- long-lived application instances such as `CFDP`

## Consequences

### Positive

- Cadence can add spacecraft and enable first-party applications without
  redeploy.
- Protocol/application meaning is scoped correctly for mixed fleets.
- Relay and transport context can be modeled without making contacts the root
  place where packet meaning is defined.
- Replay and live behavior stay aligned because both resolve against explicit
  governed configuration bases.
- The selector model leaves room for later first-class support of `TM`, `AOS`,
  `USLP`, `CFDP`, and custom first-party application families.

### Negative

- Configuration and activation become a core platform concern, not a secondary
  convenience feature.
- `source_endpoint_ref` resolution must be designed carefully; it cannot be
  treated as a trivial alias for `spacecraft_id`.
- The runtime must support controlled rebind or restart behavior when active
  configuration changes.
- Validation becomes more complex because selector ambiguity must be detected
  before activation.

### Constraints Introduced

- Runtime changes do not implicitly backfill historical traffic.
- Mission-supplied executable plugins are out of scope for the current phase.
- Global APID meaning is explicitly disallowed.

## Open Questions

1. How exactly is `source_endpoint_ref` resolved for relay and provider-mediated
   traffic?
2. Which selector fields are mandatory in release one, and which are deferred
   until additional protocol families are implemented?
3. Which activation changes can be applied by live rebinding, and which require
   scoped process restart?
4. What approval or authorization policy should govern runtime activation?
5. What future plugin ABI should Cadence support for mission-supplied logic,
   such as `WASM`?

## See Also

- [Architecture Decision Records](./_index.md)
- [Legacy Mission Runtime Architecture](../../legacy/cadence_legacy/docs/architecture/mission-runtime.md)
- Designed GDS reference docs in the adjacent `new-gds` repo, especially
  `spec/00-product-requirements.md` and `spec/10-security-and-authorization.md`
