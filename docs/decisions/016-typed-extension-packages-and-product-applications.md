---
title: "ADR-016: Typed Extension Packages and Product Applications"
aliases:
  [application host, extension package, product application, surface definition]
tags:
  [adr, architecture, extensibility, application, plugin, liveview, runtime]
status: accepted
created: 2026-07-24
updated: 2026-07-26
---

# ADR-016: Typed Extension Packages and Product Applications

## Status

Accepted

The implemented slices provide typed application, surface, surface-query,
surface-document, action, host-context, status, installation, and
configuration-reference value types; typed application-dependency,
resource-claim, preflight-check, and preflight-report contracts; a tolerant
first-party application registry; validated, versioned Transport Kind, Provider
Connector, dashboard Widget Type, built-in dashboard Source Adapter, and
Catalog Importer registries; a validated extension-package envelope and
composition-level contribution catalog with package-backed application,
transport-kind, provider-connector, widget-type, source-adapter, and
catalog-importer discovery; a fail-closed compiled-catalog and application-host
provider integrity task in the precommit gate; an application and
typed-extension authoring guide;
read-side application status and surface-query contracts;
a shared registry-driven mission and spacecraft inventory projection used by
inventory, overview, and readiness surfaces; a version-aware typed
action dispatcher; a typed host-owned lifecycle-action and confirmation registry;
typed host-owned domain-action triggers;
fail-closed validation of compiled application and surface definitions;
retained install, disable, uninstall, and reinstall
lifecycle; and a generic authenticated application host with stable
multi-surface navigation, typed action feedback, and an enforced activation
preflight boundary. Declarative surface documents now fail closed against the
complete bounded host grammar before rendering. Telemetry
Decom is the first trusted renderer and action-provider adapter. Derived
Telemetry is the first mission-scoped declarative application, using host-owned
summary, generated-form, and bounded paginated-table primitives over its
existing governed definitions and latest-value projection.

Limits and Alarming is the third proving application. Its compiled mission-
assurance package composes the existing governed limit definitions and latest-
state projection into a mission-scoped application. The host renders numeric
threshold inputs and definition summaries on a configuration surface, and a
severity-ordered activity ledger on a separately addressable current-posture
surface. The typed action boundary persists the next immutable definition
version without moving evaluation or projection ownership into the application
host.

The extension-package vocabulary is also adopted outside the application host.
TCP transport kinds, provider connectors, dashboard widget types, built-in
dashboard source adapters, and catalog importers now publish typed, compiled
definitions. Comms, Ground Networks, Dashboards, and Catalog retain
normalization, validation, credentials, authorization, persistence, execution,
and lifecycle ownership. These extensions do not become product applications
and do not contribute routes.

Mission- and spacecraft-scoped installations are durable, pin an exact
application version, record append-only lifecycle events, and may reference
versioned configuration owned by the application domain. The host reauthorizes
installation mutations, surface queries, and actions; verifies declarations and
exact installed versions; and owns all Phoenix routes. Additional declarative
primitives and complete CFDP product integration remain in the adoption sequence
below. The typed package envelope is implemented, and CFDP has a bounded
Class-1 receive `ManagedApplication` runtime proof while remaining unavailable
as an installable product.

This ADR extends, but does not supersede:

- [ADR-007](007-first-party-capability-abi.md), which defines runtime capability
  families and their execution constraints; and
- [ADR-015](015-management-control-data-plane-architecture.md), which defines
  authority and dependency direction across the management, control, and data
  planes.

Mission-supplied executable packages remain deferred. This decision defines the
first-party product and frontend architecture needed before a future distribution
or sandboxing decision can be made safely.

## Context

Cadence needs to add mission-varying capabilities without building a separate
navigation, configuration page, status page, action flow, and operational view
for every capability.

The current implementation contains several independent extension mechanisms:

- `Cadence.Extensions.Registry` publishes compiled, versioned first-party
  package envelopes and typed application and capability contributions;
- `Cadence.Applications.Registry` publishes product-facing application metadata;
- `Cadence.Capabilities.Registry` publishes runtime capability families;
- `Cadence.Dashboards.WidgetRegistry` publishes versioned renderer and data
  contracts;
- `Cadence.Comms.TransportKind` publishes transport-specific validation and
  partial form metadata;
- `Cadence.ProviderAdapters.Registry` publishes runtime provider adapters; and
- `Cadence.Catalog.Registry` publishes catalog importers.

These registries solve different domain problems, but they repeat parts of the
same extension concern: stable identity, versioning, trust, configuration,
compatibility, presentation, and implementation ownership.

Before the first adoption slice, the application UI also exposed a scaling
problem. The apparently generic route
`/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key`
is dispatched directly to the Telemetry Decom LiveView. The spacecraft
application listing contains Telemetry-Decom-specific status and publication
logic. Adding another product application therefore requires router, catalog,
listing, lifecycle, status, and renderer changes in addition to its domain
implementation.

The term "application" is overloaded:

- Telemetry Decom is a product application, but its runtime behavior is supplied
  primarily by a `SemanticHandler` capability;
- `packet_counter` is a runtime `ManagedApplication`, but is not necessarily a
  user-facing product application;
- CFDP is both a natural product application and a long-lived runtime
  `ManagedApplication`; and
- widgets, catalog importers, transport kinds, and provider connectors are
  extensible features without being product applications.

Treating all of these as one universal plugin callback would erase important
lifecycle, authority, and safety differences. Treating every product application
as a runtime `ManagedApplication` would incorrectly couple product packaging to
one execution model.

Cadence therefore needs a broader product extension model while retaining typed,
domain-specific extension points.

## Decision

Cadence will model extensibility through versioned, typed extension packages.
A package may contribute one or more product applications, runtime capability
families, resource adapters, data sources, widgets, and host-rendered surfaces.

The distribution unit, product unit, installation unit, runtime unit, and
presentation unit are distinct concepts.

### 1. Extension Package Is The Distribution Unit

An `ExtensionPackage` is a versioned, trusted bundle of typed contributions. Its
conceptual contract includes:

```elixir
%ExtensionPackage{
  package_id: binary(),
  version: pos_integer(),
  trust: :first_party,
  compatibility: %{compatibility_contract() => pos_integer()},
  dependencies: [PackageDependency.t()],
  contributions: [typed_contribution()]
}
```

