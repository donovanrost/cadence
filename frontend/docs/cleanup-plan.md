# Frontend cleanup plan

Status: complete. Batches A–G and findings 6–12 pass the frontend acceptance and publication gates.
All authored frontend owners use the shared strict compiler and unsafe-flow lint rules.
No structural migration exclusions remain. Findings 1–5 were deferred by this earlier cleanup;
their implementation and current validation are tracked in the [Vue quality follow-up](vue-quality-followup.md).

The source baseline is `a38ad3005a0fdb723167258340f21ec26c4c7cea` on
`poc/federated-application-registry`. The existing README, frontend instructions, and code
standard edits are retained. The inventory preserves the preparation snapshot; execution evidence is recorded below.

## Scope and baseline

| Finding | Work                                                                               |
| ------- | ---------------------------------------------------------------------------------- |
| 6       | Close TypeScript coverage gaps and replace imprecise domain contracts.             |
| 7       | Split the telemetry chart into typed, directly testable responsibilities.          |
| 8       | Consolidate compatibility workflows according to their actual callers.             |
| 9       | Establish one frontend acceptance command and its enforcement path.                |
| 10      | Classify lint findings, enable useful Vue rules, and make regressions blocking.    |
| 11      | Replace publication discovery's source-text parsing with shared explicit metadata. |
| 12      | Remove confirmed leftovers, stale documentation, and duplicate test execution.     |

Findings 1–5 were outside this cleanup: release-output safety, fleet-policy navigation recovery,
eager bundling, duplicate page composition, and error-boundary diagnostics. The follow-up
addresses those behaviors separately; the evidence below describes this earlier baseline.

The [preparation inventory](cleanup-inventory.json) records exact file paths and scan methods:

- 443 tracked SFCs: 424 TypeScript, 16 JavaScript, and 3 without scripts.
- 252 explicit `any` AST nodes in 37 production source files, including declaration files.
  The earlier text scan counted 250; the difference is the counting method, not new code.
- 175 of those nodes are in planning and contacts, 64 in data operations, 9 in Ops Console,
  and 4 in dashboards and exploration.
- 104 standalone JavaScript files include tests, Node tools, and application helpers.
- All 28 leaf compiler configurations enable `strict`; only the SDK currently enables both
  `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`.
- The current route catalog has 91 entries across 14 kinds.
- No checked-in CI workflow or hook configuration was found in the usual provider locations.
  A local command must not be described as an enforced CI gate until that integration exists.

The earlier frontend audit at this source commit passed `check` and `test`, with 238 lint
warnings, 1,463 tests in the Vitest/Storybook reports, and 7 skipped tests. Those are prior
baseline results; preparation does not rerun the suites or establish new runtime evidence.
The inventory is a snapshot for assigning work, not a numeric allowance for future violations.

## Execution order

| Batch                      | Findings                        | Result required before closing the batch                                                                                                 |
| -------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| A. Acceptance and lint     | 9, 10, test duplication from 12 | One frontend acceptance entry point; complete task inventory; explained lint exceptions; new actionable warnings fail.                   |
| B. Confirmed leftovers     | Remaining 12                    | Unused wrapper/constant and tracked compiler cache removed; publication and route documentation corrected.                               |
| C. Typed policy reference  | First part of 6                 | One feature demonstrates correlated actions, validated inputs/results, and explicit operation states without feature-level type escapes. |
| D. Publication metadata    | 11                              | Discovery and build configuration consume the same validated metadata; output identities remain unchanged.                               |
| E. Workflow consolidation  | 8                               | Shared behavior has one owner; supported transport differences are explicit; unused route fallback is retired with coverage.             |
| F. Remaining type coverage | 6, except chart controller      | Remaining host, UI, domain, test, and tool code is checked; strict configuration adoption is tracked by owner.                           |
| G. Chart extraction        | 7 and remaining 6               | Typed chart inputs, pure model functions, bounded rendering/lifecycle ownership, and direct behavioral tests.                            |

Run A first. B and D can follow without waiting for the larger domain refactors. C establishes
the reference for E and F. Consolidate or retire compatibility code before spending effort
typing duplicate implementations. The chart's controller conversion belongs with G, where
its responsibilities can be separated together.

