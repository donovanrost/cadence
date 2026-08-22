# Design: Comms Transport, Routing, and Spacecraft Profile UX

- Status: draft for implementation planning
- Created: 2026-06-01
- Scope: Reframe spacecraft creation and comms setup around Spacecraft Profiles, Transports, and Routing Rules while preserving ADR-006 runtime semantics for Contacts and Links.
- Supersedes: portions of [Mission Comms and Spacecraft Interpretation UX](2026-04-29-comms-spacecraft-interpretation-ux-design.md) that treated Link or Link Assignment as persistent primary setup nouns.
- Related decisions:
  - [ADR-006: Contact, Link, and Transport Runtime Model](../../decisions/006-contact-link-and-transport-runtime-model.md)
  - [ADR-012: Provider Adapter and Ground Station Simulator Model](../../decisions/012-provider-adapter-and-ground-station-simulator-model.md)

## Summary

The comms setup UI should not expose Cadence's persistence model as the
operator's product model. `SourceEndpoint`, `ProviderProfile`,
`TransportProfile`, `PathTemplate`, and `LinkAssignment` are useful backend
concepts, but they currently leak into the primary workflow and make spacecraft
creation feel like object-graph assembly.

This design introduces a clearer product vocabulary:

- **Spacecraft Profile**: reusable byte-interpretation and application defaults.
- **Spacecraft**: mission asset identity, selected profile, and per-spacecraft
  application configuration.
- **Transport**: durable capability for moving bytes into or out of Cadence.
- **Routing Rule**: durable policy for how a spacecraft uses transports for a
  purpose and direction.
- **Contact**: temporal opportunity or execution window. Contacts remain out of
  scope for this implementation pass.
- **Link**: transient runtime realization during a contact, ingest run, test
  session, or other execution. Link is not a persistent setup object in the
  primary UI.

The immediate implementation should salvage the useful parts of the current
worktree's Spacecraft Type direction, but rename and narrow it to
Spacecraft Profile. It must not delete the durable comms setup surface until
Routing Rules replace the old path/template/link-assignment assumptions.

## Product Principle

The primary setup model is:

> Profile defines interpretation. Transport defines capability. Routing defines
> intended use.

The runtime model remains:

> Contact is time. Link is runtime realization. Transport runtime is session
> local.

These two statements should both stay true. Setup pages describe durable
configuration. Runtime pages later show contacts, active links, and link
history.

## Mission Management, Not Operations

The pages in this implementation pass are mission-management setup pages. They
support infrequent configuration and maintenance work, such as initial
spacecraft setup, spacecraft profile management, catalog setup, transport setup,
routing setup, validation of durable configuration, future firmware update
workflows, and enabling new antennas or external capabilities.

They are not day-to-day spacecraft operations pages. Do not design them as an
ops console, live dashboard, alarm surface, command queue, active timeline, or
real-time link/contact monitor. They should be dense, scannable, table-oriented,
and audit-friendly. Copy should describe durable setup state and configuration
gaps, not live operational state.

Future spacecraft operations pages should live in a separate operations area,
following the legacy Cadence pattern under `/missions/:id/ops`. That future
area can own active operations such as command execution, queue management,
alarms, timelines, active contacts, runtime links, and live telemetry
monitoring.

## Problem

The current implementation direction has the right instinct but the wrong
boundary.

It correctly observes that creating a spacecraft should not require users to
think in terms of provider profiles, source endpoints, transport profiles, and
path templates.

It incorrectly treats Spacecraft Type/Profile as a replacement for comms setup.
Spacecraft Profiles describe byte interpretation and enabled applications. They
do not make KSAT antennas available, configure a lab TCP stream, describe an S3
back-orbit archive, or decide which spacecraft traffic should use which
transport.

The old UI also overloaded "Link" as a persistent configuration object. That
conflicts with ADR-006, where paths and links are runtime/contact-scoped
operational realities. A Link should be something Cadence realizes, observes,
and records during execution, not something users create as a durable template.

## Terminology

The first implementation pass should use these user-facing terms in navigation,
headings, empty states, tests, and validation copy.