The initial registry is compiled into Cadence and contains only first-party
packages. A package identifier is a durable string. Package discovery must not
create atoms from uploaded or operator-controlled input.

Package identity does not replace the stable identifiers of contributed types.
Application keys, capability-family keys, widget-type identifiers, importer
keys, and adapter keys retain their domain-specific identities and versioning.

An extension package is not automatically visible as an application in the
product. For example, a package containing catalog importers or dashboard
widgets may contribute no product application.

The implemented structural package registry validates the compiled envelope
before fetch. Package identifiers, versions, trust, compatibility contracts,
typed dependencies, contribution types, bounds, and identity uniqueness fail
closed. Compatibility declarations use only the host's current application,
surface, and capability contract identifiers and exact supported versions.

Exact cross-registry resolution belongs to the composition-level extension
catalog rather than making the package-definition catalog depend on the
application runtime context. Application contributions resolve through the
application registry at their exact declared version; applications with
surfaces require the surface contract. Capability contributions resolve through
the plane-neutral capability definition registry at their exact family version
and kind. Transport Kind, Provider Connector, dashboard Widget Type, built-in
Source Adapter, and built-in Catalog Importer contributions resolve through
their owning registries at the exact declared definition version. Transport
Kind and Provider Connector contributions also require the shared
configuration-presentation contract.
Required package dependencies must resolve at or above their declared
minimum version, while absent optional dependencies remain valid. Capability
descriptors therefore carry a version distinct from both package and application
versions. Invalid or unresolved packages remain known compiled entries but are
excluded from composed contribution discovery and rejected by catalog fetch.
`mix cadence.extensions.check` evaluates the complete compiled registry rather
than the tolerant discovery subset, so invalid packages, duplicate package
identifiers, duplicate contribution ownership, and unresolved exact definitions
fail the precommit gate. The same command cross-validates the deliberately
plane-owned action, activation-preflight, status, declarative-surface, and
reference provider registries against every declared application contract.
Provider ownership remains separate so management dispatch does not depend on
projection implementations and projections do not acquire management authority.

The composition catalog is authoritative for product application discovery.
Mission and spacecraft inventories, Spacecraft Profile selection, application
host mounts, trusted-renderer fallbacks, and install events resolve an exact
package contribution before consuming its registered application definition.
The installation context still validates that exact definition and its scope as
a defense-in-depth domain boundary. Disable and uninstall remain available for
retained installation records even if a contribution later becomes unavailable,
so operators are not trapped with an orphaned lifecycle record.

### 2. Product Application Is The Operator-Facing Vertical

An `ApplicationDefinition` describes an independently configured and observed
product capability. Its conceptual contract includes:

```elixir
%ApplicationDefinition{
  application_key: binary(),
  version: pos_integer(),
  display_name: binary(),
  description: binary(),
  trust: :first_party,
  installable_scopes: [application_scope()],
  dependencies: [application_dependency()],
  configuration_contract: configuration_contract(),
  resource_contract: resource_contract(),
  preflight_query_id: binary() | nil,
  activation_contract: activation_contract(),
  status_query_id: binary() | nil,
  status_placements: [status_placement()],
  actions: [action_definition()],
  surfaces: [surface_definition()],
  capability_contributions: [capability_contribution()]
}
```

A product application may span all three authority planes:

- management owns configuration authoring, validation, versions, approval, and
  audit;
- control owns activation, reconciliation, and conversion of approved intent
  into exact operational specifications;
- the data plane owns live record processing, protocol state, runtime timers,
  and typed action requests; and
- projections expose application status, history, health, and operational read
  models.

The application definition describes this vertical composition. It does not
allow one module or facade to bypass the plane boundaries in ADR-015.

### 3. Application Installation Is Durable Scoped Intent

An `ApplicationInstallation` records the desired application and version at an
allowed scope such as organization, mission, spacecraft, source endpoint, or
transport.

Its conceptual state includes:

```elixir
%ApplicationInstallation{
  installation_id: binary(),
  application_key: binary(),
  application_version: pos_integer(),
  scope: application_scope_ref(),
  configuration_ref: versioned_ref(),
  lifecycle_state: :installed | :disabled | :uninstalled,
  metadata: map()
}
```

The exact lifecycle vocabulary may evolve, but the model must distinguish:

- installed or desired application version;
- saved configuration version;
- pending or approved activation intent;
- active runtime generation; and
- projected runtime health.

These are different facts and must not be collapsed into one mutable status
field.

The initial durable implementation supports mission and spacecraft scopes and
requires one retained installation record per application key and scope.
Repeating install is idempotent; installing a disabled record enables it; and
installing an uninstalled record reinstalls it. Disable and uninstall remove
host workspace access and prevent future host actions, but do not impersonate
application-specific deactivation: saved configuration and any independently
governed active runtime state remain intact. Reinstall preserves the installation
identity and configuration reference. Every install, reinstall, enable, disable,
uninstall, application-version, or configuration-reference transition is
append-only history. Each supported scope has an explicit foreign key and a
typed host context rather than an unchecked polymorphic reference. Additional
scope kinds require the same explicit treatment.

Spacecraft Profiles may declare desired applications and default configuration,
but a profile declaration is not the authoritative operational installation or
active runtime state. Application bindings and resource claims are also not the
installation itself; they are application-owned configuration or compiled
activation artifacts.

Telemetry Decom keeps its configuration in
`spacecraft_application_bindings`. A monotonically increasing
`configuration_version` changes only when operator-owned configuration changes;
runtime applied-generation stamps preserve that version. Its installation
stores a typed reference to the binding id and configuration version rather than
duplicating the configuration payload.

### 4. Runtime ManagedApplication Remains One Capability Kind

ADR-007's capability kinds remain unchanged:

- `SemanticHandler`;
- `ManagedApplication`;
- `Projection`; and
- `TransportExtension`.

A product application may contribute zero, one, or several capability families
of different kinds.

`ManagedApplication` continues to mean a long-lived, stateful mission- or
endpoint-scoped runtime instance with initialization, record handling, timers,
and snapshot behavior. It does not mean every feature presented under an
"Applications" page.

