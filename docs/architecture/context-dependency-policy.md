---
title: Cadence Context Dependency Policy
tags: [developer, architecture, boundaries, xref]
status: active
created: 2026-07-18
updated: 2026-08-02
owner: Cadence core architecture
review_by: 2026-10-18
---

# Cadence Context Dependency Policy

## Purpose

This policy turns the bounded-context direction in the
[architecture and test performance review](../architecture-and-test-performance-review.md)
into a concrete dependency target. It describes ownership and allowed
dependencies inside `:cadence`; it does not require an immediate umbrella split.

The
[management, control, and data plane target](management-control-data-plane-target.md)
adds a second architectural axis. This policy answers which business context
owns a capability. The plane architecture answers which authority owns a
specific state transition. A module must satisfy both. Current contexts that
contain operations from multiple planes are migration boundaries, not evidence
that the plane distinction should be collapsed.

Dependencies point from a caller to a callee. A context may call only the
contexts listed in its row, plus its own modules. Asynchronous facts should
cross boundaries through explicit events or projections. Synchronous calls
should use the callee context's public application service or value types.

## Target context matrix

| Context | Primary ownership | May depend on |
| --- | --- | --- |
| Identity and tenancy | organizations, users, mission scope, spacecraft identity, authorization | Platform |
| Catalog and activation | telemetry/command definitions, revisions, imports, governance, activation | Identity and tenancy; Platform |
| Comms configuration | spacecraft profiles, transports, routing rules, ground-station configuration, source endpoints | Identity and tenancy; Catalog and activation; Platform |
| Ground-network provider integration | provider accounts, credentials, capabilities, opportunities, provider contacts, wire translation | Identity and tenancy; Comms configuration; Platform |
| Contact planning | requirements, candidates, constraints, scoring, optimization, proposed plans | Identity and tenancy; Catalog and activation; Comms configuration; Ground-network provider integration; Platform |
| Contact lifecycle | committed schedules, provider reservations, realized contacts, runtime handoff | Identity and tenancy; Comms configuration; Ground-network provider integration; Contact planning; Mission runtime and capabilities; Platform |
| Commanding | staging, approvals, release queues, dispatch, verification | Identity and tenancy; Catalog and activation; Comms configuration; Mission runtime and capabilities; Telemetry, history, and projections; Platform |
| Mission runtime and capabilities | runtime partitions, workload ownership, capability descriptors and execution | Identity and tenancy; Catalog and activation; Comms configuration; Telemetry, history, and projections; Platform |
| Telemetry and history | ingress, decom, current values, history, archives, replay inputs, and limits | Identity and tenancy; Catalog and activation; Comms configuration; Platform |
| Data Sources | physical source definitions, logical bindings, non-secret credential references, health/watermark projections, probes, and provisioning | Identity and tenancy; Platform |
| Dashboards | documents, lifecycle, source requests, data links, execution, and visualization contracts | Data Sources and Read models for IO; other contexts only through public value types and pure domain services; Platform |
| Read models | cross-plane mission events, status, health, and query projections | All domain contexts through public facts, services, and value types; Platform |
| Platform | observability, jobs, secrets, notifications, identifiers, generic infrastructure | Platform only |
| Composition roots | supervisors, job runners, and explicit workflow assembly | All contexts through public boundaries |
| Adapters | web, external I/O, operational event delivery, and cache invalidation | All contexts through public boundaries |

This matrix deliberately avoids bidirectional context pairs. When an existing
workflow appears to need a reverse dependency, move the orchestration to the
higher-level caller, publish an event, or introduce a small public value/API
boundary instead of adding the reverse call.

## Namespace ownership map

The current tree does not map perfectly to the target contexts. These prefixes
are the working ownership map for refactors and future xref enforcement:

| Context | Current namespace prefixes |
| --- | --- |
| Identity and tenancy | `Accounts`, `Auth`, `Missions`, `Organizations`, `Spacecraft*` |
| Catalog and activation | `Catalog`, `Activations`, `Governance` |
| Comms configuration | `Comms`, `SourceEndpoints` |
| Ground-network provider integration | `GroundNetworks`, `ProviderAdapters` |
| Contact planning | `ContactPlanning` |
| Contact lifecycle | `Contacts` |
| Commanding | `Commanding`, `ActionRequests` |
| Mission runtime and capabilities | `Runtime`, `Capabilities`, `Applications`, `ApplicationDispatch` |
| Telemetry and history | `Telemetry`, `Ingress*`, `DerivedTelemetry`, `Limits`, `Replay`, `Protocol` |
| Data Sources | `DataSources`, `Management.DataSources`, `Control.DataSources`, `Projections.DataSources`, `Reads.DataSources` |
| Dashboards | `Dashboards` |
| Platform | `Observability`, `Jobs`, `Secrets`, `Notifications`, `Ids` |
| Read models | `Projections`, `Reads`, `MissionEvents`, `Ops` |
| Composition roots | application and plane supervisors, job runners |
| Adapters | `CadenceWeb`, external delivery adapters, operational event and cache-invalidation boundaries |

The following namespaces are transitional and are not context APIs:

- root `Cadence` is a facade to retire;
- `Cadence.Persistence` and `Cadence.Persistence.Schemas` are horizontal storage
  namespaces whose schemas should move under their owning contexts;
- `Cadence.Reads` is the explicit query boundary for cross-context projections;
  owner-specific implementations remain behind those APIs; and
- `Cadence.Application` is composition-root code, not a domain dependency
  escape hatch.

## Executable enforcement

Run the policy check from the Workspace root:

```bash
mix cadence.architecture.check
```

The ratchet now enforces the complete plane and bounded-context axes:

1. every core production module has an explicit plane and context
   classification; every `cadence_web` module is explicitly an adapter;
2. new namespaces fail closed as unclassified until ownership is assigned;
3. the full context matrix rejects reverse dependencies while named vertical
   orchestration handoffs remain explicit;
4. plane direction and cross-plane public API rules reject reverse and
   implementation-level dependencies;
5. no internal production module may call the root `Cadence` compatibility
   facade;
6. no production module may cross a context or plane boundary through an Ecto
   row;
7. controllers and LiveViews reach the transitional
   `CadenceWeb.ControlPlane*` modules only through resource-owned
   `CadenceWeb.API.*` boundaries; and
8. dashboard source, registry, and evidence adapters cannot call management,
   control, repository, or owner-store IO directly; they must use
   `Cadence.Reads` or a configured provider boundary.

The schema ownership guard covers Identity and tenancy, Catalog and activation,
Comms configuration, Contacts, Limits, Jobs, Notifications, Applications,
Dashboards, Derived Telemetry, Ground Networks, Operational Events,
Projections, Telemetry, Runtime persistence, and the archive backends. Extend
the executable ownership map in the same change whenever another context
receives row modules.

The live debt is recorded in
[`dependency-baseline.txt`](dependency-baseline.txt). Each entry is an existing
xref edge, not permission for new code. The check fails when an edge is added,
when a removed edge is left in the baseline, or when the baseline review date
expires. Removing an edge and its baseline entry in the same change makes the
policy ratchet toward the target. As of 2026-08-02, root-facade, horizontal
persistence-schema, cross-context row, web catch-all, unclassified-module,
reverse context/plane direction, and cross-plane internal debt are all zero.

## Dependency exceptions

New exceptions are not added directly to the baseline. A proposed exception
must update this policy or an ADR in the same change and record:

- the exact caller and callee;
- why an event, public service, or orchestration move is not yet suitable;
- the responsible owner;
- a removal condition; and
- a review-by date.

Expired or ownerless exceptions fail the architecture check.
