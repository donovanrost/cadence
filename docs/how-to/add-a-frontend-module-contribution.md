# Add a frontend module contribution

Use [ADR-024](../decisions/024-host-composition-and-vertical-frontend-modules.md)
for ownership decisions. A module may appear in several host areas without
transferring ownership of its features to those areas. This is not a new Managed
Application runtime API and does not make every frontend module installable.

## Start with a vertical feature

Place the component, DTO types, runtime validator, interactions, contribution
declaration, and tests together under `modules/<module>/src/features/<feature>/`.
The module's public entry assembles registrations. Host composition code imports
that entry, not feature internals. Host feature slices follow the same convention.

The first reference implementation is
`frontend/modules/dashboards-and-exploration/src/features/runtime-diagnostics/`.
Its historical organization-admin renderer delegates to the same implementation;
it is not a second owner.

## Use a named slot

The first implemented slot is `administration.diagnostics`, version 1, declared
in `frontend/packages/plugin-sdk/src/diagnostics-contribution.ts`. It accepts
compiled UI contributions with stable identity, ordering, a component, and a
feature-owned validator. It does not accept component names or import URLs from
server data. Admission happens in the host diagnostics feature's `contributions.ts`.

Keep the feature's DTO in its own slice. The generic host must not acquire
dashboard-specific filter keys, evidence fields, or rendering branches. Currently
diagnostics interactions support query changes on the same diagnostics page;
refresh is host-owned. Add other slot kinds only for actual consumers.

## Data-only readiness contributions

`spacecraft.readiness`, version 1, is a data slot rather than a component slot.
Its public contract is `@cadence/plugin-sdk/readiness`. The host spacecraft
readiness feature owns its validator, standard card renderer and mounted tests.
The server composition boundary is `Cadence.Reads.Spacecraft.ReadinessContributions`;
Communications owns routing setup status, while registered capability status
providers retain their domain logic and installation admission.

Each contribution carries a stable identity, version, organization/mission/
spacecraft context, availability, standard status, bounded facts and an optional
navigation action. The server selects providers; payloads cannot name code to load.
The consumer rejects duplicate identities, unsupported versions, scope mismatch,
unsafe links and malformed fields individually. Provider exceptions become
sanitized unavailable entries. An unavailable contribution must not leave a ready
page badge. Routing setup is explicitly not a runtime-connectivity or commanding
approval check.

Use this standard data contract when a host needs status composition; use a UI
slot when a feature genuinely needs its own renderer and interactions. Do not
introduce a renderer hook merely to display a few status facts.

## Preserve server authority

### Spacecraft page contributions

`spacecraft.page`, version 1, is a UI slot for one host-selected module page at a
spacecraft URL. Its contract is `@cadence/plugin-sdk/spacecraft-pages`. The initial
consumer is `comms.spacecraft-routing`, exported through
`@cadence/communications/spacecraft-routing`; renderer, contracts, validation and
tests stay in the Communications routing feature.

The host route selects a compiled registration by identity, never by a component
name supplied in the response. `CadenceWeb.SpacecraftModulePage` maps the same route
to an authorized read provider. Its snapshot includes slot, identity, version,
organization/mission/spacecraft context and availability. The host validates that
envelope against its path-owned context, then invokes the feature's `read` function
to obtain admitted props. The host does not interpret routing fields or grant any
action authority. A failed contribution leaves navigation available and retries
through `host:context`, including normal session and resource authorization.

This is coordinated build-time composition, not a new requirement for independent
releases or a Managed Application installation. Historical remote adapters can
delegate to the feature's public entry during migration. Use the corresponding
host/module component tests and `spacecraft_module_page_test.exs` as references.

### Ops workspace page contributions

`ops.page`, version 1, places a module-owned page inside the persistent Ops
workspace frame. The public contract is `@cadence/plugin-sdk/ops-pages`.
The first registration is `dashboards.directory`, exported by
`@cadence/dashboards-and-exploration/directory`; its DTO, validator, presentation,
URL filters, action state and tests are colocated in `features/directory/`.
The host frame and its rails live in `ops-workspace/features/frame/`.

