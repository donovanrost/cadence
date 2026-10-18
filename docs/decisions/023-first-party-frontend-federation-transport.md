---
title: "ADR-023: First-Party Frontend Federation Transport"
aliases:
  [frontend federation, module federation, native federation, browser application host]
tags: [adr, architecture, frontend, extensibility, module-federation, vue, vite]
status: accepted
created: 2026-08-23
updated: 2026-08-23
---

# ADR-023: First-Party Frontend Federation Transport

## Status

Accepted

The frontend proof of concept implements the release catalog, host bridge,
transport adapter, exact release validation, Module Federation remotes, shared
Vue singleton, independently built current and previous releases, and browser
failure containment described here. Production Phoenix integration, signed
release metadata, artifact publication, CDN policy, and operational rollout
remain pending.

This decision refines the trusted-renderer tier in
[ADR-016](016-typed-extension-packages-and-product-applications.md). It does not
change ADR-016's host ownership of routes, scope, authorization, actions,
side effects, or application lifecycle.

## Context

ADR-016 established host-rendered generated forms and declarative blocks as the
default presentation tiers. It also retained a trusted first-party renderer for
application workflows whose local interaction and presentation state should not
be flattened into a generic form or round-trip through LiveView for every
gesture.

As those workflows grow, compiling every trusted renderer into the Phoenix
asset bundle couples unrelated application releases to one host deployment.
Cadence needs independently built first-party browser applications while
retaining a generic authenticated host, exact installed application versions,
server-owned authority, typed queries and actions, common UI contracts, and
failure containment.

The proof of concept built the same Vue Contract Probe source as both a Module
Federation remote and a Native Federation remote. Both used the same
application manifest, release catalog, host context, query bridge, Cadence UI
package, and containment boundary.

Both transports worked, but their integration cost differed materially:

- Module Federation used the maintained Vite plugin and runtime for remote
  manifests, Vue singleton selection, exposed-module loading, and Vue style
  assets.
- Native Federation required Cadence-owned import-map bootstrapping, host Vue
  provider artifacts, production CSP nonce propagation, development dependency
  optimizer policy, separate development and production Vue providers, and a
  custom Vue style-injection adapter.

Native Federation's use of ESM, import maps, and integrity metadata is useful,
but its federation manifest, dependency negotiation, and orchestration remain a
runtime protocol. The standards-based module resolution layer did not remove
the host integration and operational ownership demonstrated by the proof of
concept.

## Decision

### 1. Module Federation Is The Supported First-Party Transport

Cadence will use Module Federation as the initial and only
production-supported transport for independently built first-party frontend
applications.

The host loads only an exact release returned by the authoritative application
catalog. A remote does not install itself, select its own version, contribute a
route, or become trusted merely because its manifest is reachable.

Module Federation is an implementation choice for transporting a trusted
renderer. It is not the application ABI, authorization boundary, installation
model, or third-party plugin system.

### 2. Application Contracts Remain Transport-Neutral

The versioned application manifest continues to declare package identity,
application and surface versions, supported scopes, host compatibility, data
contracts, and action identifiers without referring to Module Federation.

Transport-specific release metadata remains in the host-approved catalog and is
dispatched through a host-owned adapter. Its conceptual shape is:

```text
FrontendRelease
  federation
  release_id
  remote_name
  manifest_url
  exposed_module
```

The current host registers only a Module Federation adapter. Known alternative
transport values may remain representable for compatibility and evaluation,
but a release using a transport without a registered host adapter fails closed.
Application source and domain contracts must not import the federation runtime.

This boundary permits a future transport migration without changing
application identity, installation records, host queries and actions, or
surface contracts.

### 3. The Host Retains Authority And Lifecycle Ownership

Federated applications remain inside host-owned authenticated Phoenix routes.
The host resolves organization, mission, spacecraft, installation, package,
application version, surface, and operator scope before loading a renderer.

Browser applications receive a bounded host context and bridge. The bridge:

- derives operator authority from the server session rather than browser
  claims;
- exposes registered, versioned, scoped queries;
- mediates typed actions through CSRF, authorization, idempotency, validation,
  persistence, and audit boundaries; and
- returns structured failures without granting direct database, secret,
  runtime, or external-system access.

Local filtering, selection, expansion, drafts, and other ephemeral presentation
state stay in the browser. Durable, authorized, governed, runtime, or external
effects cross the host bridge.

### 4. Runtime Sharing Is Deliberately Narrow