| User-facing term | Definition | Backend mapping for first pass |
| --- | --- | --- |
| Spacecraft Profile | Reusable bus/profile contract: data-link protocols, frame parameters, packet protocol, enabled platform applications, and future defaults. | Rename current `SpacecraftType` UI/domain to `SpacecraftProfile` or introduce aliases while migrating. |
| Spacecraft | Mission-owned vehicle identity. Holds display name, SCID, selected profile version, and per-spacecraft app config. | `Cadence.Spacecraft` plus profile reference fields. |
| Transport | Durable capability for moving bytes into or out of Cadence. Can be live, scheduled, pull-based, file-backed, provider-backed, or simulated. | First-class domain object. Existing `ProviderProfile` records may be materialized for adapter compatibility. |
| Routing Rule | Durable policy that says how a spacecraft uses one or more transports for a purpose and direction. It is not time-bound. | First-class domain object. Existing `PathTemplate` and `LinkAssignment` records may be materialized for compatibility/runtime integration. |
| Contact | Time-bounded operational opportunity or execution window. | Existing `ScheduledContact` and `RealizedContact`; out of scope here. |
| Link | Transient runtime realization during a contact, ingest run, simulator run, or test session. | Runtime/contact/path records and observations; not a setup object. |

Terms to avoid in primary setup UI:

- **Spacecraft Type**: use Spacecraft Profile.
- **Provider Profile**: use Transport.
- **Transport Profile**: do not rename this to product Transport. Treat it as
  internal extension/config machinery until a domain-specific workflow gives it
  a product home.
- **Source Endpoint**: use Runtime Identity only in advanced/debug contexts.
- **Path Template**: use Routing Rule or advanced/internal wording.
- **Link Template**, **Link Assignment**, **Spacecraft Links**: avoid for
  durable setup. Reserve Link for runtime state and history.

## Conceptual Model

### Spacecraft Profile

A Spacecraft Profile captures what is stable across vehicles of the same bus or
mission configuration:

- downlink data-link protocol, such as TM, AOS, or USLP
- uplink data-link protocol, such as TC or USLP
- packet protocol, initially Space Packet
- frame parameters
- enabled first-party applications, initially Telemetry Decom
- future defaults for command interpretation and derived applications

Profiles are versioned. A spacecraft should pin the profile version it was
configured against. If a newer profile version exists, the spacecraft page can
show drift without silently changing runtime behavior.

Profile must stay narrower than a generic spacecraft template. It owns shared
interpretation assumptions, not every setting that might be copied to a new
spacecraft.

Profile should include:

- downlink data-link family
- uplink data-link family
- packet protocol
- frame defaults that are truly bus/profile-level
- enabled first-party applications
- application defaults that are safe to share across spacecraft of this profile

Profile should not include:

- SCID or spacecraft display name
- runtime telemetry identity or source endpoint
- transport selection
- routing rules
- contact preferences
- provider or antenna choices
- environment-specific values such as lab versus ops settings
- credentials
- current telemetry catalog revision
- per-spacecraft APID ownership when APIDs can differ per vehicle
- current application runtime state

Boundary rule:

> If a value changes because of where, when, or how the spacecraft communicates,
> it belongs in Routing or Transport. If it changes because of which physical
> spacecraft or loaded mission database is being configured, it belongs on
> Spacecraft or per-spacecraft application config. If it is stable across the
> bus/profile and required to interpret bytes, it belongs in Spacecraft Profile.

For the first pass, catalog binding and APID ownership remain
spacecraft-specific. A profile may enable Telemetry Decom, but the spacecraft's
Telemetry Decom config chooses the catalog revision and handled APIDs.

### Transport

A Transport is a reusable capability for moving bytes. It does not imply that a
connection is currently open.

Examples:

- KSAT X-band antenna/service pool
- lab AI&T TCP connect or listen socket
- S3 back-orbit telemetry archive
- simulator stream
- future SLE return or forward service

Transport setup answers:

> What external capability can Cadence use to send or receive bytes?

It should support provider-backed, file-backed, and simulator-backed transports
without forcing all of them to feel like live network connections.

Credential handling is intentionally deferred until Cadence ships a credentialed
transport implementation. The first pass should not design a generic secrets UI
ahead of concrete S3, GSaaS, SLE, or cloud-provider adapters. When a transport
type requires credentials, that transport-specific form should define the
minimum credential capture, rotation, audit, and storage contract needed for
that adapter.

Transport should be a first-class durable setup object, distinct from the
current `TransportProfile` backend module. In the existing codebase,
`ProviderProfile` is closer to durable external I/O adapter configuration, while
`TransportProfile` configures runtime-local extensions under a path. Product
Transports should initially wrap or materialize `ProviderProfile` records for
compatibility, not absorb every `TransportProfile` use case.

An initial domain shape:

```elixir
%Cadence.Comms.Transport{
  transport_id: "transport_...",
  organization_id: "org_...",
  mission_id: "mission_...",
  version: 1,
  lifecycle_state: :active,
  display_name: "Lab TCP",
  transport_kind: :tcp_socket,
  direction_capability: :bidirectional,
  adapter_key: :tcp_socket,
  configuration: %{},
  materialized_provider_profile_id: nil,
  metadata: %{}
}
```

