# Design: Mission Comms and Spacecraft Interpretation UX

- Status: draft
- Created: 2026-04-29
- Scope: Reframe communication setup UI around mission-owned network paths and spacecraft-owned data interpretation.
- Related decisions:
  - [ADR-006: Contact, Link, and Transport Runtime Model](../../decisions/006-contact-link-and-transport-runtime-model.md)
  - [ADR-012: Provider Adapter and Ground Station Simulator Model](../../decisions/012-provider-adapter-and-ground-station-simulator-model.md)

## Summary

Cadence currently exposes communication setup through internal resource nouns:
source endpoints, provider profiles, transport profiles, and path templates.
Those nouns are valid in the domain model, but they make the UI feel like a
table editor. Operators and mission engineers are forced to assemble lower-level
records in the right order before they can answer the practical question:

> Can this spacecraft communicate, and can Cadence understand its bytes?

This design splits the product model into two clear ownership boundaries:

> **Mission owns connectivity. Spacecraft owns interpretation.**

Mission-level comms describes the shared ground/network infrastructure and
available paths: ground providers, sockets, GSaaS integrations, reusable link
templates, and path availability.

Spacecraft-level configuration describes how bytes are identified and
interpreted for one vehicle: SCID, TM/TC protocol interpretation, APID
ownership, telemetry decom, command encoding defaults, and readiness.

The underlying storage model keeps source endpoints, provider profiles,
transport profiles, and path templates, but spacecraft usage of a mission link
is represented explicitly by `LinkAssignment`. The primary UI should not lead
with the lower-level records.

## Problem

The current comms UI has three related problems.

1. **It exposes implementation tables as primary navigation.** Users see
   "Source Endpoints", "Provider Profiles", "Transport Profiles", and
   "Links & Paths" as peer concepts. That mirrors the persistence model more
   than the operational workflow.
2. **Bulk link creation feels like a workaround.** The bulk flow compensates
   for the absence of a real constellation-level link assignment workflow. It
   creates many low-level path templates instead of letting users define a
   reusable mission link and apply it to spacecraft.
3. **Connectivity and interpretation are blurred.** Many spacecraft can use
   the same ground path, but each spacecraft may interpret the incoming bytes
   differently. Putting both under `/comms` makes the UI treat shared network
   paths and spacecraft-specific data meaning as one configuration surface.

## Product Principle

Mission comms answers:

> What paths can Cadence use to exchange bytes with external ground systems?

Spacecraft configuration answers:

> When bytes belong to this spacecraft, how does Cadence identify, decode,
> validate, and command it?

The route structure, navigation labels, empty states, validation messages, and
creation flows should reinforce that split.

## Terminology

The user-facing vocabulary is locked for the first implementation pass.
Backend modules may keep their current names; primary UI copy, navigation, and
tests should use these product terms unless a page is explicitly labeled
Advanced.

| Backend concept | User-facing term | Definition |
| --- | --- | --- |
| `SourceEndpoint` | Runtime Identity | Ground-side identity Cadence uses to route incoming bytes to the right spacecraft or mission partition. Usually derived from spacecraft identity such as SCID. |
| `ProviderProfile` | Provider | External ground-side system or adapter Cadence connects to for sending or receiving bytes. Examples: TCP socket, simulator, GSaaS provider. |
| `TransportProfile` | Protocol Behavior | Reusable behavior attached to a link or spacecraft flow, such as heartbeat monitoring, uplink gateway behavior, TC framing, or COP-1 behavior. Prefer concrete behavior names when possible. |
| `PathTemplate` | Link Template | Reusable mission-owned blueprint for communication links. It is not assigned to a spacecraft by itself. |
| `LinkAssignment` | Link Assignment | Spacecraft-specific application of a mission-owned link template to a runtime identity. This is the source of truth for which spacecraft uses a link. |

Additional product terms:

- **Mission Network**: shared ground-side connectivity available to a mission.
  Includes providers, links, link templates, simulator paths, and GSaaS
  integrations.
- **Link**: a usable communication path between Cadence and an external
  ground-side system. Links may be downlink, uplink, or bidirectional.
- **Spacecraft Identity**: spacecraft-specific values that let Cadence
  recognize bytes as belonging to one vehicle. SCID is the first identity field.
