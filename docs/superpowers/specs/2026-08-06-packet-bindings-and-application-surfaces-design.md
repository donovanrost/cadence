# Design: Packet Bindings and Application Surfaces

- Status: Packet-binding and host-surface foundation implemented; Event Reports deferred
- Created: 2026-08-06
- Updated: 2026-08-10
- Scope: shared packet-model inputs, application bindings, mission runtime composition,
  and host-owned Packet Bindings and Ops Dock surfaces
- Concretizes:
  [Packet Model and Application Binding](2026-04-20-packet-model-and-application-binding-design.md)
- Related ADRs:
  [ADR-001](../../decisions/001-mission-scoped-runtime-and-selector-model.md),
  [ADR-007](../../decisions/007-first-party-capability-abi.md),
  [ADR-008](../../decisions/008-multi-format-catalog-import-architecture.md),
  [ADR-009](../../decisions/009-canonical-telemetry-catalog-model.md), and
  [ADR-016](../../decisions/016-typed-extension-packages-and-product-applications.md)

## Summary

Cadence will treat an APID as packet-routing material, not as an exclusively
owned application resource.

Applications bind to packet-model inputs:

- a whole packet;
- telemetry-compatible scalar fields;
- named fields used as application context; or
- opaque binary regions such as image or science payload bytes.

Bindings are shared by default. Two applications may consume the same packet or
field when they produce different operational products. Exclusivity belongs to
authoritative output identities or genuinely scarce resources, not to passive
access to packet bytes.

The application host now has one reusable `PacketBindings` surface element.
Telemetry Decom contributes the first application-workspace surface using that
element. The Ops shell can resolve `:ops_dock` contributions, but no application
contributes a dock tab yet, so the dock remains absent from the rendered DOM.

The mission binding basis is now application-neutral and accepts typed
contributions. The runtime declaration includes an isolated failure policy, but
independent consumer commit/checkpoint behavior remains deferred until a second
runtime consumer exists.

## Decisions

1. APID is a selector attribute, not an ownership boundary.
2. Packet input bindings are many-to-many and non-exclusive by default.
3. A governed packet model is the preferred application input when a catalog
   definition exists.
4. Whole-packet selector bindings remain available for bounded applications
   such as ASCII Event Reports when no richer packet model exists.
5. Binary payload regions are not telemetry samples and do not enter the
   telemetry current-value or time-series stores.
6. Telemetry Decom consumes supported scalar fields from a mixed packet without
   rejecting that packet because a binary sibling field exists.
7. Large binary fields are exposed as evidence-backed regions or views rather
   than copied into every consumer envelope.
8. Input-consumer failures are isolated and recorded per binding.
9. Cadence owns the Packet Bindings renderer, route, authorization, action
   mediation, loading states, and validation presentation.
10. Applications contribute typed input contracts, data providers, runtime
    capabilities, and output contracts. They do not contribute arbitrary DOM,
    HEEx, CSS, JavaScript, routes, or LiveView events.
11. The first implementation will not create a universal output-claim registry.
    Known product domains will validate authoritative output collisions at their
    owning compilation or persistence boundary until another concrete consumer
    justifies a shared registry.

## Motivating Cases

### ASCII Event Reports

In a future slice, flight software may send a complete ASCII event report in a
space-packet payload.
The Event Reports application consumes the whole packet, validates and trims the
text according to its configuration, and persists an append-only Event Report
record with packet and evidence provenance.

Telemetry Decom need not claim or decode the packet merely because it arrived on
a telemetry link.

### Mixed Camera Packet (contract fixture only)

A camera packet contains both scalar instrument telemetry and image bytes:

```text
APID 450 · CAMERA_FRAME
  PAYLOAD.camera_temp       float32
  PAYLOAD.exposure_ms       uint32
  PAYLOAD.frame_id          uint32
  PAYLOAD.chunk_index       uint16
  PAYLOAD.camera_bytes      binary
```