Examples:

- Telemetry Decom is a built-in product application whose primary runtime
  contribution is a `SemanticHandler`;
- CFDP is a built-in product application whose sender and receiver behavior fits
  `ManagedApplication`;
- Derived Telemetry is a built-in product application whose execution fits a
  projection or semantic transformation; and
- a runtime test capability such as Packet Counter need not become a product
  application merely because it implements `ManagedApplication`.

### 5. Contributions Are Typed, Not Universal Hooks

An extension package may contribute definitions to explicit extension points,
including:

- product applications;
- runtime capability families;
- transport kinds and transport extensions;
- provider control clients and runtime adapters;
- catalog importers;
- dashboard widget types;
- dashboard data-source adapters;
- operational observable families; and
- UI surfaces attached to host-approved locations.

Each extension point retains its own behavior, validation, and compatibility
contract. The shared package envelope does not create a universal callback or a
universal configuration type.

Core platform contexts may consume these typed definitions through registries,
but an extension may not query another context's persistence schema or reach
through a root facade to obtain hidden authority.

### 6. Configuration Contracts Are Separate From Presentation

Every application or resource extension that accepts configuration separates:

1. configuration validity and normalization;
2. configuration presentation;
3. host-provided reference data;
4. preview and diagnostics; and
5. activation or operational effects.

A runtime ABI, WIT interface, Elixir behavior, or domain struct may describe
valid runtime configuration. It does not also define form layout, LiveView
events, navigation, or operator copy.

Presentation metadata may identify host-owned fields, sections, help text,
conditional visibility, and reference selectors. Server-side domain validation
remains authoritative even when the host generates the form.

The implemented shared presentation contract provides typed configuration,
section, and field definitions. Fields are limited to host-supported input
types, compiled field identifiers, labels, defaults, constraints, bounded
options, and simple compiled visibility conditions. Definitions cannot carry
HTML, CSS, JavaScript, queries, validation callbacks, or side-effect callbacks.
Product applications, transport kinds, and provider connectors consume this
same vocabulary while retaining separate domain contracts and registries.

Reference selectors resolve through registered host providers such as catalog
revisions, spacecraft, transports, telemetry points, or provider profiles.
Definitions may not embed arbitrary Ecto queries or unrestricted module calls in
presentation data.

The first reference-selector slice is implemented for application surfaces. The
registered `SurfaceDefinition` owns a map from durable reference IDs to compiled
provider identifiers, provider versions, host-supported selection modes, and
bounded result limits. Declarative query output may identify a reference field,
but it cannot select or replace that field's provider. Trusted renderers consume
the same surface declaration through the host dispatcher rather than querying a
domain store directly.

After surface authorization, the host resolves a declaration through its
provider registry and validates typed result pages. Eager select mode fails when
its hard option bound would truncate the valid set. Search mode issues debounced,
bounded queries through the host. Every public resolution or query re-resolves
the exact registered surface, active installation, installed application
version, and operator authorization; the renderer cannot name a query module or
bypass the registry. Unknown providers, unsupported versions, client-supplied
reference IDs, mismatched declarative contracts, malformed fields, duplicate
values, and over-limit results fail closed.

Two providers and both renderer tiers now prove the contract. The canonical
telemetry-point provider composes the mission's active decom point inventory with
governed Derived Telemetry outputs. Limits consumes its search mode through a
host-rendered text input and native suggestion list. The Telemetry Decom trusted
workflow consumes a telemetry-bearing catalog-revision provider through its
existing native select. The entered canonical ID remains the Limits action value,
so reference data assists selection without becoming a new validity boundary or
preventing domain-supported future identifiers. Derived Telemetry's point ID
remains a plain text field because it creates a new output identity rather than
referencing an existing point. Server-side domain action validation remains
authoritative and does not move into selector providers.

Activation preflight is a separate typed contract. Application dependencies
declare a compiled application key, minimum version, required or advisory
semantics, and a host-scope relationship. Resource claims declare a compiled
resource family, scope, and exclusive, shared, or reference mode. These
declarations do not resolve conflicts themselves.

The host verifies exact installations and evaluates dependency declarations,
then invokes only the registered domain provider named by the application's
preflight query. The provider returns bounded configuration, resource, and
compilation checks. It retains ownership of resource identity, conflict
detection, validation, and compilation. A preflight report may be ready, carry
non-blocking advisories, or be blocked; it cannot execute activation effects.

### 7. SurfaceDefinition Is The Shared UI Contract

Cadence will introduce a host-owned `SurfaceDefinition` contract usable by
product applications and other typed resource extensions.

Conceptually, a surface declares:

```elixir
%SurfaceDefinition{
  surface_id: binary(),
  version: pos_integer(),
  purpose: surface_purpose(),
  scope: application_scope(),
  placement: host_slot(),
  subject_contract: subject_contract() | nil,
  navigation: navigation_contract(),
  data_contract: surface_data_contract(),
  references: %{reference_id() => reference_definition()},
  actions: [action_id()],
  refresh: refresh_contract(),
  renderer: renderer_definition()
}
```

The initial surface purposes are:

- **Overview** — application identity, dependencies, installation state,
  configuration version, activation state, health, and important diagnostics.
- **Configuration** — forms, reference selectors, resource claims, validation,
  and draft configuration state.
- **Preview and diagnostics** — compiled intent, conflicts, warnings, affected
  resources, expression results, or other expected operational outcomes.
- **Operations** — live application state and application-specific operational
  commands.
- **Collection** — a pageable or filterable collection owned by the application,
  such as CFDP transactions, derived telemetry definitions, evaluation runs, or
  limit events.
- **Subject detail** — a deep-linkable view of one application-owned subject such
  as a transaction, definition, run, diagnostic, or event.
- **Activity and evidence** — configuration history, activation history, domain
  events, failures, and audit evidence.

Application inventory summaries are host-standard projections rather than
custom-rendered surfaces. Their definition and status contracts provide the
application name, installed version, configuration state, activation state,
health, and outstanding actions. This keeps the inventory consistent as the
number of applications grows.

