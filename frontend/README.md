# Cadence federated frontend PoC

This workspace proves the trusted first-party frontend application boundary with a Vue host and two
independently built Module Federation remotes:

- `apps/host` receives a host-approved release catalog and owns mission context, navigation,
  compatibility checks, HTTP query/action dispatch, loading and render-error containment, and the
  operator activity rail.
- `apps/telemetry-decom` contributes a trusted Telemetry Decom renderer. Packet filtering and draft
  selection stay client-local; saving crosses the host-owned bridge.
- `apps/contract-probe` is a deliberately small fixture on a separate release train. It proves that
  discovery, mounting, shared UI, context, and host queries are generic rather than hard-coded to
  Telemetry Decom.
- `apps/storybook` is the isolated design-system workshop. It renders the real token and UI
  packages with controls, generated documentation, accessibility checks, and Chrome-backed story
  tests without starting Phoenix or the federation host.
- `packages/plugin-sdk` defines and validates the versioned application, surface, catalog, release,
  and host-bridge contracts.
- `packages/design-tokens` owns the framework-neutral Cadence theme, typography, focus treatment,
  and semantic CSS variables inherited by host-mounted remotes.
- `packages/ui` provides Cadence-owned Vue components built on Reka UI primitives. It is a normal
  build-time dependency of each release, not another federated runtime singleton.

The existing Phoenix and LiveView assets in `apps/cadence_web/assets` remain unchanged. A
frontend-only HTTP service models the eventual authenticated Phoenix boundary: it derives actor
permissions from a server session, requires a CSRF token, validates requested scope, uses action
idempotency keys, and returns structured errors. Browser-supplied actor permissions are never used
as authority.

## Toolchain

- Vue 3 with TypeScript
- Vite+ for the Vite/Rolldown build, tests, Oxlint, Oxfmt, type-aware checks, workspace tasks, and
  package management
- `@module-federation/vite` and `@module-federation/runtime` for independently built releases
- Reka UI behind Cadence-owned component APIs for accessible checkbox and tooltip behavior
- Storybook 10 with Vue/Vite, autodocs, accessibility checks, and Vitest browser stories
- pnpm and Node managed and pinned through Vite+

The server catalog selects an exact frontend release and manifest URL. The host then verifies that
the loaded module claims the exact package, application version, surface, data contract, exposed
module, and `cadenceThemeContract` it approved. A remote manifest is a compatibility claim, not a
source of installation or authorization truth. Domain-specific components stay inside the owning
application until repeated use justifies promotion into `packages/ui`.

Vite+ is currently beta software. Vite+, Module Federation, Node, and pnpm are pinned so the PoC
does not silently move with their release channels.

## Commands

Run these commands from the `frontend` directory:

```sh
corepack pnpm install
corepack pnpm dev
corepack pnpm check
corepack pnpm test
corepack pnpm build
corepack pnpm preview
corepack pnpm storybook
corepack pnpm storybook:test
corepack pnpm storybook:build
```

The equivalent commands can be run from the worktree root with `vp -C frontend`, for example
`vp -C frontend run dev`. If `vp` is not globally installed, use the checked workspace binary:

```sh
frontend/node_modules/.bin/vp -C frontend run dev
```

`dev` runs the host on `127.0.0.1:5173`, Telemetry Decom on `127.0.0.1:4174`, and Contract Probe
on `127.0.0.1:4175`. `build` emits independently deployable artifacts, including current and
previous Telemetry Decom releases. `preview` serves those artifacts through a production-shaped
server with no-store catalogs and manifests, immutable hashed assets, explicit remote CORS, and a
restrictive host CSP. Run `build` before `preview`.

## Design-system workflow

`corepack pnpm storybook` starts the workshop at `http://127.0.0.1:6006`. It is intentionally not
part of `pnpm dev`, so token and component work does not start the three federation services and
application work does not pay for Storybook.

Edit framework-neutral foundations in `packages/design-tokens/src`. Component stories live beside
their Vue components in `packages/ui/src`, keeping states, controls, accessibility expectations,
and interaction tests owned by the component. Foundation references that are specific to the
workshop live under `apps/storybook/src`.

Every story receives the real `@cadence/design-tokens/base.css` entrypoint. Token changes therefore
refresh the foundation reference and all component states together. New public components should
include at least a playground story, meaningful edge states, and a `play` interaction for behavior
that cannot be proven by rendering alone. `storybook:test` renders all stories in installed Chrome;
`storybook:build` produces the shareable static workshop under `apps/storybook/dist`.

## Runtime proof matrix

The default URL loads the current Telemetry Decom release. These URLs exercise the other evidence:

| URL                            | Expected result                                                             |
| ------------------------------ | --------------------------------------------------------------------------- |
| `/?application=contract_probe` | Loads a second application through the same generic host path               |
| `/?release=previous`           | Pins and loads the previous Telemetry Decom production artifact             |
| `/?scenario=offline`           | Contains an unreachable approved release without losing the host shell      |
| `/?scenario=incompatible`      | Rejects an application-version mismatch before mounting                     |
| `/?scenario=throw`             | Contains an exception raised after the remote component mounts              |
| `/?scenario=malformed`         | Rejects the host catalog before loading any remote code                     |
| `/?scenario=viewer`            | Loads data but rejects configuration actions using server-owned permissions |
| `/?scenario=stale`             | Returns a structured optimistic-concurrency conflict                        |

## Federation transport decision

[ADR-023](../docs/decisions/023-first-party-frontend-federation-transport.md) selects Module
Federation as the one production-supported transport for first-party browser applications. The
earlier A/B proof established that the same Contract Probe application and host contract could be
loaded through Module Federation and Native Federation. Native Federation worked, but required
additional Cadence-owned import-map, CSP nonce, Vue provider, development optimizer, and style
injection integration for this Vue and Vite+ stack. That implementation has been retired rather
than maintained as a second operational path.

The application contract remains transport-neutral. Federation metadata belongs to the
host-approved release descriptor, and the generic loader dispatches through a host-owned adapter
registry. The current host registers only the Module Federation adapter. A known release transport
without a registered adapter is rejected before remote code is loaded. This preserves an explicit
migration seam without carrying two build and runtime stacks.

## Phoenix integration boundary

The production adapter should retain the TypeScript `HostBridge` interface while replacing the
demo service with authenticated Phoenix endpoints for catalog discovery, versioned queries, and
typed actions. The server is authoritative for `current_scope`, installations, package versions,
scope, permissions, query/action registration, validation, persistence, and audit receipts.

The application page remains in the existing authenticated `:spacecraft_show` `live_session`
because that host already owns organization, mission, spacecraft, navigation, and authorization
context. If the bridge is implemented with controller endpoints, those routes belong in a
`CadenceWeb` scope using `pipe_through [:browser, :require_authenticated_user]`: the browser
pipeline supplies the authenticated session and CSRF protection, while
`:require_authenticated_user` prevents a remote from reaching the bridge without `current_scope`.
Plugins do not contribute routes or authentication plugs.

This PoC does not add those Phoenix routes, alter Elixir code, or approve third-party browser code.
Signed release metadata, artifact integrity enforcement, CDN failover, and the separate Extism/WIT
third-party execution boundary remain ADR and productionization decisions.