- **Interpretation**: spacecraft-owned configuration that turns bytes into
  meaningful telemetry, commands, events, or protocol state.
- **Telemetry Interpretation**: downlink interpretation for one spacecraft:
  TM frame handling, catalog binding, APID ownership, and decom configuration.
- **Command Interpretation**: uplink interpretation for one spacecraft:
  command encoding, TC framing defaults, VCID, and spacecraft-specific command
  routing behavior.
- **Link Assignment**: the bridge between mission-owned links and
  spacecraft-owned interpretation. It describes which mission links a
  spacecraft can use or is configured to use.

Terms to avoid in primary UI:

- **Source Endpoint**: use only in Advanced/debug views.
- **Provider Profile**: use Provider.
- **Transport Profile**: use Protocol Behavior, or the concrete behavior name.
- **Path Template**: use Link Template.
- **Bulk Links**: use Apply Link Template or Assign Link.
- **Assigned Link Template**: avoid this phrasing in primary UI. A link
  template is reusable; a link assignment attaches it to a spacecraft.

## Goals

- Make mission-level comms about shared network and path availability.
- Move spacecraft-specific identity and protocol interpretation into the
  spacecraft area.
- Make the primary workflow "make spacecraft contact-ready", not "create four
  records in the right order".
- Preserve the existing domain model where it is useful.
- Keep advanced object-level views available for debugging, versioning, and
  power users.
- Replace "bulk create path templates" with explicit template application and
  spacecraft assignment flows.

## Non-goals

- No rewrite of ADR-006 contact/path/transport runtime ownership.
- No further schema redesign is required by this spec after introducing
  `LinkAssignment`.
- No removal of provider profiles, transport profiles, source endpoints, or
  path templates from the backend.
- No real-time contact operations UI. This spec is about setup and readiness,
  not live contact execution.
- No final naming decision for every domain object. Proposed labels may evolve
  during implementation.

## Conceptual Model

### Mission-Owned Connectivity

Mission-level comms owns shared communication infrastructure:

- Ground network providers and adapters.
- TCP listeners and clients.
- GSaaS integrations.
- Simulator-facing links.
- Provider credentials and endpoint configuration.
- Reusable downlink and uplink path templates.
- Mission-wide link availability and validation.
- Template application across many spacecraft.

These objects are not spacecraft-specific by default. A constellation may have
hundreds of spacecraft eligible for the same ground station or TCP downlink.

### Spacecraft-Owned Interpretation

Spacecraft configuration owns per-vehicle meaning:

- SCID and spacecraft identity.
- Runtime source endpoint mapping, mostly hidden behind identity/readiness UI.
- TM transfer frame interpretation.
- VCID and APID ownership.
- Telemetry decom configuration and catalog binding.
- Command interpretation and TC framing defaults when spacecraft-specific.
- Per-spacecraft readiness: identity, telemetry, downlink, uplink, commanding.

This is where Cadence turns bytes into spacecraft data.

### Bridge: Link Assignment

Link assignment connects the two sides:

- A mission defines available paths and reusable templates.
- A spacecraft is attached to those templates through explicit
  `LinkAssignment` records.
- A future spacecraft group or constellation segment workflow may create many
  `LinkAssignment` records from one template application.
- Spacecraft-specific interpretation remains local to the spacecraft.

The assignment flow should be visible as a product concept. It should not feel
like a bulk insert of path template rows.

### Scheduled Contacts

Scheduled contacts should plan against domain objects, not derived routing
strings:

- `ScheduledContact.link_assignment_refs` is the primary way to say which
  spacecraft links should be active during a planned pass.
- Each ref pins a `link_assignment_id`. Realization resolves the assignment,
  fetches its pinned link template version, and produces concrete runtime
  `Path` records.
- `ScheduledContact.source_endpoint_refs` is runtime/read-model metadata. It
  may be accepted for manual compatibility, but when link assignments are
  present it is derived from those assignments.
- `ScheduledContact.path_template_refs` and embedded `paths` remain available
  for advanced/manual overrides where the operator is deliberately bypassing
  spacecraft link assignment.
- Contact scheduling should not depend on `PathTemplate.source_endpoint_ref`.

#### Contact Intent