The host and remotes share Vue as a strict singleton. Cadence design tokens,
Reka-backed UI components, the plugin SDK, and domain components are ordinary
versioned build dependencies of each application release.

Cadence will not turn the design system or domain packages into a broad runtime
share scope. Build-time copies let a release retain the component behavior it
was tested with, while the stable theme and application contracts preserve host
coherence.

### 5. Releases Are Exact, Immutable, And Independently Deployable

The application catalog selects an exact release identifier and manifest URL.
The host loads that release and then verifies that the module's application
manifest matches the approved package, application version, surface, data
contract, exposed module, and theme contract before mounting it.

Hashed assets may be cached immutably. Catalogs and federation manifests remain
refreshable control documents. A production rollout must add signed release
metadata, artifact provenance, publication policy, and rollback evidence; a
remote manifest alone is not an installation or trust assertion.

### 6. Dual Transport Support Is Not A Production Goal

The Native Federation proof established that the application and host contracts
can survive a transport change. Its runtime, build adapter, second remote, and
production server path will not remain in the active proof of concept after
this decision.

Operating two transports would double build, development, CSP, caching,
browser, dependency-sharing, and incident-response paths without a current
product requirement. Transport neutrality is preserved by contracts and the
adapter boundary, not by permanently shipping two implementations.

### 7. Third-Party Execution Remains Separate

This decision authorizes only host-approved first-party browser releases. It
does not authorize mission-uploaded JavaScript, CSS, Vue components, federation
manifests, or arbitrary browser code.

A future third-party plugin decision must define signing, compatibility,
sandboxing, WIT component boundaries, resource limits, capabilities, and UI
projection separately. Extism or another WASM runtime may be part of that
decision, but neither frontend federation transport is a security sandbox.

### 8. Revisit The Transport Only On Concrete Triggers

Cadence will reconsider the supported transport when at least one of these is
true:

- the Module Federation plugin blocks a required Vite+, Rolldown, Vue, or
  browser upgrade;
- first-party applications require materially different build systems or
  frameworks that the supported runtime cannot integrate reliably;
- production evidence shows unacceptable bootstrap, caching, failure, or
  dependency-sharing behavior;
- a standards-oriented alternative removes the custom Vue, CSS, development,
  CSP, and integrity integration demonstrated by the proof of concept; or
- a new security or artifact-verification requirement cannot be met through the
  catalog and Module Federation release pipeline.

Preference for a standards label or abstract build-tool independence is not by
itself sufficient to operate a second transport.

## Consequences

- First-party application teams receive independently built and deployable Vue
  releases without application-specific Phoenix routes.
- The host has one federation runtime, development path, CSP model, and
  operational failure surface.
- Application, surface, query, action, installation, and theme contracts remain
  independent of the selected transport.
- Vue is a runtime compatibility constraint and must be upgraded deliberately
  across host and active releases.
- Module Federation's runtime and Vite chunking behavior become pinned
  infrastructure dependencies and must be covered by browser and release
  compatibility tests.
- Native Federation's import-map integrity model is not inherited
  automatically; production artifact trust must be implemented explicitly at
  the catalog and release-publication boundary.
- Third-party execution and presentation remain deferred to a separately
  sandboxed contract.

## Alternatives Considered

### Use Native Federation As The Primary Transport

Rejected for the current Vue and Vite+ stack. The standards-oriented artifacts
were attractive, but the proof required more Cadence-owned build, host, CSP,
style, and development integration for equivalent behavior.

### Support Module Federation And Native Federation Equally

Rejected. The proof demonstrated reversibility; permanent dual operation would
convert that evidence into an ongoing compatibility matrix without a concrete
consumer.

### Compile Every First-Party Renderer Into The Host

Rejected as the only trusted-renderer model. It preserves simple runtime
loading but couples every application release and rollback to the Phoenix host
asset deployment.

### Allow Application-Owned Routes Or Direct APIs

Rejected by ADR-016. Independent frontend delivery does not transfer routing,
authentication, authorization, persistence, or side-effect ownership to an
application.

## See Also

- [ADR-007: First-Party Capability ABI](007-first-party-capability-abi.md)
- [ADR-016: Typed Extension Packages and Product Applications](016-typed-extension-packages-and-product-applications.md)
- [ADR-021: Monorepo Poncho Project and Package Layout](021-monorepo-poncho-project-and-package-layout.md)
- [Frontend federation proof of concept](../../frontend/README.md)
