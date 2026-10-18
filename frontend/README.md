# Cadence frontend

This is the production Vue frontend workspace: independently built application remotes,
a Phoenix-integrated host, a shared design system, and Storybook.

```text
packages/design-tokens   Production theme and framework-neutral foundations
packages/ui              Cadence Vue components and shared CSS recipes
packages/plugin-sdk      Application and host contracts
apps/storybook           Production design-system workshop
apps/host                Federation host
apps/*                   Domain applications and the contract-probe fixture
```

The [design-system architecture](docs/design-system/architecture.md) documents ownership,
CSS integration, component APIs, and validation. All applications import the shared UI package;
Phoenix imports its styles and retains ownership of routes, authentication, and durable actions.
The visual baseline is the current production application. The diagnostic federation styling and
DaisyUI vendor have been removed.

The [frontend code standard](docs/code-standard.md) defines the agreed TypeScript, runtime
validation, Vue ownership, and enforcement rules. Its adoption section tracks the gaps between
that standard and the current workspace checks.

The [cleanup plan](docs/cleanup-plan.md) maps the selected quality findings to implementation
batches, caller inventories, and validation gates.

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

## Entry journey

The standalone Vue host starts at `/` and immediately discovers the demo catalog. It has no
application-specific routes, authentication flow, default application, or application identity
allowlist. The catalog chooses the active application and release; the Phoenix entry uses the
same host renderer with route-provided application and surface identity.

## Commands

Run these commands from the `frontend` directory:

```sh
corepack pnpm install
corepack pnpm dev
corepack pnpm verify # formatting, lint, types, structural rules, and all frontend tests
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

`dev` starts all eight services with fixed ports from [the shared service map](tools/dev-services.ts).
Each service fails if its port is occupied, so catalog URLs cannot silently drift.

| Service                 | Port |
| ----------------------- | ---- |
| Host                    | 5173 |
| Telemetry Decom         | 4174 |
| Contract Probe          | 4175 |
| Communications Overview | 4176 |
| Mission Catalog         | 4177 |
| Organization Admin      | 4178 |
| Spacecraft              | 4179 |
| Ops Console             | 4180 |

`build` emits independently deployable demo artifacts. `corepack pnpm build:publication` builds the Phoenix host plus the
six approved first-party remotes into
`apps/cadence_web/priv/static/assets/application-host/`: `host`, `organization-admin`,
`mission-catalog`, `spacecraft`, `telemetry-decom`, `comms`, and `ops-console`.
`preview` serves the host, Telemetry Decom current/previous releases, and Contract Probe demo
artifacts through a production-shaped server with no-store catalogs and manifests, immutable hashed assets, explicit remote CORS, and a
restrictive host CSP. Run `build` before `preview`.

## Continuous integration and producer fixtures

[The frontend workflow](../.github/workflows/frontend.yml) runs `verify` independently of the
Phoenix producer and federation browser job on every pull request. The jobs use the pinned
Node/pnpm toolchain, locked dependencies, PostgreSQL, and an installed Chromium browser.
Action usage follows [checkout](https://github.com/actions/checkout),
[setup-node](https://github.com/actions/setup-node), and
[setup-beam](https://github.com/erlef/setup-beam); action revisions are pinned in the workflow.
GitHub branch protection must select those status checks if merges should require them.

The ordinary frontend suite explicitly skips 29 tests whose real Phoenix fixtures are absent.
Run `corepack pnpm test:producers` with the Elixir workspace and test PostgreSQL available to
execute their [producer/consumer inventory](tools/producer-contracts.json). The gate requires
every fixture and records each consumer's execution; missing fixtures, failed producer tests,
and filtered-out consumers fail the command. No environment-dependent test counts as a pass
without executing its assertions.

## Design-system workflow

Edit tokens in `packages/design-tokens/src`, components and shared CSS in `packages/ui/src`,
and production application examples in `apps/storybook/src`. Component stories live beside their
implementations. Storybook uses the same production stylesheet as Phoenix and standalone apps.

`corepack pnpm storybook` starts the workshop at `http://127.0.0.1:6006` independently of the
federation services. `storybook:test` runs Chrome-backed accessibility and interaction checks;
`storybook:build` produces a static workshop in `apps/storybook/dist`.

The [charter](docs/design-system/charter.md) and
[operational state model](docs/design-system/operational-state-model.md) define the system's
product principles. The [architecture](docs/design-system/architecture.md) defines its implementation.

## Runtime proof matrix

At `/`, the generic host loads the first catalog application. These URLs exercise the other
evidence:

| URL                           | Expected result                                                             |
| ----------------------------- | --------------------------------------------------------------------------- |
| `/?application=<catalog-key>` | Selects a catalog application without a host allowlist                      |
| `/?release=previous`          | Requests the catalog's previous release                                     |
| `/?scenario=offline`          | Contains an unreachable release without losing the host shell               |
| `/?scenario=incompatible`     | Rejects an application-version mismatch before mounting                     |
| `/?scenario=throw`            | Contains an exception raised after the remote component mounts              |
| `/?scenario=malformed`        | Rejects the host catalog before loading any remote code                     |
| `/?scenario=viewer`           | Loads data but rejects configuration actions using server-owned permissions |
| `/?scenario=stale`            | Returns a structured optimistic-concurrency conflict                        |

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

The production host uses authenticated Phoenix catalog, query, and action endpoints.
Phoenix owns session/CSRF handling, router authorization, scoped LiveView transport, and
immutable frontend artifact delivery. Cadence core owns application registration, queries,
actions, validation, and persistence. Vue owns the shell and screen presentation.

See [frontend and web ownership](docs/host-architecture.md) for the route catalog, page
lifecycle, package boundaries, and test commands.
