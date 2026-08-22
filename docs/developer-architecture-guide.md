---
title: Developer Architecture Guide
tags: [developer, architecture, runtime, persistence, simulator, onboarding]
status: active
created: 2026-04-03
updated: 2026-08-21
---

# Developer Architecture Guide

This guide is the developer-facing companion to the ADRs in
[`docs/decisions`](./decisions/_index.md). The ADRs define accepted
architecture decisions. This document explains how those decisions currently
show up in the codebase, how the main runtime and persistence paths are laid
out, and what development patterns we want contributors to follow.

For task-oriented workflows, see the
[How-To Guides](./how-to/_index.md).

For the runtime substrate and capability model specifically, see
[Understand the Runtime Substrate and Capabilities](./how-to/understand-the-runtime-substrate-and-capabilities.md).

Use this guide when you need to answer questions like:

- where does a new runtime concern belong?
- should a new record be persisted in Postgres, archived, or kept in memory?
- what is on the hot path for telemetry ingress?
- how should providers, runtime workers, and simulator tooling interact?

If this guide and the ADRs ever disagree, the ADRs win. If this guide and the
code disagree, the code is the current reality and this document should be
updated in the same change.

## 1. System Shape

Cadence is a multi-tenant management plane, an operational control plane, and a
reconciled mission data plane. The authority model is defined by
[ADR-015](./decisions/015-management-control-data-plane-architecture.md), and
the intended end state is described in the
[target architecture](./architecture/management-control-data-plane-target.md).

At the Workspace project level:

- `apps/cadence` contains the core domain, runtime, persistence, replay, and
  provider-client boundary.
- `apps/cadence_web` contains the Phoenix API and UI boundary.
- `apps/cadence_simulator` contains the independently runnable external ground
  network simulator.
- `packages/cadence_catalog` contains the catalog and Mission Model compiler.
- `packages/cadence_ccsds` contains protocol primitives shared by Cadence and
  external peers.
- `legacy/cadence_legacy` is a preserved reference snapshot of the previous
  system and is useful for migration and performance comparisons.

Conceptually, the system has three authority planes and two cross-cutting
structures:

1. Management: governed intent, policy, approval, and audit
2. Control: activation, scheduling, selection, reconciliation, and dispatch
3. Data: ordered live runtime and protocol execution
4. Async persistence and archive projections
5. Query, dashboard, and replay read models

The most important architectural rule is that **mission meaning is governed by
mission-scoped configuration, not by transport artifacts alone**.

## 2. Runtime Scopes

The accepted runtime scope model comes from
[ADR-001](./decisions/001-mission-scoped-runtime-and-selector-model.md),
[ADR-005](./decisions/005-runtime-partitioning-and-workload-isolation.md), and
[ADR-006](./decisions/006-contact-link-and-transport-runtime-model.md).

The scopes matter because they determine where code and state belong.

### Organization

- Tenant boundary
- Owns missions, identities, and management-plane records
- Not a hot runtime scope

### Mission

- Semantic root of the runtime
- Owns active basis, selectors, source endpoints, spacecraft associations, and
  mission-scoped operational meaning
- Root runtime workers live under `Cadence.Runtime`

### Realized contact and path

- Operational scope for live link activity
- Path-local provider and transport workers live here
- A path can have provider adapters and transport runtimes attached to it

### Source endpoint

- Default live partition identity for ingress semantics
- The runtime commonly reasons about live traffic in terms of
  `source_endpoint_ref`

Do not treat `APID`, port number, or one specific provider transport as the
semantic root. Those are inputs to mission-scoped interpretation.

## 3. Provider Boundary

The provider model is defined by
[ADR-012](./decisions/012-provider-adapter-and-ground-station-simulator-model.md).

Provider integration spans three deliberately separate responsibilities:

- provider account, credential, grant, and mission-provider administration is
  management-plane work;
- provider capabilities, inventory, opportunities, reservations, and recovery
  use the control-plane `Cadence.Contacts.ProviderClient` boundary; and
- live data delivery uses path-local data-plane provider adapters.

Data-plane provider adapters own:

- external socket or session lifecycle
- connect/listen/accept logic
- provider-native framing into ingress message units
- provider-local metadata
- transport-local status and error reporting

Data-plane provider adapters do **not** own:

- mission semantic interpretation
- selector matching
- telemetry extraction
- command approval or release policy
- durable persistence strategy

The current TCP data-plane provider implementation is
`Cadence.ProviderAdapters.TCPSocket`.

When adding a new provider data adapter, the correct question is:

> How do I convert external I/O into canonical Cadence ingress or transport
> events?

Not:

> How do I reimplement mission logic or provider reservation policy inside the
> delivery adapter?

## 4. Telemetry Ingress Path

The current downlink path is intentionally split into an ordered execution lane
and an async persistence lane.

### 4.1 Ordered live lane