Layering language for engineers:

- Product **Transport**: durable byte-moving capability exposed in setup UI.
- **Provider adapter/profile/binding**: concrete external I/O implementation
  used by runtime compatibility layers.
- Current **TransportProfile/TransportRuntime**: runtime-local extension
  configuration and process state. These are not the product Transport.

Do not introduce **Transport Behavior** as a primary product noun. Cadence is an
aerospace domain tool, not a generic networking tool. Runtime extension concepts
such as heartbeat monitoring, uplink gateway, COP-1, retries, or provider health
should be placed inside domain-specific workflows when they matter:

- telemetry downlink configuration
- command uplink configuration
- command link reliability / COP-1
- link or provider health monitoring
- backfill ingest configuration

For example, COP-1 belongs with command uplink execution, not under a generic
"transport behavior" page.

Transport configuration is schemaless at the database boundary but typed at the
domain boundary through per-kind modules. Do not add one database column for
every possible future transport field, and do not scatter ad hoc map validation
through LiveViews.

Common persisted transport fields stay stable:

```elixir
%Cadence.Comms.Transport{
  transport_id: "transport_...",
  mission_id: "mission_...",
  version: 1,
  lifecycle_state: :active,
  display_name: "Lab TCP",
  transport_kind: :tcp_socket,
  direction_capability: :bidirectional,
  adapter_key: :tcp_socket,
  configuration: %{},
  metadata: %{}
}
```

Each `transport_kind` owns its config parser, validator, UI summary, and runtime
materialization:

```elixir
Cadence.Comms.TransportKinds.TCPSocket
Cadence.Comms.TransportKinds.S3Archive
Cadence.Comms.TransportKinds.KSAT
Cadence.Comms.TransportKinds.SimulatorStream
```

The behavior contract can start small:

```elixir
@callback normalize_config(map()) :: {:ok, map()} | {:error, term()}
@callback validate_config(map()) :: :ok | {:error, term()}
@callback display_summary(map()) :: map()
@callback materialize_provider_profile(Transport.t()) ::
            {:ok, Cadence.Contacts.ProviderProfile.t()} | {:error, term()}
```

The first implemented kind should be TCP socket. Future S3, GSaaS, SLE, and
simulator transports add modules without changing the transport table shape.

### Routing Rule

A Routing Rule is durable handling policy. It answers:

> When bytes for this spacecraft move through this transport for this purpose,
> what should Cadence do with them?

A routing rule can include:

- spacecraft
- purpose label, such as live telemetry, command uplink, AI&T telemetry,
  back-orbit ingest, or simulation
- direction: inbound, outbound, or bidirectional
- transport selection: one transport, a tagged transport set, or a future
  provider selection policy
- interpretation source: the spacecraft's profile and per-spacecraft app config
- operational defaults, such as priority, enabled state, environment, or fallback

Routing Rules are not Contacts. They do not schedule or execute anything. They
describe durable intent that a future Contact, ingest run, or operator action can
realize as runtime Links.

The first pass does not need a formal purpose taxonomy. Purpose can begin as a
small user-facing label or constrained form field used for sorting, filtering,
and readiness copy. Do not over-design a global ontology until runtime behavior
actually depends on purpose-specific semantics.

Routing Rule should be a real durable setup object, not only UI copy over
`PathTemplate` and `LinkAssignment`. The current path-template/link-assignment
pair is close to routing for simple downlink cases, but it is too path/runtime
shaped to be the product source of truth: it requires source endpoints, selected
path semantics, provider profile references, and path template versions. Routing
Rules should own the user-facing intent and may materialize lower-level records
for compatibility with the existing contact/runtime path resolution.

An initial domain shape:

```elixir
%Cadence.Comms.RoutingRule{
  routing_rule_id: "routing_rule_...",
  organization_id: "org_...",
  mission_id: "mission_...",
  spacecraft_id: "spacecraft_...",
  lifecycle_state: :active,
  display_name: "Alpha live telemetry via Lab TCP",
  purpose_label: "Live telemetry",
  direction: :inbound,
  transport_ref: %{"transport_id" => "transport_...", "version" => 1},
  provider_path_ref: nil,
  role: :primary,
  enabled?: true,
  materialized_link_assignment_id: nil,
  metadata: %{}
}
```

Field notes:

- `spacecraft_id` belongs directly on the rule.
- `purpose_label` stays lightweight for the first pass.
- `direction` is product-facing: `:inbound`, `:outbound`, or `:bidirectional`.
  The compatibility layer can map these to current `:downlink` and `:uplink`
  path directions.