The implemented `CadenceWeb.ApplicationInventory` host adapter is the shared
entry point for mission inventory, spacecraft inventory, spacecraft overview,
and spacecraft readiness. It resolves package contributions at the composition
boundary, then delegates to `Cadence.Reads.Applications.Inventory` to compose
the exact retained installation version, lifecycle state, and plane-owned status
provider into one typed item. This keeps projections from depending upward on
the composition root. Catalog inventory lists all available applications at a
host scope; profile inventory lists the profile's declared keys and retains
unknown custom extension keys as unavailable. Retained installations that are
absent from the current profile remain visible and manageable, because profile
declaration and installation lifecycle are separate facts; only a brand-new
install requires a declaration. A missing exact installed version is reported
as an upgrade requirement rather than being silently interpreted through the
latest contract. Cross-application host surfaces therefore do not call Telemetry
Decom or any other application-owned configuration module directly.

Mission and spacecraft inventories render the same
`CadenceWeb.ApplicationInventoryCard` and delegate lifecycle transitions to
`CadenceWeb.ApplicationInventoryLifecycle`. Their LiveViews now own only the
scope-specific inventory source, installation eligibility, breadcrumbs, and
workspace path. Status facts, action controls, stable DOM identities, lifecycle
feedback, and refresh behavior are host-standard. Supporting another durable
application scope therefore requires a scoped context and route shell, not
another copy of the application lifecycle UI.

An application may opt its standard status into a bounded cross-application
surface with a `StatusPlacement`. The placement declares only a host-approved
location, application scope, and whether an absent installation is blocking.
It cannot provide copy, routes, rendering metadata, or a callback. A definition
with a status placement must name a registered status query, and each placement
must match one of the application's installation scopes.

The first status placement is spacecraft-scoped `:comms_validation`. The Comms
host loads the exact pinned Spacecraft Profile plus retained installations
through `CadenceWeb.ApplicationInventory`, selects only applications that
declare that placement, and converts their standard status tone into a Comms
finding. Comms owns the Spacecraft Setup group, blocking-versus-warning policy,
and links to host-owned application inventory or workspace routes. Telemetry
Decom owns only its registered status provider and declares that its absence is
blocking. Unrelated applications do not become Comms findings merely because
they are installed, and Comms no longer knows Telemetry Decom states, stores,
or route keys.

The initial declarative block vocabulary is limited to:

- status summaries;
- key-value details;
- form sections and fields;
- host-provided reference selectors;
- data tables with host-owned filtering and pagination;
- diagnostics and validation results;
- progress or job-status panels;
- activity timelines;
- action bars and confirmation forms; and
- links to or embeddings of existing dashboard surfaces.

Definitions describe semantic grouping, data, and actions. They do not describe
Tailwind classes, responsive breakpoints, arbitrary HTML nesting, or general page
layout. The host owns visual styling, accessibility, loading and error states,
and responsive composition.

Surface data contracts name registered, scoped queries and bounded result
schemas; they do not contain arbitrary Ecto queries or module calls. Refresh
contracts may select host-supported behavior such as static loading, reload after
an action, bounded polling, or a registered projection subscription. They do not
grant access to arbitrary PubSub topics or browser timers.

The implemented table contract carries a bounded `Cadence.Listing.Page` rather
than an unbounded row list. The host rejects oversized pages, inconsistent page
metadata, malformed row identities, and duplicate row identities before
rendering. Derived Telemetry and Limits both use the same 20-row query helper.
Pagination is ephemeral presentation state rather than an application action;
the host emits it as a query-string patch, reloads the authorized registered
surface, and resets the LiveView row stream to the returned page. This preserves
shareable links and browser history without exposing provider modules or query
functions to the renderer.

The implemented diagnostic contract is an exception-only, bounded list rather
than a general notification feed. Each finding has a stable identity, code,
severity, title, detail, and optional compact value; the block also carries its
total count so a trusted adapter may report omitted findings. The host validates
the contract, limits rendered items to 20, owns severity presentation and
accessibility semantics, and renders nothing when there are no exceptional
findings. Limits uses the block declaratively for current red and yellow
departures. Telemetry Decom adapts compiler findings to the same block from its
trusted renderer, proving that the primitive crosses both renderer tiers.
Activation preflight remains a separate typed contract because it governs
whether an operational transition may proceed.

The host validates the complete declarative surface document, not only its
largest collections. Documents are limited to six summary facts, 24 generated
form fields, 12 table columns with schema-complete bounded rows, 20 activity
items, and 20 rendered diagnostics. All host-visible block, row, activity, and
field identities must be well formed and unique within their namespace; tones,
field types, options, numeric bounds, table columns, and optional text values
must match the compiled vocabulary. A generated form may submit only the exact
action declared by its containing surface. Invalid provider output is rejected
before HEEx rendering or action dispatch, making the renderer boundary
fail-closed rather than relying on first-party provider correctness.

The compiled definition boundary is also validated before registry resolution,
inventory inclusion, navigation, or rendering. Application validation composes
the separate dependency, resource-claim, lifecycle, domain-action, surface, and
reference validators; it does not replace them with one universal schema.
Definitions fail closed on malformed or duplicate identities, unsupported
vocabulary, self-dependencies, lifecycle/domain action collisions, actions not
declared by both the application and surface, action or surface scope mismatch,
unbounded references, application-owned presentation keys, or an available
installation scope without an application workspace. Roadmap definitions may
remain intentionally surface-less until their product contract is ready.

The supported renderer tiers are:

1. **Generated form** — host-rendered fields from configuration and presentation
   contracts.
2. **Declarative blocks** — host-owned status, detail, table, diagnostics,
   action, and dashboard primitives composed as data.
3. **Trusted renderer** — a compiled first-party LiveView function component,
   LiveComponent where isolated state and lifecycle are necessary, or registered
   client hook for interactions not covered by host primitives.
4. **Sandboxed renderer** — a future restricted scene or specification protocol;
   this tier is not approved by this ADR.

The host may add a reusable primitive after repeated product evidence. A
declarative surface cannot introduce arbitrary DOM behavior or a new rendering
primitive.

