---
title: Add a Product Application or Typed Extension
tags: [how-to, developer, applications, extensions, packages, liveview]
status: active
created: 2026-07-26
updated: 2026-07-26
---

# Add a Product Application or Typed Extension

Use this guide when adding an operator-facing capability or one implementation
of an existing Cadence extension point.

The first decision is whether the feature is a product application, a typed
extension, a runtime capability, or core platform behavior. Do not start by
adding a LiveView or a package.

The governing design is
[ADR-016](../decisions/016-typed-extension-packages-and-product-applications.md).

## 1. Classify the feature

Choose a **product application** when the feature:

- can be installed, disabled, or absent at a declared scope;
- has an independently versioned configuration or lifecycle;
- consumes typed platform resources;
- exposes application-specific status, configuration, or operations; and
- leaves Cadence coherent when it is unavailable.

Choose a **typed extension** when the feature is one implementation of an
existing host-owned extension point, such as:

- a transport kind;
- a provider connector;
- a catalog importer;
- a dashboard widget type; or
- a dashboard source adapter.

Choose a **capability only** when the behavior needs governed runtime execution
but no independently installable product identity. See
[Add a Capability Family](add-a-capability-family.md).

Keep identity, tenancy, activation governance, catalog infrastructure,
commanding, contact lifecycle, and other required platform authority in their
owning core contexts. Packaging is not a reason to turn them into applications.

## 2. Start in the owning domain

The owning domain defines behavior and validity before the composition catalog
publishes anything.

For a product application, add or reuse:

- domain services for reads and writes;
- an `ApplicationDefinition` in
  [`Cadence.Applications.Registry`](../../apps/cadence/lib/cadence/applications/registry.ex);
- typed action definitions and an `ActionProvider` for durable mutations;
- a versioned surface-query provider for declarative surfaces; and
- resource claims or activation preflight providers when the application owns
  scarce runtime resources.

Application provider registries remain separated by authority plane:

| Contract | Registry boundary |
| --- | --- |
| Actions | `Cadence.Applications.ActionDispatcher` in management |
| Activation preflight | `Cadence.Applications.ApplicationPreflight` in management |
| Status | `Cadence.Reads.Applications` in projections |
| Declarative surface queries | `Cadence.Reads.ApplicationSurfaces` in projections |
| Surface references | `Cadence.Reads.ApplicationSurfaces.ReferenceResolver` in projections |

Do not combine those provider modules into `ApplicationDefinition` or one
universal callback manifest. The definition declares stable contract
identifiers; each plane registers the provider that it is authorized to own.
The integrity task cross-validates the separate registries as one host contract.

For a typed extension, add a versioned definition to its owning registry. The
definition owns the extension-specific contract. The shared package envelope
does not replace it.

Current owning registries include:

| Extension | Owning registry |
| --- | --- |
| Runtime capability | `Cadence.Capabilities.DefinitionRegistry` |
| Transport kind | `Cadence.Comms.TransportKind` |
| Provider connector | `Cadence.Contacts.ProviderClients.Registry` |
| Catalog importer | `Cadence.Catalog.Registry` |
| Dashboard widget | `Cadence.Dashboards.WidgetRegistry` |
| Dashboard source adapter | `Cadence.Dashboards.DefaultSourceAdapters` |

The definition must fail closed when its stable identity, version, trust,
configuration, presentation, or behavior module is invalid.

## 3. Add one typed package contribution

Add the appropriate contribution value under
[`Cadence.Extensions`](../../apps/cadence/lib/cadence/extensions), then include
it in a compiled `ExtensionPackage` in
[`Cadence.Extensions.Registry`](../../apps/cadence/lib/cadence/extensions/registry.ex).

Keep these identities separate:

- package id and package version;
- application key and application version;
- capability family and ABI version; and
- extension definition id and definition version.

Declare every compatibility contract required by the contribution. The
composition boundary in
[`Cadence.ExtensionCatalog`](../../apps/cadence/lib/cadence/extension_catalog.ex)
must resolve the exact contributed identity and version through the owning
domain registry.

Do not add a generic callback map, arbitrary module hook, or atom derived from
operator input.

## 4. Use the host before writing UI

Product applications use the existing application host routes:

- mission applications run in the authenticated `:mission` LiveView session;
- spacecraft applications run in the authenticated `:spacecraft_show`
  LiveView session.

Those sessions already establish the browser pipeline, authenticated scope,
organization, mission, user navigation, and—at spacecraft scope—the selected
spacecraft. A package does not add routes, pipelines, `live_session` blocks, or
authentication callbacks.

Do not add an application-specific `live_action` to the generic host. If an
older product URL must remain compatible, add an authenticated permanent
redirect to the generic route and keep that historical mapping in a legacy
redirect controller. Applications without a previously shipped URL need no
route change at all.

Describe each application surface with a `SurfaceDefinition`. Prefer the
declarative renderer and a `SurfaceDocument` assembled by a host-registered
query provider. Current host primitives cover:

- summary statistics;
- generated forms;
- bounded paginated tables;
- bounded diagnostics;
- streamed activity;
- text, textarea, numeric, select, and query-backed reference inputs; and
- inline action outcomes and field failures.

The document contains presentation data, not HEEx, CSS, JavaScript, Ecto
queries, or effect callbacks. The host owns rendering, form events, table
navigation, action dispatch, and feedback.

Use a trusted renderer only when the workflow cannot be expressed without
losing essential behavior. Telemetry Decom's interactive APID claim editor is
the current example. Register the renderer explicitly in
[`CadenceWeb.ApplicationSurfaceRegistry`](../../apps/cadence_web/lib/cadence_web/application_surface_registry.ex)
and keep all mutations behind the same typed action dispatcher.