`Contact Intent` is the operator's declaration of what the planned contact
window is meant to accomplish. It belongs to the scheduled contact as a whole
and should drive validation and UI language.

Initial intents should remain directional and operational:

- `telemetry_downlink`: receive telemetry, payload data, files, logs, or
  recorder dumps. Requires at least one selected downlink path.
- `command_window`: send commands, command loads, or time-tagged sequences.
  Requires at least one selected uplink path once commanding workflows exist.
- `tracking`: support ranging, Doppler, orbit determination, or antenna
  tracking. Path requirements depend on the provider integration.
- `health_check`: short low-rate contact to confirm spacecraft state. May use
  downlink-only, uplink-only, or bidirectional paths depending on mission
  practice.
- `maintenance`: provider, simulator, or ground-system exercise where mission
  data may not be expected.

Until command scheduling exists, Cadence should allow directional contacts,
including downlink-only contacts. Validation should require at least one
selected path and should only enforce direction-specific requirements when the
contact intent requires that direction.

#### Future Work: Activity Role

`Activity Role` is the role a specific planned link or path plays inside a
contact. It belongs to an individual planned link/path assignment rather than
the scheduled contact as a whole.

Examples:

- `primary_downlink`
- `backup_downlink`
- `command_uplink`
- `ranging`
- `monitoring`
- `simulator_input`

Activity roles are useful for split contacts where different antennas,
providers, or bands serve different operational purposes, such as X-band
high-rate downlink plus S-band commanding. They are future work and should not
block the first scheduling implementation.

Implementation rule:

- New primary UI flows must not infer assignment from
  `PathTemplate.source_endpoint_ref`.
- `PathTemplate.source_endpoint_ref` is legacy/read-only compatibility only.
  New code must not create, update, count, or resolve spacecraft usage from
  this field.
- Development data can be dropped and recreated rather than backfilled from
  legacy direct path-template assignments.

## Proposed Route Shape

Routes stay under the authenticated browser scope with
`[:browser, :require_authenticated_scope]`.

Mission-level comms routes belong in a mission-loaded `live_session` because
they require both organization and mission context but do not require a
spacecraft:

```elixir
live_session :comms,
  on_mount: [
    {CadenceWeb.OrganizationAuth, :require_organization_scope},
    {CadenceWeb.MissionAuth, :load_mission},
    {CadenceWeb.UserAuth, :attach_user_menu}
  ],
  layout: {CadenceWeb.Layouts, :mission_sidebar} do
  live "/missions/:mission_id/comms", CommsOverviewLive, :index
  live "/missions/:mission_id/comms/links", CommsLinkListLive, :index
  live "/missions/:mission_id/comms/providers", CommsProviderListLive, :index
  live "/missions/:mission_id/comms/templates", CommsTemplateListLive, :index
  live "/missions/:mission_id/comms/validation", CommsValidationLive, :index
end
```

Spacecraft interpretation routes belong in a spacecraft-loaded `live_session`
because they require `@current_spacecraft` and must be scoped by
organization, mission, and spacecraft:

```elixir
live_session :spacecraft_show,
  on_mount: [
    {CadenceWeb.OrganizationAuth, :require_organization_scope},
    {CadenceWeb.MissionAuth, :load_mission},
    {CadenceWeb.SpacecraftAuth, :load_spacecraft},
    {CadenceWeb.UserAuth, :attach_user_menu}
  ],
  layout: {CadenceWeb.Layouts, :mission_sidebar} do
  live "/missions/:mission_id/spacecraft/:spacecraft_id", SpacecraftShowLive, :show
  live "/missions/:mission_id/spacecraft/:spacecraft_id/identity", SpacecraftIdentityLive, :show
  live "/missions/:mission_id/spacecraft/:spacecraft_id/telemetry", SpacecraftTelemetryLive, :show
  live "/missions/:mission_id/spacecraft/:spacecraft_id/commanding", SpacecraftCommandingLive, :show
  live "/missions/:mission_id/spacecraft/:spacecraft_id/links", SpacecraftLinksLive, :show
  live "/missions/:mission_id/spacecraft/:spacecraft_id/readiness", SpacecraftReadinessLive, :show
end
```

This placement follows the authentication rule: mission network routes require
authenticated organization and mission context, while interpretation routes
also require the spacecraft preload.

## Navigation Model