Collection and subject-detail surfaces may declare an opaque subject contract so
the host can provide stable deep links without allowing application-owned
routes. Comms Validation establishes the first concrete embedded status
placement: it uses the authenticated mission and organization scope already
owned by the `:comms` LiveView session, reads the existing bounded application
status contract at spacecraft scope, and renders a host-standard finding rather
than an application-owned layout. Additional embedded placements require their
own concrete authorization, data, readiness, and layout semantics; they are not
enabled by this first vocabulary entry.

Telemetry Decom's APID claim table remains a trusted renderer initially. Its
catalog revision selection, resource conflicts, filtering, bulk selection,
preview diagnostics, autosave, and activation behavior must not be flattened
into a generic settings form merely to satisfy this architecture.

### 8. Hosts Own Routes, Scope, Authorization, And Side Effects

Extension packages do not install Phoenix routes.

Cadence hosts resolve registered definitions, load authorized scope, verify the
installation, build host context, render a declared surface, and mediate typed
actions.

The initial route ownership is:

- spacecraft application surfaces remain inside the authenticated
  `:spacecraft_show` LiveView session so organization, mission, spacecraft, user,
  navigation, and authorization context are loaded by the host;
- mission configuration workspaces live inside the authenticated `:mission`
  LiveView session so organization, mission, user, navigation, and authorization
  context are loaded by the host;
- mission operational surfaces may live inside the authenticated `:ops`
  LiveView session when the Ops shell and operational context are required; and
- organization-scoped provider and administration surfaces remain in their
  existing authenticated and administrator-gated sessions.

An extension may request a host-approved navigation or surface placement. It may
not contribute routes or authentication plugs. Declarative definitions may not
embed HEEx, JavaScript, CSS, browser globals, or direct DOM access. A trusted
renderer may reference only a compiled first-party component or client hook that
the host has registered explicitly.

Host-owned route shapes may include registered surface and opaque subject
identifiers, for example an application workspace, collection surface, and
subject-detail surface. The host resolves and authorizes every segment; the
application definition does not install or generate a Phoenix route.

The implemented workspace route shapes are
`/missions/:mission_id/applications/:application_key/:surface_id` and
`/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/:surface_id`.
The shorter application route resolves the first workspace surface by declared
navigation order. The host resolves exact registered surface identifiers and
renders navigation only when an application contributes more than one workspace
surface. Unknown surface identifiers do not fall through to application code.

Retired application-specific URLs are compatibility redirects, not alternate
application hosts. The legacy Telemetry paths remain inside the authenticated
browser pipeline and issue permanent redirects to the generic spacecraft
application route. `ApplicationHostLive` therefore resolves an application key
only from the host-owned route parameter; it has no application-specific
`live_action` branches. New applications require neither new routes nor redirect
mappings unless they are replacing a previously shipped URL.

`ApplicationDefinition.actions` contains application-defined domain action
definitions. Its lifecycle contract declares supported host-standard actions. A
surface references stable identifiers from either set rather than redefining an
action for each placement.

#### Surface Queries Are Not Actions

Read operations such as loading configuration, projected status, history,
reference data, and subject details belong to typed surface-data query contracts.
They remain scoped and authorized, but they do not become `ActionDefinition`s.

Renderer interactions that only change ephemeral presentation state are also not
application actions. Filtering a table, expanding a row, changing a tab, editing
a local draft, or making a local bulk selection remains renderer behavior. A
gesture becomes an action only when it crosses a durable, authorization,
governance, runtime, or external-effect boundary.

#### Standard Lifecycle Actions Are Host-Owned

Cadence defines the common lifecycle operations and their semantics. An
application lifecycle contract declares which operations it supports rather than
redefining them. The standard set includes:

- install;
- upgrade or migrate stored configuration;
- save a new configuration version;
- restore a prior configuration version;
- request activation;
- request deactivation;
- disable; and
- uninstall.

In the implemented installation lifecycle, `disable` means disable host
workspace access and `uninstall` means retain the durable installation record as
uninstalled. Neither operation is a runtime deactivation request. Applications
with active behavior continue to use their separately authorized deactivation
and reconciliation contracts, so the UI cannot imply that removing a workspace
has made the runtime safe or inactive.

Activation approval and rejection remain core activation-governance operations,
not actions contributed independently by every application. A pure configuration
preview is a query. A preview or test that persists a run, consumes significant
resources, contacts an external system, or produces an operational effect is an
explicit application action.

Before dispatching a declared `request_activation`, the host reruns the
authorized preflight against the exact installed application version. Any
blocking check prevents provider execution even if the browser submits the
action directly. Advisory checks remain visible but do not block. Approval and
control-plane activation still occur through the existing governance boundary
after preflight succeeds.

The standard lifecycle vocabulary is implemented as a typed host registry.
Each `LifecycleActionDefinition` owns the stable action identity, label,
permission, effect, execution mode, button treatment, and optional typed
confirmation. An application's `LifecycleContract` contains only the standard
action identities it supports, so an application cannot redefine `disable` or
`request_activation`. The dispatcher resolves lifecycle permissions through the
same registry rather than hard-coded action branches.

The trusted Telemetry Decom renderer and both mission and spacecraft application
inventories render lifecycle controls through the same host component. Its
confirmation metadata supplies stable DOM evidence and the browser confirmation
prompt, including the warning that disabling or uninstalling workspace access
does not change active runtime state. Confirmation is an operator safeguard, not
authorization: direct or replayed events are still reauthorized, version-checked,
preflighted where applicable, and dispatched only through the host boundary.

#### Domain Actions Are Application-Defined

Applications may declare operations unique to their product behavior. Examples
include submitting or cancelling a CFDP transfer, requesting a historical
derived-telemetry recomputation, acknowledging an alarm event if acknowledgement
becomes part of the Limits product model, or retrying a failed event-processing
run.

Conceptually, a domain action declares:

```elixir
%ActionDefinition{
  action_id: binary(),
  version: pos_integer(),
  intent: :configuration | :diagnostic | :operation | :maintenance,
  scope: application_scope(),
  input_contract: action_input_contract(),
  result_contract: action_result_contract(),
  required_permission: binary(),
  effect: :none | :durable | :external,
  execution: :immediate | :asynchronous | :approval_required,
  concurrency: concurrency_contract(),
  confirmation: confirmation_contract(),
  progress_contract: progress_contract() | nil
}
```