The hypothetical intended bindings are:

```text
Telemetry Decom
  reads    camera_temp, exposure_ms, frame_id, chunk_index
  emits    canonical telemetry samples

Camera
  reads    camera_bytes, frame_id, chunk_index, exposure_ms
  emits    image chunks and completed image artifacts
```

Both applications may read `frame_id` and `exposure_ms`. Reading the same field
does not create a conflict. The products have different authoritative identities
and storage lifecycles.

No Camera application or camera runtime is implemented by this work. A future
Camera capability would be stateful when images span multiple packets and own
chunk assembly, duplicate detection, completion, and image-product persistence.
It would not own scalar telemetry persistence.

## Implemented Preparation

The foundation now provides:

- a versioned `PacketInputDefinition` on capability descriptors;
- normalized packet-binding configuration, binding, and resource rows with no
  cross-application APID or resource uniqueness constraint;
- scoped list, preview, replace, disable, desired/applied, and optimistic
  configuration-version behavior;
- a pinned canonical telemetry revision, snapshot, packet identity, and content
  hash as the first immutable packet-model reference;
- mixed packet compilation that preserves binary regions while Telemetry Decom
  extracts supported scalar siblings;
- a bounded, streamed, host-owned `PacketBindings` surface and typed save action;
- Telemetry Decom's packet selection moved to that shared surface, with its old
  APID mutation controls removed;
- shared APID resource declarations and non-blocking overlap semantics;
- an application-neutral mission basis and typed contribution composer; and
- `:ops_dock` placement discovery and an empty-invisible host dock seam.

The intentionally deferred pieces are:

- the Event Reports application, ASCII decoding, report persistence, and dock tab;
- selector-only whole-packet binding;
- explicit field and binary-region selection;
- a Camera application or any image assembly runtime;
- independent per-consumer runtime commit/checkpoint and replay; and
- a universal authoritative output-claim registry.

## Terminology

### Packet selector

Low-level match material used to route a canonical packet record. It includes
the mission/spacecraft scope and the supported subset of protocol family,
packet kind, source endpoint, APID, and future governed match criteria.

APID remains visible and operationally useful, but it is not the durable
semantic identity of a catalog-defined packet.

### Packet model

A governed, mission-scoped representation of packet identity and layout. It can
represent scalar fields, fixed regions, nested structure as it matures, and
opaque binary regions even when built-in Telemetry Decom cannot consume them.

### Packet-model resource

A bindable resource identified by a pinned packet-model reference:

- whole packet;
- named field;
- named binary region; or
- a bounded group selected by an application input contract.

### Application input contract

A versioned declaration of the packet-model resources one capability can
consume. It constrains configuration and presentation; it does not contain a
query callback, renderer module, or effect function.

### Packet binding

A versioned, scoped configuration connecting one installed application
capability to packet-model resources or, for whole-packet fallback, a governed
packet selector.

### Product contribution

A declared record or artifact family emitted by a capability. A contribution
states whether it is authoritative or observational. Known product domains own
the uniqueness and persistence semantics of their authoritative identities.

## Packet Model Contract

The canonical catalog remains the source of semantic packet identity. The first
runtime packet-model reference may be represented conceptually as:

```elixir
%PacketModelReference{
  mission_model_revision_id: binary(),
  telemetry_runtime_plan_id: binary(),
  packet_id: binary(),
  content_sha256: binary()
}
```

The content hash prevents a binding from silently changing meaning when a
catalog revision is superseded.

A resolved resource has this conceptual shape:

```elixir
%PacketResource{
  resource_id: binary(),
  packet_model_ref: PacketModelReference.t(),
  resource_kind: :whole_packet | :field | :binary_region,
  path: binary() | nil,
  data_type: atom() | nil,
  offset_bits: non_neg_integer() | nil,
  size_bits: pos_integer() | nil,
  selector: PacketSelector.t(),
  provenance: map()
}
```