### Mission Sidebar

Keep the mission sidebar high-level:

- Overview
- Spacecraft
- Comms
- Catalog
- Commanding
- Contacts

`Comms` means mission network and path infrastructure.

`Spacecraft` means per-vehicle identity, interpretation, and readiness.

The sidebar label should remain **Comms** for brevity. The primary page heading
inside that section should be **Mission Network** to make the ownership boundary
explicit.

### Comms Section Navigation

Mission comms should expose operational nouns first:

- Mission Network
- Links
- Providers
- Link Templates
- Validation
- Advanced

The current "Source Endpoints", "Provider Profiles", "Transport Profiles", and
"Path Templates" pages should move under Advanced or be renamed into product
language:

| Current label | Proposed primary label | Placement |
| --- | --- | --- |
| Source Endpoints | Runtime Identity | Spacecraft identity / Advanced |
| Provider Profiles | Providers | Mission comms |
| Transport Profiles | Protocol Behaviors | Advanced or template details |
| Path Templates | Link Templates | Mission comms |

### Spacecraft Section Navigation

The spacecraft detail page should become the entry point for interpretation:

- Overview
- Identity
- Telemetry Interpretation
- Command Interpretation
- Link Assignments
- Readiness

The overview should show a compact readiness panel:

```text
Identity
SCID 42 configured

Telemetry
Catalog Rev 18 bound, 14 APIDs handled

Downlink
Eligible for Goldstone TCP Downlink

Commanding
TC uplink profile missing
```

Each row links to the responsible surface. Shared network link issues navigate
to mission comms. Interpretation issues stay under spacecraft.

## Primary Workflows

### 1. Create A Shared Mission Link

Entry point: `/missions/:mission_id/comms/links/new`

Flow:

1. Choose direction: downlink, uplink, or bidirectional.
2. Choose provider type: TCP, simulator, GSaaS, custom adapter.
3. Configure provider connection.
4. Configure path-level protocol behavior, if reusable.
5. Name the link.
6. Save as an available mission link.

Output:

- Provider profile and transport/profile details may be created behind the
  scenes.
- The user sees a mission link, not a collection of rows.
- Created link templates remain reusable and unassigned until a
  `LinkAssignment` is created.

### 2. Apply A Link Template To Spacecraft

Entry point: mission comms template page, or a spacecraft readiness action.

Flow:

1. Select a link template.
2. Choose apply scope:
   - all spacecraft matching the current filter, or
   - explicitly checked spacecraft from the preview table.
3. Preview impact:
   - already assigned
   - missing SCID
   - will assign
   - conflicts
4. Apply.
5. Show a result summary with created/updated/skipped/failed counts.

Persistence must be atomic for all-or-nothing mode, or explicitly partial with
row-level result reporting. A silent half-applied batch is not acceptable.

The persistence output is one `LinkAssignment` per successfully applied
spacecraft, not cloned or directly assigned path-template rows.

API surface:

```http
POST /api/organizations/:organization_id/missions/:mission_id/path_templates/:path_template_id/link_assignments
```

Request body:

```json
{
  "link_template_application": {
    "target_mode": "selected",
    "spacecraft_ids": ["spacecraft-001", "spacecraft-002"],
    "path_template_version": 2,
    "provider_path_ref_pattern": "{spacecraft_id}-{direction}",
    "display_name_pattern": "{spacecraft_name} {direction}"
  }
}
```

`target_mode` may be:

- `selected`: apply only to the explicit `spacecraft_ids` list.
- `matching`: apply to all spacecraft matching `spacecraft_query`; if no query
  is provided, apply to all spacecraft in the mission preview set.

Response body:

```json
{
  "data": {
    "applied_count": 1,
    "skipped_count": 1,
    "failed_count": 0,
    "rows": [
      {
        "spacecraft": {"spacecraft_id": "spacecraft-001"},
        "kind": "applied",
        "status": "ready",
        "label": "Applied",
        "detail": "Link assignment was created."
      }
    ]
  }
}
```

The API intentionally reports per-row results because constellation-scale
application can be partially blocked by missing SCIDs, duplicate provider path
refs, or existing assignments.

### 3. Make One Spacecraft Contact-Ready

Entry point: `/missions/:mission_id/spacecraft/:spacecraft_id/readiness`