Action identity and version are durable strings and integers. An asynchronous or
external action defines idempotency, progress, terminal results, and cancellation
semantics where cancellation is supported. Availability reported to a surface is
not authorization; the host reauthorizes and revalidates every request.

The implemented domain-action trigger resolves the action through both the
application definition and the current surface declaration, validates the typed
definition, and fails closed on an undeclared action or scope mismatch. It emits
stable intent, scope, effect, execution, version, and confirmation metadata while
retaining the surface-owned label. Generated forms are the first real consumer,
so their submit controls now share the same host action treatment as lifecycle
controls. A standalone action-bar document primitive remains deferred until a
real application contributes a non-form action that needs it.

Actions are dispatched through host-owned domain services. The host re-resolves
the installation and definition, verifies the declared action and expected
versions, authorizes the current scope, validates input, records audit evidence,
and then invokes the registered domain operation. An application renderer does
not directly execute external effects. Runtime and control-plane effects continue
through typed action requests, governed services, and platform-owned executors.

First-party action adapters also own translation of application-specific domain
failures into a bounded `ActionFailure` contract with a stable string code,
operator-facing message, optional declared field identifier, and retryability
fact. The host may attach that failure to an exact field declared by the current
generated form and renders one standard inline outcome treatment. It does not
pattern-match on application-specific error tuples, inspect arbitrary failures
into operator copy, or create atoms from returned field identifiers. Generated
forms supply their own successful-action message because that copy belongs to
the surface, not the generic host.

### 9. Core Platform Verticals Do Not Become Applications By Default

A feature is application-shaped when it is independently installable or
configurable at a declared scope, has a separate lifecycle and version, consumes
typed platform resources, emits typed records or actions, and can be absent
without making Cadence itself incoherent.

The following are initial product-classification targets:

| Feature | Product classification | Expected runtime contribution |
| --- | --- | --- |
| Telemetry Decom | built-in application | `SemanticHandler` |
| CFDP | built-in application | `ManagedApplication` |
| Derived Telemetry | built-in application | `Projection` or semantic transformation |
| Limits and Alarming | built-in, normally installed application | projection or semantic evaluation plus typed actions |
| Event Reporting | future application | `SemanticHandler` |
| Mission payload/science parser | future application | `SemanticHandler` or `ManagedApplication` |
| Packet Counter | capability only unless a product need emerges | `ManagedApplication` |

Commanding, Contact Planning, Contact Lifecycle, catalog infrastructure,
activation governance, Dashboards, identity, and tenancy remain core platform
verticals. They expose typed services and extension points that applications use;
they do not become applications solely to reuse the surface system.

Transport kinds, provider connectors, catalog importers, data-source adapters,
and dashboard widgets are typed extensions rather than product applications.
They may use the same configuration and surface primitives without appearing in
the application inventory.

### 10. Versioning And Compatibility Are Explicit

Package, application, capability, surface, catalog-importer, and
stored-configuration versions are related but distinct.

- installations pin an application version;
- application versions reference compatible capability and surface versions;
- package contributions resolve exact application or capability versions and
  capability kinds before discovery;
- active runtime specifications pin exact capability configuration and code
  compatibility;
- catalog import runs pin the exact importer key and version selected when the
  run is created, and queued execution re-resolves that exact definition;
- stored surfaces and configuration documents declare schema versions; and
- migrations are explicit, deterministic operations rather than implicit
  interpretation of old documents by the latest implementation.

Registries must tolerate unknown, removed, or unsupported definitions so an old
installation or stored document can be reported as unavailable or incompatible
without crashing navigation or the host.

### 11. First-Party Compile-Time Packages Come First

This ADR authorizes only compiled first-party packages.

It does not authorize:

- mission-uploaded Elixir modules;
- arbitrary HEEx, JavaScript, CSS, or browser code;
- package-owned Phoenix routes;
- direct database or secret access by declarative surfaces;
- arbitrary external side effects; or
- mission-uploaded WASM execution.

A future ADR may define signed distribution, compatibility negotiation,
sandboxing, WIT component boundaries, and resource limits after the first-party
contracts have been exercised by multiple real applications.

## Existing Features And Migration Direction

### Telemetry Decom

Telemetry Decom becomes the first application-host adapter without changing its
domain behavior. The generic host takes ownership of application lookup, scope,
common page structure, status contract, and action mediation. Its APID workflow
remains a trusted renderer until repeated workflows justify additional host
primitives.

Its first activation-preflight provider is implemented over the existing saved
configuration, APID ownership query, and runtime-artifact compiler. The host
renders configuration-version, exclusive packet-claim, and compilation checks
immediately before the governed activation request. Empty or conflicting APID
claims and compiler errors block dispatch server-side; compiler warnings remain
operator-visible advisories. This does not move APID ownership or compilation
into the host.

### CFDP

The `cadence_ccsds` library continues to own pure codecs, protocol validation,
segmentation, reassembly, and state machines. A first-party CFDP extension
package in Cadence owns installation, authorization, activation, persistence,
file-effect execution, operational records, and surfaces. The protocol library
does not acquire Cadence tenancy, Repo, LiveView, or action-execution
dependencies.

The first runtime proving slice is implemented without claiming the unfinished
product boundary. The compiled `cadence.cfdp` package contributes a roadmap CFDP
application and the `:cfdp_receive` capability family. That family runs a real,
long-lived Class-1 receiver at source-endpoint partition affinity, decodes CFDP
PDUs through `cadence_ccsds`, carries transaction state across packet records,
uses platform-owned Check timers, emits sanitized transaction events, enforces
hard memory and transaction-count bounds, and persists only its declared
JSON-safe snapshot. It explicitly rejects acknowledged mode, closure-requested
transfers, outbound PDUs, and external filestore effects until Cadence defines
the transport, durable file-effect executor, storage, activation, and operator
contracts they require. The product application therefore remains `:roadmap`
and cannot be installed through the host.

### Derived Telemetry

Derived Telemetry becomes a mission-scoped built-in application over its
existing governed definitions, immutable evaluation snapshots, emitted samples,
run history, and latest-value projection. Its management surface may use
generated forms and declarative diagnostics while expression editing may use a
trusted renderer when needed.