`resource_id` is stable within the pinned packet model. A point or packet entry
identifier is preferred over a display name. `path` such as
`PAYLOAD.camera_bytes` is presentation and diagnostics context, not the sole
database identity.

### Selector-only packet resource

An application may bind to a whole packet without a catalog packet definition
when all of these are true:

- its registered input contract allows `:whole_packet`;
- scope and source endpoint are explicit;
- protocol family, packet kind, and APID are validated;
- the configuration is versioned and included in activation preflight; and
- the application retains raw evidence provenance.

This deferred fallback supports complete ASCII Event Reports without pretending
an APID is a semantic packet name. The future UI should label it as an
"APID-only packet" and offer a later handoff to a catalog-backed model.

## Application Input Contract

Capability definitions will declare accepted packet inputs. The exact compiled
module names may change, but the typed contract needs the following semantics:

```elixir
%PacketInputDefinition{
  input_id: "event-report-packets",
  version: 1,
  capability_family_key: :event_reports,
  accepted_resource_kinds: [:whole_packet],
  accepted_data_types: [],
  selection_mode: :whole_packet,
  min_selected: 1,
  max_selected: 32,
  delivery: :packet_record,
  failure_policy: :isolated
}
```

```elixir
%PacketInputDefinition{
  input_id: "telemetry-fields",
  version: 1,
  capability_family_key: :definition_bound_telemetry,
  accepted_resource_kinds: [:field],
  accepted_data_types: [:uint, :int, :float, :bool],
  selection_mode: :compatible_fields,
  min_selected: 1,
  max_selected: 4_096,
  delivery: :decoded_fields,
  failure_policy: :isolated
}
```

```elixir
%PacketInputDefinition{
  input_id: "camera-frame-input",
  version: 1,
  capability_family_key: :camera_receive,
  accepted_resource_kinds: [:field, :binary_region],
  accepted_data_types: [:integer, :float, :binary],
  selection_mode: :explicit_fields,
  min_selected: 2,
  max_selected: 32,
  delivery: :field_views,
  failure_policy: :isolated
}
```

Selection modes mean:

- `:whole_packet` binds the resolved packet record once;
- `:compatible_fields` automatically binds every supported field and shows the
  resolved selection to the operator; and
- `:explicit_fields` lets the operator select named resources within the
  capability's declared bounds.

The capability registry owns runtime validation of the resolved binding. The
application definition references the registered capability contribution and
surface; it does not duplicate executable validation logic.

## Packet Binding Contract

The durable configured binding is conceptually:

```elixir
%PacketBinding{
  packet_binding_id: binary(),
  organization_id: binary(),
  mission_id: binary(),
  spacecraft_id: binary(),
  application_installation_id: binary(),
  application_key: binary(),
  application_version: pos_integer(),
  input_id: binary(),
  input_version: pos_integer(),
  capability_instance_id: binary(),
  source_endpoint_ref: binary() | nil,
  packet_model_ref: PacketModelReference.t() | nil,
  selector: PacketSelector.t(),
  resources: [PacketBindingResource.t()],
  configuration_version: pos_integer(),
  enabled: boolean(),
  applied_binding_set_id: binary() | nil,
  applied_binding_set_version: pos_integer() | nil,
  applied_at: DateTime.t() | nil,
  metadata: map()
}
```

Each selected resource is explicit:

```elixir
%PacketBindingResource{
  resource_id: binary(),
  resource_kind: :whole_packet | :field | :binary_region,
  role: :primary | :context
}
```

`role` is descriptive and helps the surface explain why a camera capability
reads `frame_id` alongside `camera_bytes`. It does not create exclusivity.

### Validation invariants

- The installation exists, is version-pinned, and belongs to the authenticated
  organization, mission, and spacecraft.
- The input definition belongs to a capability contributed by the installed
  application version.
