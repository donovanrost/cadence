# Frontend code standard

This is the agreed standard for authored frontend code: applications, domain modules,
shared packages, tests, and tools. Apply it to new code and substantive refactors. Existing
violations are migration work; their presence does not establish a convention to copy.

Types should express the rules that callers must follow. Prefer simple, readable contracts
that make invalid operations difficult to express. Phoenix remains responsible for
authorization, durable state, validation, and action execution.

## Model valid states

Use discriminated unions when available data depends on a state. Preserve the relationships
established by runtime validation in the returned type. For example, a policy outcome with a
completed receipt can be represented as:

```ts
type PolicyReceipt = Readonly<{
  receiptId: string;
  completedAt: string;
  result: PolicyApprovalResult;
}>;

type PolicyOutcome =
  | { status: "completed"; receipt: PolicyReceipt }
  | { status: "rejected"; receipt: null }
  | { status: "unconfirmed"; receipt: null };
```

`PolicyApprovalResult` is the domain-specific result type. This example describes one
operation; operations with different inputs or results need corresponding contracts.
Checking `status` must be enough to establish whether the receipt exists. Apply the same
approach to loading states, editable and submitted drafts, and available and unavailable
pages. Keep genuinely independent state independent.

Handle closed sets of states exhaustively. Adding a variant should expose consumers that
need updating. Optional properties describe optional data, rather than substituting for a
missing state model. Default values must have a domain meaning; do not invent empty objects
or successful results to satisfy a type.

## Expose precise operations

Feature APIs name supported actions and connect each action to its input and result types.
For example, `approvePolicy(input: ApprovePolicyInput): Promise<ApprovePolicyOutcome>` makes
the required evidence and possible outcomes visible to callers. A typed action map is also
appropriate where several operations share a transport.

Keep generic event names, payload dictionaries, and unknown responses at the transport
adapter. The adapter validates responses before returning domain values. Model expected
rejections and unconfirmed outcomes explicitly. Required capabilities belong in the feature's
required dependencies; a workflow that requires a navigation guard must receive one.

Use distinct, branded types when mixing values would cause a concrete error, such as resource
IDs, time units, or validated scalar command text. Construct them through validation or an
explicit conversion. A brand records a checked property; it does not confer server authority.
Keep ordinary primitives where a distinction would add no useful protection.

## Decode external data at boundaries

Network responses, persisted browser data, and remote-module exports enter as `unknown`.
Decode each value at its meaningful boundary, then pass a precise value to feature code.
Derive static types from runtime schemas or composable readers where practical, so there is
one definition of the accepted shape. The existing
[communications form readers](../modules/communications/src/shared/form-validation.ts)
illustrate inferred reader output; domain validation stays with its owning module.

Validate identity, scope, versions, bounds, and evidence relationships as well as structure.
Preserve distinctions that matter to the protocol, including exact numeric text and missing
versus null values. Do not introduce coercion or reduce existing checks during a type cleanup.

Runtime validation must establish what its return type promises. A type predicate or assertion
alone provides no runtime proof. Test malformed inputs and relationships that a structural
schema cannot establish. Domain code should not repeatedly rediscover the same shape.

## Keep Vue ownership explicit

Use TypeScript for authored application code, including `<script setup lang="ts">` in ordinary
SFCs. Components have typed props and events; typed render functions remain appropriate for
transparent UI adapters. Components compose presentation and interactions. Composables own
reactive workflows and their lifetimes. Ordinary TypeScript functions own calculations,
normalization, and validation that do not require Vue.

Expose server snapshots as readonly data and give editable drafts an explicit owner. Apply
readonly types to nested collections where needed; `Readonly<T>` is shallow. Use computed
values for derived state instead of synchronizing duplicate mutable copies.

Keep timers, subscriptions, DOM integration, and cleanup with their owner. Async work must
handle rejection and define what happens after unmount, navigation, or context replacement.
Writing `void promise` does not handle rejection. Type checking does not establish cleanup or
stale-response behavior; verify these through lifecycle tests.

Import other features and packages through their declared public APIs. Share domain behavior
when multiple supported transports need it. Give transport differences explicit contracts and
keep a caller inventory before retiring compatibility code. Extract responsibilities at useful
boundaries; moving an entire controller into a composable does not improve its ownership.

Follow the existing [host architecture](host-architecture.md) and
[design-system architecture](design-system/architecture.md) for page composition, shared UI,
and server authority.

## Keep type escapes small and visible

Ordinary feature code must be free of explicit `any`, unsafe flows from `any`, double assertions
such as `as unknown as Model`, and unexplained non-null assertions. Put unavoidable interop
assertions in small adapters. Document the guarantee that makes an assertion sound and keep
its public return type precise. Scope lint exceptions to the affected rule and code, with a
reason. Do not add file-wide suppression to make a migration pass.

Use inference for local values and deliberate types for exported contracts. Prefer `satisfies`
for checked configuration and fixtures, and `as const` for literal values. These do not replace
runtime decoding. Build valid test fixtures through typed values or builders; assertion-based
fixtures can hide incomplete contracts. Documented `@ts-expect-error` cases are appropriate
when testing that invalid programs are rejected. Avoid `@ts-ignore`.

Choose descriptive names and straightforward functions. Introduce generics when they preserve
a useful relationship or remove demonstrated duplication. Formatting belongs to the shared
formatter; readability still needs review.

## Enforce the standard

The shared compiler baseline must include:

```json
{
  "strict": true,
  "noUncheckedIndexedAccess": true,
  "exactOptionalPropertyTypes": true,
  "noUnusedLocals": true,
  "noUnusedParameters": true,
  "noFallthroughCasesInSwitch": true
}
```

All authored source must belong to a checked project, including Vue templates, tests, and
tooling. Native Node `.mjs` tools can retain that format with checked JavaScript and JSDoc.
Generated artifacts and vendored dependencies need explicit ownership and exclusions.

Enforced lint rules must cover unsafe type escapes, unhandled promises, exhaustive handling,
Vue correctness, and import boundaries. Enable supported rules in the existing toolchain and
record any remaining enforcement gaps. Intentional cases need narrow, explained exceptions.
Acceptance must reject new warnings rather than silently accumulating them.

### Structural rules and migrations

Use each tool for the information it understands:

| Concern                                                           | Tool                             |
| ----------------------------------------------------------------- | -------------------------------- |
| Valid states, correlated inputs and results, template types       | TypeScript and `vue-tsc`         |
| Unsafe type flows, promises, established Vue rules                | Existing typed lint and Vue lint |
| Cadence-specific syntax patterns and repeatable source migrations | ast-grep                         |
| Cleanup, stale responses, interaction, and server authority       | Behavioral tests                 |

Ast-grep can match source structure and offer rewrites. It does not have type, scope, or
control-flow information, so its matches cannot prove which symbol a call resolves to or
whether a workflow handles every outcome. Keep those checks with the compiler, typed lint,
and behavioral tests. [Ast-grep analysis limits](https://ast-grep.github.io/advanced/faq.html#does-ast-grep-support-some-advanced-static-analysis)

Good candidates include finding compatibility dispatches such as `port.captured`, detecting
retired API calls after their callers migrate, and restricting literal imports at declared
package boundaries. Prefer existing lint rules for general language rules when available.
Use source rewrites for mechanical changes with a known replacement; choosing a domain union,
decoder, or lifecycle owner requires design work.

Every structural rule needs valid and invalid examples, including comments, strings,
formatting variations, and legitimate adapter exceptions. A rule that checks script code
must also have a real Vue file test verifying discovery, embedded language handling, and
reported locations. Mapping `.vue` files to HTML lets ast-grep inspect embedded scripts;
this does not provide Vue template type checking.
[Language configuration](https://ast-grep.github.io/reference/sgconfig.html#languageglobs),
[rule testing](https://ast-grep.github.io/guide/test-rule)

Pin the CLI version when adding it to the workspace. First inspect existing matches, then
enable blocking rules for migrated code with explicit remaining exceptions. Do not replace
the cleanup with a growing warning allowance. Any autofix needs before-and-after fixtures,
reviewed diffs, and the relevant compiler and behavior checks.

### Acceptance checks

For frontend-only code changes, run these gates from `frontend`:

```sh
corepack pnpm verify
```

For documentation-only changes, check formatting and links. Keep Elixir tests out of
frontend-only validation. Run `mix precommit` from the repository root when backend or server
integration changes require it. CI must run the frontend gates for frontend changes,
independently of whether backend checks are selected. Production builds and federation browser
checks remain required evidence for changes that affect those boundaries; unit or Storybook
tests do not establish production federation behavior.

## Adoption status

All authored Vue, TypeScript, and JavaScript sources, tests, and tools belong to referenced
strict compiler projects, including checked indexed access and exact optional properties.
Native Node probes use checked JavaScript. The coverage gate rejects missing files, unchecked
JavaScript, unreferenced projects, and weakened compiler options. The first-party Heroicons
Tailwind adapter is checked with the shared UI package; upstream distributions remain excluded.

Typed lint rejects explicit `any`, unsafe assignments/calls/returns/member access, non-null
assertions, and incomplete switches across the workspace. Vue rules, warning rejection, and
unused-suppression reporting are enabled. Ast-grep rejects double assertions, JavaScript Vue
scripts, and retired captured-workflow dispatch; no migration exclusions remain.

Imported SFC constructors have narrow, explained lint exceptions where the lint type service
cannot resolve them; `vue-tsc` checks those registrations and their templates. The compiler and
lint cannot establish semantic evidence validation, lifetime ownership, or all public-import
boundaries. Those still require feature/architecture tests and code review. Interop assertions
remain isolated and explained, including the consumed LiveVue hook, uPlot cursor publication,
Tailwind's CommonJS export, and generic test mocks.

`corepack pnpm verify` runs formatting/lint, compiler coverage and Vue checking, structural
rules, package/browser stories, root tools, and transport tests. Each shared test suite has
one aggregate owner. CI/provider integration and a production Phoenix/federation browser
journey are separate from these local checks. `mix precommit` does not run the complete
frontend gates, and Elixir tests remain outside frontend-only acceptance.

The cleanup plan records verification and completion for findings 6–12. Findings 1–5 remain
deferred; stricter types and passing frontend checks do not close those behavior findings.

Compiler and framework references:

- [TypeScript discriminated unions](https://www.typescriptlang.org/docs/handbook/2/narrowing.html#discriminated-unions)
- [Checked indexed access](https://www.typescriptlang.org/tsconfig/noUncheckedIndexedAccess.html)
- [Exact optional properties](https://www.typescriptlang.org/tsconfig/exactOptionalPropertyTypes.html)
- [The satisfies operator](https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-9.html#the-satisfies-operator)
- [Vue Composition API with TypeScript](https://vuejs.org/guide/typescript/composition-api.html)
