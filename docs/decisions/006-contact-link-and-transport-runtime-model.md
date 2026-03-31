---
title: "ADR-006: Contact, Link, and Transport Runtime Model"
aliases: [contact runtime model, link runtime model, transport runtime model]
tags: [adr, architecture, contact, link, transport, cop-1, runtime]
status: accepted
created: 2026-03-28
updated: 2026-03-28
---

# ADR-006: Contact, Link, and Transport Runtime Model

## Status

Accepted

## Context

Cadence already has these architectural baselines:

- [ADR-001](001-mission-scoped-runtime-and-selector-model.md): mission is the
  semantic root and packet or application meaning is mission-scoped
- [ADR-005](005-runtime-partitioning-and-workload-isolation.md): mission
  execution is partitioned by `source_endpoint_ref` and may span nodes

Those decisions imply an important constraint:

- contact, link, and transport runtime must be first-class operational scopes
  without becoming the root place where telemetry or application meaning is
  defined

Cadence also needs a runtime model that supports:

- scheduled provider contacts
- realized operational contacts
- uplink and downlink path selection
- multiple simultaneous downlink contributors
- uplink transport state such as `COP-1`
- preservation of raw evidence from each contributing path

## Decision

Cadence will model contacts as mission-scoped operational envelopes, with
directional paths and transport runtimes under realized contacts, while keeping
semantic telemetry and application interpretation in mission endpoint
partitions.

### 1. Contact Is An Operational Envelope

`contact` is a mission-scoped operational coordination scope.

Contact owns:

- provider association
- operational lifecycle
- selected and candidate paths
- operator-facing contact state
- path selection and failover context

Contact does not own the semantic meaning of telemetry packets or mission
applications.

### 2. Scheduled Contact And Realized Contact Are Distinct

Cadence distinguishes:

- `scheduled_contact`
- `realized_contact`

`scheduled_contact` represents planned provider or operator intent.

`realized_contact` represents the live operational truth that Cadence actually
executes and observes.

Live path and transport runtime hang from `realized_contact`, not from
`scheduled_contact`.

This separation preserves schedule history without conflating it with actual
execution state.

### 3. Realized Contact May Involve Multiple Source Endpoints

Cadence will model `realized_contact` as a mission-scoped operational envelope
that may involve multiple source endpoints.

Release one should optimize for the common case of one primary source endpoint,
but the runtime model must not assume contact is permanently one-endpoint-only.

This preserves room for:

- relay scenarios
- multi-endpoint coordination
- provider or path workflows that affect more than one endpoint

### 4. Directional Paths Live Under Realized Contact

`path` is directional and belongs to a `realized_contact`.

Cadence should model at minimum:

- uplink paths
- downlink paths

Paths carry operational state such as:

- candidate versus selected status
- provider path association
- degradation state
- handover or failover status

### 5. Transport Runtime Lives Under Path

Transport-session and session-local protocol state lives under the directional
path runtime.

Transport runtime owns:

- provider session adapters
- transport continuity and delivery state
- session-local timers
- sender or receiver state machines tied to one active path

Transport runtime is operational and session-local, not a mission-wide semantic
application instance.

### 6. COP-1 Is An Uplink Transport Concern

`COP-1` belongs under the uplink transport runtime for the selected uplink path.

Cadence will not model `COP-1` as a mission-wide application instance.

This keeps `COP-1` aligned with:

- selected uplink path
- session-local sender state
- transport timers and delivery semantics

### 7. Uplink And Downlink Are Not Symmetric

Cadence intentionally models uplink and downlink with different operational
rules.

#### Uplink

Release one assumes exactly one selected active uplink path at a time for a
realized contact.

Candidate or standby uplink paths may exist, but only one path is the selected
active uplink path for command release and transport state.

#### Downlink

Release one may have multiple simultaneous active downlink contributing paths
within one realized contact.

One downlink path is still designated as the selected or preferred path for
operator-facing state, but alternate contributing paths remain active and
meaningful.

### 8. Raw Evidence Remains Path-Specific

Cadence must retain raw evidence separately for each contributing downlink path.

Cadence must not collapse simultaneous path contributions at ingest time.

This preserves:

- source truth
- replay fidelity
- continuity investigation
- path-quality comparison