- Runtime telemetry identity is resolved internally from the spacecraft. The UI
  must not ask users to choose `SourceEndpoint` rows or SCID-based routing keys.
- `role` should be product-facing, such as `:primary`, `:candidate`, or
  `:contributing`, and only map to current `selection_role` internally.
- `transport_ref` points to the product-level Transport. It should not expose
  `provider_profile_id` as the primary UI contract.
- `materialized_link_assignment_id` is optional compatibility metadata, not the
  conceptual identity of the routing rule.

### Contact And Link

Contacts are intentionally out of scope for this implementation pass. The spec
only needs to preserve their boundary:

- Contact is the temporal envelope.
- Contacts materialize selected Routing Rules into runtime Paths.
- Link is runtime realization and observation under an execution context.
- Setup UI should not ask users to create Links.

Future Contact pages can show active and historical Links. Those pages should
derive Links from realized runtime state and routing decisions, not from a
persistent "link" CRUD table.

Contact compatibility constraints:

- Routing Rules are durable, time-independent route intent. They must not store
  `starts_at`, `ends_at`, provider contact IDs, pass IDs, or schedule fields.
- Future scheduled or realized Contacts should snapshot selected Routing Rule
  references and/or resolved runtime path configuration so later routing edits do
  not mutate contact execution truth.
- Routing Rule `role` must map cleanly to runtime path selection semantics:
  `:primary` -> selected, `:candidate` -> candidate, and `:contributing` ->
  contributing.
- Routing Rule `direction` must map cleanly to runtime path directions:
  `:inbound` -> downlink, `:outbound` -> uplink, and `:bidirectional` -> a
  paired or multi-path materialization.
- Contact owns final execution selection. Routing Rules provide default intent;
  future contact planning/runtime may select, override, or fail over among
  eligible rules.

## Information Architecture

Mission-management sidebar should expose:

- Overview
- Spacecraft
- Catalog
- Comms
  - Overview
  - Transports
  - Routing
  - Validation

Do not add Spacecraft Profiles as a top-level mission-sidebar item in this
implementation pass. Profiles are reusable spacecraft setup configuration, not a
separate mission operating lane. They should be discoverable from the Spacecraft
management area.

Contacts and spacecraft operations are intentionally not added by this spec.

Spacecraft management should expose:

- Vehicles: `/missions/:mission_id/spacecraft`
- Profiles: `/missions/:mission_id/spacecraft/profiles`

The default Spacecraft page should become a setup hub rather than only a table.
It should keep the vehicle table as the primary default view, but add lightweight
management structure:

- page title: Spacecraft
- compact setup summary for vehicles, profiles, missing profile assignments, and
  profile drift or stale profile references
- management cards or panels for Vehicles and Profiles

This is still a mission-management page, not an operations dashboard. Summary
cards should report durable setup inventory and configuration gaps. They should
not show live contact state, active links, alarms, command queues, or operational
timelines.

Use management cards or panels rather than tabs for the first pass. Both
Vehicles and Profiles should remain visible on the Spacecraft management hub so
operators can see that profiles are part of spacecraft setup without switching
modes.

Scope actions to the card they affect instead of collecting unrelated actions in
the page header:

- Vehicles card owns `New spacecraft`.
- Profiles card owns `New profile`.

Each card should include:

- heading
- compact count and setup-status summary
- scoped primary action
- dense preview table or row list
- scoped empty state
- link to the full inventory when the preview is truncated

Vehicles card content should prioritize the existing spacecraft inventory and
setup state. Suggested columns:

- spacecraft display name
- SCID
- selected profile and pinned version
- application setup state
- setup status
- row actions

Profiles card content should summarize reusable interpretation contracts and
usage. Suggested columns:

- profile display name
- latest version
- downlink and uplink data-link families
- packet protocol
- enabled applications
- spacecraft using the profile
- lifecycle or drift state
- row actions

Cards should behave as inventory panels, not decorative dashboard cards. Keep
their styling restrained: quiet borders, compact spacing, low-radius corners,
and table/list content that scales beyond small fleets.

Spacecraft detail should expose:

- Identity
- Profile
- Applications
- Comms Routing
- Readiness

Runtime/debug surfaces may still expose source endpoints, path templates,
provider profile IDs, and transport profile IDs in advanced sections.

## Primary Workflows

### 0. Manage Spacecraft Setup

Entry point:

- `/missions/:mission_id/spacecraft`

The page should answer:

> Which spacecraft exist, which profiles exist, and which setup gaps need
> attention?