- A catalog-backed binding pins an existing packet model and content hash.
- A selector-only binding is allowed only for whole-packet input contracts.
- Every resource exists in the pinned packet model.
- Resource kinds and data types satisfy the registered input definition.
- Selection cardinality is within the declared bounds.
- Resource identities are unique within one binding.
- Multiple bindings may reference the same packet or field.
- Configuration replacement uses optimistic configuration-version checking.
- Disabling an installation preserves configuration but removes its bindings
  from the next composed mission basis.
- Applied stamps describe the live mission basis; they are never inferred from
  saved configuration alone.

## Persistence Boundary

`spacecraft_application_bindings.handled_apids` should not become the canonical
packet-binding store. It combines application configuration, packet selection,
and Decom-specific catalog state in one row.

The implementation introduces normalized packet-binding persistence with:

- one header row per application installation, input definition, and resolved
  packet/selector binding;
- child rows for selected packet-model resources;
- a unique constraint for resource identity within one binding;
- no cross-application uniqueness constraint on input resources;
- pinned definition and configuration versions;
- desired and applied state; and
- organization-scoped foreign keys.

Telemetry Decom's catalog revision and preview configuration remain owned by
Telemetry Decom. Its selected packet inputs now live in the shared binding
domain. The legacy row remains during this bounded migration for Decom-owned
catalog and activation settings. A future Event Reports application should keep
ASCII parsing policy in its own configuration and packet selection in the
shared binding domain.

The public context functions follow existing authorization rules and accept
`current_scope` first:

```elixir
PacketBindings.list(current_scope, host_context, application_installation_id, opts)
PacketBindings.preview(current_scope, host_context, application_installation_id, attrs)
PacketBindings.replace(current_scope, host_context, application_installation_id, attrs)
PacketBindings.disable(current_scope, host_context, application_installation_id)
```

Application code cannot supply an arbitrary installation identity, capability
module, query, or mutation callback through these APIs.

## Decode and Delivery

### Host-owned decode

For catalog-backed packets, Cadence resolves the pinned packet model and creates
a decoded packet envelope or bounded field views once per packet:

```elixir
%DecodedPacket{
  packet_record: PacketRecord.t(),
  packet_model_ref: PacketModelReference.t(),
  field_views: %{required(binary()) => FieldView.t()},
  diagnostics: [term()]
}
```

Scalar field views may carry decoded values. Large binary views should carry
offset/length and evidence references and materialize a binary slice only at the
consumer boundary. They must not be copied into telemetry sample envelopes or
LiveView assigns.

### Failure isolation

Packet-model resolution and structural decode are shared prerequisites. If they
fail, all dependent consumers receive a common decode failure with evidence.

After decode, each binding is an independently observable consumer result:

```text
packet decode
  ├─ Decom consumer          succeeded
  └─ Camera consumer         failed: missing chunk metadata
```

The Camera failure does not remove successful telemetry samples. Cadence records
the failed binding, capability instance, packet, evidence, and reason so that
the application can retry or replay independently.

The existing sequential, fail-fast `:multi` execution is not sufficient for
this guarantee. Runtime composition must define per-binding results and commit
or checkpoint successful consumers independently.

## Mission Binding-Set Composition

There is one active binding-set basis per mission. Applications therefore
contribute to a mission composer instead of independently replacing that basis:

```text
Telemetry Decom bindings ─┐
Event Reports bindings ───┼─ Mission application composer ─ governed activation
Camera bindings ──────────┘
```

The composer:

1. loads installed and enabled application versions for the mission;
2. loads their versioned packet bindings;
3. resolves pinned packet models and registered input contracts;
4. asks registered capability compilers for capability instances and routing
   contributions;
5. validates selector, capability, product, and resource compatibility;
6. emits one deterministically ordered binding set;
7. persists a new immutable version; and
8. submits the existing governed mission-data-plane activation request.

