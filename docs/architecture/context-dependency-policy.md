---
title: Cadence Context Dependency Policy
tags: [developer, architecture, boundaries, xref]
status: active
created: 2026-07-18
updated: 2026-09-10
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
| Telemetry and history | ingress, decom, current values, history, archives, replay inputs, and limits | Identity and tenancy; Catalog and activation; Comms configuration; Data Sources through public observation APIs; Platform |
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

The check compiles `apps/cadence_web` and its domain dependency in the selected
Mix environment, then reads both compiler manifests from that child's actual
build path. One module index includes cross-project references. Both `lib/**/*.ex`
inventories must be nonempty and exactly match the compiled sources, and each
source must match its compiler content digest. Test helpers are outside this
production graph. Missing, stale, incomplete, or duplicate source/module
ownership fails closed. A supplied `--xref-json` must equal that complete current
graph, including reference labels and edges; it cannot remove dependencies.

The ratchet enforces the complete plane and bounded-context axes:

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
policy ratchet toward the target. The former zero-debt claim did not establish
production coverage: the workspace-root `mix xref graph` could return an empty
graph. The September 2026 recovery rejects that condition and exposes outstanding
production findings. An empty baseline does not establish that the current graph
passes. Remaining findings must be resolved and the actual command must pass
before the migration can claim completion.

## Reviewed source ownership

`PlaneBoundary` maintains an exact `@host_adapter_paths` ledger for the reviewed
Ops action cohorts and first-party application action/query providers, including
organization-admin compatibility providers. These modules admit host request
identities and scope, translate bounded input, and delegate to domain owners.
They are adapters on both architectural axes. Neighboring `Applications` modules
retain their own classification; adding a module under an action directory does
not grant adapter authority. Root-facade and cross-context row guards also apply
to adapters.

Packet binding declarations and surface DTOs are shared values. Configuration
locking, packet-binding persistence and mission binding preparation belong to
Management. Data Sources health/watermark observation journals and their live status rows
belong to Data in the Data Sources context, despite their historical
`Projections.DataSources` namespace. Their two public owner APIs record observed
source facts; operator/dashboard composition remains read-side. The exact file
ledger does not permit Data to call general projections or Management. Reads access domain events and
credential references through the public owning APIs; persistence rows remain
inside their stores. Notification recipient authorization and invitation actions
belong to Identity in Management, while generic notification persistence remains
Platform.

The four subsystem supervisors and `Platform.RootComposition` are composition.
`Control.ProcessNamespace` and `Runtime.ProcessNamespace` are the two explicit
public process-address contracts. They construct validated existing-atom
addresses and `:via` tuples, including default module-named process addresses;
they do not start, stop or call supervised processes. Domain callers may consume
these address contracts. This does not grant access to the supervisors or other
composition modules. Cadence core architecture owns these contracts; review of
changes to either constructor must preserve that value-only boundary.

The exact public composition value ledger also names the compiled application
and extension catalogs and the metadata-only application contributors: Comms,
DerivedTelemetry, Limits, MissionCatalog, OpsConsole, Spacecraft,
LegacyCommsOverview and OrganizationAdmin. Their public APIs assemble typed
contribution declarations, provider identities and validated catalog values.
Callers consume these declarations without obtaining workflow authority. The
mixed `TelemetryDecom` module remains Management and delegates its surface-query
declarations to `TelemetryDecomCatalogContribution`, alongside that module's
existing catalog/release declarations. The internal extension
package registry remains private composition. The action contract ledger and
provider dispatch registries are host adapters. Cadence core architecture owns
this explicit metadata contract; effectful configuration and runtime functions
must remain outside it.

The deterministic semantic evaluator, expression/monitoring plans, state/result
values and Mission Model plan decoder are shared Catalog services used by both
qualification and live execution. Their exact file ledger excludes the semantic
runtime store and commit row, which remain Runtime-owned Data persistence.
Reuse of the pure evaluator does not grant a
qualification workflow access to active partitions or runtime persistence.