The default view remains the spacecraft vehicle list, but the page should grow
into the Spacecraft management hub described in Information Architecture.
Operators should see Vehicles and Profiles as sibling management cards in this
area, with each card owning its own create action and full-inventory link.

The page should stay work-focused:

- use management cards, dense tables or row lists, and compact summaries
- show durable setup counts and gaps
- scope actions to the relevant card
- avoid dashboard, live-state, and operations-console patterns
- do not show contacts, active links, command queues, alarms, or live telemetry
  operations

### 1. Create A Spacecraft Profile

Entry point:

- `/missions/:mission_id/spacecraft/profiles/new`

Form sections:

1. Identity: display name.
2. Data-link protocols: downlink protocol and uplink protocol.
3. Frame parameters: fields adapt to the selected downlink protocol.
4. Applications: enabled first-party applications.

Persistence:

- Rename or wrap the current `SpacecraftType` work as `SpacecraftProfile`.
- Persist versioned profile rows.
- Keep profile application config shallow in this pass. Per-spacecraft
  application configuration remains on the spacecraft/application config pages.

### 2. Create A Spacecraft

Entry point:

- `/missions/:mission_id/spacecraft/new`

Form sections:

1. Identity: display name and SCID.
2. Profile: optional Spacecraft Profile selection.

Creation must not ask for transport, routing, provider, source endpoint, path, or
contact details.

Post-create next actions:

- Configure telemetry
- Configure comms routing
- Review readiness

### 3. Create Or Manage A Transport

Entry point:

- `/missions/:mission_id/comms/transports`
- `/missions/:mission_id/comms/transports/new`

Transport type choices should be capability-oriented:

- Ground network/provider
- TCP socket
- Object storage archive
- Simulator stream

The current TCP provider form can become the first Transport form. It should
avoid copy that implies every transport is a present-tense connection.

Persistence should introduce a thin `transports` table. A compatibility layer
can materialize existing `ProviderProfile` records as needed so runtime provider
bindings continue working while the UI and Routing Rules reference product
Transports.

### 4. Create Or Manage Routing

Entry points:

- `/missions/:mission_id/comms/routing`
- `/missions/:mission_id/spacecraft/:spacecraft_id/routing`

The mission view should answer:

> Which spacecraft have routing rules, and which purposes/directions are covered?

The spacecraft view should answer:

> How does this spacecraft use available transports?

Routing creation should ask:

1. Spacecraft
2. Purpose label
3. Direction
4. Transport or transport selection policy
5. Optional operational defaults

Examples:

- Alpha live telemetry inbound via KSAT X-band.
- Alpha AI&T telemetry inbound via Lab TCP.
- Alpha back-orbit ingest inbound via S3 archive.
- Beta command outbound via KSAT command-capable transport.

Outbound command routing is structurally allowed in the Routing Rule model, but
command-specific execution settings are deferred. A first-pass outbound rule can
declare route intent and transport selection; it must not imply that command
uplink execution, COP-1, CLCW handling, or command link reliability UX is
complete.

Persistence should introduce a thin `routing_rules` table. A compatibility layer
can materialize existing `PathTemplate` and `LinkAssignment` records as needed
so scheduled contacts and runtime path resolution continue working while the UI
and readiness logic move to Routing Rules.

### 5. Review Spacecraft Setup

The first pass should only report spacecraft setup completeness. Broader comms
readiness is not a blocker for this implementation and should not be solved
before Contacts/runtime execution are in scope.

Spacecraft setup should report:

- Identity: SCID and internal telemetry identity sync state.
- Profile: profile bound, pinned version, drift.
- Applications: telemetry/command app config state.

Suggested labels:

- Setup complete
- Needs SCID
- Needs profile
- Profile drift
- Telemetry not configured

Do not use generic "Comms Ready" or "Ready for communication" language in this
pass. Cadence can check durable configuration without Contacts, but it cannot
truthfully assert operational communication readiness until a contact, ingest
run, simulator run, or other execution context exists.

## Validation

Comms validation should not hide findings merely because the old nouns are no
longer in primary navigation.

Validation groups should become:

- Spacecraft Setup findings
- Transport Setup findings
- Routing Setup findings
- Internal runtime artifact findings

Old `PathTemplate` and `LinkAssignment` findings may remain internally, but the
rendered finding should translate them into routing language and navigate to a
real Routing page.

First-pass validation scope:

Spacecraft Setup:

- missing SCID when CCSDS telemetry identity resolution requires it
- missing profile
- profile version missing or archived
- profile drift
- required spacecraft application config missing

Transport Setup:

- transport config invalid for its kind
- transport archived
- materialized provider profile missing or stale, when materialization is used

