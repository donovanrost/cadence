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
`corepack pnpm check` and `corepack pnpm test`, plus relevant build and browser gates for
affected boundaries. For documentation-only changes, check formatting and links. Do not run
Elixir tests for frontend-only work. Use the root project's `mix precommit` when backend or
server integration changes require it. State which checks actually ran and identify incomplete
enforcement explicitly.