### 9. Path Runtimes Emit Observations, Not Final Meaning

Each active path runtime emits path-local observations such as:

- evidence-linked protocol observations
- continuity or quality signals
- link or transport anomalies

Those observations are inputs to later reconciliation and semantic processing.

Path runtimes do not define final packet or application meaning by themselves.

### 10. Downlink Combiner Lives At The Realized Contact Layer

Cadence will introduce a contact-level downlink combination stage for realized
contacts with multiple active downlink contributors.

This stage is referred to here as the `DownlinkCombiner`.

The `DownlinkCombiner` consumes path observations and produces:

- one merged operational stream for downstream mission processing
- parallel comparison and continuity diagnostics records

The merged operational stream is what mission endpoint partitions use for normal
live semantic handling.

The diagnostics output preserves forensic truth about alternate contributors and
selection decisions.

### 11. Reconciliation Happens Above Raw Evidence

Cadence reconciles duplicate or overlapping downlink contributions above raw
evidence, not inside raw ingest.

This means:

- raw evidence is preserved per path
- combination and preference logic occur in protocol-processing or contact
  combination layers
- semantic endpoint processing receives the merged operational stream plus
  attached contact and path context

### 12. Endpoint Partitions Still Own Semantic Processing

Mission endpoint partitions keyed by `source_endpoint_ref` remain responsible
for:

- selector resolution
- packet or application meaning
- managed application execution
- derived telemetry
- limit evaluation

Contact, path, and transport context are attached to the records they consume,
but that context does not move semantic ownership out of the mission endpoint
partition.

### 13. Contact Runtime Responsibilities

Contact-scoped runtime responsibilities include:

- realized contact lifecycle
- path selection and failover
- provider-session coordination
- active-path and degradation summary
- operator-facing contact narrative
- downlink combination across contributing paths

Mission-scoped semantic responsibilities remain outside the contact runtime.

### 14. Release-One Operational Defaults

Release one defaults are:

- `realized_contact` supports one primary endpoint but may include multiple
  endpoints if needed
- exactly one selected uplink path
- one or more active downlink contributing paths
- one selected downlink path for operator-facing summaries
- `COP-1` under the selected uplink transport runtime
- downlink combination emits both merged operational output and diagnostics

### 15. Anti-Decisions

Cadence should not model release one as if:

- scheduled contacts are the same as realized operational truth
- contact runtime owns packet or application meaning
- multi-path downlink evidence should be collapsed at ingest
- `COP-1` is a mission-wide semantic application
- uplink and downlink need identical path semantics

## Consequences

### Positive

- Contact execution truth stays distinct from planned schedules.
- Uplink transport state and downlink diversity can both be modeled cleanly.
- Multi-path downlink operations remain explainable because raw evidence is
  preserved per path.
- Mission endpoint partitions retain semantic authority while still receiving
  rich operational context.
- The architecture can support relay and multi-endpoint contact scenarios
  without forcing contact to become the semantic root.

### Negative

- Cadence must coordinate across contact runtime and endpoint partitions rather
  than assuming one layer owns everything.
- Downlink combination becomes a first-class runtime concern.
- Operator-facing contact state and semantic mission processing are related but
  intentionally separate, which increases model complexity.
- Recovery and replay need to preserve both merged operational outputs and
  path-local diagnostics.

### Constraints Introduced

- Raw evidence remains path-specific.
- Exactly one selected active uplink path exists in release one.
- Downlink may have multiple simultaneous contributors.
- Contact runtime must not redefine mission semantic meaning.

## Open Questions

1. What exact record families should path runtimes emit before the downlink
   combiner stage?
2. How should the `DownlinkCombiner` express contributor choice, confidence, or
   continuity rationale in diagnostics records?
3. Do relay or multi-endpoint realized contacts require a coordination record
   above the endpoint partition plus contact runtime boundary?
4. What operator-visible current-state APIs should be derived from
   `realized_contact`, selected paths, and path degradation state?

## See Also

- [Architecture Decision Records](./_index.md)
- [ADR-001: Mission-Scoped Runtime and Selector Model](001-mission-scoped-runtime-and-selector-model.md)
- [ADR-005: Runtime Partitioning and Workload Isolation](005-runtime-partitioning-and-workload-isolation.md)