Do not broaden the surface grammar for a hypothetical future workflow. Add a
primitive only with a real application consumer and bounded validation.

If the application's standard status is materially part of an existing
cross-application workflow, declare a bounded `StatusPlacement` instead of
teaching that host about application-owned states or persistence. The initial
placement is spacecraft-scoped `:comms_validation`. It is appropriate only when
the application's readiness genuinely affects Comms setup. Set `required?: true`
when a declared but absent installation must block that host workflow.

A status placement does not carry labels, finding copy, route fragments,
renderer identities, or callbacks. The registered status provider owns the
typed status; the receiving host owns grouping, severity policy, presentation,
and navigation. Do not infer placement from a resource claim and do not opt
unrelated applications into Comms merely to gain visibility.

## 5. Keep actions and effects host-owned

An application action declares stable intent, scope, input and result contract,
required permission, execution mode, and concurrency semantics.

The host must:

1. re-resolve the exact installed application version;
2. verify the action belongs to the current surface or lifecycle contract;
3. authorize the current scope;
4. validate input;
5. dispatch through the registered domain provider; and
6. render a bounded result or `ActionFailure`.

Application renderers must not write persistence directly or perform arbitrary
external effects. Runtime and control-plane effects continue through governed
Cadence services and platform-owned executors.

## 6. Pin versions in durable records

If a durable record is interpreted by an extension later, store the exact
definition identity and version on that record.

Examples include:

- application installations pinning an application version;
- dashboard widgets pinning a widget type version;
- runtime specifications pinning capability versions; and
- catalog import runs pinning an importer version.

Queued or replayed work must re-resolve that exact version. Do not silently
interpret an old record with the latest implementation.

Configured runtime modules may remain supported where the owning domain already
allows them. Being configured or loadable does not make a module a compiled
package, grant it product visibility, or let it replace a first-party packaged
identity.

## 7. Wire discovery into an existing host surface

The UI asks `Cadence.ExtensionCatalog` what compiled contributions are
available. It does not duplicate module lists, labels, configuration fields, or
capability maps in a LiveView.

Application inventory surfaces consume
[`CadenceWeb.ApplicationInventory`](../../apps/cadence_web/lib/cadence_web/application_inventory.ex).
Use `catalog/2` for a host scope that shows every available packaged application,
and `declared/3` when a Spacecraft Profile supplies the desired application
keys. The web host first resolves contributions through `Cadence.ExtensionCatalog`,
then delegates to `Cadence.Reads.Applications.Inventory` to compose durable
installation lifecycle and the registered status provider. This preserves the
projection-to-composition dependency boundary. Unknown profile extension keys
remain visible as unavailable items instead of being dropped. Retained
installations that are no longer declared by the current profile also remain
visible and may be disabled or uninstalled; only a brand-new install requires a
profile declaration.

Inventory route shells render `CadenceWeb.ApplicationInventoryCard` and use
`CadenceWeb.ApplicationInventoryLifecycle` for install, enable, disable, and
uninstall events. Do not copy those cards or event handlers into a new host
scope. Supply the scope-specific inventory source, install-eligibility decision,
host context, and generic workspace path to the shared host behavior.

Do not load an application-owned configuration module directly from a mission
or spacecraft overview, readiness page, navigation surface, or application
inventory. Those are cross-application host surfaces: render the shared
inventory item and aggregate status. Application-owned reads remain appropriate
inside that application's registered workspace renderer or surface provider.

The owning context still validates and executes the selected definition. This
keeps composition discovery separate from domain authority.

When a new extension requires a brand-new top-level workflow rather than one
more option in an existing workflow, stop and revisit the product
classification. It may be an application instead of an extension.

## 8. Add contract and product-path tests

At minimum, prove:

- the owning definition validates;
- the package contribution resolves its exact definition and version;
- malformed definitions and unsupported versions fail closed;
- the composition catalog remains globally valid;
- durable records retain the selected version;
- the existing host UI discovers the contribution without a new route; and
- the domain execution path still authorizes and validates independently.

For declarative applications, test key DOM ids through `Phoenix.LiveViewTest`
and assert outcomes rather than raw HTML. For trusted renderers, also prove that
mutations pass through the typed action boundary.

## 9. Run the extension integrity gate

Run:

```console
mix cadence.extensions.check
```

The command validates every compiled package, dependency, compatibility
declaration, typed contribution, exact owning-registry resolution, package-id
ownership, and contribution ownership. It also proves that every declared
application action, activation preflight, status query, declarative surface
query, and reference identity has a valid plane-owned provider, with no orphaned
provider entries. It then prints the composed inventory.

Finish with:

```console
mix precommit
```

`mix precommit` includes the extension integrity check, formatting,
warnings-as-errors compilation, Credo, architecture boundaries, plane tests,
and the full default test suite.

## Checklist

- feature classified before UI work begins
- behavior and validation live in the owning domain
- stable identity and version are explicit
- exact typed contribution added to one compiled package
- compatibility contract declared
- declarative host surface used when the bounded grammar fits
- cross-application status placement declared only for a concrete host workflow
- no package-owned route, authentication, query, persistence, or side effect
- durable consumers pin the definition version
- host discovery uses `Cadence.ExtensionCatalog`
- cross-application host surfaces use `CadenceWeb.ApplicationInventory`
- owning domain revalidates before execution
- contract and real product-path tests added
- `mix cadence.extensions.check` passes
- `mix precommit` passes