`Control.Missions` is explicit cross-context mission lifecycle assembly while
retaining Control-plane authority. It settles the public Contact owner before
shutdown or reconfiguration; it no longer calls the contact scheduler directly.
Job availability is a producer-owned fact delivered through the platform event
bus. The job store does not reference the dispatcher; a subscribing dispatcher
claims durable queued rows and retains its safety scan for missed notifications.

`ContactPlanning.FleetRunActions` and `FleetRunRepairs` belong to Contact lifecycle
in Control, alongside `FleetPlanner` and `FleetRepairs`: they continue persisted
execution and claim exact execution/commitment evidence before creating repair
successors. Requirement, template, policy and proposed-run declarations retain
Management ownership.

`Reads.MissionModels.ActiveBasis` is the exact read-only adapter between Control's
active-generation records and Management's command qualification/authoring.
Its API returns a current revision identity, an immutable runtime basis, or a
bounded command-catalog snapshot under the Control owner's held read transaction.
It exposes no activation mutation, runtime process operation, or persistence row.
Management callers retain their plane and cannot call Control services directly.
The command evidence digest is a shared value contract; extracting the adapter
preserves its existing deterministic bytes and lock duration. General read-model
modules do not inherit this adapter classification. Cadence core architecture
owns this specific read contract and its native scope/concurrency checks.

Spacecraft configuration drafts, application input reconciliation, and review
preparation belong to Management in the Applications context, under
`Applications.SpacecraftConfiguration`. Its immutable revision rows stay private
to that owner. `Activations.SpacecraftConfiguration` belongs to Control in the
Catalog and activation context and admits the exact reviewed configuration in
the activation transaction. Profile resolution remains an Identity store API;
catalog choices and installation identities are queried through their owners.
The existing `Reads.MissionModels.ActiveBasis` adapter also exposes an immutable
active generation for saved-versus-active comparison and applied-state stamps.
It grants no activation mutation or runtime process authority.

`Catalog.SpacecraftConfigurationInput`, `Catalog.SpacecraftModelBindings`, and
`Catalog.Command.Compatibility` are shared Catalog value services. They validate
finite documents and compute deterministic command semantics without IO.
`Control.SpacecraftModelBindings` owns activation admission and runtime model
resolution in the Catalog context, using artifacts already parsed and compiled
during import. `Reads.Catalog.SpacecraftUsage` assembles saved and active catalog
bindings through public owner APIs.

Telemetry ingestion may synchronously record observed source progress through
Data Sources' public observation APIs. This is a forward dependency: Data Sources
does not call Telemetry. The journal write result remains part of the ingestion
result; replacing it with fire-and-forget notification would weaken failure
semantics. Cross-context rows and Management/Control writes remain forbidden.

The public mission lifecycle ingress has two exact additional orchestration
contracts: `Contacts.Scheduler -> Control.Missions` ensures its mission owner
exists, and `Control.MissionRecovery -> Control.Missions` restores approved active
missions after restart. Both retain Control-plane authority; other contexts do
not receive a general composition dependency. Owner: Cadence core architecture.
Review by: 2026-10-18. Remove each exact entry when its caller is removed or moved
into the mission composition owner. Events cannot replace these calls because
the caller needs the concrete startup result before continuing.

## Dependency exceptions

New exceptions are not added directly to the baseline. A proposed exception
must update this policy or an ADR in the same change and record:

- the exact caller and callee;
- why an event, public service, or orchestration move is not yet suitable;
- the responsible owner;
- a removal condition; and
- a review-by date.

Expired or ownerless exceptions fail the architecture check.

### Scoped settings and spacecraft review

`Management.Settings` is an explicit composition boundary for registered settings
providers. `Applications.SettingsSectionDefinition` and `SettingsProvider` are
shared public composition contracts (definition metadata and provider callbacks only); `Platform.ScopedSettings` owns generic revision storage.
Governance owns activation requirements and Commanding owns workspace defaults.

`Control.SpacecraftConfiguration` belongs to Catalog and activation. It consumes
the public saved-configuration review and approved-activation boundaries.
`Activations.ApprovalAdmission` validates the durable approved handoff against
current Governance evidence within the final activation transaction. Its section
lock precedes the generation/configuration locks. These additions preserve the
existing context matrix and plane directions.
