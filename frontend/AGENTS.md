# Frontend contribution rules

Read and follow [the frontend code standard](docs/code-standard.md) for work in this workspace.
It defines the agreed rules for domain types, runtime decoding, Vue ownership, type escapes,
and enforcement. Its adoption section identifies existing gaps; do not copy those gaps into
new code or weaken checks to accommodate a refactor.

Keep frontend changes within the ownership boundaries in
[host architecture](docs/host-architecture.md) and
[design-system architecture](docs/design-system/architecture.md). Preserve Phoenix authority
and existing runtime validation when changing frontend contracts.

Run frontend commands from this directory. For frontend-only code changes, use
`corepack pnpm check` and `corepack pnpm test` (side worktrees only; see below), plus relevant build and browser gates for
affected boundaries. For documentation-only changes, check formatting and links. Do not run
Elixir tests for frontend-only work. Use the root project's `mix precommit` when backend or
server integration changes require it. State which checks actually ran and identify incomplete
enforcement explicitly.

## Hand-off checks and how to invoke them

Before handing off any frontend change, run these from this directory and read each exit code.
They call the binaries directly, so they are the same in a side worktree and in the shared tree:

- lint, 0 errors: `./node_modules/.bin/vp lint`
- formatting, exit 0: `./node_modules/.bin/vp fmt --check`
- the workspace type-check (every project in the root `tsconfig.json` references):
  `node tools/typecheck-workspace.mjs`
- test:structure: `./node_modules/.bin/ast-grep test --config sgconfig.yml --skip-snapshot-tests && node --test tools/structural-rules.test.mjs`
- lint:structure: `./node_modules/.bin/ast-grep test --config sgconfig.yml --skip-snapshot-tests && ./node_modules/.bin/ast-grep scan --config sgconfig.yml`
- test:tools (includes the 400-line rule, shrink-only `tools/file-lines-baseline.json`):
  `node --test tools/*.test.mjs`
- the tests of every project you touched (`../../node_modules/.bin/vp test --run` from the project)

Never use pnpm in the shared team tree (served live through Vite): no `pnpm install`, no
`pnpm exec` and no `pnpm <script>`. pnpm 11 verifies dependencies before any script and, when
`node_modules` is stale against the lockfile or a `package.json` (for example right after a pick
that changes dependencies), installs and relinks first, which rewrites the live `node_modules`.
Use pnpm only in side worktrees.

Never run `corepack pnpm exec vp ...` anywhere: `pnpm exec` puts a relative `./node_modules/.bin`
first on `PATH`, and vp cannot resolve `node` from a relative entry ("Cannot find binary path for
command 'node'").