The route chooses the compiled registration. The host checks slot, identity,
version, organization, mission and page token before handing the DTO to the
feature validator. The feature constructs its own dashboard URLs and UI labels;
server data cannot name a renderer. Directory filters and pagination navigate
through the host so Back and reload preserve them.

Phoenix reauthorizes each action, binds its page-local sequence and displayed
dashboard/version, and invokes scoped directory commands. Star and restore effects
are never automatically retried. Unknown outcomes remain locked through read-only
refresh; page-instance guards do not imply cross-session exactly-once execution.
The existing route stays in the authenticated `/` scope, using
`[:browser, :require_authenticated_scope]` and the `:application` live session
with its `:ops` host policy. No public endpoint is added.

`dashboards.editor` is a resource-bound contribution exported through
`@cadence/dashboards-and-exploration/editor`. Its forms and command state live
inside `features/editor/`. The host's editor adapter binds the page identity,
sequence and observed document version before invoking domain commands. A
conflict or uncertain outcome remains locked through ordinary refresh; an
explicit `reload_editor` read reconciles the saved state before editing resumes.
This does not promise durable idempotency across page instances.

The optional `OpsPagePort.guardNavigation(guard)` hook returns a disposer. An
editing feature registers a synchronous leave decision and disposes it when
unmounted. The host router invokes it before internal navigation, including
Back/Forward; the feature owns its unsaved-change decision, not the router.
Use native `beforeunload` separately for full-page exits. Guard registration is
bound to the admitted contribution token and context and never grants action
authority. Do not reach into host router internals from a module.

Remaining Ops features still use the historical remote. The relocated context rail
still has legacy domain-summary interpretation; introduce domain-owned rail
contribution contracts when migrating those consumers.

`dashboards.creation` is a second registration in the same module, exported by
`@cadence/dashboards-and-exploration/creation`. Its `features/creation/` slice
owns blank, clone and import presentation, draft state, validation and tests.
The host forwards only `mode` and `source_dashboard_id` as creation URL state.
The semantic producer authorizes the mission and clone source; the scoped
creation command authorizes again and never accepts organization or mission
identity from form fields. The host admits only `create`, with its page token,
next sequence and displayed source version. Known pre-persistence validation
failures allow correction. Successful and uncertain submissions remain consumed
through refresh; there is no automatic retry or cross-session deduplication claim.

### Mission page contributions

`mission.page`, version 1, places a compiled module-owned read page at a mission
URL. Its contract is `@cadence/plugin-sdk/mission-pages`; the first eight
registrations are exported by `@cadence/communications/mission-pages`.
Registration declarations stay in each feature's `mission.contribution.ts`.
The public entry assembles them without moving validators or renderers out of
their vertical slices.

`CadenceWeb.MissionModulePage` selects a bounded read by the matched host route.
`Cadence.Reads.Comms.Pages` authorizes the supplied scope independently of that
host and of the historical federation query adapter. The host checks the
slot/identity/version and organization/mission/resource envelope; the feature
then validates its DTO and checks that detail data matches the path-owned
`resourceId`. A payload may not select a different component or resource.
Unavailable reads and renderer failures retain the shell and a host refresh
control. Search remains a native GET form; pagination and detail links use
ordinary host navigation. These read registrations carry no action port.

The existing Communications routes remain in the authenticated application
live session with the `:comms` host policy. No new route or public endpoint is
introduced.

The four Communications setup forms use feature-local `setup.contribution.ts`
registrations in the same slot, with a finite `validate`/`save` action list.
`CadenceWeb.CommunicationsSetupPage` binds a page token to the authenticated user,
organization, mission, full path and (for station edit) resource. Validation stores
the exact admitted draft; save revalidates that draft and consumes the instance
before calling `Cadence.Management.CommunicationsSetup`. The latter authorizes
independently and is also used by the legacy action adapter.

Keep initial form props and the port stable for a mounted token so refresh does
not replace drafts. A completed phase hides the consumed form; an uncertain
submission disables it and offers a records-review link. Never automatically
retry effects. Navigating away creates a new instance on return, so this is not
cross-session idempotency.

