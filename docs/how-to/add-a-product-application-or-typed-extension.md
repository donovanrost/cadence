---
title: Add a Product Application or Typed Extension
tags: [how-to, developer, applications, extensions, packages]
status: active
created: 2026-07-26
updated: 2026-11-28
---

# Add a Product Application or Typed Extension

Use this guide when adding an operator-facing capability or one implementation
of an existing Cadence extension point.

The first decision is whether the feature is a product application, a typed
extension, a runtime capability, or core platform behavior. Do not start by
adding a screen or a package.

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
- a status provider registered in `Cadence.Reads.Applications` when the
  definition declares a `status_query_id`; and
- resource claims when the application owns scarce runtime resources.

Every application is headless: it declares no screens of its own and no actions
([DECISIONS #116](../apogee/DECISIONS.md)). The console's own screens install it, show its status and edit
its settings, and its configuration is written through its owning domain paths.

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

## 4. Build its screens in the console

An application's screens are console screens (`frontend/apps/console`), built
like every other console screen and calling `/api/v1` endpoints that call the
owning domain. A package does not add routes, pipelines, authentication, or
frontend code of its own. The console's Apps lists
(`Cadence.Reads.MissionApps`, at mission and spacecraft scope) install, disable
and uninstall it through `ApplicationInstallations` and show its status.

Writes go through the owning domain's services, which authorize the current
scope and validate input themselves. Runtime and control-plane effects continue
through governed Cadence services and platform-owned executors.

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

## 7. Platform availability is not application installation

`ApplicationDefinition.installation_policy` separates platform modules
(`:platform`) from optional product capabilities (`:optional`, the default).
Platform modules, such as the Ops Console at mission scope, are always installed
at their declared scopes and need no installation records. Telemetry Decom is an
optional installation at spacecraft scope.

Use the registry's canonical policy (`Registry.platform?/2`) for admission; do
not keep separate installation-exemption lists. Platform availability does not
bypass authentication or scope permissions. Platform installation mutations are
rejected.

The console asks `Cadence.ExtensionCatalog` what compiled contributions are
available. It does not duplicate module lists, labels, configuration fields, or
capability maps.

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
- durable records retain the selected version; and
- the domain execution path still authorizes and validates independently.

## 9. Run the extension integrity gate

Run:

```console
mix cadence.extensions.check
```

The command validates every compiled package, dependency, compatibility
declaration, typed contribution, exact owning-registry resolution, package-id
ownership, and contribution ownership. It also proves that every declared
application status query has a valid provider, with no orphaned provider
entries. It then prints the composed inventory.

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
- screens built in the console against `/api/v1`, none in the package
- no package-owned route, authentication, query, persistence, or side effect
- durable consumers pin the definition version
- discovery uses `Cadence.ExtensionCatalog`
- owning domain revalidates before execution
- contract and real product-path tests added
- `mix cadence.extensions.check` passes
- `mix precommit` passes