Routing Setup:

- routing rule references missing or archived transport version
- routing rule references missing spacecraft
- routing rule cannot materialize runtime compatibility records
- duplicate or ambiguous primary inbound route for one spacecraft/purpose
- enabled rule with unsupported direction/kind combination

Validation must not:

- hide findings because replacement UI is incomplete
- claim comms/contact/runtime readiness
- validate live provider, Contact, or Link state in this slice

## Route And Auth Guidance

Spacecraft Profile routes belong in the authenticated mission-scoped spacecraft
LiveSession because profiles are mission-owned spacecraft configuration. They
should be presented as a management card or panel inside the Spacecraft
management area, not as a top-level mission-sidebar item:

```elixir
live_session :spacecraft,
  on_mount: [
    {CadenceWeb.OrganizationAuth, :require_organization_scope},
    {CadenceWeb.MissionAuth, :load_mission},
    {CadenceWeb.UserAuth, :attach_user_menu}
  ],
  layout: {CadenceWeb.Layouts, :mission_sidebar} do
  live "/missions/:mission_id/spacecraft/profiles", SpacecraftProfileListLive, :index
  live "/missions/:mission_id/spacecraft/profiles/new", SpacecraftProfileNewLive, :new
  live "/missions/:mission_id/spacecraft/profiles/:profile_id", SpacecraftProfileShowLive, :show
end
```

Transport and Routing routes belong in the authenticated mission-scoped comms
LiveSession because they are mission-owned comms setup:

```elixir
live_session :comms,
  on_mount: [
    {CadenceWeb.OrganizationAuth, :require_organization_scope},
    {CadenceWeb.MissionAuth, :load_mission},
    {CadenceWeb.UserAuth, :attach_user_menu}
  ],
  layout: {CadenceWeb.Layouts, :mission_sidebar} do
  live "/missions/:mission_id/comms", CommsOverviewLive, :index
  live "/missions/:mission_id/comms/transports", CommsTransportListLive, :index
  live "/missions/:mission_id/comms/routing", CommsRoutingListLive, :index
  live "/missions/:mission_id/comms/validation", CommsValidationLive, :index
end
```

This route placement is intentional:

- Authenticated organization and mission scope are required because these are
  mission-owned setup resources.
- `current_scope` is available through the existing auth hooks.
- `current_mission` is loaded before LiveView mount.
- Spacecraft Profile navigation stays inside Spacecraft because profiles support
  spacecraft setup and can be managed before or across multiple spacecraft.
- Spacecraft-specific routing pages that require `current_spacecraft` belong in
  the spacecraft show LiveSession with `SpacecraftAuth`.

## Early-Development Migration Policy

Cadence is still early enough that this spec does not require backward
compatibility with existing database rows, old comms UI routes, or old product
terminology. It is acceptable to drop/reset the database during implementation.

Prefer clean schema and route design over carrying compatibility weight:

- new primary route: `/missions/:mission_id/spacecraft/profiles`
- new primary route: `/missions/:mission_id/comms/transports`
- new primary route: `/missions/:mission_id/comms/routing`
- new first-class table/domain: Spacecraft Profile
- new first-class table/domain: Transport
- new first-class table/domain: Routing Rule

Do not preserve old provider/path/link UI routes merely for backward
compatibility. Redirects are optional developer convenience, not a product
requirement.

The only remaining compatibility concern is runtime integration. If existing
runtime or scheduled-contact code still requires `PathTemplate` and
`LinkAssignment`, Routing Rules may materialize those records internally as a
temporary bridge. That bridge is for runtime compatibility, not data migration
or user-facing compatibility.

Tests should be rewritten around the new product model rather than preserving
old terminology.

API and facade naming should follow the new product model when the domain
objects land:

- `SpacecraftProfile`
- `Transport`
- `RoutingRule`

New control-plane APIs may be added for these objects. Existing provider,
path-template, transport-profile, and link-assignment APIs are not product
compatibility requirements in this early-development phase. Keep or remove them
based on runtime/dev-tool needs, not backward compatibility.

## Versioning, Archival, And Events

Different setup objects have different change risks.

### Spacecraft Profile

Spacecraft Profiles are versioned immutable records. A spacecraft pins
`profile_id` plus `profile_version` so protocol/frame/application-default
changes never silently reinterpret bytes.

Rules:

- creating a profile creates version 1
- changing interpretation fields creates a new version
- existing versions remain fetchable
- archived profiles cannot be selected for new spacecraft
- spacecraft referencing an older active profile version show drift when a newer
  active version exists