The basis identity should be application-neutral, for example
`mission_applications:<mission_id>`, rather than
`telemetry_decom:<mission_id>`.

Application applied stamps are reconciled only after that exact composed basis
is activated. Activation metadata includes every contributing installation and
configuration version.

## Product Contributions and Conflicts

Input sharing is allowed. A conflict exists when authoritative effects collide,
not when inputs overlap.

Examples:

- Decom and Camera both read `frame_id`: valid.
- Decom emits a telemetry sample while Camera emits an image artifact: valid.
- Event Reports and a packet-rate observer read the same whole packet: valid.
- Two camera capabilities both declare the same authoritative image stream
  identity: conflict.
- Two telemetry capabilities both emit the same canonical point identity for
  the same source/binding context: conflict unless the telemetry domain defines
  an explicit reconciliation policy.
- Two capabilities request incompatible transport or command side effects from
  one packet: conflict or approval-gated policy decision.

Capability descriptors already declare emitted record and action kinds. The
mission composer and owning product domains should use those declarations for
bounded compatibility checks. A generic output-claim persistence model is
deferred until a second concrete product domain requires identical ownership
semantics.

## Packet Bindings Surface

### Surface declaration

Telemetry Decom now declares this application-workspace surface; Event Reports
can reuse the same declaration in its later slice:

```elixir
%SurfaceDefinition{
  surface_id: "packet_bindings",
  version: 1,
  purpose: :configuration,
  scope: :spacecraft,
  placement: :application_workspace,
  navigation: %{label: "Packet bindings", order: 20},
  data_contract: %{
    query_id: "cadence.packet_bindings.manage",
    version: 1
  },
  actions: ["save_packet_bindings"],
  refresh: :after_action,
  renderer: {:declarative, "cadence.host.surface.v1"}
}
```

The surface remains application-scoped: the host resolves the current
installation and registered input definitions from the authenticated host
context. It does not accept an application key or installation ID from form
parameters as authority.

### Host-owned surface element

`SurfaceDocument` gains one optional `PacketBindings` element. It is a reusable
host primitive, not an application renderer:

```elixir
%SurfaceElements.PacketBindings{
  id: "packet-bindings",
  title: "Packet bindings",
  description: "Route packet-model inputs into this application.",
  action_id: "save_packet_bindings",
  input_definition: PacketInputDefinition.t(),
  source_endpoints: [option()],
  packet_groups: [PacketBindingGroup.t()],
  configured_version: 4,
  applied_version: 3,
  activation_state: :outdated,
  empty_state: map()
}
```

This element is concrete product evidence for extending the declarative grammar.
It must remain bounded and versioned. It does not permit arbitrary columns,
events, callbacks, selectors, or nested application documents.

### Query document

The registered query provider returns:

- application and installation identity for display;
- configured and applied versions;
- source endpoint choices allowed by the host context;
- packet groups matching the input definition;
- resolved packet-model identity and selector summary;
- available resources and compatible/incompatible reasons;
- the current application's consumer label, with cross-application consumer
  aggregation deferred until a second application is registered;
- the current application's desired selection;
- activation drift and diagnostics; and
- APID-only candidates when the input definition permits whole-packet fallback.

It never returns executable modules, route fragments, raw SQL, HEEx, CSS, or
client hooks.

### Visual direction

The surface uses a dense industrial signal-routing ledger rather than a generic
settings form. Packet groups read like harness junctions: a thin cyan signal
rail anchors packet identity on the left, field resources sit in the center,
and compact consumer/product badges show where data flows on the right.

Color communicates state only:

- cyan: selected by the current application;
- neutral: consumed by another application;
- green: selected configuration matches the active basis;
- amber: saved but not active;
- red: invalid binding or authoritative product conflict; and
- violet or decorative gradients are not part of this operational vocabulary.

### Layout