The first proving slice is implemented. Its application definition contributes
a mission-scoped management surface backed by a registered, versioned query. The
host renders summary facts, a generated definition form, and the paginated
governed definition table; dispatches `save_definition` through the typed action
boundary; enforces mission authority; and reloads the surface after the durable
action. Definitions remain owned and versioned by the Governance and Derived
Telemetry contexts rather than copied into the installation record.

### Limits And Alarming

Limits and Alarming becomes a built-in application that may be installed by
default for missions. Existing governed limit definitions, evaluation events,
latest-state projections, dashboard source, and mission-health reads remain in
their owning contexts. The application definition composes them into one
configuration, activation, status, and operations experience.

The first proving slice is implemented as the compiled
`cadence.mission-assurance` extension package. The `limits` application is
installable at mission scope, reports host-standard status from governed
definitions and current red/yellow departures, and contributes two declarative
surfaces. The default Definitions surface adds a registered host reference
selector for active or derived telemetry, adds host-owned numeric form fields,
pages the governed definition table, and persists new immutable limit-definition
versions through a typed
`save_limit_definition` action. The separately addressable Current posture
surface contributes an exception-only diagnostic summary for current red and
yellow departures plus a bounded streamed activity primitive over the existing
latest-state projection, and has no configuration action. The host renders
their shared navigation from the application definition. Limit evaluation,
lifecycle evidence, operational events, and dashboard integrations remain in
the Limits and read-model contexts.

### Transport And Provider Extensions

Transport kinds and provider connectors now expose explicit typed definitions
before a second production implementation is added. The TCP transport kind
contributes its versioned identity, adapter key, behavior module, and bounded configuration
presentation, including compiled conditional fields for framing and reconnect
policy. The existing transport setup LiveView resolves that definition and
renders it through the shared host configuration primitive. Transport-specific
normalization, validation, materialization, persistence, and lifecycle remain in
Comms.

The compiled `cadence.tcp-transport` package contributes the exact TCP Transport
Kind definition. Direct and provider-derived setup now resolve through the
composition catalog, and provider Delivery Profile derivation is a typed
Transport Kind behavior rather than a TCP-specific LiveView branch. The Comms
registry revalidates the exact compiled definition for lower-level persistence
and runtime materialization.

The simulator provider connector similarly contributes its stable form value,
definition version, provider type, client key, runtime module, account defaults, and bounded
control-plane configuration presentation. The existing provider-account setup
LiveView resolves the exact connector, renders its control-plane fields through
the same host primitive, and persists the connector's compiled provider and
client identities. Credential handling, policy guardrails, authorization,
account persistence, provider lifecycle, and runtime adapter behavior remain in
Ground Networks and the existing provider registries.

The compiled `cadence.ground-network-simulator` package contributes that exact
Provider Connector definition. Provider-account creation and inventory labels
discover connectors through the composition catalog; the Ground Networks
registry remains the runtime client authority for retained account versions.

Neither package contribution appears in the application inventory or contributes
routes, surfaces, or installation lifecycle. The shared field vocabulary is a
presentation contract, not a universal extension behavior.

### Dashboard Widget And Source Extensions

The compiled `cadence.dashboard-widgets` package contributes the exact versions
of the seven first-party dashboard widget types. `WidgetRegistry` remains the
owner of renderer, frame, binding, option, layout, drilldown, trust, and
authoring-presentation contracts. The composition catalog is authoritative for
which compiled widget types the dashboard authoring UI offers; persisted
dashboard validation and execution continue to resolve the exact stored type and
version through `WidgetRegistry`.

The compiled `cadence.dashboard-sources` package contributes the four built-in
logical source adapters for telemetry, limits, operational observables, and
events. Each typed source-adapter definition owns its stable logical source,
definition version, operator label, implementation module, and initial physical
data-source capabilities. Data-source registration discovers these definitions
through the composition catalog instead of duplicating adapter modules and
capability maps in the LiveView layer.

`DefaultSourceAdapters` remains the runtime mapping authority. Explicitly
configured adapter modules used by retained records, tests, or customer-owned
runtime integration remain supported by the source runtime; they do not become
installed or operator-selectable extensions merely by being loadable modules.
Dashboard authoring and data-source registration remain on their existing
authenticated `:ops` LiveView routes. Packages add neither routes nor access to
organization, mission, or user scope.

### Catalog Importer Extensions

The compiled `cadence.catalog-yaml` package contributes version 1 of the
first-party `cadence_yaml` importer. `Cadence.Catalog.Registry` remains the
owner of importer validation, source detection, and invocation. Its typed
`ImporterDescriptor` carries the stable importer key, definition version,
trust, catalog family, source formats, media types, and operator-facing
description.

The composition catalog is authoritative for which compiled first-party
importers the catalog upload UI discovers. Explicitly configured importer
modules remain supported by the Catalog runtime, control-plane API, and tests;
being loadable or configured does not make an importer a compiled package or
grant it product visibility.

Each catalog import run stores both the importer key and its exact definition
version. Queued execution resolves that exact pair rather than silently using a
newer definition. The version belongs to the import run rather than the
artifact because one artifact can have multiple attempts using different
importer definitions.

Catalog pages remain on their existing authenticated `:catalog` LiveView
session inside the `[:browser, :require_authenticated_scope]` pipeline. The
session continues to require organization scope, load mission scope, and attach
the user menu. Packages contribute no routes and receive no authority from
discovery.

## Consequences

### Positive

- New applications do not require new router entries or duplicated application
  list and status logic.
- Product packaging no longer depends on one runtime execution kind.
- Common configuration and operational surfaces become reusable data rather than
  repeated LiveViews.
- Novel workflows retain a trusted renderer escape hatch.
- Existing capability, widget, importer, transport, and provider registries gain
  a common distribution and presentation vocabulary without losing their typed
  contracts.
- Application activation preserves management, control, and data-plane
  authority boundaries.
- CFDP, Derived Telemetry, Limits, Event Reporting, and mission payload handlers
  gain a coherent product path.

### Negative

- Package, application, installation, capability, binding, surface, and active
  runtime generation are separate concepts that require clear APIs and UI copy.
