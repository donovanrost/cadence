# Frontend contribution rules

The console (`apps/console`, with the design system in `packages/apogee-ui`) is the only UI.
Read [apps/console/ARCHITECTURE.md](apps/console/ARCHITECTURE.md) before you change it, and the
UI rules in the root `CLAUDE.md`. Everything else in this workspace is legacy that is being
deleted (see [README](README.md)). Don't extend it. Delete what the console replaces.

The [frontend code standard](docs/code-standard.md) covers domain types, runtime decoding, Vue
ownership and type escapes. Don't weaken a check to fit a change.

Run frontend commands from this directory. Don't run Elixir tests for frontend-only work. Say which
checks you actually ran.

## Hand-off checks

Before a PR, run these from this directory and read each exit code. Full suites and browser tests
run in CI.

- lint, exit 0 (warnings fail too): `./node_modules/.bin/vp lint`
- formatting, exit 0: `./node_modules/.bin/vp fmt --check`
- the workspace typecheck (every project in `tsconfig.json`'s references; the console runs on its
  `tsconfig.app.json`): `node tools/typecheck-workspace.mjs`
- test:structure: `corepack pnpm -s test:structure`
- lint:structure (ast-grep over every app and package, not only the one you edited):
  `corepack pnpm -s lint:structure`
- test:tools, which includes the 400-line rule with its shrink-only `tools/file-lines-baseline.json`:
  `corepack pnpm -s test:tools`
- the tests of every project you touched: `../../node_modules/.bin/vp test --run <files>`, run from
  the project

Playwright specs (`apps/console/e2e`) run in CI. Run one locally only while writing or fixing that
spec.

Never run `corepack pnpm exec vp ...`: `pnpm exec` puts a relative `./node_modules/.bin` first on
`PATH`, and vp then can't resolve `node` ("Cannot find binary path for command 'node'"). Call
`./node_modules/.bin/vp` directly.