```text
PACKET BINDINGS                         Configured v4 · Active v3 · OUTDATED
Route packet-model inputs into Camera                     [Apply mission changes]

Source endpoint  [Payload downlink A]     Search [camera________________]
Show             [All packets v]          2 packets · 7 selected resources

│ APID 450  CAMERA_FRAME                         catalog rev 27 · 4 consumers
│ Selector    space_packet / Payload downlink A
│
│ Resource                  Type       Current consumers         This app
│ PAYLOAD.camera_temp       float32    Telemetry Decom           context [x]
│ PAYLOAD.frame_id          uint32     Telemetry Decom, Camera   context [x]
│ PAYLOAD.chunk_index       uint16     Camera                    context [x]
┃ PAYLOAD.camera_bytes      binary     Camera                    primary [x]
│                            3.9 MiB region · evidence-backed, not telemetry

│ APID 451  CAMERA_STATUS                        catalog rev 27 · unbound
```

The heavier binary-region rail makes the memorable visual distinction: this is
payload data traveling through the same packet fabric, not a broken telemetry
field.

### Interaction

- Packet groups are collapsed by default when they are neither selected nor in
  error.
- Selected, drifted, and invalid groups expand on first render.
- The current application can select only resources allowed by its registered
  input contract.
- Existing consumers remain visible and do not disable a resource merely
  because they read it.
- A primary/context selector is shown only when the input definition supports
  explicit field roles.
- `:compatible_fields` surfaces offer a packet-level selection and show the
  resolved scalar fields read-only.
- `:whole_packet` and `:explicit_fields` interaction remain deferred.
- Changing the source endpoint or packet selection updates desired state on save.
- Save updates desired configuration only.
- Apply uses the existing typed, approval-aware mission activation action.
- Rows never offer deletion of packet evidence or product data.
- Search and paging are deferred; the current surface enforces 512 packet groups
  and 4,096 rendered resource rows, distributing the resource budget across the
  visible groups while retaining all selected packet controls.

### LiveView and accessibility

- The LiveView assigns a `to_form/2` form and renders it with `<.form>` and
  `<.input>` components.
- Key DOM IDs include `packet-bindings-surface`, `packet-bindings-form`,
  `packet-bindings-filter`, `packet-binding-group-<resource_id>`, and
  `packet-binding-resource-<resource_id>`.
- Bounded packet groups use LiveView streams with `phx-update="stream"`.
- Packet expansion uses native `details` and `summary` semantics.
- Selection controls have explicit labels containing the packet and resource
  names.
- The status summary uses a polite live region; individual packet arrivals do
  not announce here.
- Color is never the only indication of selection, drift, or conflict.

The current flat `Table` element is not stretched to represent this hierarchy.
`PacketBindings` is a purpose-built host element with bounded interaction and
validation.

## Application Surface Composition

### Telemetry Decom

Telemetry Decom retains its trusted Manage surface for catalog revision,
compiler diagnostics, preview, and activation context. It adds Packet Bindings
as a second surface.

The migration removes APID mutation from the trusted Manage surface in the same
coherent release that enables the new binding surface. Manage may summarize and
link to bindings, but there must not be two writable sources of truth.

Selecting a packet for Decom resolves every telemetry-compatible scalar field.
Binary regions remain visible as resources consumed by other applications or
available for binding; they do not block scalar compilation.

### Event Reports

The deferred Event Reports slice should contribute:

1. `packet_bindings` in `:application_workspace` for whole-packet selection and
   source endpoint configuration; and
2. `reports` in `:ops_dock` for the live ASCII report stream.

Its first input contract accepts catalog packets or APID-only whole-packet
selectors. Its application configuration defines ASCII validation, maximum
message bytes, and optional NUL-padding policy. Those settings are not embedded
in the shared packet-binding contract.

The future Ops Dock tab should remain visible for an installed application even
when no binding is active. Its empty state should explain the missing binding
and provide a host-approved navigation link to the Packet Bindings surface.

