# Structural checks

`pnpm lint:structure` tests the rules before scanning the workspace. The root tool test suite
also checks real `.vue` discovery, script injection, exclusions, and source locations using the
pinned CLI. Vue script injection is provided by ast-grep's HTML parser; a second custom
injection would duplicate findings.

All migration exclusions are removed. The general rules cover authored frontend code, including
Vue scripts, and exclude vendored distributions and intentional rule fixtures. Any new authored
file is checked immediately.

These structural checks supplement Vue-aware TypeScript and typed lint. They cannot establish
type relationships, runtime data admission, or lifecycle behavior.

## Typing rules A and B (typing plan §12B, lead 11-15)

`vocabulary-field-decoded-as-text` only checks fields _named_ like a vocabulary (state, kind,
reason, code…), so enum-like fields under other names slipped past it. Two rules close that gap,
each with a baseline in `migration-baselines.json` that may only shrink:

- **A, `word-map-keyed-by-text`** (ast-grep): a non-empty map typed `Record<string, …>`. Key it
  by the vocabulary's union so a renamed or misspelled key is a compile error. A map that really
  is keyed by open text (HTTP headers, a query-param bag, keyboard keys) takes
  `// keyed-by-text: <why>` on the line above; the reason is required.
- **B, `tools/decoded-text-compared.mjs`** (TypeScript checker, run by `test:structure`): an
  `===` / `!==` or `switch` case against a string literal where the compared property was decoded
  as `token` or `string`, whatever it's named. That includes decoders marked `// free-text:`:
  branching on a field contradicts the claim that it is free text. Decode it with
  `known` / `knownText` (and tell the server side if the vocabulary isn't in the contract yet). A
  comparison against genuinely open text takes `// compared-as-text: <why>` on the line above.
  Baseline: hits per file. **Limit: `.ts` files only; comparisons in Vue SFCs (script blocks and
  templates) aren't checked.**