- spacecraft referencing an archived or missing profile version show a stale
  reference finding

### Transport

Transports are versioned immutable records. Routing Rules pin `transport_id`
plus `transport_version` so external I/O configuration changes are explicit.

Rules:

- creating a transport creates version 1
- changing adapter/configuration fields creates a new version
- existing versions remain fetchable
- archived transports cannot be selected for new routing rules
- routing rules referencing an older active transport version show drift when a
  newer active version exists
- routing rules referencing an archived or missing transport version show a
  stale reference finding

### Routing Rule

Routing Rules use current-state projection plus append-only events.

This preserves the user experience of editing one durable rule while retaining
an operational history of intent changes.

State table:

```text
comms_routing_rules
- routing_rule_id
- organization_id
- mission_id
- spacecraft_id
- lifecycle_state
- display_name
- purpose_label
- direction
- transport_id
- transport_version
- provider_path_ref
- role
- enabled
- materialized_link_assignment_id
- metadata
- inserted_at
- updated_at
```

Event table:

```text
comms_routing_rule_events
- routing_rule_event_id
- organization_id
- mission_id
- routing_rule_id
- event_type
- actor_id
- occurred_at
- payload
```

Rules:

- writes go through context functions that append an event and update the state
  table in one transaction
- reads use the state table, not event replay
- events record meaningful operator/system changes such as created, updated,
  enabled, disabled, archived, materialized, and stale reference detected
- archived routing rules are excluded from active routing coverage
- current state is the product source of truth; materialized path/link records
  are internal runtime artifacts

## Implementation Plan

### Phase 0: Stabilize The Current Worktree

- Do not merge a change that deletes comms setup pages without a Routing
  replacement.
- Because early-development DB reset is allowed, prefer replacing old routes
  with clean Profile, Transport, and Routing routes over preserving old
  provider/path/link routes.
- Stop filtering out comms findings unless they have a replacement route.
- Keep tests that prove users can configure durable comms setup.

### Phase 1: Rename Type To Profile

- Rename user-facing copy from Spacecraft Type to Spacecraft Profile.
- Prefer route paths under `/spacecraft/profiles`.
- Either rename backend modules or add a clear alias layer if a full rename is
  too noisy for the first pass.
- Add database constraints or validation so a spacecraft cannot reference a
  non-existent profile version.

### Phase 2: Transport Surface

- Add a thin persisted Transport domain object and store.
- Rename provider pages to Transports in primary UI.
- Materialize or reference `ProviderProfile` records from Transports as a
  compatibility/runtime integration layer.
- Keep provider/profile identifiers in advanced details.
- Make TCP the first concrete transport form.
- Add placeholders or disabled choices for provider-backed, S3, and simulator
  transports if implementation is not ready.
- Defer generic credential management until a concrete credentialed transport is
  implemented.
- Do not create a generic Transport Behavior UI. Place extension settings in
  domain-specific workflows such as command uplink configuration when they are
  needed.

### Phase 3: Routing Surface

- Define the first routing-rule shape.
- Keep purpose lightweight in the first pass; avoid a broad purpose taxonomy
  until routing/runtime semantics require it.
- Add a thin persisted Routing Rule domain object and store.
- Materialize existing `PathTemplate` + `LinkAssignment` records from Routing
  Rules only as a compatibility/runtime integration layer.
- Replace "Spacecraft Links" and "Apply Link Template" with Routing workflows.
- Update validation to route users to Routing pages.
- Keep first-pass readiness scoped to Spacecraft Setup. Defer broader comms,
  contact, and runtime readiness.

### Phase 4: Runtime Link Cleanup

- Reserve Link terminology for runtime/contact views and history.
- Rename old persistent "link" UI copy to routing language.
- Remove old persistent Link UI once Routing exists. Keep only internal runtime
  materialization needed by existing runtime code.

## Acceptance Criteria

- Creating a spacecraft only requires identity and optional profile selection.
- The mission-management sidebar exposes Spacecraft, not a separate top-level
  Spacecraft Profiles item.
- `/missions/:mission_id/spacecraft` is a Spacecraft management hub with
  visible Vehicles and Profiles management cards, compact setup summaries,
  scoped card actions, and full-inventory links when previews are truncated.
- The Spacecraft page header does not collect unrelated create actions; the
  Vehicles card owns `New spacecraft` and the Profiles card owns `New profile`.
- Spacecraft Profile pages do not mention contacts or transports.
- Transport pages describe durable byte-moving capabilities without implying an
  active connection.
- Routing pages describe durable spacecraft use of transports without using Link
  as the setup noun.