Provider directory, creation and detail are also mission-page contributions,
declared inside `features/providers/mission.contribution.ts`. Their finite port
exposes creation, validation, synchronization, archival, and read-only refresh.
The feature adapts that port to its existing workflows; the host never interprets
provider DTO fields. `CadenceWeb.MissionProviderPage` binds path/token/context,
checks the observed provider version and page-local sequence, and consumes each
effect before invocation. Refresh does not unlock an uncertain effect.

Registration requires the account and grant versions that were admitted in the
form. Its domain command authorizes independently and preserves every supported
bounded-policy timing field. Provider control actions retain the existing
control-plane implementations. Version checks are admission checks, not atomic
concurrency control or cross-session exactly-once guarantees.

### Organization page contributions

`organization.page`, version 1, places a compiled, module-owned page in the host's
organization area. The initial consumer is `comms.provider-account-directory`,
exported by `@cadence/communications/provider-accounts`. The contract lives at
`@cadence/plugin-sdk/organization-pages`; feature-local DTO admission binds the
organization, row identities, counts and account links.

`CadenceWeb.OrganizationModulePage` selects the read provider from the host route
and contains read failures. `Cadence.Reads.Comms.ProviderAccountDirectory` requires
provider-account management permission even when invoked without the web host.
The existing `/provider-accounts` route remains in the authenticated application
session with its `:provider_accounts` policy. Refresh reauthorizes through
`host:context`; there is no new endpoint or frontend release dependency.

Registrations can declare a finite action list. The first action consumer is
`comms.provider-account-registration`, with `validate` and `save`. Only these
declared actions receive a host port; read-only contributions receive none.
`host:organization-page` carries the contribution identity, server-issued token,
path, event and bounded input. Phoenix checks the active user/organization/page
instance before and after reauthorization. This is not an arbitrary host-event API.

`CadenceWeb.ProviderAccountRegistrationPage` pins the domain's generated account
and credential identities for the page instance. Validation does not replace the
mounted draft. Leaving the page rotates the token; submission consumes it before
effects, even when the outcome cannot be confirmed. Same-instance refresh cannot
clear an uncertain-outcome lock. Completed responses carry validated receipts;
unknown outcomes are not presented as confirmed rejection or safe automatic retry.
Partial external effects and cross-session exactly-once remain outside this
page-instance guarantee.

`comms.provider-account-detail` also admits `resourceId` from the host-matched
account URL. Its finite port includes five account/grant actions and a read-only
`refresh`. `CadenceWeb.ProviderAccountDetailPage` binds the same account, path,
user, organization and token before and after reauthorization. Each effect carries
the next page-local sequence as well as observed domain versions. Repeated or
out-of-order sequences cannot repeat effects. An uncertain result locks mutations
in both server session and mounted feature; refresh still reads the selected
account and preserves draft/lock state. A fresh page instance has a fresh token.
The module's DTO reader, not the host, interprets account and grant fields.

### Administration diagnostics authority

The dashboard read provider owns diagnostic data assembly. The web composition
boundary owns registration and isolates an unavailable provider. Both the
composition boundary and provider require active platform-admin scope. The existing
`/admin/runtime` route uses the authenticated browser scope and its `:admin` host
policy; every `host:context` request, including filtering and refresh, reauthorizes
through that policy. There is no new public diagnostics endpoint.

The browser receives snapshots with stable ID, contract version, status, and data.
It joins those to compiled registrations, validates the feature DTO, and contains
renderer failures. Missing/duplicate snapshots, unavailable providers, unsupported
versions, and malformed data do not remove host navigation. Filters update the
panel in place so typing retains focus; stale refreshes cannot replace newer
navigation.

## Verify the boundary

Run `corepack pnpm check` from `frontend`. It runs formatting and type-aware lint,
then uses Vue's compiler for TypeScript diagnostics across every application,
domain module, shared package and the root TypeScript tools. Vue props, templates
and colocated tests are checked by `vue-tsc`; no generic Vue declaration shim is
used to make this gate pass. Legacy JavaScript SFCs can participate through
`allowJs` while their declared props remain visible to typed consumers.