Report history should use dedicated append-only Event Report records and a
virtualized, bounded client window. It must not place an unbounded report list in
LiveView assigns. Selected reports may later be promoted explicitly into the
existing mission or operational event model when they represent a durable
operator-significant occurrence; ordinary report traffic must not become a
second high-rate event spine.

### Camera contract proof

A production Camera application is outside this foundation. The mixed camera
packet remains a compiler and extractor contract test only:

- the packet model retains `camera_bytes` as a binary resource;
- Decom compiles and extracts scalar siblings; and
- the binary resource is not emitted into canonical telemetry.

Camera binding, image assembly, and consumer-failure behavior remain deferred.

## Ops Dock Placement

`SurfaceDefinition.placement` now accepts `:ops_dock`. The Ops shell resolves
eligible surfaces from installed applications. Its host seam owns ordering and
conditional rendering today; tab state, resizing, persistence, loading, and
stream virtualization wait for the first concrete dock contribution.

When a contribution exists, the dock renders below `@inner_content` inside the
current Ops `<main>` column, so it does not cover the navigation rail or mission
context rail. With no contributions, it emits no dock DOM.

Dock surface data and events flow through the authenticated Ops LiveView and
`OpsShellHook`. Applications do not open independent sockets or install client
hooks. A future generic streaming-activity element may be added with Event
Reports as its concrete first consumer, but the Packet Bindings work does not
require that element to be specified here.

## Routing and Authorization

No application-contributed route is added.

Packet Bindings remains on the existing generic `ApplicationHostLive` route in
the authenticated spacecraft application LiveView session. That placement is
required because organization, mission, spacecraft, installation, user scope,
and application version must be loaded by the host before querying or mutating
bindings.

Ops Dock surfaces are mounted only in the existing authenticated `:ops`,
`:ops_dashboard_author`, and `:ops_admin` LiveView sessions because they require
the mission Ops shell and mission-scoped operational context.

Reads use the authenticated `current_scope`. Binding changes require the
existing mission-operation permission. Applying the composed basis requires the
existing activation-request authorization and approval policy. Templates derive
the user from `@current_scope.user`; no `@current_user` assign is introduced.

## Lifecycle and Operator States

The UI distinguishes:

- **Unconfigured** — no desired packet bindings;
- **Configured** — saved bindings have never been applied;
- **Activation pending** — a request references the configured composed basis;
- **Active** — saved application configuration matches the active mission basis;
- **Outdated** — saved bindings differ from the active basis;
- **Disabled** — configuration is retained but contributes nothing to the next
  basis; and
- **Unavailable** — a pinned packet model, endpoint, application version, or
  capability contract cannot be resolved.

An APID being read by another application is not a conflict state.

## Replay and Provenance (target contract)

Every emitted record preserves:

- raw evidence ID;
- packet ID;
- packet model reference and content hash when present;
- packet binding ID and configuration version;
- capability instance and application installation IDs;
- active binding-set ID and version;
- source and receipt times; and
- replay run identity when applicable.

Future replay should resolve the pinned packet model and binding configuration
used by the selected basis. Binding persistence already pins those identities;
per-consumer replay and evidence-backed binary materialization are not part of
this foundation.

## Diagnostics

Diagnostics must distinguish:

- invalid catalog packet structure;
- packet model valid but unsupported by a selected application input contract;
- desired binding references a superseded or missing packet model;
- consumer runtime failure;
- authoritative product conflict;
- saved-versus-active drift; and
- application unavailable or disabled.

Binary content is informational for Telemetry Decom, not an error. The import
summary continues to say that the packet model is valid and available for
application binding.

## Incremental Delivery

### Slice 1: Mixed-packet compiler correction — implemented

- Preserve binary regions in the packet model.
- Compile supported scalar siblings for built-in Decom.
- Reclassify the binary field as not consumed by Decom rather than skipping the
  packet.
