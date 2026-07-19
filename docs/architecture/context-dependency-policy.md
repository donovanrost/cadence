---
title: Cadence Context Dependency Policy
tags: [developer, architecture, boundaries, xref]
status: active
created: 2026-07-18
updated: 2026-07-18
owner: Cadence core architecture
review_by: 2026-10-18
---

# Cadence Context Dependency Policy

## Purpose

This policy turns the bounded-context direction in the
[architecture and test performance review](../architecture-and-test-performance-review.md)
into a concrete dependency target. It describes ownership and allowed
dependencies inside `:cadence`; it does not require an immediate umbrella split.

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
| Telemetry, history, and projections | ingress, decom, current values, history, archives, replay, limits, materialized views | Identity and tenancy; Catalog and activation; Comms configuration; Platform |
| Dashboards | documents, lifecycle, source contracts, data links, execution, visualization-facing read models | All domain contexts through public services, value types, events, and read models; Platform |
| Platform | observability, jobs, secrets, notifications, identifiers, generic infrastructure | Platform only |

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
| Telemetry, history, and projections | `Telemetry`, `Ingress*`, `Projections`, `DerivedTelemetry`, `Limits`, `Replay`, `MissionEvents`, `OperationalEvents`, `Protocol` |
| Dashboards | `Dashboards` |
| Platform | `Observability`, `Jobs`, `Secrets`, `Notifications`, `Ids` |

The following namespaces are transitional and are not context APIs:

- root `Cadence` is a facade to retire;
- `Cadence.Persistence` and `Cadence.Persistence.Schemas` are horizontal storage
  namespaces whose schemas should move under their owning contexts;
- `Cadence.Reads` groups read models that should move to their owning domain or
  an explicitly shared projection boundary; and
- `Cadence.Application` is composition-root code, not a domain dependency
  escape hatch.

## Executable enforcement

Run the policy check from the umbrella root:

```bash
mix cadence.architecture.check
```

The current ratchet enforces three high-confidence rules from this policy:

1. no new internal production module may call the root `Cadence` facade; and
2. no new production module outside the persistence implementation may depend
   directly on `Cadence.Persistence.Schemas.*`; and
3. once a row moves under its owning context, callers outside that bounded
   context may not depend on the row directly.

The moved-row guard currently covers Identity and tenancy, Catalog and
activation, Comms configuration, Limits, Jobs, Notifications, Applications,
Dashboards, Ground Networks, Operational Events, and Projections ownership
paths. Extend the executable ownership map in the same change whenever another
context receives row modules.

The live debt is recorded in
[`dependency-baseline.txt`](dependency-baseline.txt). Each entry is an existing
xref edge, not permission for new code. The check fails when an edge is added,
when a removed edge is left in the baseline, or when the baseline review date
expires. Removing an edge and its baseline entry in the same change makes the
policy ratchet toward the target. The moved-row cross-context exception
baseline is currently empty; callers reach those rows through their owning
context APIs.

Full pair-by-pair enforcement of the matrix is staged until current
cross-context edges are assigned to an owning workflow. That later baseline
must follow the same rule: explicit owner, rationale, review date, no silent
growth, and removal in the same change as resolved debt.

## Dependency exceptions

New exceptions are not added directly to the baseline. A proposed exception
must update this policy or an ADR in the same change and record:

- the exact caller and callee;
- why an event, public service, or orchestration move is not yet suitable;
- the responsible owner;
- a removal condition; and
- a review-by date.

Expired or ownerless exceptions fail the architecture check.
