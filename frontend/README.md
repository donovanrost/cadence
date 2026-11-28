# Cadence frontend

The console is Cadence's UI: a Vue 3 single-page app that Phoenix serves at `/console/`.

```text
apps/console          The console (@cadence/console)
packages/apogee-ui    The design system (@cadence/apogee-ui): tokens, Ap* components, formatting
tools/                Workspace checks (typecheck, file lines, structural rules)
ast-grep/             Structural lint rules
```

How the console is built (routing, decoders, remote state, live data, words, accessibility, scale):
[apps/console/ARCHITECTURE.md](apps/console/ARCHITECTURE.md). Contribution rules and hand-off
checks: [AGENTS.md](AGENTS.md).

Everything else in this workspace is legacy UI that is being deleted (epic #209):

- the federated remotes (`apps/*` other than `console`, and `modules/*`); `apps/host` holds only
  the route catalog (`src/routes.json`) that `plugin-sdk` and `CadenceWeb.HostRoutes` still read;
- `packages/ui` and `packages/design-tokens`;
- `packages/plugin-sdk`, which the console's application surfaces (`src/features/apps`) still use
  until their replacement lands.

Don't build on them, and don't document them further.

## Toolchain

- Vue 3 with TypeScript, vue-router, Tailwind v4.
- Vite+ (`vp`) for dev, build, test, Oxlint and Oxfmt. It also pins Node and pnpm.
- Playwright with axe for the console's browser tests (`apps/console/e2e`), which run in CI.

## Commands

From `frontend/`:

```sh
corepack pnpm install
corepack pnpm --filter @cadence/console dev     # Vite on 127.0.0.1:5181; Phoenix stays the origin
corepack pnpm --filter @cadence/console build   # writes apps/cadence_web/priv/static/console/
```

Run Phoenix for your worktree, sign in at `/sign-in` and open `/console/`. The architecture doc
explains the dev setup.

The checks to run before a PR are listed in [AGENTS.md](AGENTS.md). Full suites and browser tests
run in CI.