- Spacecraft setup checks and copy agree on what is actually being checked.
- Setup pages remain mission-management surfaces: dense, scannable,
  table-oriented, and free of ops-console patterns such as live contact state,
  active links, command queues, alarms, or operational timelines.
- Comms validation findings are visible and actionable.
- Old persistent Link/PathTemplate/ProviderProfile UI is not required for
  backward compatibility after the clean model exists.
- Tests assert user-facing vocabulary: Spacecraft Profile, Transport, Routing
  Rule, Contact, and runtime Link boundaries.

## Test Plan

Domain tests:

- create, fetch, list, and version Spacecraft Profiles
- detect profile drift for spacecraft pinned to an older profile version
- reject spacecraft references to missing or archived profile versions
- create, fetch, list, and version Transports
- normalize and validate TCP transport config through
  `Cadence.Comms.TransportKinds.TCPSocket`
- materialize provider profile compatibility records from a Transport when
  runtime integration needs them
- create Routing Rule current state and append `created` event in one
  transaction
- update, enable, disable, and archive Routing Rules while recording events
- reject Routing Rules with missing or archived transport refs
- materialize runtime compatibility records from Routing Rules when needed

LiveView tests:

- Spacecraft management page exposes visible Vehicles and Profiles management
  cards without a top-level Spacecraft Profiles sidebar item
- Spacecraft management page scopes `New spacecraft` to the Vehicles card and
  `New profile` to the Profiles card
- Spacecraft Profile pages use "Spacecraft Profile", not "Spacecraft Type"
- spacecraft create/edit can select a profile and do not ask for transport,
  routing, contact, provider, path, or link fields
- Transport pages use "Transport" and create the first TCP transport
- Routing pages use "Routing Rule" or "Routing", not "Link Assignment" or
  "Link Template"
- Spacecraft Setup pages show identity, profile, and app setup only
- Spacecraft setup and comms setup pages do not use operations-console
  vocabulary for deferred surfaces such as command queues, alarms, operational
  timelines, active contacts, or active links
- validation pages show Spacecraft Setup, Transport Setup, and Routing Setup
  findings with actionable links

Route and navigation tests:

- `/missions/:mission_id/spacecraft` exposes Vehicles and Profiles management
  cards
- `/missions/:mission_id/spacecraft/profiles`
- `/missions/:mission_id/comms/transports`
- `/missions/:mission_id/comms/routing`
- primary navigation exposes Spacecraft, Catalog, and Comms as
  mission-management areas, but does not expose Spacecraft Profiles as a
  separate top-level item
- primary navigation no longer exposes old persistent link/path/provider-profile
  pages after the replacement surfaces exist

## Implementation Order

1. Stabilize the current worktree.
   Stop the unsafe middle state first: do not hide validation findings and do
   not delete comms setup without replacement surfaces.

2. Implement Spacecraft Profile.
   Rename Type to Profile in domain/UI/routes, keep versioned immutable
   behavior, validate spacecraft pinned profile references, and make
   `/missions/:mission_id/spacecraft` a Spacecraft management hub with visible
   Vehicles and Profiles management cards.

3. Implement Transport.
   Add first-class Transport domain/table/store, add the TCP transport kind
   module, add basic Transport list/new/show UI, and materialize
   `ProviderProfile` records only where runtime integration needs them.

4. Implement Routing Rule.
   Add state table plus append-only event table, transaction-backed writes,
   basic Routing list/new/show UI, routing validation, and runtime compatibility
   materialization where needed.

5. Update Spacecraft Setup.
   Update spacecraft create/edit/show/setup surfaces to use Profile and
   setup-only language. Remove misleading readiness language and keep setup
   summaries scoped to durable mission-management state.

6. Replace validation and tests.
   Replace deleted comms tests with new product-model tests and add validation
   coverage for Profile, Transport, and Routing.

7. Remove old primary setup UI.
   Once Transport and Routing exist, remove old provider/path/link setup pages
   and routes. Keep backend internals only where runtime still needs them.

## Open Questions

- Which routing purposes are required for the first release: live telemetry,
  command uplink, AI&T telemetry, back-orbit ingest, simulation?
- How should mission-level routing requirements be declared for readiness
  checks?
- What is the first credentialed transport, and what credential contract does it
  require?
- Which command-uplink settings deserve first-class product placement before
  generic runtime extension configuration is exposed?

## Explicit Deferrals

- Contact planning and scheduling UX.
- Active Contact execution UI.
- Runtime Link history UI.
- Broader comms/contact/runtime readiness beyond Spacecraft Setup.
- Provider health monitoring.
- Generic credential and secrets-management UI.
- Full command routing and COP-1 setup UX.