- Add the mixed Camera packet contract test.

### Slice 2: Shared packet-binding domain — implemented

- Add input definitions and normalized packet-binding persistence.
- Add scoped list, preview, replace, and disable APIs.
- Add desired/applied lifecycle and optimistic version checks.
- Make the normalized store canonical for packet selection without retaining a
  dual writable UI path. The legacy row continues to own Decom-specific catalog
  and activation settings during migration.

### Slice 3: Packet Bindings surface — implemented foundation

- Add the bounded `PacketBindings` `SurfaceDocument` element.
- Register its query provider and typed action contract.
- Add Telemetry Decom's second application surface.
- Verify streams, empty/error states, and authenticated scope. Browser-level
  visual and accessibility acceptance remains a separate verification gate.

### Slice 4: Application-neutral mission composition — partial foundation

- Compose installed application contributions into one mission binding set.
- Replace the Decom-specific basis identity.
- Reconcile application applied stamps after exact-basis activation.
- Defer independent consumer results and commit/checkpoint isolation until a
  second runtime consumer exists.

### Slice 5: Event Reports — deferred

- Register the application and whole-packet input contract.
- Add ASCII validation and append-only Event Report persistence.
- Add the Event Reports Packet Bindings surface.
- Add the Ops Dock placement and streaming report surface.

Each slice runs focused tests during development. The authoritative final gate
for a completed implementation remains root `mix precommit`.

## Acceptance Criteria

The preparation slice is accepted when:

- A mixed packet containing scalar camera telemetry and `camera_bytes` compiles
  a valid packet model.
- Telemetry Decom emits scalar samples from that packet.
- Multiple application bindings may read the same packet or field.
- Overlapping reads do not produce a resource conflict.
- Packet Bindings validates and persists a versioned, catalog-pinned Decom
  selection through the generic application host.
- Telemetry Decom has no second writable APID-selection control.
- Decom activation uses the application-neutral mission basis and stamps the
  exact applied packet-binding configuration.
- An installed application may declare an Ops Dock surface; no contribution
  means no dock is rendered.
- The host owns routes, authorization, actions, and rendering.
- No application supplies arbitrary HEEx, JavaScript, CSS, browser globals, or
  dynamic Phoenix routes.

Camera bindings, isolated Camera failures, whole-packet Event Report bindings,
Event Report persistence, report virtualization, and multi-application runtime
composition are acceptance criteria for later slices, not this one.

## Explicit Non-goals

- Implementing a general visual dataflow editor.
- Allowing uploaded or untrusted packet decoders.
- Treating every packet observer as a durable product application.
- Storing image bytes in telemetry samples, current values, LiveView assigns, or
  operational events.
- Defining every possible output ownership policy before a concrete collision
  exists.
- Replacing capture-first raw evidence or the existing activation approval
  workflow.
- Implementing the Camera application.
- Implementing the Event Reports application or its report persistence.
- Sending every Event Report into `mission_events` or `operational_events`.

## Open Implementation Questions

1. Whether independent consumer delivery is implemented inside partition
   ownership or through binding-specific processing journal cursors.
2. The maximum binary-region size delivered synchronously before the host
   requires evidence-backed streaming or object-store handoff.
3. Whether selector-only Event Reports bindings synthesize a minimal governed
   packet-model resource at activation time or remain explicitly APID-only.
4. The exact Event Report retention, paging cursor, and explicit mission-event
   promotion policy.

The first packet-model question is resolved for this slice: bindings pin the
immutable canonical telemetry revision/snapshot content hash and resolve its
compiled runtime view. A separate persisted compiled artifact is not required.
The existing `spacecraft_application_bindings` table remains the bounded
Decom-owned catalog and activation configuration during migration.

These questions affect implementation shape. They do not reopen the decisions
that packet inputs are shareable, binary regions are not telemetry samples, and
the host owns the Packet Bindings surface.