Current flow:

1. A provider receives bytes from an external system.
2. The provider turns those bytes into fixed-size message units or transport
   events.
3. The provider enqueues those units into a path-local
   `Cadence.Runtime.ProviderIngressExecutor`.
4. The executor performs the mission-facing live work:
   - source resolution
   - runtime processing
   - current-value updates for hot-path-safe backends
5. The executor emits a compact processed batch to the async persistence
   projector.

This ordered lane is the place where latency matters most.

### 4.2 Async sink lanes

The current implementation routes several durable side effects through
`Cadence.Runtime.IngressPersistenceProjector`. ADR-019 accepts a more explicit
target: raw archive replication, protocol archive, telemetry history, and sparse
operational-event projection have separate sink contracts, acknowledgements,
retry state, and observability.

Those responsibilities include:

- archive writes
- protocol anomaly writes
- history store writes
- current-value fallback writes for non-hot-path-safe backends
- other low-rate projections that are not required to complete inline

Each required sink is backpressured by bytes, items, and oldest-work age. The
provider and executor prefer bounded flow over unbounded memory growth, while a
slow sink remains identifiable instead of disappearing behind one generic
projector backlog.

The generic projector remains migration code while these sink contracts are
introduced. Do not add another high-rate effect to it.

### 4.3 Why this split exists

We explicitly moved away from the earlier model where one ingress step tried to
do everything synchronously:

- full Postgres writes
- current-value updates
- sample history writes
- frame and packet record writes
- dispatch persistence

That approach made Postgres the hot-path bottleneck and made throughput tuning
much harder than it needed to be.

## 5. Storage Tiers

One of the main lessons from the telemetry performance work is that not all
operational data belongs in the same storage system.

Cadence now uses multiple storage tiers.

| Concern | Default runtime backend | Hot path? | Notes |
| --- | --- | --- | --- |
| Current telemetry values | `Cadence.Telemetry.CurrentValueStore.ETS` | Yes | Runtime state, latest-per-point reads |
| Telemetry sample history | `Cadence.Telemetry.HistoryStore.Noop` | No | Pluggable; Postgres compatibility exists for tests |
| Raw ingress evidence | `Cadence.IngressArchive.FileSystem` | Async projector | Filesystem archive plus lightweight index rows |
| Packet and frame records | `Cadence.Protocol.RecordArchive.FileSystem` | Async projector | Archive-oriented, not default OLTP rows |
| Protocol anomalies | Postgres | Async projector | Low-rate operational facts worth querying live |
| Numerical ingress/runtime metrics | OpenTelemetry metrics backend | No | Histograms, counters, and gauges; never one operational-event row per observation |
| Management/control records | Postgres | N/A | Missions, governed configuration, approvals, activations, reservations, queues, and lifecycle state |

### 5.1 Current value store

`Cadence.Telemetry.CurrentValueStore` is a behavior. The default runtime
backend is ETS.

This is runtime state, not a canonical history store.

Use this when the question is:

- what is the latest value right now?

Do not use it as a durable history mechanism.

### 5.2 History store

`Cadence.Telemetry.HistoryStore` is also a behavior. Runtime defaults to
`Noop`, because full telemetry history does not belong in the synchronous live
path by default.

### 5.3 Ingress and protocol archives

High-rate append-only artifacts are archived through explicit archive
boundaries:

- `Cadence.IngressArchive`
- `Cadence.Protocol.RecordArchive`

Those default to filesystem segment writers in runtime and use Postgres-backed
compatibility implementations in tests.

These archives exist because raw evidence and packet/frame artifacts are much
closer to event or recording data than to OLTP control-plane data.

### 5.4 What should not be default OLTP data

As a working rule:

- current values are runtime state
- history and raw evidence are archive data
- high-rate per-packet/per-frame decisions are usually archive or event-stream
  data
- low-rate anomalies and control-plane state are good Postgres candidates

`ingress.processing_latency_ms` is a numerical observation. It belongs in
runtime health and the metrics/time-series boundary. Only a sparse transition,
such as entering or clearing a sustained latency alarm, belongs in the
operational event spine.

This rule is more important than any one backend implementation.

## 6. Replay Model

Replay should not depend on live OLTP tables as its primary data source.

The intended replay basis is:

1. durable archived ingress and protocol artifacts
2. governed mission configuration and active/runtime materializations
3. explicit replay scope selection

The replay path in `Cadence.Replay` already reads through archive abstractions
instead of assuming raw evidence is always stored as Postgres rows.

When designing a new historical feature, prefer:

- archive + lightweight discovery index

over:

- large permanent Postgres rowsets on the live path

## 7. Development Patterns

These patterns are the practical rules we want developers to follow.

### 7.1 Keep Postgres off the hot path unless the record is truly operational

Before adding a new write, ask:

- Is this a low-rate operational fact that must be queryable live?
- Or is this archive, replay, or forensic data?