Flow:

1. Set SCID and identity.
2. Select eligible downlink path from mission-owned links.
3. Configure telemetry interpretation:
   - catalog revision
   - APID selection
   - TM frame handling
4. Configure commanding interpretation, if needed:
   - TC frame defaults
   - VCID
   - COP-1 or uplink behavior when spacecraft-specific
5. Review readiness summary.

This is the main single-spacecraft workflow.

### 4. Diagnose Mission-Wide Setup

Entry point: `/missions/:mission_id/comms/validation`

Validation should group findings by ownership:

- Mission network findings:
  - no providers
  - provider unreachable or incomplete
  - no available downlink links
  - template references stale provider versions
- Spacecraft interpretation findings:
  - missing SCID
  - no telemetry decom
  - catalog missing
  - command interpretation incomplete
- Link assignment findings:
  - spacecraft has no eligible downlink
  - spacecraft has no eligible uplink
  - duplicate selected path for same spacecraft/source identity

Do not warn that multiple selected uplinks exist across the whole mission.
That warning should be scoped to the contact, spacecraft, source identity, or
assignment group that actually requires uniqueness.

## Page-Level Design

### Mission Comms Overview

Purpose: show shared network readiness and coverage.

Sections:

1. **Network availability summary**
   - providers configured
   - active link templates
   - spacecraft covered by at least one downlink
   - spacecraft covered by at least one uplink
2. **Coverage table**
   - spacecraft
   - SCID
   - downlink eligibility
   - uplink eligibility
   - interpretation status
   - actions
3. **Network resources**
   - providers
   - links
   - templates
   - validation

The table should distinguish "network missing" from "interpretation missing".

### Spacecraft Overview

Purpose: show everything needed to operate one spacecraft.

Sections:

1. Identity summary.
2. Telemetry interpretation summary.
3. Command interpretation summary.
4. Link eligibility summary.
5. Recent validation findings.

Actions should be direct:

- Set SCID
- Configure telemetry
- Configure commanding
- Assign link
- View mission link

### Link Detail

Purpose: describe a shared mission path.

Show:

- Provider and connection settings.
- Direction.
- Reusable protocol behaviors.
- Link assignment coverage count.
- Version history.
- Validation findings.

Do not show source endpoint internals unless in an Advanced section. If a
legacy direct runtime identity reference exists on a path template, label it as
legacy compatibility, not as the normal assignment model.

### Spacecraft Links

Purpose: show how one spacecraft uses mission-owned paths.

Show:

- Available mission links.
- Whether this spacecraft is eligible or assigned.
- Direction.
- Provider.
- Any spacecraft-specific override.
- Interpretation readiness for that link.

This page should not duplicate provider configuration forms. It should link to
mission comms when the shared path itself needs editing.

## Data Model Mapping

The current backend concepts map to the locked product vocabulary as follows:

| Backend concept | Product concept | Primary owner |
| --- | --- | --- |
| `SourceEndpoint` | Runtime Identity | Spacecraft |
| `ProviderProfile` | Provider | Mission comms |
| `TransportProfile` | Protocol Behavior | Mission comms or advanced |
| `PathTemplate` | Link Template | Mission comms |
| `LinkAssignment` | Link Assignment | Spacecraft |
| Spacecraft SCID | Spacecraft Identity | Spacecraft |
| Telemetry decom config | Telemetry Interpretation | Spacecraft |

Important rule:

- The UI may create or update source endpoints as a side effect of spacecraft
  identity setup, but users should rarely need to create source endpoints
  directly.
- Link templates are reusable mission-owned definitions. Link assignments are
  the source of truth for spacecraft usage.
- New UI forms for creating or versioning link templates should not expose
  runtime identity assignment. Assignment belongs in Apply Link Template and
  Spacecraft Links workflows.
- The API must not write `PathTemplate.source_endpoint_ref`. It may return the
  field for old rows, but direct path-template assignment is not part of the
  active contract.

### API Examples

Create a reusable link template:

```http
POST /api/organizations/org-alpha/missions/mission-alpha/path_templates
```

```json
{
  "path_template": {
    "path_template_id": "goldstone-downlink",
    "path_id": "goldstone-downlink",
    "direction": "downlink",
    "selection_role": "selected",
    "provider_profile_refs": [
      {"provider_profile_id": "goldstone-tcp", "version": 1}
    ]
  }
}
```

