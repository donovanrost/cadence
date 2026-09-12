# Structural checks

`pnpm lint:structure` tests the rules before scanning the workspace. The root tool test suite
also checks real `.vue` discovery, script injection, exclusions, and source locations using the
pinned CLI. Vue script injection is provided by ast-grep's HTML parser; a second custom
injection would duplicate findings.

All migration exclusions are removed. The rules cover authored frontend code, including
Vue scripts, and exclude vendored distributions and intentional rule fixtures. The shared UI
Heroicons Tailwind adapter is first-party code and belongs to the UI compiler and lint checks;
its SVG data remains vendored. Any new authored file is checked immediately. The historical
inventory remains in `docs/cleanup-inventory.json` and is not a violation allowance.

The `no-captured-workflow-dispatch` rule rejects the retired `port.captured` flag. Both
supported adapters now declare an explicit `page-snapshot` or `remote-query` protocol.

These structural checks supplement Vue-aware TypeScript and typed lint. They cannot establish
type relationships, runtime data admission, or lifecycle behavior.