If it is archive or forensic data, it should probably go behind an archive
boundary or event stream, not directly into live OLTP tables.

### 7.2 Keep provider adapters narrow

Providers should own I/O. Runtime workers should own mission logic.

If a provider change needs to know too much about selectors, dispatch, replay,
or activation, the boundary is probably wrong.

### 7.3 Preserve ordering only where semantics require it

The ordered lane should stay as small as practical.

Good ordered-lane work:

- transport framing into ingress message units
- source resolution
- runtime processing
- immediate current-value updates

Good async work:

- archive flush
- Postgres projections
- analytics-like views
- UI/event fan-out

### 7.4 Prefer bounded backpressure over unbounded buffering

We explicitly chose backpressure and queue watermarks instead of letting the
provider, executor, or projector grow without limit.

When adding a new async stage, include:

- queue depth visibility
- oldest buffered age if buffering is time-based
- high/low watermarks or other bounded flow control

### 7.5 Add observability with the stage

If you add a new hot-path stage or queue, add:

- snapshot visibility
- profiler visibility, if it materially affects ingress timing
- enough counters to tell whether that stage is saturated or merely noisy

### 7.6 Keep compatibility backends explicit

Several subsystems have a runtime backend and a compatibility backend:

- current value store
- history store
- ingress archive
- protocol record archive

That is intentional.

Compatibility backends are useful for:

- tests
- migration
- temporary bridging to older assumptions

They should not silently become the production default again.

## 8. Developer Tooling Workflow

The preferred local workflow is profile-driven.

### 8.1 Start Cadence

Run the server as a named node when you want to use the profiler tasks:

```bash
cd apps/cadence_web
iex --sname cadence -S mix phx.server
```

### 8.2 Optional environment administrator

Cadence supports an environment-backed platform administrator for development
and operator-directed administration.

Relevant environment variables:

- `CADENCE_ADMIN_EMAIL`
- `CADENCE_ADMIN_PASSWORD`
- `CADENCE_ADMIN_DISPLAY_NAME` (optional)
- `CADENCE_ADMIN_MODE_TTL_SECONDS` (optional)

Email and password must be set together. The reserved administrator exists only
while they are configured, signs in through the normal browser form, and enters
admin mode immediately. Durable users granted platform-admin eligibility must
reauthenticate before entering admin mode.

### 8.3 Run the external simulator

Start the provider simulator in its own application directory and BEAM:

```bash
cd apps/cadence_simulator
CADENCE_SIMULATOR_HTTP_ENABLED=true mix run --no-halt
```

Cadence neither supervises this process nor exposes simulator administration in
its web UI. Configure its scheduling API and telemetry delivery settings on an
ordinary mission provider profile.

See [Simulator Provider Integration Flow](simulator_provider_integration_flow.md)
for the complete setup.

### 8.4 Runtime profiling

The Cadence-owned profiler task remains available for inspecting a running
Cadence node:

```bash
mix cadence.profile demo_spacecraft
```

Named profiler defaults live under `dev/profiles`. These files are Cadence-side
developer tooling, not simulator lifecycle configuration.

### 8.5 Provider integration boundary

The simulator implements a provider-style HTTP control plane. Cadence discovers
opportunities and reserves contacts through the provider client configured on
the mission's `ProviderProfile`. Telemetry then arrives through the same
contact-time TCP ingress used by other providers.

The simulator may use authenticated runtime lookup to discover an already
realized contact's data-plane endpoint. It must not create or administer
Cadence mission resources.

## 9. Where Code Lives

When adding new code, these are the first places to look.

### Runtime and supervision

- `apps/cadence/lib/cadence/runtime`
- `apps/cadence/lib/cadence/application.ex`

### Provider adapters

- `apps/cadence/lib/cadence/provider_adapters`

### Persistence and archive boundaries

- `apps/cadence/lib/cadence/persistence.ex`
- `apps/cadence/lib/cadence/ingress_archive*`
- `apps/cadence/lib/cadence/protocol/record_archive*`
- `apps/cadence/lib/cadence/telemetry/current_value_store*`
- `apps/cadence/lib/cadence/telemetry/history_store*`

### Web/API boundary

- `apps/cadence_web/lib/cadence_web`

### Shared CCSDS library

- `packages/cadence_ccsds/lib/cadence/ccsds`

### External simulator

- `apps/cadence_simulator/lib/cadence_simulator`

## 10. Documentation Expectations

Architectural work should update docs in the same change.

Use this rough rule:

- new long-lived architectural rule or boundary: update or add an ADR
- current implementation shape or developer workflow: update this guide
- narrow debugging or operator flow: update a focused how-to document

This guide is intended to be the first document a developer reads after the
README. Keep it current enough that new contributors can answer:

- how the system is layered
- where hot-path code belongs
- how data should be stored
- how to run and profile the system locally