Apply it to explicitly checked spacecraft:

```http
POST /api/organizations/org-alpha/missions/mission-alpha/path_templates/goldstone-downlink/link_assignments
```

```json
{
  "link_template_application": {
    "target_mode": "selected",
    "spacecraft_ids": ["sc-001", "sc-002"]
  }
}
```

List assignments for one spacecraft:

```http
GET /api/organizations/org-alpha/missions/mission-alpha/link_assignments?spacecraft_id=sc-001
```

Delete an assignment:

```http
DELETE /api/organizations/org-alpha/missions/mission-alpha/link_assignments/link-assignment-001
```

## Validation Rules

### Mission Network Validation

- At least one provider is configured when links exist.
- Each link has a provider.
- Each link references active provider/profile versions.
- Each reusable template has enough configuration to instantiate a path.
- Provider settings are structurally valid.

### Spacecraft Interpretation Validation

- Spacecraft has SCID if TM transfer-frame resolution is expected.
- Runtime identity is synced with spacecraft identity.
- Telemetry decom is configured for expected downlink operation.
- Catalog revision exists and selected APIDs are valid.
- Commanding interpretation is configured for expected uplink operation.

### Link Assignment Validation

- A spacecraft should have at least one eligible selected/preferred downlink.
- Uplink uniqueness checks are scoped, not mission-global.
- Assignment conflicts should be reported per spacecraft/source identity.
- Missing SCID blocks spacecraft-specific assignment that depends on SCID.
- Duplicate provider path refs should be detected across reusable templates and
  existing link assignments.

## Migration Plan

### Phase 1: Rename And Reframe

- Keep existing pages.
- Change top-level copy and navigation to reinforce:
  - Comms = network/path infrastructure.
  - Spacecraft = interpretation/readiness.
- Rename "Path Templates" to "Link Templates" in user-facing copy.
- Move source endpoint language behind "Runtime Identity" where possible.
- Update validation copy to identify the owner of each issue.

### Phase 2: Spacecraft Readiness Surface

- Add a spacecraft readiness page or expand spacecraft show.
- Move SCID, runtime identity, telemetry decom status, command status, and link
  eligibility into one spacecraft-level summary.
- Add direct actions for missing pieces.

### Phase 3: Mission Link Builder

- Replace separate provider/profile/path creation as the main path with a link
  builder that creates or reuses underlying records.
- Keep advanced object pages for inspection and version management.

### Phase 4: Template Application

- Replace "bulk link creation" with "apply link template".
- Add preview and explicit result reporting.
- Make apply atomic unless the UI intentionally offers partial apply with
  per-row status.
- Persist application as `LinkAssignment`, not as cloned or directly assigned
  path templates.
- Provide both all-matching-filter and explicit checked-spacecraft modes.

### Phase 5: Advanced Cleanup

- Move raw object tables under Advanced.
- Audit tests and route names to match the new product language.
- Remove redundant paths once the new flows cover existing functionality.
- Stop writing `PathTemplate.source_endpoint_ref` in API, UI, and domain
  persistence paths.
- Stop counting direct path-template runtime identity references as active link
  assignments in readiness, validation, coverage, and apply previews.
- Keep read-only legacy display only where old rows need to be inspected.

## Open Questions

- Do spacecraft groups or constellation segments already exist, or does
  template application initially filter by spacecraft attributes only?
- Which protocol behaviors are genuinely reusable at mission scope, and which
  should always live under spacecraft interpretation?
- Should command interpretation get its own spacecraft page immediately, or
  start as a readiness placeholder until command setup is broader?
- Should mission comms validation include runtime/provider health, or should
  live health stay under future contact operations?

## Acceptance Criteria

- A user can explain the UI as: "mission owns paths, spacecraft owns byte
  interpretation."
- The primary comms flow no longer requires understanding source endpoints.
- A spacecraft page shows what is missing before that spacecraft is
  contact-ready.
- A mission comms page shows what shared paths exist and which spacecraft they
  cover.
- Bulk setup is expressed as applying a reusable template to spacecraft, with
  clear preview and result reporting.
- Advanced users can still inspect and version provider/profile/path records.