A new package with TypeScript or Vue sources needs its own `tsconfig.json` and a
reference in `frontend/tsconfig.json`. The workspace driver fails when either is
missing or a reference is duplicated. CSS-only token packages need no artificial
TypeScript project. `corepack pnpm typecheck` runs this compiler gate alone;
`corepack pnpm test:typecheck` verifies discovery and actual Vue error detection.

### Dashboard workspace renderer ownership

Use `@cadence/dashboards-and-exploration/workspace` for the existing dashboard
canvas, grid, widget, comparison and chart renderers. Their implementations,
runtime port and tests are colocated in `features/workspace/`; old Ops component
paths are compatibility adapters, not a second implementation. Keep feature-local
vendor assets with their renderer. Only demonstrated domain-neutral reuse, such
as the clipboard button, belongs in `@cadence/ui`.

Provide `CHART_RUNTIME_PORT` per mounted workspace. Version 1 admits only
`open_data_link`, `open_evidence`, and `set_chart_time_range`, plus `append` and
`selection` subscriptions. Missing or unsupported ports leave a static chart;
unmount removes subscriptions and suppresses late callbacks and actions. The
owner must authorize and scope delivery and operations, and present failures;
the chart does not retry failed effects or fall back to a global browser bus.
The existing Ops adapter still translates global `tlm:append`/`tlm:select`
broadcasts, so it does not yet provide scoped inbound telemetry isolation.

These renderers retain their legacy presentation shapes. Do not treat the runtime
port's record-shape guard as a semantic DTO validator or count this extraction as
an editor/viewer host contribution.

`Cadence.Reads.Dashboards.Workspace.load/5` supplies the new authorized semantic
snapshot. Its optional runtime context and resolution dependencies are explicitly
server-owned inputs, not a browser command surface. Production reads capture
runtime dependencies once for that resolution. Published reads fetch the published
version only; draft reads additionally require the named author policy.
`Resolution.resolve_with_document/2` returns the same hydrated document used for
planning/execution. Build placement presentation from that document and result,
not a second library read or a list that drops unknown widget types.

`readWorkspaceSnapshot` is exported from the module's public `workspace` entry;
its contract, validator and tests live in the workspace slice. It binds all three
resource identities, rejects unsupported versions and malformed columnar data,
and preserves explicit unavailable placements. Frames carry typed primitive values
and units; timestamps are epoch milliseconds. Annotation DTOs carry time geometry,
title and severity. Arbitrary source metadata, evidence/action payloads and raw
diagnostic messages are not transported. A supported placement marked `ready`
is renderable, not a claim of fresh or available data: retain its warnings and
empty-data state in presentation.

This snapshot is not wired into the viewer route yet. The legacy canvas producer
still emits no groups. URL-context admission, semantic-to-renderer adaptation,
feature-owned evidence/action ports and scoped live transport remain required;
do not claim workflow completion from producer/validator tests alone.

### Contribution verification

For each contribution, test:

- The real feature component and its interactions, not only a stub or manifest.
- Actual producer output against the consumer validator, including populated and
  selected records, not only empty fixtures.
- Authorization, revoked sessions, bounded inputs, and evidence redaction.
- Missing/invalid data and renderer failure without losing the host or siblings.
- Direct load, refresh, filter/selection navigation and recovery in the browser.
- Production build and typechecking, including Tailwind scanning of module files.

For this slice, from `frontend/`:

```sh
corepack pnpm --filter @cadence/dashboards-and-exploration test
corepack pnpm --filter @cadence/plugin-host test
corepack pnpm --filter @cadence/plugin-host exec vue-tsc --noEmit -p tsconfig.app.json
```

The server/consumer checks live in
`apps/cadence_web/test/cadence_web/administration_diagnostics_test.exs`. They invoke
the feature's actual TypeScript validator using the workspace Node runtime. Run
`mix precommit` from the repository root after changes.

The remaining packages and host contribution slots in ADR-024 are a migration
target. The diagnostics slice does not claim that the entire frontend has moved.