- A generic host and surface renderer introduce new platform code and contract
  tests.
- Some currently direct LiveView-to-context calls must be replaced by explicit
  surface-query, status, and action contracts.
- Version compatibility and migration behavior become first-class product work.
- First-party packages remain compiled with Cadence until a later distribution
  and sandboxing decision.

### Risks

- A universal descriptor may become an untyped map that recreates the root
  facade problem in data form.
- A surface grammar designed from only Telemetry Decom may encode its workflow as
  supposedly generic primitives.
- Treating every bounded context as an application could obscure platform
  authority and domain vocabulary.
- Allowing trusted renderers to bypass host actions or status contracts would
  preserve the existing coupling behind a registry lookup.
- Coupling package versions directly to capability or surface versions would
  make independent compatibility and migration unnecessarily difficult.

These risks are addressed by typed contribution contracts, multiple proving
applications, host-owned actions and routes, and explicit version boundaries.

## Initial Adoption Sequence

Steps 1 through 4 and 6 through 10 are implemented, including validated package
envelopes; exact application, capability, Transport Kind, Provider Connector,
dashboard Widget Type, built-in Source Adapter, and built-in Catalog Importer
contribution resolution; and package-backed discovery across inventories,
profile selection, host mounting, install events, transport setup, provider
account setup, dashboard widget authoring, data-source registration, and catalog
upload detection. The compiled catalog and its plane-owned application provider
bindings have an executable integrity gate and a task-oriented authoring guide
covering classification, owning-domain contracts, host surfaces, route
ownership, exact version persistence, and product-path proof. Step 5 has summary,
generated-form, bounded paginated-table, numeric-input, streamed-activity, and
multi-surface navigation primitives plus typed inline action outcomes, field
failures, bounded diagnostic lists, activation-preflight diagnostics, and surface-declared select and
query-backed reference providers consumed by both renderer tiers, plus
fail-closed validation of the complete declarative document grammar and typed
host-owned lifecycle confirmations and domain-action triggers, but not the full
proposed vocabulary. The
host also implements
retained install, disable, uninstall, and reinstall lifecycle at mission and
spacecraft scope. Step 8 has a real CFDP
`ManagedApplication` runtime proof and typed roadmap package, while the
installable CFDP product remains blocked on explicit storage, transport,
activation, and operator contracts.

1. Add first-party `ExtensionPackage`, `ApplicationDefinition`, and
   `SurfaceDefinition` value types plus tolerant registries.
2. Introduce application status, surface-query, and action contracts and make the
   spacecraft application inventory registry-driven.
3. Replace the hard-wired application detail route target with a host LiveView in
   the existing authenticated `:spacecraft_show` session.
4. Adapt Telemetry Decom through the trusted-renderer tier without changing its
   behavior.
5. Add generated configuration forms and the first declarative status, detail,
   diagnostics, action, table, progress, activity, and dashboard primitives.
6. Model Derived Telemetry as the first schema- and projection-oriented proving
   application.
7. Model Limits and Alarming as the mission-assurance proving application for
   numeric configuration, current severity, and operational activity.
8. Model CFDP as the first long-lived `ManagedApplication` proving application.
9. Add typed definitions and package-backed discovery to Transport Kind,
   Provider Connector, dashboard Widget Type, built-in dashboard Source Adapter,
   and built-in Catalog Importer registries before adding their second
   production implementations.
10. Add architecture and contract tests preventing package contributions from
   bypassing context, plane, authorization, route, side-effect, or compiled
   definition-validation boundaries, and enforce complete compiled-catalog
   integrity in precommit.
11. Revisit declarative user-authored surfaces and sandboxed runtime components
    only after the first-party contracts have multiple real consumers.

## Deferred Decision Triggers

The following decisions are not required to complete this ADR. Reopen one only
when a concrete product or distribution requirement supplies the missing
evidence; they are not a backlog for speculative application-host expansion.

1. **Additional installation scopes** — decide on another scope only when a real
   application cannot be placed honestly at mission, spacecraft, or source
   endpoint scope.
2. **Durable schema formats** — standardize stored configuration and presentation
   schemas only when multiple owning domains require host-managed schema
   persistence, compatibility, and migration rather than domain-owned versioned
   configuration.
3. **Additional surface primitives** — add progress, paginated-reference,
   standalone domain-action-bar, or other primitives only when a first-party
   workflow cannot fit the implemented bounded grammar and demonstrates a
   reusable host behavior rather than application-specific layout.
4. **Limits installation semantics** — choose explicit default installation or
   implicit system-provided availability when deployment and onboarding behavior
   require one consistent product rule.
5. **Additional resource claims** — add a claim family and domain preflight
   provider when another application has a concrete exclusivity, capacity, or
   conflict contract beyond Telemetry Decom's APID ownership.
6. **Signed or mission-supplied packages** — define compatibility, distribution,
   signing, and sandboxing guarantees only after Cadence chooses to accept code
   or declarations outside the compiled first-party package set.
7. **Application-subject deep links** — define stable subject identifiers and
   routes when an operator workflow needs bookmarkable, version-resilient links
   below an application's registered surface.

## See Also

- [ADR-001: Mission-Scoped Runtime and Selector Model](001-mission-scoped-runtime-and-selector-model.md)
- [ADR-004: Activation Authorization and Approval Policy](004-activation-authorization-and-approval-policy.md)
- [ADR-007: First-Party Capability ABI](007-first-party-capability-abi.md)
- [ADR-008: Multi-Format Catalog Import Architecture](008-multi-format-catalog-import-architecture.md)
- [ADR-014: Shared CCSDS Library Boundary](014-shared-ccsds-library-boundary.md)
- [ADR-015: Management Plane, Control Plane, and Data Plane Architecture](015-management-control-data-plane-architecture.md)
- [Add a Product Application or Typed Extension](../how-to/add-a-product-application-or-typed-extension.md)
- [Packet Model and Application Binding Design](../superpowers/specs/2026-04-20-packet-model-and-application-binding-design.md)
- [Application APID Selection Design](../superpowers/specs/2026-04-23-application-apid-selection-design.md)
- [Dashboard Visualization Engine Design](../dashboards-visualization-engine-design.md)