### A. Acceptance and lint

Own [package.json](../package.json), [vite.config.ts](../vite.config.ts),
[typecheck-workspace.mjs](../tools/typecheck-workspace.mjs), its tests, and workspace test scripts
that invoke shared tooling suites. Add ast-grep configuration/rule fixtures and a pinned CLI
dependency here when integrating the prototype.

Provide `corepack pnpm verify` as the frontend-only acceptance command, running `check` and
`test` serially. Make package tests, root tool tests, and Phoenix transport Node tests explicit
tasks with one owner each. The old run executes the 114-test transport suite and the four-test
typecheck suite twice. Root `tools/*.test.mjs` coverage also needs an explicit owner; preserve
focused commands without invoking the same suite again in the aggregate. Inspect shared
release-output tests currently invoked by multiple application packages.

Classify the existing lint warnings before promoting rules. The baseline includes 126 floating
promise warnings, 33 control-regex warnings, and 17 unused-variable warnings. Distinguish native
Node test registration and intentional input sanitization from abandoned async work and unused
code. Use exceptions for known calls or narrowly identified code, preserving validation and
test-runner behavior. Enable available Vue rules, then reject unclassified warnings.

Integrate ast-grep rule tests and real SFC discovery/location tests first. The evaluated
`port.captured` pattern is an inventory query while both transports are supported; it becomes
a prohibition only after migration. Double-cast matches include boundary adapters and tests,
so they require classification. Prefer existing lint rules for general TypeScript/Vue policies.
Migration exceptions must identify their owner and scope, and be removed as that owner migrates.

Prove the aggregate command exits nonzero on a failed required gate and retains every test
suite exactly once. Record the actual CI/provider integration separately. Do not add Elixir
tests to this frontend acceptance path.

### B. Confirmed leftovers

The initial deletion/correction list is:

| File                                                          | Evidence and action                                                                                                                                               |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps/storybook/tsconfig.tsbuildinfo` (deleted)               | Tracked despite the existing `*.tsbuildinfo` ignore. Remove it from the repository.                                                                               |
| `apps/telemetry-decom/src/TelemetryDecomManage.vue` (deleted) | No import of this file. The live application uses `configurationContribution.component`; the identically named local binding is not a caller. Remove the wrapper. |
| [Ops Console Vite config](../apps/ops-console/vite.config.ts) | Remove its unused `publicationRoot` constant.                                                                                                                     |
| [Host architecture](host-architecture.md)                     | Correct the route count from 83 to 91, or describe the catalog without a manually maintained count.                                                               |
| [Frontend README](../README.md)                               | Correct the publication layout: the communications bundle is `comms`, and discovery includes the host plus six remotes.                                           |

Check imports/exports and relevant build configuration before deletion. Use the owning package
checks for source changes; formatting and links are sufficient for documentation-only edits.
Test duplication is owned by A.

### C. Typed policy reference

Use the existing fleet-policy example as a complete feature slice. Own the policy-related files
under [fleet-planning](../modules/planning-and-contacts/src/features/fleet-planning):
`fleet-policy.ts`, `policy-evidence.ts`, `policy-workflow-state.ts`, `policy-presentation.ts`,
`policy.contribution.ts`, `FleetPolicyContribution.vue`, `OpsFleetPlanningPolicy.vue`, its
contracts, and the corresponding policy test/support files. Keep new readers and action
adapters within this feature until another consumer establishes a shared need.

Represent completed/rejected/unconfirmed operations with discriminated unions. Connect each
of the six policy actions to its input and receipt result. Decode unknown input at the feature
adapter and preserve context, sequence, policy/grant evidence, and exact receipt matching.
Let components and workflow code consume those guarantees without `Record<string, any>`,
double casts, or `receipt!`.

Use the existing policy editing, decision, and workflow tests to preserve native payloads,
draft retention, stale evidence rejection, substituted receipt rejection, and lost-response
recovery. Add narrow type rejection cases for mismatched action/input/result and a completed
operation without a receipt. Do not change the server protocol or treat this as a fix for the
deferred navigation-recovery finding.

Introduce the shared strict compiler configuration and migrate consumers as their errors are
resolved. Track legacy projects explicitly rather than disabling stricter options across the
workspace. This pilot is complete only when its feature and consumed contracts satisfy the
standard; changing type aliases while leaving assertions in callers is insufficient.

### D. Publication metadata

Own [first-party-remote-workspace.mjs](../tools/first-party-remote-workspace.mjs), its tests,
the root publication/release tools and their contract tests, and the host plus six approved
remotes' federation/publication configs. The remote owners are `organization-admin`,
`mission-catalog`, `spacecraft`, `telemetry-decom`, `comms-overview`, and `ops-console`.

Give each publication an explicit descriptor for its remote name and bundle; keep its package
name authoritative in `package.json`. Use one checked reader from both discovery and build
configuration. Preserve required host presence, approved remote coverage, uniqueness, and
identifier validation. Test that moving or formatting TypeScript configuration no longer
changes discovery, and malformed or duplicate metadata fails before building.

Keep accepted output identities and release checks intact. Use fresh temporary output
directories for release probes. Run the frontend publication build/output checks for this
batch. General release-path hardening remains the separately tracked finding 1.

### E. Workflow consolidation

The static caller ledger shows both transport paths are wired into application code:

| Domain             | Host page caller                                                                                                                    | Ops Console remote caller                                                    | Current dispatcher                                                                                                      |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Scheduling         | [ContactScheduleContribution.vue](../modules/planning-and-contacts/src/features/contact-scheduling/ContactScheduleContribution.vue) | [contact-schedule-port.ts](../apps/ops-console/src/contact-schedule-port.ts) | [contact-schedule-state.ts](../modules/planning-and-contacts/src/features/contact-scheduling/contact-schedule-state.ts) |
| Reservation review | [ReservationContribution.vue](../modules/planning-and-contacts/src/features/contact-scheduling/ReservationContribution.vue)         | [reservation-port.ts](../apps/ops-console/src/reservation-port.ts)           | [reservation-state.ts](../modules/planning-and-contacts/src/features/contact-scheduling/reservation-state.ts)           |
| Plan review        | [PlanReviewContribution.vue](../modules/planning-and-contacts/src/features/contact-plans/PlanReviewContribution.vue)                | [plan-detail-port.ts](../apps/ops-console/src/plan-detail-port.ts)           | [plan-detail-state.ts](../modules/planning-and-contacts/src/features/contact-plans/plan-detail-state.ts)                |

[OpsConsoleApplication.vue](../apps/ops-console/src/OpsConsoleApplication.vue) constructs and
provides the remote ports. The host contribution wrappers set the `captured` capability.
This is source wiring evidence, not a newly executed browser journey.

Retain both supported transport adapters. Consolidate shared drafting, time handling,
validation, and domain decisions. Keep distinct receipt/recovery lifecycles explicit where
the protocols differ; do not synthesize server evidence to make them appear identical.
Replace flag-selected behavior with named, typed contracts as each domain migrates.
Test timestamp precision explicitly: the old schedule initialization truncates to minutes
while the captured path preserves seconds.

Use scheduling, reservation, contact-workflow, and plan-review tests plus the three remote
port suites. Cover context departure, pending effects, evidence identity, refresh/recovery,
and both entry paths. The current ordinary route kinds all have a host branch; retire
`RoutedFederationSurface.vue` only with exhaustive route handling and a contained unknown-kind
outcome. Preserve the separately used generic federation infrastructure.

### F. Remaining type coverage

Use the inventory's file lists as the ownership ledger. Work through small UI and navigation
components, then host lifecycle code and its JavaScript helpers/tests. Migrate the remaining
planning contracts, the two data-operations validators, and Ops Console adapters using C's
pattern. Check dashboard/editor components as a separate group; reserve `TelemetryChart.vue`
for G.

Native Node tools can keep `.mjs` with checked JavaScript and JSDoc. Include authored tests
and helpers in a checked project. Review the broad Vue declaration in Ops Console's `env.d.ts`
and deliberate interop separately from domain model escapes. Preserve exact command-number
text and existing validation semantics when sharing readers.

For each owner: remove type escapes through better contracts, enable the shared strictness
flags, run its focused tests, and run the frontend acceptance command at the batch boundary.
Remove migration exceptions as coverage expands. SDK-only strictness is not completion.

### G. Chart extraction

Own [TelemetryChart.vue](../modules/dashboards-and-exploration/src/features/workspace/TelemetryChart.vue),
[chart-runtime.ts](../modules/dashboards-and-exploration/src/features/workspace/chart-runtime.ts),
the workspace snapshot/presentation tests, and the
[Telemetry Chart story](../apps/storybook/src/TelemetryChart.stories.ts).

First extract typed point, envelope, and series normalization functions. Import them directly
from tests and preserve the current explicit-gap and invalid-coordinate assertions. Remove
the test's raw-source slicing and `new Function` evaluation.

Then separate live-window/sample state, uPlot rendering, overlays/selection, and lifecycle
cleanup into bounded owners. Pass typed inputs through the adapter. Preserve required DOM
selectors and action payloads after checking their consumers. Keep timers, event listeners,
observers, and chart destruction paired with their owner.

Add focused mounted/browser coverage for live appends, window trimming, selections, marker
updates, theme rebuilds, and unmount cleanup as those responsibilities move. Retain the
existing snapshot and chart-runtime tests. A smaller SFC delegating to one equally large,
unchecked controller does not close this finding.

## Validation and completion

Preparation uses static source inspection, parser-based inventories, documentation formatting,
and local link/path checks. It runs no Elixir tests and makes no new runtime claims.

For implementation, run the owning feature's tests while editing, followed by frontend
`check` and `test` (or `verify` once A adds it) for each completed batch. Use Storybook browser
coverage for UI/lifecycle changes and frontend build checks for publication changes. Report
production federation integration separately when host/transport changes require it; a
passing unit suite does not establish that journey.

Close a finding only when its listed outcome is achieved and its relevant gates pass. Record
remaining compiler/lint exceptions by owner. The cleanup is complete when all selected
findings are closed, supported callers still work, and the enforcement path prevents their
recurrence. Keep this dated inventory as historical evidence rather than updating its counts
into a growing allowance.

## Execution evidence — 2026-09-11

The entries below preserve intermediate batch results. The final verification entry supersedes
the earlier in-progress statuses and exception inventories.

- A/B/D: `corepack pnpm verify` passed: formatting, zero lint warnings, Vue-aware checks for
  20 projects, structural rule fixtures and real-SFC integration, package tests including
  Storybook, root tool tests, and Phoenix transport Node tests. The root runner explicitly
  excludes itself from recursive package execution. Shared release-output, typecheck, and
  transport suites each have one aggregate owner. Failure injection verified that `verify`
  stops at a failed gate and returns its exit status.
- D: publication identity/admission tests passed, including moved configs and malformed or
  duplicate metadata. `corepack pnpm build:publication` passed for the host plus six remotes;
  the production output checker accepted all seven bundles.
- A: lint now enables Vue rules and rejects warnings and unused suppression comments. Local
  comments explain deliberate control-character validators, mutable-collection snapshots,
  hostile fixtures, and bound cleanup ownership. Structural file exclusions are temporary
  migration scopes described in `ast-grep/README.md`, not a violation-count budget.
- G (partial): point/envelope normalizers are typed and imported directly by tests; the chart
  still needs its remaining state/rendering/lifecycle separation.
- CI: no provider integration is configured here. `verify` is the complete local gate; branch
  protection or provider-enforced status checks are not established by this change.
- No Elixir tests were run for this frontend cleanup.

- C: the six policy actions now have correlated request/result types and explicit operation
  states. Runtime readers preserve exact context, evidence, sequence, and receipt matching.
  Snapshots are readonly; forms retain their own mutable drafts. The policy project extends
  `tsconfig.strict.json` and passes indexed-access/optional-property checks. Its lint scope
  rejects explicit `any`, unsafe flows, and non-null assertions, with one explained SFC-import
  limitation covered by vue-tsc. Its structural migration exclusion is removed.
- C: 27 focused policy tests/type cases and `corepack pnpm verify` passed, including Storybook
  and transport suites. Native producer JSON fixtures now have readers rather than broad casts.
  Shared page-heading forwarding omits absent optional properties and passes the same frontend
  gates. The pending-operation navigation behavior from finding 2 remains deferred.

- E: page-snapshot and remote-query ports replace the captured flag in scheduling, reservation,
  contact-record, and plan-review callers. Schedule drafts, UTC handling, expiry clocks, review
  reason validation, and the remote review lifecycle now have shared owners. Page-ledger recovery
  remains distinct. Both scheduling entry paths preserve UTC seconds.
- E: 55 focused workflow tests, 14 remote-port tests, mounted coverage of all 91 routes and an
  unknown kind, and `corepack pnpm verify` passed. The unused routed federation fallback is
  deleted; generic federation infrastructure remains supported. The captured dispatcher
  prohibition passes rule fixtures and real Vue source-location coverage.

- F (host/UI complete): every host and shared UI Vue script now uses TypeScript. Host runtime,
  former JavaScript tests/helpers, and native Node probes are checked. Host app, build config,
  probes, and shared UI adopt the shared indexed-access/optional-property strictness. Their
  authored source and tests reject explicit `any`, non-null assertions, and unsafe flows;
  all host/UI structural migration exclusions are removed.
- F: native form and Ops-frame data have explicit host readers; fixed transport/provider form
  fields use named keys. Host callbacks decode unknown responses and guard optional callbacks
  at invocation. Native producer probes keep unknown JSON at their feature reader boundaries.
  A narrow, documented type declaration covers the one consumed LiveVue hook API because its
  published type entry point is vendor implementation source; host checks remain strict.
- F validation so far: host package tests passed (2 Node build probes, 489 Vitest tests, 2 skipped),
  shared UI passed 31 tests, affected communications passed 70 tests, and snapshot presentation
  passed 13 tests. Workspace type checking passed for 20 projects and structural rule/integration
  tests passed. These checks do not establish a production Phoenix/federation browser journey.
  Remaining domain/tool owners and the chart still belong to F/G; the cleanup is not complete.

- F (data operations complete): both native validators accept unknown input and return readonly
  snapshots. Source and historical workflow commands pair each action with its payload and
  completed result; rejected and unconfirmed outcomes have separate types. UI receipt details
  require the corresponding completed action. Mutable form drafts and fixture builders remain
  explicit. The historical reader now rejects an unconfirmed status carrying a completed receipt;
  recovery hints and lost-response recovery retain focused coverage.
- F data operations validation: 26 tests/type cases passed, and its shared strict compiler and
  unsafe-flow lint checks passed. Native producer fixture probes now decode unknown JSON.

- F (fleet contracts): directory/start/run readers now validate unknown JSON; snapshots are
  readonly, and creation/continuation/repair commands carry their own input types. Repair details
  require admitted evidence, and completed receipts distinguish continuation from a new repair.
  Native producer probes are checked JavaScript. Existing paging, pinned evidence, stale reply,
  and uncertain-outcome tests pass. Fleet unsafe-flow lint and the strict planning compiler pass.
- F (remote adapters): seven Ops Console query adapters use one unknown-envelope reader. The
  feature reader still owns payload admission. The broad Vue/JavaScript declaration shims are
  removed; Ops Console runtime TypeScript contains no explicit `any` or double assertions.
- F (in progress): every leaf workspace config now extends the shared strict configuration.
  Remaining indexed-access/optional-property errors are being resolved by owner; this config
  change alone does not establish a passing workspace gate. Planning's other domains, dashboard
  components, remaining native tools, and G remain open.

- B/F additional confirmed leftovers: the old DashboardComparisonInspector, its header, and
  DashboardComparisonRollup had no active producer or caller. The sole canvas branch always
  received null from both the snapshot adapter and its fixture, while the remote component
  registry rejects direct canvas payloads. Those components, exports, and the dead branch are
  removed rather than carrying the unused presentation protocol into the TypeScript migration.

- G: TelemetryChart now has a typed SFC boundary and separate owners for admitted sample/window
  state, uPlot, legend/tooltips, annotations, events, limits, selections, and live heartbeat timers.
  The mounted controller pairs its observers and root listener with teardown; the plot owns its
  range listener and reset timer. No JavaScript Vue scripts or chart structural exemptions remain.
- G validation: 40 workspace tests passed, including direct normalization/gap/window checks and
  mounted append, marker, selection, theme, and cleanup behavior. Two real uPlot browser stories
  passed, covering production rendering/theme rebuild and live append/trim, evidence selection,
  cross-chart cursor synchronization, and unmount subscriptions. The chart passes shared strict
  compilation and unsafe-flow lint. uPlot 1.6.32's undocumented-in-types cursor publish argument
  is isolated in chart-uplot.ts and exercised by the two-chart browser story.

- F/G boundary: `corepack pnpm verify` passed after the chart extraction: zero lint warnings,
  20 compiler projects, structural checks, all package tests (including 66 Storybook tests),
  root tools, and 114 transport Node tests. That passing result predates the coverage expansion below.
- F coverage expansion: the compiler runner now checks every authored source/test/tool against
  referenced projects, including JavaScript with checkJs. It rejects missing files, unused-config
  camouflage and disabled strictness. Eight runner tests pass, including real compiler rejection
  of both a broken Vue template and a broken JavaScript test. Seven previously excluded TypeScript
  files and the remaining JavaScript probes/tools are now included. Their newly exposed errors
  are still being repaired; the whole-workspace gate is currently incomplete.
- F dashboard follow-up: all dashboard native probes pass checked JavaScript compilation. Editor
  panels now use discriminated mutable drafts and action-specific command payloads. Layout nodes
  are admitted from unknown values, and preview maps/slots have explicit widget types. The last
  four production explicit-any sites in this module are removed, along with its structural
  double-assertion exemptions. Full dashboard tests pass (41 files, 262 tests); the migrated
  editor/chart scope passes unsafe-flow lint. Remaining test/helper lint adoption is still F work.

- F continuation (2026-09-12): every authored frontend file is now assigned to a referenced,
  strict compiler project, including standalone JavaScript tools and previously excluded app
  tests. The coverage gate rejects missing files, unchecked JavaScript, unreferenced projects,
  weakened strictness, and `noCheck`. Root tool tests pass (66 tests); the telemetry adapter
  passes nine tests. The browser harness passes its existing 114 transport tests after typing
  the timeout helpers and CDP client; its latest Chrome lifecycle changes pass 12 hardening
  tests. Compiler errors remain in browser diagnostics/scenario code and its test fixtures,
  so the expanded frontend acceptance gate is not yet passing.
- Checking the packager exposed filesystem constants imported from `node:crypto` and an
  unsupported numeric descriptor passed to `fs/promises.readFile`. Both Node API calls are
  corrected; a focused test proves descriptor-based key loading preserves caller ownership.
  This does not close the separately deferred release-output safety finding.

- F compiler coverage (2026-09-12): `corepack pnpm typecheck` now passes for all 20 referenced
  projects with the expanded source/test/tool coverage. Browser diagnostics distinguish private
  request authority from exposed, tamperable observations; CDP payload correlation comes from
  the installed browser protocol types. Unknown scenario responses and resource factories retain
  explicit admission. The host build config lists its two consumed root helpers rather than
  also compiling unrelated browser tools. No compiler exclusions were added to bypass errors.
- F browser/tool validation: browser tools pass lint with zero warnings, all 114 transport tests
  pass, and all 66 root tool tests pass. Tests now await diagnostic disposal and retain malformed
  factories, thenables, descriptor/accessor attacks, exact evidence, late events, cancellation,
  and process ownership coverage. These are Node contract/hardening tests; no production Phoenix
  browser journey or Elixir tests were run. Remaining planning contracts and unsafe-flow lint
  adoption still belong to F, so selected-findings completion is not yet claimed.

- F requirement and plan review (2026-09-12): requirement directory/detail readers, declaration,
  recurring templates, and requirement/plan operations now expose readonly admitted snapshots.
  Action maps tie each command to its input and completed result; rejected/unconfirmed operations
  expose only the data their validators establish. Both plan transports retain their own input
  envelope, while the shared query workflow carries correlated action/input tuples. Requirement
  selection, pagination, scope, timestamp, actor, lifecycle, hash, and receipt checks are retained.
  Malformed echoed requirement inputs are contained before exposing a typed operation.
- F validation after these owners: `corepack pnpm verify` passes with zero lint warnings, all
  20 compiler projects, structural rules, all package tests, 66 root tool tests, and 114 transport
  tests. Planning passes 25 files / 161 tests, including 44 requirement tests and new compiler
  rejection cases for mismatched payloads, unavailable receipts, readonly evidence, and protocol
  envelopes. Existing draft retention, lost-response recovery, and exact-evidence tests pass.
  This is frontend evidence; native producer environment branches were not driven by Elixir and
  no production Phoenix journey was run.
- F remaining: contact scheduling/record/reservation contracts and the remaining owners' unsafe
  lint adoption. Requirement and plan review now enforce unsafe-flow lint across their sources
  and tests; scoped SFC constructor exceptions remain because `vue-tsc`, rather than the lint
  type service, checks imported Vue modules. The five remaining structural exclusions still
  belong to SDK, Commanding, and Organization Admin.

## Final verification — 2026-09-12

- F is complete across host, shared UI, SDK, domain modules, application adapters, tests,
  Storybook, and native tools. Scheduling, reservation, contact-record, command-review, and
  spacecraft-commanding boundaries now admit unknown data and expose their validated states.
  Requests retain action-specific inputs and transport envelopes; reviewed evidence stays
  readonly, and editable fixtures/drafts have explicit owners. Contact recovery preserves
  recorded unconfirmed outcomes and requires matching reviewed evidence before completion.
- SDK release/catalog readers construct their returned contracts from validated values.
  Cross-language corpus tests preserve the admitted documents and exact signed payload bytes.
  Test fixtures, mounted feature ports, callbacks, and native JSON/reflection boundaries no
  longer carry implicit unsafe values through the harness. Browser diagnostic descriptor,
  accessor, thenable, cancellation, and process-ownership tests retain their behavior.
- Global lint rejects explicit `any`, unsafe flows, non-null assertions, and incomplete switches.
  Vue rules, zero-warning enforcement, and unused-suppression reporting apply across the
  workspace. All ast-grep migration exclusions are removed. SFC constructor resolution and
  bounded library interop exceptions remain documented at their use sites; `vue-tsc` checks
  SFC contracts and templates. Semantic admission, lifetime behavior, and all public-import
  boundaries still require the corresponding tests and review.
- `corepack pnpm verify` passes formatting for 1,547 files, lint for 1,419 files with no
  warnings, all 20 compiler projects, structural fixtures and real-SFC integration, 1,595
  Vitest/Storybook tests, 33 package Node tests, 66 root tool tests, and 114 transport tests.
  The 66 Storybook tests run in a real browser, including the chart lifecycle/cursor cases.
  One final rerun timed out during Chrome session startup before any story executed; an
  isolated retry and subsequent full acceptance run passed without changing tests or timeouts.
  Seven native-producer-dependent tests remain skipped because their environment fixtures
  were not provided. No Elixir tests were run to produce those fixtures.
- The host and six remotes build successfully, and the production publication checker accepts
  the complete inventory. The changed host runtime was reviewed and reproduced byte for byte
  in two pinned builds: 286,151 bytes, SHA-256
  `6516c6c54a7f191ef86bbb8e4872bb1a8653149907d9245e424121c2a8adef9a`.
  Its reviewed digest is added without changing prior digests or relaxing the output checks.
  A copied publication passed; appending one byte to its host bundle was rejected.
- `git diff --check` and local frontend Markdown links pass. All authored changes stay under
  `frontend`; generated publication bundles are ignored build output. The source baseline and
  preparation inventory remain unchanged. No commit or push was made.
- CI/provider enforcement and a production Phoenix/federation browser journey have not been
  established. Local compiler, unit, Storybook, transport, and build checks do not claim those
  results. Release-output safety, fleet-policy navigation recovery, eager bundling, duplicate
  page composition, and error-boundary diagnostics remain deferred findings 1–5.
