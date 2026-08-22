# Test Suite Audit

This note records durable findings from the test-value and reliability audit. It
is intentionally narrower than a general architecture plan: the goal is to keep
future test pruning from hiding process, persistence, or isolation problems.

## Decisions so far

- A test earns its place by protecting an observable contract, an important
  boundary, or a costly regression. Tests that repeat implementation details or
  restate stronger coverage are deletion candidates.
- Browser coverage is outside the current audit gate. Focused tests,
  `mix precommit.affected`, and the root `mix precommit` remain the relevant
  verification layers.
- PostgreSQL sandbox noise is not harmless merely because assertions pass. Late
  database access is evidence that a process can outlive the test resource it
  depends on.
- Do not respond to database noise by wrapping ordinary `Repo` calls in
  GenServers. `Ecto.Repo` already owns its connection processes; application
  processes should exist for state, concurrency, scheduling, or failure
  boundaries.

## Architecture smell register

### A1. LiveView async work can outlive its sandbox owner

Dashboard LiveViews start asynchronous engine resolutions, and a resolution can
spawn additional source-execution workers that read persisted state. Several
tests stopped the client proxy without first closing the enqueue/termination
race, allowing workers to reach PostgreSQL after `ConnCase` stopped the sandbox
owner.

Current containment is the shared
`CadenceWeb.OpsDashboardShowLive.ViewTestSupport`: tests track every mounted
dashboard, drain active work, suspend the LiveView, wait for active async tasks,
terminate the LiveView normally, and only then allow sandbox teardown.

Desired direction:

- every test-created process tree has an explicit owner and deterministic
  shutdown;
- source workers cannot become detached from the LiveView or supervised runtime
  that started them;
- no suite-wide ownership timeout is treated as a substitute for lifecycle
  correctness.

### A2. Dashboard planning has an implicit persistence step

`Cadence.Dashboards.Engine.plan/2` and `resolve/2` call dashboard-library
resolution before planning. Resolving a reusable widget may query the database,
so a function presented as a planner is not always pure.

Desired direction is an explicit pipeline:

1. hydrate persisted references at an I/O boundary;
2. plan from a fully hydrated typed document;
3. execute source I/O;
4. materialize and validate results with pure transformations where practical.

This is a targeted seam, not evidence that all Phoenix contexts should stop
calling `Repo` directly.

Current status: the production dashboard path now enters through
`Cadence.Dashboards.Resolution`, which owns hydration and passes a typed
`ResolutionContext` into `Engine.resolve_hydrated/2`. `Engine.plan/2` and
`Engine.resolve/2` remain compatibility conveniences, so callers that use those
APIs still opt into hydration.

### A3. Global application configuration is frequently used as dependency injection

Production modules read adapter and runtime choices from application environment,
and a meaningful set of tests temporarily mutate that environment. Those tests
must be serialized and can affect already-running processes that observe the
same global configuration.

Desired direction:

- resolve stable configuration when a supervised process starts;
- pass adapters and collaborators explicitly to pure/application functions;
- use uniquely named supervised instances when a test needs a different runtime;
- reserve `Application.put_env/3` in tests for genuine application-boot behavior.

Current status: the durable-job runtime now resolves its handler map once in
`Cadence.Application`, passes an immutable runner through its supervised tree,
and supports per-instance supervisor names. Data-source job, probe, adapter,
catalog-importer, web contact, Ops-shell, credential, and simulator-provider
policies now have explicit composition inputs as well. Telemetry persistence and
archive policies are now captured at application/runtime composition boundaries
and passed explicitly through supervised consumers, reads, and data-management
jobs. Dashboard cache, invalidation, source-execution, readiness, circuit,
health/watermark, telemetry-read, and refresh policies are now captured once at
projection startup or LiveView mount and reused by ticks, facts, and async work.

### A4. The core suite was globally serialized

The `cadence` test alias previously defaulted to `--max-cases 1` because the
application owns global runtimes and a shared database sandbox. This containment
hid which tests were independently isolated and made the suite slower than its
test count alone required.

Current status: three explicit concurrent 1,803-test runs and three default runs
proved the existing async cases at `--max-cases 8`, so the artificial cap was
removed while explicit caller overrides remain supported. DataCase, RuntimeCase,
and ConfigCase modules still serialize themselves; later layer-split and runtime
namespace tranches can make additional modules honestly async.

### A5. SQL-sandbox coordination is visible in production modules

`CadenceWeb.ScopeLoader` and dashboard resolve workers contain browser-test
sandbox ownership coordination. This keeps real asynchronous execution in tests,
but it also makes test infrastructure part of the production dependency path.

Desired direction is a narrower test adapter or boundary that preserves the
production process topology without making authentication and scope loading
responsible for Ecto sandbox ownership.

Current status: the browser-only runner now switches its existing repository
owner to SQL Sandbox shared mode before starting the endpoint. Production
session, scope-loading, LiveView, and dashboard resolve code no longer carries
owner keys or calls SQL Sandbox. Authentication routes and pipelines were not
changed.

### A6. Async workflow completion and process-tree ownership are misaligned

Earlier attribution found three deterministic PostgreSQL client-exit paths after
the dashboard lifecycle cleanup. They occurred when a test had observed its
intended outcome but the responsible process tree had not yet become idle:

- the contact scheduler could emit reconciliation telemetry before its durable
  projection refresh and wakeup scheduling had completed; this path is addressed
  by the scheduler settlement tranche below;
- a command lane dispatcher scheduled a zero-delay follow-up database pass after
  reporting a successful release; this path is addressed by the command-lane
  quiescence tranche below;
- simulator traffic can already be inside the TCP ingress executor or async
  persistence projector when the producer is stopped and the global mission
  runtime is torn down; this path is addressed by the provider-ingress
  quiescence tranche below.

SQL Sandbox ownership only grants these processes access to the test
transaction. It does not establish that their asynchronous work has completed.
The longer-term direction is to align supervision, work, and database-resource
lifetimes:

- give asynchronous workflows an explicit `await_idle`, `drain`, or equivalent
  completion barrier that includes downstream work rather than only the initiating
  process mailbox;
- stop producers first, stop accepting new work, drain queued and in-flight work,
  and only then stop consumers, runtime descendants, and the sandbox owner;
- ensure a test-owned process either owns the complete descendant tree or can
  synchronously track and stop any children placed under an application runtime;
- expose queue depth, in-flight work, and persistence completion as lifecycle
  state where a subsystem needs graceful shutdown;
- prefer per-test or injected runtime supervisors and registries over global
  application supervisors when integration tests need an isolated process tree;
- use the same graceful lifecycle APIs in production shutdown, mission
  reconfiguration, and tests instead of test-only sleeps or log suppression.

The scheduler, dispatcher, and simulator integration tests should be retained.
They protect valuable boundaries and are exposing incomplete lifecycle contracts,
not merely test-runner noise.

## What the current evidence does not show

- The pure library applications are not broadly coupled to Ecto.
- Direct `Repo` use is concentrated in the main application's contexts, stores,
  projections, and persistence adapters.
- The architecture dependency check currently reports no new cross-context row,
  persistence-schema, reverse-plane, or web-boundary violations.
- Therefore, a broad repository abstraction or "database process" rewrite is not
  justified by the test failures seen so far.

## Tranche inventory and execution record

The audit work was organized as bounded tranches rather than one serial queue.
Each implementation tranche owned an explicit file set and ran in its own Git
worktree. Shared test support, Mix aliases, configuration, and this ledger
remained integration-owned unless a tranche explicitly reserved them.

### Completed wave one

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| W1 | Reproduced web LiveView owner race | `audit/web-owner` | Exposed dashboard LiveView tests; dashboard lifecycle test support only if required | None | Integrated as `c663def8` |
| W2 | Core ExUnit concurrency pilot | `audit/core-parallelism` | Root and core `mix.exs` test-argument policy only | None | Integrated as `25e4083b` |
| W3 | Dashboard source-execution layer split | `audit/dashboard-semantics` | `source_execution_semantics_test.exs` and focused sibling tests | None | Integrated as `1968f451` |

W1 starts with the reproduced `OpsDashboardLibraryLiveTest` editor mount. In a
targeted audit, its second test emitted six PostgreSQL client/owner-exit logs in
21 otherwise passing runs; the first test emitted none. The tranche must prove
the fix under repetition before broadening the lifecycle helper.

W2 first runs the existing suite with an explicit concurrent `--max-cases`
value across multiple seeds. The default cap is removed only if those runs prove
that already-async cases are actually isolated. Concurrency findings are not
permission to absorb newly exposed lifecycle defects into the Mix-policy
tranche.

W3 moves only persistence-independent engine semantics onto the existing
hydrated request boundary. The BYO credential/circuit contract remains a
database integration test.

### Completed wave two

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| T1 | Authentication and route-boundary pruning | `audit/auth-boundaries` | Web auth and feature-route test assertions only | W1 integrated | Integrated as `fb9c2237` |
| T4 | Source credential resolver consolidation | `audit/source-credentials` | Dashboard source-credential tests only | W3 integrated | Integrated as `d2dacce7` |
| T5 | Durable-job dependencies and names | `audit/jobs-dependencies` | Jobs application service, runtime children, and focused tests | Provider-ingress/durable-job settlement integrated | Integrated as `0eb0c6ab` |

### Completed wave three

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| T2a | Core pure policies | `audit/core-pure-policies` | Core data-management and commanding tests only | Wave two integrated | Integrated as `80a5461f` |
| T2b | Web early-return commands | `audit/web-early-validation` | Three focused command test groups only | Wave two integrated | Integrated as `0e4aaacd` |
| T3 | Pure web rendering | `audit/web-pure-rendering` | UI components and user-session tests only | Wave two integrated | Integrated as `7985f794` |

### Completed wave four

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| S1 | Generic async LiveView lifecycle | `audit/liveview-async-ownership` | Web test support and non-dashboard async LiveView tests | W1 integrated | Integrated as `517838d6` |
| T7 | Data-source operational policies | `audit/data-source-policies` | Provisioning, lifecycle, probe, and adapter policies | T5 integrated | Integrated as `a2ccbb81` |
| T9 | Catalog importer registry | `audit/catalog-importer-registry` | Catalog registry, consumers, and focused tests | Wave three integrated | Integrated as `8bef144a` |

### Completed wave five

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| S2 | Remove production SQL Sandbox bridge | `audit/remove-prod-sandbox-bridge` | Browser test ownership setup plus production scope/session/dashboard bridge removal | S1 integrated | Integrated as `ceacbb86` |
| T6 | Web composition dependencies | `audit/web-composition-deps` | Contact schedule LiveView dependencies and Ops shell refresh hook | S1 integrated | Integrated as `d886664d` |
| T8 | Credential and provider configuration | `audit/credentials-provider-config` | Ground-network, data-source, and simulator provider configuration | T7 integrated | Integrated as `2494648a` |

### Completed wave six

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| S3 | Telemetry persistence dependencies | `audit/telemetry-persistence-deps` | Telemetry storage/current/history and ingress/protocol archive policies | S2 integrated | Integrated as `9747a83b`; Explore follow-up `1de8d3a5` |

### Completed wave seven

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| S4 | Dashboard cache and invalidation composition | `audit/dashboard-composition` | Projection and mounted LiveView runtime policies | S3 integrated | Integrated as `cf3edcd6` |

### Completed wave eight

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| S5a | Runtime process addressability | `audit/runtime-process-addressability` | Runtime/Control namespaces and same-mission two-root proof | S3 integrated | Integrated as `0a5cb3b8` |

### Completed S5b parallel work

| ID | Tranche | Branch | Ownership | Dependency | Status |
| --- | --- | --- | --- | --- | --- |
| B1 | EventBus instance API | `audit/event-bus-instances` | EventBus plus fact facade explicit bus clients | S5a integrated | Integrated as `16c4e4d1` |
| B2 | Explicit fact publication | `audit/explicit-fact-publication` | Post-commit publishers and persistence/storage policies | B1 integrated | Integrated as `475d9ecb` |
| B3 | Non-dashboard fact consumers | `audit/non-dashboard-fact-consumers` | Control and projection consumer bus clients | B1 integrated | Integrated as `16ad656e` |
| B4 | Dashboard fact consumer | `audit/dashboard-fact-consumer-instances` | Dashboard EventBus routing and cache-client isolation | B1/S4 integrated | Integrated as `f8a0f69a` |
| A1 | Ingress archive instances | `audit/ingress-archive-instances` | Ingress archive facade/backends/writer identity | S5a integrated | Integrated as `49f27647` |
| A2 | Protocol archive instances | `audit/protocol-archive-instances` | Record archive facade/backends/writer identity | S5a integrated | Integrated as `8f954224` |
| P1 | Profiler and runtime-health instances | `audit/profiler-runtime-health-instances` | Profiler ETS/handlers/archive clients and runtime-health routing | A1/A2 integrated | Integrated as `0c9c2ae7` |
| E1 | Telemetry ETS store instances | `audit/telemetry-ets-instances` | Current-value/history facades, ETS identities, and focused tests | S3 integrated | Integrated as `57a885b7` |
| C1 | Command process owners | `audit/command-owner-instances` | Dispatch namespace, lane ownership, verifier scheduler collaborators | S5a integrated | Integrated as `17b68d71` |
| J1 | Ingress journal and path instances | `audit/ingress-journal-instances` | Journal filesystem identity plus runtime journal/archive/path collaborators | A1/S5a integrated | Integrated as `53c7118f` |
| I1 | Root resource composition | `audit/root-resource-composition` | Immutable Application/Platform/Runtime/Control/Projections wiring and two-root proof | B1-B4/A1-A2/E1/P1/C1/J1 integrated | Integrated as `287c32d3` |
| R1 | RuntimeCase non-shared Sandbox pilot | `audit/runtimecase-sandbox-pilot` | Opt-in isolated RuntimeCase setup and parallel verifier-scheduler proof | C1 integrated | Integrated as `267532cc` |

### Original independent tranche plan

- **T1 — authentication and route-boundary pruning:** retain centralized user,
  organization, and mission authorization contracts plus a representative router
  smoke; remove repeated feature-local redirects after comparison.
- **T2 — pure policy and early-return command contracts:** move data-management
  policies and command-validation branches that return before persistence into
  async unit cases.
- **T3 — pure web rendering:** remove SQL Sandbox setup from component rendering
  that only builds structs and calls `render_component/2`; consolidate static
  sign-in markup coverage after a no-sandbox proof.
- **T4 — source credential resolver consolidation:** retain persistence, audit,
  scope, rotation, and lifecycle coverage while moving adapter behavior already
  represented by a `ResolvedSourceCredential` below the repository layer.
- **T5 — durable-job dependencies and names:** replace request-time application
  environment lookup with explicit runner/worker dependencies and injectable
  runtime names.
- **T6 — web composition dependencies:** resolve provider, contact-schedule,
  Ops-refresh, and dashboard-refresh collaborators once at mount rather than
  repeatedly consulting global application configuration.
- **T7 — data-source operational policies:** make managed QuestDB provisioning,
  TSDB lifecycle, probes, and adapter selection explicit composition inputs.
- **T8 — credentials and provider configuration:** treat ground-network,
  data-source, and simulator-provider credential configuration as one tranche
  because their integration fixtures overlap.
- **T9 — catalog importer registry:** distinguish genuine boot configuration
  from request-local importer injection and keep the former in configuration
  cases.

T1 through T4 are test-value and layer corrections. T5 through T9 are
application-configuration ownership corrections. They can run concurrently only
when their file reservations do not overlap.

### Original sequential or high-conflict tranche plan

- **S1 — generic async LiveView lifecycle support:** extract reusable tracked
  view shutdown beneath dashboard-specific resolved-state assertions, then apply
  it to the remaining `start_async/3` LiveViews. This follows W1.
- **S2 — remove production SQL Sandbox coordination:** remove browser-test
  ownership concerns from `ScopeLoader`, session handling, and dashboard resolve
  workers only after W1/S1 prove lifecycle cleanup without that guard.
- **S3 — telemetry persistence dependencies:** keep storage, current-value,
  history, ingress archive, protocol archive, and affected data-management tests
  under one owner because their facades and tests overlap heavily.
- **S4 — dashboard cache and invalidation composition:** follows S3 and owns the
  resolution context, web composition boundary, cache/invalidation policy,
  source-execution options, and refresh behavior.
- **S5a — runtime process addressability:** give Runtime and Control roots,
  registries, dynamic supervisors, capability processes, and mission-runtime
  names explicit namespace values while preserving production defaults. Its
  acceptance is limited to two independent OTP roots; it does not make
  `RuntimeCase` async-safe.
- **S5b — runtime resource isolation:** separately address fact-bus routing,
  named ETS and profiler state, archive writer identities and roots, and command
  dispatch ownership. Only after those boundaries exist should one
  low-dependency `RuntimeCase` test attempt an instrumented non-shared SQL
  Sandbox pilot.

### Parallel worktree protocol

- Every worktree receives a stable, unique `MIX_TEST_PARTITION`. Test PostgreSQL
  databases, the ingress journal, and simulator DETS storage already incorporate
  that partition.
- Worker BEAMs use a bounded scheduler count so parallel compilation and test
  pools do not exhaust local CPU or PostgreSQL connections.
- Focused and repeated tests may run concurrently. Broad affected gates are
  queued, and the authoritative root `mix precommit` runs once, serially, after
  integration.
- The integration branch cherry-picks verified tranche commits. A tranche that
  needs files owned by another active tranche stops and requests a dependency or
  ownership change rather than editing across the boundary.
- Schema-changing work is rebased onto the latest integration branch before its
  final verification, even though each worktree has its own database.

### Later diagnostic backlog

- Classify the remaining explicit sleeps individually. Some manufacture time or
  poll global state and should become clocks or barriers; others intentionally
  block injected callbacks and protect concurrency behavior.
- Audit raw-HTML assertions for outcome value and selector stability. CSS class
  assertions that intentionally protect the design system should not be removed
  mechanically.
- Treat source-size warnings as candidate generators rather than automatic
  refactors. The current architecture diagnostic reports no oversized test files,
  one test function over 300 lines, and fourteen production files over 1,000
  lines.
- Snapshot environment-admin authentication policy and activation-governance
  policy in later bounded tranches. Their production reads and tests remain
  outside T6, T8, S3, S4, and S5 and should not be folded opportunistically into
  dashboard or runtime namespace work.

## Tranche log

### Dashboard lifecycle and duplicate coverage

- Replaced duplicated LiveView teardown helpers with the shared deterministic
  lifecycle helper across the dashboard test surface.
- Made that helper idempotent when a LiveView exits normally between suspend,
  termination, and resume; normal concurrent death is a completed teardown, while
  errors from a still-live process remain failures.
- Deleted 63 redundant tests in nine files while retaining stronger behavioral
  coverage at the appropriate boundary.
- The authoritative root precommit gate passed after that tranche. Its remaining
  PostgreSQL client-exit logs were attributed to the scheduler, dispatcher, and
  simulator lifecycle gaps recorded in A6.
- A later authoritative run produced one web-side PostgreSQL client exit, but an
  exact-seed trace replay passed all web tests without reproducing it. Dashboard
  containment has therefore reduced these exits, not yet proved their complete
  elimination; future occurrences still require trace attribution.

### Selection panel test-layer split

- Moved six in-memory `SelectionPanel` transformation contracts into an async
  `ExUnit.Case`; they no longer start a SQL Sandbox owner.
- Kept data-link resolution tests in `Cadence.DataCase`. A focused no-sandbox run
  proved that these apparently in-memory calls can read activations, telemetry
  catalogs, operational resources, source-state events, and historical workflow
  events through `DataLinkResolver`.
- Source-level searches for direct `Repo` usage are therefore only a candidate
  generator. A test should move below the database layer only after a no-sandbox
  run proves the complete call path is independent of persistence.

### Explicit dashboard hydration boundary

- Added a typed `HydratedResolveRequest` boundary that rejects unresolved
  library placements before dashboard planning.
- Moved persistence-backed library materialization behind
  `ResolveRequestHydrator`; `Engine.plan_hydrated/2` now consumes the typed,
  already-materialized request without performing that database step.
- Kept `Engine.plan/2` and `resolve/2` as compatibility orchestration APIs. Both
  hydrate once, and `resolve/2` no longer repeats library resolution through a
  nested call to `plan/2`.
- The pure boundary test runs in `UnitCase`; repository hydration and missing
  pinned-version fallback remain explicit `DataCase` integration tests.

### Production-path dashboard resolution

- Migrated the operational-observable scope LiveView group off the VM-global
  `:dashboard_engine_resolve_inline?` test switch. These tests now exercise the
  same `start_async/3` resolution topology used in production.
- Added a shared outcome-based wait that drains LiveView async work and verifies
  the keyed dashboard root reports an idle, resolved runtime before assertions
  continue. Copied-link dashboard reopens use the same boundary and are tracked
  for deterministic teardown.
- Removed the group's obsolete `:config` tags and inline-resolution setup. The
  modules remain synchronous because their LiveViews share an SQL Sandbox owner;
  this tranche removes global configuration coupling but does not yet prove
  database-process isolation suitable for `async: true`.
- Extended the same boundary to widget creation and lifecycle workflows. Initial
  hydration, staged create/reconfigure/remove operations, viewer reopen, and the
  stale-edit conflict reload now wait for the rendered runtime outcome while
  exercising production `start_async/3` execution.
- Migrated the remaining ordinary dashboard lifecycle, operational-observable
  rendering, frame-evidence, and source-capability timeline tests. Initial mounts
  and copied-link reopens now prove the idle-and-resolved UI outcome under the
  production async path.
- The inline-resolution switch and delayed-resolution setting have now been
  removed from production, standard tests, test support, and the browser setup.
  The replay/evidence tranche exercises production async resolution, including
  copied-link reopens through an outcome-based resolved-dashboard harness.

### Explicit dashboard resolution context and deterministic cancellation

- Added `Cadence.Dashboards.ResolutionContext` as the typed policy and dependency
  input for one mounted dashboard runtime. The web composition boundary reads
  application configuration once at mount and records explicit persistence,
  contract validation, source execution, audit, and cache choices in the socket.
- Added `Cadence.Dashboards.Resolution` as the application service that owns
  persistence-backed hydration before calling `Engine.resolve_hydrated/2`.
  `Engine` and `SourceRequestExecution` no longer discover a named runtime cache
  or cache enablement through `Application` configuration; cache use requires an
  explicit server argument.
- Dashboard refreshes now always use `start_async/3`. The production branch that
  ran resolution inline and the unconditional test-delay hook were deleted.
- Replaced the sleep-driven LiveView cancellation test with a small
  `RuntimeDecisionExecutor` contract. `RuntimeCoordinator` proves supersession
  and stale-result rejection; the executor test proves the cancel effect occurs
  before the replacement start effect. Existing LiveView tests continue to prove
  the normal production async path.
- The 23 replay and runtime-evidence LiveView tests now wait on the keyed runtime
  outcome for every dashboard open and copied-link reopen. Their focused tranche
  passes without either global timing switch.
- Browser setup no longer enables inline resolution, but browser execution was
  intentionally not part of this tranche's verification. Its SQL Sandbox owner
  bridge remains the architectural smell recorded in A5.

### Command-lane quiescence and ownership

- Added `LaneDispatcher.drain/1` as an explicit lifecycle contract. It processes
  every immediately eligible command before returning the released count and the
  reason the lane became quiescent: empty, waiting for `not_before`, or waiting
  for a release target.
- Removed both continuation mechanisms that followed a successful release. The
  command context no longer sends the owner a redundant `:dispatch` message, and
  the owner no longer schedules a zero-delay database pass; the owner continues
  synchronously until it reaches a real blocking condition.
- Lane children are transient, so reaching an empty lane and exiting normally no
  longer causes the dynamic supervisor to restart an empty dispatcher.
- The owner can now start anonymously with an injected dispatch function. Three
  async unit contracts prove full drain, future-timer cancellation, and partial
  progress on failure without a repository or SQL Sandbox owner.
- The database integration coverage now uses the production drain boundary. It
  proves priority ordering, retry after a release target appears, persisted
  release outcomes, and normal child termination without sleeps or repository
  polling.
- The pure and database dispatcher slice passed 20 consecutive in-VM repetitions
  (100 tests), and the affected gate passed with 1,801 core, 133 simulator, and
  1,727 web tests. Suite-wide gates still emitted PostgreSQL client-exit logs
  outside the clean focused dispatcher slice, with counts varying by seed, so
  exact attribution plus the contact and simulator ownership work in A6 remains
  open.

### Contact-scheduler settlement

- Added `Scheduler.await_settled/1` as the explicit completion barrier for
  asynchronous contact notifications and timer reconciliation. A successful
  barrier means prior reconciliation, synchronous contact-runtime transitions,
  durable projection refresh, and wakeup scheduling have completed; future
  wakeups may remain scheduled.
- Reconciliation telemetry now describes a completed scheduler transition. Boot,
  manual, safety, notification, and timer paths emit only after their projection
  and wakeup state has settled instead of from the middle of a handler.
- Timer and notification reconciliation now use one continuation path that
  applies the summary and schedules the next wakeup before reporting completion.
- Scheduler integration coverage uses the production barrier instead of polling
  the repository for eventual state.
- Mission-control settlement covers both the contact scheduler and its sibling
  mission-runtime reconciler. `Control.Missions.stop/1` now waits on that owner
  boundary before terminating the control tree, while the runtime case stops the
  separate data-plane mission tree before releasing the SQL Sandbox owner.
- Data-plane mission and realized-contact stops now quiesce contact paths before
  terminating supervisors. Transport runtimes reject new interactions, cancel
  their live timers, and turn already-delivered timer messages into stale no-ops
  only after any in-flight callback has returned.
- Before the change, 20 repeated scheduler-file runs produced PostgreSQL
  client-exit logs across many seeds. The final focused stress ran the scheduler,
  runtime-owner guard, and transport lifecycle contracts 51 consecutive times
  (918 tests) without a client-exit log. The broader focused contact/runtime slice
  also passed 28 tests.
- The affected gate passed. Its full core run still emitted two PostgreSQL
  client-exit logs outside the clean focused slice, consistent with the remaining
  simulator/provider ingress ownership work recorded in A6; this tranche does not
  claim those paths are resolved.
- The authoritative root `mix precommit` gate passed with 1,802 core, 26 catalog,
  295 CCSDS, 133 simulator, and 1,727 web tests. The core and web runs each
  emitted one PostgreSQL client-exit log outside the clean focused slice. Browser
  tests remained excluded by the agreed audit boundary.

### Provider-ingress quiescence

- Extended the provider-adapter ABI with an explicit quiescence boundary. The
  TCP adapter closes its listener and connected socket, synchronously stops its
  receiver, rejects later uplink delivery, and ignores stale accept results only
  after the external producer boundary is closed.
- Realized-contact quiescence now runs in a task owned by the realized-contact
  supervisor. This keeps the contact coordinator mailbox responsive so accepted
  transport events cannot deadlock by calling back through the owner while its
  path is draining.
- The path owner quiesces in producer-first order: transport runtimes, provider
  adapters, journal processing consumers, raw-archive consumers, ordered ingress
  executors, and persistence projectors. Each asynchronous stage has an explicit
  lifecycle and only reports settlement after its accepted queue and in-flight
  work are complete.
- Added a controllable persistence adapter proving projector quiescence waits for
  an operation already executing inside the persistence boundary. Journal and
  archive consumer tests now use their production settlement contracts instead
  of repository polling for the covered shutdown cases.
- The TCP integration contract observes the journal append event, immediately
  stops the realized contact, and then proves the accepted frames and telemetry
  are already durable and the runtime is gone. It no longer waits for those final
  database outcomes before requesting shutdown.
- The focused executor, projector, consumer, TCP, contact, and transport slice
  passed 21 consecutive runs (609 tests) without a PostgreSQL client-exit log.
- The simulator bootstrap, coordinator, runtime, and COP-1 integration slice also
  passed 21 consecutive runs (336 tests) without a PostgreSQL client-exit log.
- The affected gate passed with 1,803 core, 133 simulator, and 1,727 web tests.
  None of those application suites emitted a PostgreSQL client-exit log.
- The first authoritative root gate after this tranche passed with 1,803 core,
  26 catalog, 295 CCSDS, 133 simulator, and 1,727 web tests. It emitted one
  core and one web PostgreSQL client-exit log. Exact-seed tracing localized the
  core exit to the durable-job tests; the serialized web trace passed all 1,727
  tests without reproducing its concurrency-sensitive exit.

### Durable-job dispatcher settlement

- Added a dispatcher quiescence boundary that closes notification and safety
  timer ingress, lets already-started workers exit, and reports settlement only
  after the monitored worker set is empty.
- The dispatcher tests now quiesce and explicitly stop their owned supervisor
  before the shared sandbox owner is released. Observing a terminal job row is
  no longer treated as proof that the worker and dispatcher process tree has
  stopped using the database.
- The eight durable-job tests passed 101 seed permutations (808 tests) without
  a PostgreSQL client-exit log, including the permutation that reproduced two
  exits before the explicit supervisor stop was added.
- The final affected gate passed with 1,803 core, 133 simulator, and 1,727 web
  tests. Core and simulator were clean; web emitted one PostgreSQL client-exit
  log outside the focused provider-ingress and durable-job slices.
- The final authoritative root gate passed with 1,803 core, 26 catalog, 295
  CCSDS, 133 simulator, and 1,727 web tests. Only the web run emitted a
  PostgreSQL client-exit log. Browser tests remained excluded by the agreed
  audit boundary, and the remaining web owner race is not claimed as resolved.

### Batch persistence ordering

- The batch-ingress persistence test asserted values in input order after sorting
  rows by receipt time and generated sample ID. Neither field defines the input
  list's order, so the assertion failed when the same two valid rows were returned
  as `[8, 7]`.
- The contract is that both samples are persisted, not that storage-generated IDs
  preserve caller order. The test now compares the normalized value set while
  retaining the independent row-count assertions.

### Revision decision action test-layer split

- Removed the synthetic successful-action test. It injected a fake command result
  but then crossed into database-backed data-link resolution, while the stronger
  historical-workflow LiveView test already executes the real command and verifies
  persistence, URL selection, action metadata, inspector state, and canonical-read
  behavior.
- The remaining confirmation and typed-error contracts now run as an async
  `ExUnit.Case` with injected commands and no SQL Sandbox owner.

### Lifecycle event chronology regression

- The affected gate exposed a reproducible Data Operations workflow failure: an
  approved group occasionally offered Approve again instead of Start.
- Persistence returned the requested and approved events in chronological order,
  but the web presentation layer re-sorted `{DateTime, event_id}` tuples using
  raw Erlang term ordering. A `DateTime` struct is not chronologically ordered as
  a raw term, so events crossing a second boundary could be reversed.
- The presentation now sorts on Unix microseconds plus event ID. A pure async
  regression test crosses the observed second boundary and proves state,
  eligibility, latest-event selection, and audit ordering without a database.
- This is a useful example of an integration test earning its cost: repeated
  execution exposed a real projection defect, which is now pinned by a cheap unit
  test at the faulty boundary.

### Parallel wave one

- The exposed-dashboard lifecycle tranche reproduced the remaining web owner
  race before changing the tests: 16 PostgreSQL client exits in 20 executions of
  the library-to-editor case. After every dashboard mount waited for a resolved
  runtime and every exposed LiveView was tracked for deterministic shutdown, the
  same case passed 20 repetitions without an exit. The six-file slice passed 91
  total test executions without an exit and was integrated as `c663def8`.
- The core concurrency pilot ran three complete 1,803-test suites with an
  explicit `--max-cases 8`, then three complete suites after removing the
  artificial root and child Mix caps. All six passed, an explicit
  `--max-cases=1` override remained effective, and no partition-owned PostgreSQL
  or BEAM process leaked. The change was integrated as `25e4083b`.
- Fourteen dashboard source-execution semantics now use the typed hydrated
  request boundary in an async `UnitCase`. The one BYO credential/circuit
  contract remains a `DataCase` integration test. The unit file passed without a
  sandbox owner, the retained database case passed, and all 876 dashboard-domain
  tests passed. The tranche was integrated as `1968f451`; its commit hook also
  passed the full affected core, simulator, and web suites.
- The post-merge affected task passed formatting, compile, Credo, workspace,
  extension, and architecture checks but skipped application tests because the
  cherry-picked files were already committed. Post-merge wave verification must
  therefore run explicit application suites rather than relying on affected-file
  discovery alone.
- The explicit merged suites passed: 1,803 core tests at `max_cases: 16` in 41.0
  seconds and 1,727 web tests at `max_cases: 16` in 52.0 seconds. Browser tests
  remained excluded, and neither suite emitted a PostgreSQL owner/client-exit
  log.

### Parallel wave two

- Authentication behavior is now concentrated at its actual boundaries. Thirty
  feature-test files dropped repeated sign-in, organization-membership, and
  mission-membership assertions while retaining their feature contracts. The
  central user, organization, and mission authorization files plus a new direct
  plug contract passed 19 tests, and all 29 changed LiveView files passed 140
  tests. The three plug cases run as plain async ExUnit without starting a SQL
  Sandbox owner. The tranche was integrated as `fb9c2237`.
- Dashboard source-credential coverage now separates three async compatibility
  contracts from twelve database-backed persistence, audit, scope, rotation,
  and lifecycle contracts. The focused credential/secrets group passed 23 tests;
  the consolidation removed ten redundant cases and 364 net lines. The tranche
  was integrated as `d2dacce7`.
- Durable jobs now receive an immutable handler snapshot at application
  composition, and the runner is propagated through the supervisor, dispatcher,
  and worker tree. The jobs supervisor, dispatcher, and worker supervisor can be
  named per runtime or left anonymous, so integration tests no longer mutate
  global handler configuration. Two async runner contracts and eight retained
  database/runtime contracts passed twice; the pre-change full repository gate
  passed, and the final removal of two unused fallback paths was rechecked by the
  ten focused tests. The tranche was integrated as `0eb0c6ab`.
- The explicit post-merge suites passed: 1,795 core tests at `max_cases: 16`
  with seed 148058 and 1,696 web tests at `max_cases: 16` with seed 558817.
  Browser tests remained excluded, and neither merged suite emitted a PostgreSQL
  owner/client-exit log.

### Parallel wave three

- Four data-management policy contracts, one correction-request validation, and
  the empty command-verifier clauses now run in six async UnitCase tests without
  a SQL Sandbox owner. The invalid direct-command case remained database-backed
  because its failure path first reads mission, source-endpoint, activation, and
  runtime-plan state. The 25 retained core integration cases passed, and the
  tranche was integrated as `80a5461f`.
- Ten web command-validation cases now run as plain async ExUnit contracts. They
  cover missing or blank group, run, job, event, decision, execution-mode, and
  observation identities plus unsupported recovery and execution modes. Eleven
  persistence, audit, transition, and no-write outcome cases remain in their
  original ConnCase files. Both groups passed and were integrated as `0e4aaacd`.
- All twelve user-menu component contracts now render from in-memory assigns in
  plain async ExUnit and use LazyHTML selectors instead of raw-markup matching.
  The five sign-in tests remain in ConnCase because they intentionally cover the
  routed endpoint, browser pipeline, auth layout, form action, and LiveView
  change event; their assertions now use element selectors. Both focused files
  passed and were integrated as `7985f794`.
- One worker full-gate attempt completed static checks but was interrupted before
  test results, and its redundant rerun was deliberately stopped. No worker
  claims an authoritative full gate for this wave; post-merge application suites
  and the final root precommit own that evidence.
- The explicit post-merge suites passed: 1,796 core tests with seed 996340 and
  1,696 web tests with seed 596180, both at `max_cases: 16`. Browser tests
  remained excluded, and neither suite emitted a PostgreSQL owner/client-exit
  log.

### Parallel wave four

- A generic `AsyncLiveViewTestSupport` now owns deterministic shutdown for
  exercised non-dashboard LiveViews that start asynchronous work. The existing
  dashboard support delegates lifecycle cleanup to it while retaining its
  dashboard-resolved assertion. Five contact, provider, and fleet-planning
  files adopted the shared support. Their pre-change slice did not reproduce an
  owner exit, but the post-change slice passed 21 repetitions (525 tests) with
  an empty runtime log. The tranche was integrated as `517838d6`.
- Catalog importer selection now accepts an immutable registry through the
  catalog application service and queued-run boundary. Core tests use a local
  fake registration and web tests exercise the built-in YAML importer instead
  of mutating application configuration. Production boot configuration remains
  the compatibility default. The focused catalog suite passed 27 tests and the
  tranche was integrated as `8bef144a`.
- Managed QuestDB provisioning and TSDB lifecycle workers now execute with
  policies captured when the application composes the durable-job runner.
  QuestDB probes and data-source adapter selection accept explicit policies,
  with documented public compatibility entry points retaining application
  configuration defaults. Ordinary focused tests no longer rewrite those four
  configuration families. The affected core slice passed 88 tests and the
  data-source LiveView slice passed 6 tests. The tranche was integrated as
  `a2ccbb81`.
- The explicit post-merge suites passed: 27 catalog tests with seed 389924,
  1,796 core tests with seed 691966, and 1,696 web tests with seed 512184, all at
  `max_cases: 16`. Browser tests remained excluded, and neither the core nor web
  suite emitted a PostgreSQL owner/client-exit log.

### Parallel wave five

- The browser-only rendered-viewport runner now switches its existing Repo
  owner to SQL Sandbox shared mode before starting the endpoint. Production
  session, scope-loading, plug, LiveView, and dashboard resolve code no longer
  carries owner keys or calls SQL Sandbox. The focused slice passed 29 tests,
  the non-browser web suite passed 1,691 tests, and the browser support module
  compiled without launching browser execution. The tranche was integrated as
  `ceacbb86`; no router scope or pipeline changed.
- Contact scheduling callbacks, asynchronous work, and polling now share one
  `LiveDeps` snapshot captured at mount. Ops-shell context refreshes share one
  hook-owned `ContextDeps` snapshot across ticks. Routine tests inject those
  snapshots directly, while narrow boot-configuration compatibility contracts
  remain. Focused tests passed 11 contact/hook cases and 4 direct dashboard
  refresh-consumer cases; the non-browser web suite passed 1,699 tests. The
  tranche was integrated as `d886664d`.
- Ground-network and data-source credential resolution now accepts explicit
  configuration options; provider LiveViews capture their configured options at
  mount. The simulator captures auth, HTTP, store, and default-path settings at
  application startup and passes them to its Router and Orchestrator. The
  five-application warnings-as-errors compile passed along with 42 core, 28
  simulator, and 12 web focused tests. The tranche was integrated as
  `2494648a`.
- The explicit post-merge suites passed: 1,796 core tests with seed 545675, 136
  simulator tests with seed 746523, and 1,694 web tests with seed 448957, all at
  `max_cases: 16`. Browser tests remained excluded, and none emitted a
  PostgreSQL owner/client-exit log.

### Sequential wave six

- Telemetry current-value, history, storage, ingress-archive, and protocol-
  archive choices are represented by immutable policies. `Cadence.Application`
  captures the production policies once and passes them through the runtime
  supervision tree and durable data-management handler. Compatibility arities
  still read application configuration for callers that deliberately exercise
  that boundary; ordinary persistence, read, archive, runtime-consumer, and
  data-management tests now supply policies explicitly. The focused tranche
  passed 126 tests and its full core suite passed 1,796 tests before integration.
  It was integrated as `9747a83b`.
- The first merged web gate found one missed fixture boundary: Telemetry Explore
  persisted rehearsal samples through a compatibility default while querying a
  source-specific history view. The fixture now uses one explicit Postgres
  persistence/read policy and no longer mutates `:telemetry_storage`. Its
  focused rerun passed and the follow-up was integrated as `1de8d3a5`.
- The explicit post-merge suites passed: 1,796 core tests with seed 889701, 136
  simulator tests with seed 29713, and 1,694 non-browser web tests with seed
  971686, all at `max_cases: 8`. Browser tests remained excluded, and none
  emitted a PostgreSQL owner/client-exit log.

### Sequential wave seven

- Added one immutable `RuntimeComposition` snapshot for dashboard cache clients
  and timeouts, invalidation, source execution/readiness/circuit behavior,
  health and watermark visibility/recording, data-source persistence, and
  telemetry read policies. Projections capture it at supervisor startup and
  mounted LiveViews retain it across asynchronous resolves, live ticks, chart
  appends, and invalidation decisions. Public compatibility constructors remain
  at configuration boundaries.
- The named catalog, limits, source-health, telemetry-storage, frame-evidence,
  replay, cache, and invalidation fixtures now inject policy or use captured
  runtime state. The only retained mutation in the audited family is the narrow
  `LiveRefresh.default_refresh_ms/1` compatibility contract. Browser paths were
  not changed or executed.
- Focused verification included 868 core dashboard tests, 25 projection/startup
  cases, and the affected LiveView policy/evidence groups. Final-code
  authoritative runs on `_dashboard_composition` passed 1,798 core tests with
  seed 43307 and 1,694 non-browser web tests with seed 97211. The tranche was
  integrated as `cf3edcd6`.

### Sequential wave eight

- Added immutable `Cadence.Runtime.ProcessNamespace` and
  `Cadence.Control.ProcessNamespace` values. Runtime/Control roots, registries,
  mission supervisors, capability registry, mission/contact/path/transport
  children, and direct lookup/lifecycle APIs now accept explicit addresses;
  compatibility arities retain the exact production names.
- A standalone non-Sandbox acceptance test starts two Runtime/Control root
  pairs with identical mission, contact, path, and transport identities while
  disabling persistence, recovery, facts, scheduling, and shared resources. It
  proves every addressed process differs, stops the alpha roots, and verifies
  bravo remains alive and operational. Twenty-one repeated runs (42 tests)
  passed, along with 92 affected Runtime/Control/architecture tests, the
  no-start Control/Data plane gates, and two full core seeds.
- The authoritative `_runtime_addressability` run passed 1,798 core tests with
  seed 309771. After integrating S4 and S5a together, `_s4s5root` passed 1,800
  core tests with seed 446046 and 1,694 non-browser web tests with seed 229657.
  The tranche was integrated as `0a5cb3b8`. RuntimeCase remains synchronous:
  fact routing, ETS/profiler state, archives/journal roots, command ownership,
  SQL ownership, and global teardown are explicitly deferred to S5b.

### S5b parallel resource isolation

- `Cadence.Platform.EventBus` and each fact facade now accept an explicit bus
  server while preserving the production registered-name arities. Independent
  buses isolate subscriptions, publication, delivery mode, monitors, and
  pre-notification behavior. The focused bus test passed 255 executions across
  51 consecutive repeats, and the full core suite passed 1,805 tests with seed
  481920. The tranche was integrated as `16c4e4d1`.
- Ingress archive policies now carry the filesystem writer name, stable instance
  identity, root, and repository through every facade/backend operation. Two
  instances accepted identical mission and evidence IDs while independently
  flushing, fetching, resetting, stopping, and retaining files, rows, and
  statistics. The isolation proof passed 25 repetitions; the full core suite
  passed 1,802 tests with seed 926531. The tranche was integrated as
  `49f27647`.
- Protocol record archive policies now provide the same explicit writer,
  identity, root, and repository boundary. Instance-qualified index identities
  allow identical packet and transfer-frame IDs without changing default legacy
  rows. The two-instance proof passed across 20 seeds; the full core suite passed
  1,803 tests with seed 654805. The tranche was integrated as `8f954224`.
- The merged EventBus and two archive slices passed 1,810 core tests on the
  `_archives_root` partition with seed 717233.
- Control contact/runtime and projection domain/runtime/telemetry consumers now
  capture an explicit EventBus at initialization while retaining their existing
  module-name and default-bus boundaries. One two-set lifecycle scenario covers
  all five consumers across independent buses, stop, restart, and survivor
  continuity; it passed 20 same-VM repetitions at seed 220019. The full core
  suite passed 1,811 tests with seed 57657, and the tranche was integrated as
  `16ad656e`.
- Profiler instances now own anonymous ETS tables, unique query-handler routes,
  and explicit ingress/protocol archive policies. Runtime-health instances own
  unique handler identities and metadata routes. The same-mission two-instance
  proof covers distinct counters, database timings, archive statistics,
  targeted resets, handler routing, owner shutdown, and survivor operation; it
  passed seeds 41001 through 41020. The full core suite passed 1,811 tests with
  seed 180837, and the tranche was integrated as `0c9c2ae7`.
- Post-commit publishers now accept an explicit EventBus, including nested
  runtime and telemetry-storage policies, while compatibility arities preserve
  the production bus. The two-bus proof tags deliveries through independent
  forwarding processes, so publishing to the wrong bus fails the positive
  assertion; it passed 20 repetitions at seed 699147. The directly affected
  slice passed 151 tests with seed 778563, and the full core suite passed 1,810
  tests with seed 442028. The tranche was integrated as `475d9ecb`.
- The dashboard runtime fact consumer now captures its EventBus at
  initialization and routes all five fact subscriptions through that instance.
  A two-bus/two-cache lifecycle proof covers plan, source-result, and frame
  invalidation before and after stopping and restarting one consumer while the
  other remains monitored and operational. It passed 21 executions, the focused
  cache/fact/invalidation slice passed 85 tests with seed 56381, and the full
  core suite passed 1,812 tests with seed 603721. The tranche was integrated as
  `f8a0f69a`.
- Current-value and history ETS backends now receive explicit child, process,
  data-table, and configuration-table identities through captured facade
  policies. Option-aware callbacks keep instance routing separate from semantic
  operation options while legacy optionless backends retain compatibility. The
  same-identity two-store proof covers distinct current values, history
  retention limits, targeted reset, stop, restart, and survivor continuity; it
  passed 21 executions at seed 27001. The focused store slice passed 23 tests
  with seed 27002, and the final full core suite passed 1,812 tests with seed
  27003. The tranche was integrated as `57a885b7`.
- Command dispatch roots now own explicit supervisor, registry, lane-supervisor,
  dispatcher, and verifier-scheduler addresses. Dispatchers capture their lane
  and query collaborators, and verifier schedulers expose a deterministic
  bootstrap gate plus instance telemetry metadata. The same-identity two-root
  proof exercises lanes and verifier timers across alpha shutdown and bravo
  continuity; it passed 21 executions on the final source at seed 379976. The
  focused command-owner slice passed 11 tests with seed 346607, and the final
  full core suite passed 1,814 tests with seed 519659. The tranche was integrated
  as `17b68d71`.
- Ingress journal configuration is now a captured policy split between
  filesystem and processing-consumer options. Path coordinators retain that
  policy and the archive-consumer policy from initialization, so event and
  quiescence paths no longer re-read application configuration. A same-identity
  two-runtime proof uses independent journal/archive roots, drains through the
  production quiescence boundary, and verifies different bytes under identical
  derived evidence IDs after alpha shutdown. It passed 21 executions at seed 0;
  the focused four-file slice passed 19 tests with seed 19, and the full core
  suite passed 1,818 tests with seed 193979. The tranche was integrated as
  `53c7118f`.
- One immutable `Cadence.Platform.RootComposition` now captures the identities,
  policies, and child configuration passed through Platform, Runtime, Control,
  and Projections. Composed EventBus and mission-runtime starts no longer let a
  later application-environment mutation override their captured policy. The
  two-root lifecycle proof exercises archives, journal, ETS stores, facts,
  commands, scheduling, dashboard cache, alpha shutdown, and bravo continuity.
  The focused integration matrix passed 61 tests and the five-application suite
  passed 3,979 tests. The tranche was integrated as `287c32d3`.
- `Cadence.RuntimeCase` now has an opt-in `isolated: true` mode with a non-shared
  SQL Sandbox owner and no global runtime teardown. The verifier-scheduler pilot
  overlaps two owners and two gated schedulers using identical database IDs,
  rolls the first owner back before the second writes, and terminates its
  coordination barrier after each pair. The overlap proof passed 202 tests over
  101 repetitions at seed 424242; the full core suite passed 1,823 tests at seed
  619233. The tranche was integrated as `267532cc`. This is a bounded pilot, not
  evidence that every RuntimeCase module is safe to mark async.
- After both final tranches were merged, their combined focused matrix passed 31
  tests with seed 860819 on the `_audit_final` partition.
- The first integrated root gate cleared every functional and architecture
  check through strict Credo, which then surfaced 26 accumulated style findings.
  Alias cleanup stayed mechanical in core and web tests, while the three
  production refactors only grouped managed-application initialization state
  and extracted dashboard cache/circuit composition helpers. Scoped suites
  passed 66 core tests, 9 web tests, and 53 production-focused tests. The
  cleanup was integrated as `88365142`, `f7e228c4`, and `e7c09266`.
- The next root gate exposed one remaining ownership leak: no-start data-plane
  runtimes still called the default registered Profiler. Root composition now
  routes its captured profiler through mission, partition, path, provider, and
  persistence-projector owners. Bounded replay explicitly selects `:disabled`,
  whose nested instrumentation is a true no-op; an alternate-profiler contract
  proves persistence measurements reach only the selected instance. The
  no-start data-plane gate passed 33 tests, the focused ownership matrix passed
  21 tests, and the full core suite passed 1,829 tests. The correction was
  integrated as `64e50f2c`.
- The final authoritative root `mix precommit` passed on `_audit_final`: all
  five projects compiled with warnings as errors; strict Credo found no issues
  across 2,725 files; workspace, extension-host, and architecture checks
  passed; management, control, data, and projections plane gates passed 5, 2,
  33, and 2 tests; and the application suites passed 1,829 core, 27 catalog,
  295 CCSDS, 136 simulator, and 1,694 non-browser web tests. Browser tests were
  intentionally excluded. No router scope or pipeline changed because the
  audit affected test ownership and runtime composition, not authentication or
  route placement.

### Post-audit RuntimeCase and DataCase profile

The initial follow-up profile on 2026-08-19 found 32 `RuntimeCase` files with
184 tests and 85 `DataCase` files with 364 tests. Two scheduler modules used the
isolated async `RuntimeCase` pilot, one `DataCase` module was async, and the
other 114 modules were explicitly synchronous. The five web `DataCase` files
accounted for only nine tests and about 0.1 to 0.2 seconds, so the useful
optimization surface was in the core application.

Three normal-concurrency runs used seeds 424242, 1001, and 2002 with
`max_cases: 8`, `ERL_FLAGS='+S 4:4'`, and the dedicated
`_runtime_data_profile` partition. The selected `RuntimeCase` group was stable
at 10.6 to 11.0 seconds inside ExUnit, including 8.2 to 8.5 seconds in the
serialized phase. The core `DataCase` group was stable at 8.9 to 9.4 seconds,
including 5.7 to 6.0 seconds in the serialized phase.

The normal-concurrency module profile for seed 424242 reported these leading
`RuntimeCase` modules:

| Module | Tests | Wall time |
| --- | ---: | ---: |
| `Cadence.Reads.MissionEventsTest` | 7 | 2,596 ms |
| `Cadence.Runtime.ContactRuntimeTest` | 6 | 2,481 ms |
| `Cadence.CommandingVerifierSchedulerTest` | 4 | 802 ms |
| `Cadence.Applications.TelemetryDecomTest` | 21 | 615 ms |
| `Cadence.Contacts.ProviderReservationReconcilerTest` | 7 | 402 ms |
| `Cadence.Runtime.ManagedApplicationRuntimeTest` | 2 | 279 ms |
| `Cadence.Runtime.TCPSocketProviderTest` | 3 | 234 ms |
| `Cadence.Dashboards.DataLinkResolverTest` | 10 | 178 ms |

`MissionEventsTest` and `ContactRuntimeTest` alone account for about 62 percent
of the serialized `RuntimeCase` window. Both exercise the downlink combiner
through a live realized-contact runtime. The contact-runtime case owns the
runtime and persistence contract; the mission-events file is a mixed-layer
module in which one test reaches that full runtime to prove the downstream
read projection while its other six tests protect database projection and read
contracts. `TelemetryDecomTest` is another mixed-layer candidate: most of its
21 cases protect persisted configuration and compilation behavior, while a
smaller set exercises live runtime refresh.

The same profile reported these leading core `DataCase` modules:

| Module | Tests | Wall time |
| --- | ---: | ---: |
| `Cadence.DataSources.ProbeSchedulerTest` | 5 | 1,079 ms |
| `Cadence.Platform.FactPublicationIsolationTest` | 2 | 857 ms |
| `Cadence.Contacts.ProviderChangeApprovalsTest` | 9 | 287 ms |
| `Cadence.ReplayTest` | 5 | 231 ms |
| `Cadence.Applications.PacketBindingsTest` | 4 | 204 ms |
| `Cadence.Telemetry.Storage.ObservationIdentityStatesTest` | 15 | 155 ms |
| `Cadence.GroundNetworks.ProviderEventProcessorTest` | 5 | 147 ms |
| `Cadence.ContactPlanning.FleetPlannerTest` | 6 | 146 ms |

The first two modules account for about 32 percent of the serialized
`DataCase` window. Their cost is primarily timing control rather than database
work. `ProbeSchedulerTest` performs five sequential default-duration negative
receives and one intentionally injected 500 ms timeout. The fact-publication
isolation test performs eight sequential default-duration negative receives
after asynchronous publication. These should become deterministic mailbox or
delivery barriers before attempting broad SQL concurrency.

`mix test --slowest-modules` was useful only as a secondary check because it
forces trace mode and `max_cases: 1`. That mode cannot run the two scheduler
isolation peers, which deliberately rendezvous as concurrent modules, and its
database timings varied substantially by order. The rankings above instead
come from a temporary formatter that measured module start-to-finish time while
preserving normal concurrency; the formatter was removed after profiling.

The recommended follow-up order is:

1. Replace the probe-scheduler and fact-publication quiet-period waits with
   deterministic completion barriers while preserving the negative-delivery
   contracts.
2. Split mixed-layer `RuntimeCase` modules, beginning with mission-event reads
   and telemetry decom configuration, so only tests that own live runtime
   behavior pay for and serialize on `RuntimeCase`.
3. Move the database-only `RuntimeCase` cohort onto non-shared `DataCase`
   owners, then convert ordinary row/store/read `DataCase` modules to async in
   bounded domain cohorts with repeated collision and owner-lifecycle checks.
4. Treat genuinely runtime-owning modules such as contact runtime, TCP ingress,
   managed applications, and mission coordination as the later isolation
   tranche. They should use explicit composed roots rather than being marked
   async against the default global runtime.

### Deterministic wait cleanup and first async DataCase cohort

The first follow-up tranche removed timing cost without deleting coverage:

- Probe scheduling is synchronous at the `run_once/1` boundary, so skipped-source
  assertions now inspect the completed caller mailbox instead of waiting 100 ms
  for each of five messages that can no longer be sent. The one real timeout
  contract remains: its slow probe blocks until the task supervisor kills it,
  and the injected timeout is 100 ms rather than a two-second sleep behind a
  500 ms timeout.
- The fact-publication test now uses the EventBus's supported synchronous test
  delivery with two independent GenServer forwarders. Expected facts retain
  their bus-origin tags, wrong-bus delivery is still asserted absent, and the
  publication call itself is the deterministic completion boundary.
- Both files now use async `DataCase` owners. They have disjoint database
  identities, explicitly owned child processes, and no competing async user of
  the fact test's ETS instance.

The focused module profile fell from 1,936 ms to 272 ms, an 86 percent
reduction. The two-file synchronous stress passed 707 tests over 101 executions;
the async cohort plus the pre-existing async mission-timeline `DataCase` passed
909 tests over 101 executions. Across the same seeds used for the baseline, the
complete 355-test core `DataCase` group fell from 8.9 to 9.4 seconds to 6.7 to
7.1 seconds, and its serialized phase fell from 5.7 to 6.0 seconds to 3.5 to
3.9 seconds. The complete 1,829-test core suite then passed seeds 424242, 1001,
and 2002 in 44.2, 42.5, and 33.8 seconds. Those broader timings retain enough
seed-dependent runtime and external-retry variation that this tranche claims
the isolated DataCase reduction, not a fixed whole-suite reduction.

### RuntimeCase layer correction and replay-timer cleanup

The next RuntimeCase tranche removed two unrelated live-runtime costs while
preserving the owner-level contracts:

- The mission-events downlink case now begins at the committed-record boundary.
  It projects explicit `CombinedDownlinkRecord` and `DownlinkDiagnostic` values,
  persists the four mission-event rows, and asserts their read order and selected
  path. `ContactRuntimeTest` remains the live proof that duplicate observations
  are combined and all three record families are persisted. The EventBus
  consumer-isolation scenario now also publishes `DownlinkRecordsPersisted` and
  proves that the selected projection consumer receives combined records and
  diagnostics, preserving the post-commit handoff that the lowered read test no
  longer owns.
- The live combiner fixture used a 25 ms heartbeat interval while advancing a
  replay clock by 10 and 15 seconds. Each observation therefore processed and
  persisted hundreds of unrelated heartbeat timer cycles before testing the
  combiner. Its heartbeat interval is now 60 seconds, beyond the fixture's
  observation window. The separate contact-runtime timer case retains its 25 ms
  interval and still proves scheduled, fired, canceled, paused, resumed, and
  persisted timer behavior.

The focused mission-events module fell from 2,596 ms to 372 ms. The combiner
case fell from about 2,410 ms to 83 ms on the first isolated run and 14 to 22 ms
on four subsequent executions; before the correction, repeated runs were 2.4
seconds and one reached 13.0 seconds while processing the replay-timer backlog.
The three affected runtime/consumer files passed 1,414 tests over 101
executions at seed 424242.

Across the same three normal-concurrency seeds as the baseline, the complete
184-test RuntimeCase cohort fell from 10.6 to 11.0 seconds to 5.6 to 6.1 seconds.
Its serialized phase fell from 8.2 to 8.5 seconds to 3.4 to 3.6 seconds. This is
a direct cohort measurement; trace-mode module rankings remain unsuitable for
the scheduler overlap pair and materially inflate database-heavy module times.

### Telemetry Decom layer split

The Telemetry Decom module mixed persisted configuration and compilation
contracts with governed activation and live mission-runtime refresh. Its 21
tests are now split without deleting coverage:

- Thirteen configuration, revision-reader, conflict, request-preflight, and
  apply-preflight tests use an async `DataCase`. They stop at database-backed
  application boundaries and neither execute an activation nor own a mission
  runtime.
- Eight governed-apply and post-apply reconfiguration tests remain in a
  synchronous `RuntimeCase`. They execute approved activations, refresh the
  mission coordinator, or assert behavior after a live apply.
- The catalog, spacecraft, source-endpoint, qualification, and user-scope setup
  is shared through a test fixture module. The two layers use different
  organization and mission identities, so their concurrent setup cannot alias.

The combined focused run passed all 21 tests in 1.0 seconds, with 0.7 seconds
of async work and 0.3 seconds of serialized work. The async database cohort
passed 2,222 tests over 101 executions, and the runtime half passed 808 tests
over 101 executions. Both used seed 424242 and dedicated database partitions.

After the split, the 32-file RuntimeCase cohort contains 171 tests. Its three
normal-concurrency runs passed in 5.7, 6.3, and 6.1 seconds, with 3.4 to 3.6
seconds serialized. The 81-file core DataCase cohort contains 368 tests and
passed in 8.5, 8.3, and 9.2 seconds. Moving the database-heavy setup into the
async phase increases that cohort's standalone work, while the RuntimeCase
critical path remains defined by other live-runtime modules. This tranche is
therefore an ownership and future-concurrency correction, not a claimed
standalone cohort speedup.

The final root `mix precommit` passed on the `_telemetry_decom_final`
partition: warnings-as-errors compilation, strict Credo, workspace and
architecture checks, all four plane checks, 1,829 core tests, 27 catalog tests,
295 CCSDS tests, 136 simulator tests, and 1,694 non-browser web tests. Browser
tests remained intentionally excluded.

### Telemetry Decom fixture capability split

The first layer split still gave every Telemetry Decom revision the strongest
possible fixture: catalog import, mission-model approval, semantic execution,
and qualification-case registration. Production tracing showed three distinct
capabilities instead:

- Configuration, APID projection, and preflight compilation need an imported
  revision and its generated runtime plans, but do not inspect approval or
  qualification state.
- Mission apply reaches mission-model promotion, which requires an approved
  revision and a passing qualification comparison.
- Dependency evaluation, missing-revision behavior, and APID conflict listing
  need no catalog revision. Conflict rows treat revision and endpoint IDs as
  opaque values at that storage boundary.

The shared fixture now exposes those capabilities explicitly as
`setup_spacecraft!/2`, `setup_imported_mission!/2`,
`setup_qualified_mission!/2`, `persist_imported_revision!/3`, and
`persist_qualified_revision!/3`. Of the 13 DataCase tests, two use the qualified
path, eight use the imported path, and three create no revision. All eight
RuntimeCase tests retain a qualified initial revision; the one secondary
revision that is only reconfigured uses the imported path.

Qualification cases are mission-scoped, so the qualified fixture intentionally
assumes one qualified packet schema per test mission. A future test that needs
multiple incompatible qualified schemas must use separate mission identities
or explicitly manage the shared qualification corpus.

The focused 21-test slice passed in 0.9 seconds, split between 0.6 seconds of
async work and 0.3 seconds of serialized work. The DataCase file passed 1,313
tests over 101 executions, its four-module async overlap cohort passed 2,222
tests over 101 executions, and the RuntimeCase file passed 808 tests over 101
executions, all at seed 424242.

The normal-concurrency RuntimeCase cohort passed its three seeds in 5.5, 5.2,
and 5.5 seconds, with 3.1 to 3.2 seconds serialized, improving on the prior 5.7
to 6.3 second range. DataCase passed in 11.7, 7.9, and 6.9 seconds; the 11.7
second result was an unrelated serialized-phase outlier, and an exact seed
424242 rerun passed in 7.1 seconds. These measurements support the bounded
fixture reduction, while retaining the audit's existing warning that broader
DataCase timing remains order- and load-sensitive.

The final root `mix precommit` passed on the `_telemetry_fixture_final`
partition: warnings-as-errors compilation, strict Credo, workspace and
architecture checks, all four plane checks, 1,829 core tests, 27 catalog tests,
295 CCSDS tests, 136 simulator tests, and 1,694 non-browser web tests. Browser
tests remained intentionally excluded.

### ConnCase profile and first low-contention cohort

The next normal-concurrency profile found 134 `CadenceWeb.ConnCase` modules and
435 tests, all synchronous. At seed 424242 and `max_cases: 8`, the selected
cohort passed in 44.2 seconds. A second run with the temporary module formatter
passed in 45.1 seconds and attributed 40.0 seconds directly to module
start-to-finish time. The formatter was removed after profiling.

The leading modules were:

| Module | Tests | Wall time |
| --- | ---: | ---: |
| `CadenceWeb.OpsDashboardShowLive.RuntimeTransportEvidenceLiveTest` | 5 | 5,476 ms |
| `CadenceWeb.AdminLiveTest` | 14 | 2,770 ms |
| `CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeLiveTest` | 3 | 1,737 ms |
| `CadenceWeb.ControlPlaneApiTest` | 6 | 1,318 ms |
| `CadenceWeb.SpacecraftTelemetryDecomLiveTest` | 14 | 1,002 ms |
| `CadenceWeb.ControlPlaneMissionDataApiTest` | 3 | 918 ms |

The first retained cohort is intentionally low-contention:

- Eight files under the LiveView test tree never mount a LiveView. Five exercise
  authentication, scope, or notification hooks directly, and three exercise
  database-backed dashboard command modules. They now use async `DataCase`
  owners instead of `ConnCase`.
- Four controller modules and the user-menu plug module execute requests in the
  test process and now use async `ConnCase` owners. The sign-in LiveView is
  database-free and is also async.
- The stale `:config` tags were removed from the scope-loader and user-session
  controller tests; neither mutates application configuration after the A5
  sandbox bridge removal.

The resulting 53-test cohort passed 5,353 tests over 101 executions at seed
424242, with no sandbox-owner exits or cross-test failures. The web inventory is
now 126 `ConnCase` modules: six async and 120 synchronous. The eight corrected
files join the web `DataCase` inventory as async database tests.

A later full-web run exposed a separate 60-second ownership boundary even
though all assertions passed. The default `Cadence.Control.MissionRecovery`
timer fired while a synchronous `ConnCase` had placed the Repo under a shared
owner, borrowed that transaction, and was still querying when the owner exited.
The test boot composition now disables the unrelated periodic recovery child;
tests of recovery and multi-root behavior continue to start explicit recovery
instances. Production retains the supervisor's existing enabled-by-default
behavior.

A broader CRUD/read LiveView experiment was correctness-clean but was rejected
on performance evidence. Twenty-seven async `ConnCase` modules grew from 2.29
seconds of serialized module work in the baseline profile to 5.41 seconds of
module wall time when allowed to compete freely for PostgreSQL. All 149 tests
still passed 15,049 tests over 101 executions, demonstrating that correctness
and throughput were separate questions.

An ExUnit resource-group experiment serialized the repository-owning async
modules while allowing them to overlap database-free work. It removed the
direct contention spike, but an exact three-seed full-web A/B remained worse and
more variable overall: the committed baseline passed in 56.5, 59.5, and 52.3
seconds, while the grouped experiment passed in 51.7, 62.7, and 64.6 seconds.
The group and broad conversion were therefore removed rather than claiming a
one-seed win.

The next web tranche should target the cost inside the remaining serialized
modules, beginning with the dashboard transport-evidence and operational-scope
outliers, before attempting another blanket async conversion. Control-plane API
tests also retain destructive table reset and global fact-consumer coupling;
those ownership seams should be removed before those modules become async.

### Dashboard evidence journey reduction

The two leading serialized dashboard modules were dominated by one composite
scenario each, not by their ordinary LiveView cases. Stage timing attributed
the replay transport scenario's roughly 5.0 seconds across seven follow-on
evidence stages. The source-endpoint command-queue scenario mounted and
resolved about two dozen dashboards while walking related links, copy links,
reopened routes, and back links through the same record graph.

Those graph walks repeated contracts already owned by the focused data-link
resolver tests for command requests, queue entries, release attempts, verifier
instances, transport actions, capability records, operational events, and
their related links. The web tests now retain the boundaries that only the web
layer can prove:

- the operational-observable widget renders the scoped record and exposes its
  evidence action;
- the evidence inspector resolves the expected reference;
- selecting the reference hydrates the data-link inspector with the selected
  realm, source, binding, time mode, and scope;
- the copied URL reopens the same resolved record and displays its identifying
  fields.

The repeated cross-record traversal stages were deleted, along with fixture
records that existed only to feed them. This removed 8,600 lines and added
seven lines of deterministic view cleanup. The affected eight-test web slice
passed in 1.7 seconds, compared with 7.2 seconds of attributed module time in
the baseline profile. Its two retained boundary scenarios passed 202 tests over
101 executions at seed 424242. The 30 focused core resolver tests also passed.

After this tranche, the complete 126-file ConnCase cohort contains 403 tests
and passed at seed 424242 in 41.1 seconds, with 4.8 seconds of async work and
36.2 seconds of serialized work. The original profile contained 435 tests and
passed in 44.2 seconds; the intervening layer correction moved 32 tests out of
ConnCase, so that cohort comparison includes both the ownership and journey
reductions rather than attributing the full difference to this tranche alone.

The final root `mix precommit` passed: warnings-as-errors compilation, strict
Credo over 2,716 source files, workspace and architecture checks, all four
plane checks, 1,829 core tests, 27 catalog tests, 295 CCSDS tests, 136 simulator
tests, and 1,694 non-browser web tests. Browser tests remained intentionally
excluded.

### Environment-admin boot policy and runtime authentication

The next serialized outlier exposed a production ownership problem rather than
an intrinsically expensive LiveView. Every `AdminLiveTest` case mutated the
process-global environment-admin configuration, reconciled a special principal,
and truncated the organization graph before exercising otherwise ordinary
platform-admin behavior. Production sign-in and session validation also reread
that mutable application configuration, so boot input remained an ambient
runtime dependency after it had already been persisted.

Environment-admin configuration is now captured once as an immutable, redacted
boot policy. Application startup passes that policy explicitly into
reconciliation. After reconciliation, active user, credential, lifecycle, and
session rows are the runtime authentication truth; sign-in and session
validation no longer consult application configuration. The zero-arity
configuration APIs remain as compatibility boundaries, while application-owned
startup and tests use the explicit policy API.

The tests now follow the same ownership split:

- policy parsing and secret redaction are database-free `UnitCase` tests;
- account reconciliation uses async sandboxed `DataCase` tests with explicit
  policies rather than global configuration mutation;
- the browser-shell boundary explicitly reconciles the environment admin when
  it is testing boot-provisioned authentication; and
- general admin LiveView tests issue a session for a durable platform-admin
  principal, without reconciling an environment administrator or truncating
  unrelated control-plane state.

The isolated 14-test admin module passed in 0.7 seconds, down from 2.77 seconds
of attributed module time in the baseline profile. The 27 browser-shell/admin
tests passed in 1.0 second, and an 85-test authentication/admin consumer slice
passed in 0.8 seconds. The browser boundary passed 2,727 tests over 101
executions and the policy/account boundary passed 2,222 tests over 101
executions, with no failures.

This is deliberately not recorded as a suite-wide timing claim. The complete
403-test ConnCase cohort passed at the same seed in 45.2 seconds, versus 41.1
seconds in the preceding run, demonstrating the variance elsewhere in that
cohort. The useful evidence is that a slow, uniform setup path revealed and
removed ambient configuration, destructive reset, and mixed authentication/UI
responsibilities.

The final root `mix precommit` passed: warnings-as-errors compilation, strict
Credo over 2,718 source files, workspace and architecture checks, all four
plane checks, 1,832 core tests, 27 catalog tests, 295 CCSDS tests, 136 simulator
tests, and 1,694 non-browser web tests. Browser tests remained intentionally
excluded.

### Remaining slow-design inventory and parallel reservations

The remaining inventory uses slow tests as design evidence rather than treating
wall-clock reduction as the objective. Trace profiles force `max_cases: 1`, so
their timings rank serialized ownership cost but do not predict normal-suite
throughput. On isolated worktree partitions the current serialized families
passed 212 ConfigCase tests across 31 files in 46.9 seconds, 166 RuntimeCase
tests across 30 files in 11.1 seconds, 355 DataCase tests across 82 core and web
files in 9.7 seconds, and 426 non-control-plane ConnCase tests across 132 files
in 42.4 seconds.

The ranked remaining design seams are:

| Rank | Area | Evidence and likely design seam | First bounded slice |
| ---: | --- | --- | --- |
| 1 | Control-plane API ownership | Nine tests occupy 2,414 lines, recreate the same graph after `TRUNCATE organizations CASCADE`, and mix auth, catalog, contact runtime, ingress, commanding, and read-projection owners. | Extract database-only authenticated API contracts into async modules; retain only explicitly owned runtime workflows. |
| 2 | Data-source persistence ownership | `DataSourcesTest` and `DataSourcesBindingHistoryTest` contributed 10.17 and 7.70 seconds of serialized trace work without mutating application configuration. | Move binding history from ConfigCase to private async DataCase before splitting the broader lifecycle module. |
| 3 | Read models classified as runtimes | Mission events, operational events, observable families, and Postgres current values mostly persist, rebuild, and read rows while paying RuntimeCase global teardown. | Move row-backed cases to async DataCase; isolate only the durable-job rebuild owner. |
| 4 | Telemetry ingress persistence | A 2.66-second ConfigCase/runtime module combines database persistence, archive policy, and filesystem lifecycle. | Split explicit Postgres policy contracts from owned archive integration. |
| 5 | Cache policy/default clients | A 2.31-second runtime ConfigCase mixes anonymous composed caches, global invalidation compatibility, and a quiet-period assertion. | Separate local client behavior from the default global compatibility boundary. |
| 6 | Command-dispatch retry ownership | One wall-clock retry case accounts for about 3.12 seconds and relies on registered dispatcher lifecycle and timer passage. | Expose a deterministic trigger/settled boundary for an explicitly named dispatcher while preserving default arities. |
| 7 | Contact-scheduler boot policy | Setup mutates VM-global scheduler configuration even though most cases use names, process namespaces, and `await_settled/1`. | Capture immutable scheduler policy and retain one serialized default-boot compatibility test. |
| 8 | Ordinary store and LiveView ownership | Eighty-two DataCase files remain serialized; non-dashboard ConnCase leaders may still hide unowned tasks, subscriptions, or runtime lookups. | Convert one domain store cohort at a time, then use the existing deterministic LiveView lifecycle support on a small clean cohort. |

Three Herdr worktrees reserve the first collision-free slices:

- `audit/control-plane-api-ownership`, partition `_cpapi_w1`, owns only
  `control_plane_api_test.exs` and new auth/contact controller-test files;
- `audit/mission-data-api-ownership`, partition `_missionapi_w2`, owns only
  `control_plane_mission_data_api_test.exs` and a new catalog controller-test
  file; and
- `audit/remaining-slow-design`, partition `_slowdesign_w3`, owns only
  `data_sources_binding_history_test.exs` for its first implementation.

Shared `ConnCase` support, `ControlPlaneApiFixtures`, router/controllers,
production EventBus and root composition, `config/test.exs`, and this audit
document remain integration-owned. The API routes remain under the existing
`/api` scope with `[:api, :authenticated_api]`: these endpoints require service
bearer authentication and `current_scope`, and no router change is indicated.

All three reservations produced bounded changes and were integrated. The
control-plane file was split into an async authentication contract, an async
contact-configuration contract, and three explicitly runtime-owned workflows
(`87247ac4`). The mission-data file yielded an async catalog/import contract
while retaining its two runtime workflows (`41b66b4f`). Binding-history coverage
now uses async `DataCase` rather than serialized `ConfigCase` (`e8961bb1`); its
12-test file passed 101 repetitions, and the combined 28-test data-source cohort
passed after integration.

Integration stress exposed one issue hidden by the former destructive reset:
the retained runtime API workflow failed on its second execution with
`{:generation_conflict, 1}` because `ConnCase` owned SQL rollback but did not own
the runtime processes created by the request. `Cadence.RuntimeTestSupport` now
defines the shared default-runtime preparation and cleanup boundary used by
both `RuntimeCase` and runtime-tagged `ConnCase`. With that lifecycle in place,
the final `TRUNCATE organizations CASCADE` reset and its helper were deleted.
The three-workflow API file then passed 63 tests over 21 executions, the
two-workflow mission-data file passed 42 tests over 21 executions without the
truncate, and the broader runtime gates passed 209 core and 5 web tests. This
is the intended diagnostic outcome: the slow tests revealed two independently
owned resources, not merely an opportunity to shorten setup.

### Process-owned persistence wave

The next three reservations addressed ranks 2 through 4 in parallel, with a
separate review pass before integration. That review was important: individually
green tests still hid a timed child-process owner, process-global fact consumers,
and PostgreSQL keys that would have serialized nominally async modules.

The data-source lifecycle tranche split one 16-test `ConfigCase` module into
three async `DataCase` modules: two lifecycle contracts, seven probe contracts,
and seven credential/BYO contracts. The probe tests own anonymous synchronous
event buses and prove that capability materialization and source-health facts are
published through the selected bus. Production capability materialization now
propagates an explicitly supplied `:event_bus` into its nested persistence call;
callers that omit the option retain the application-global compatibility
fallback. Each async module uses a distinct organization and mission identity so
unique-index locking cannot silently serialize their sandbox transactions. The
combined three-module overlap gate passed 1,616 tests across 101 executions with
`--max-cases 3`.

The read-model tranche moved 33 row-backed contracts into four async `DataCase`
modules. Activation and source-binding paths use explicit non-delivering event
bus targets, and mission-event projection is performed by the sandbox owner.
Three genuine integrations remain in a synchronous `RuntimeCase` sibling:
contact/limit projection through the application fact consumer, managed-action
projection through the mission runtime, and durable job-queue rebuild. The four
async modules passed 3,333 tests across 101 executions, and the 60-test neighbor
cohort passed after the reviewer-requested ownership corrections.

The telemetry-ingress tranche split nine contracts by resource owner. Three
explicit Postgres-policy contracts are async `DataCase`; configured public-arity
compatibility and filesystem archive writers remain synchronous `ConfigCase`;
four state-carrying archive, retry, and TM-reassembly contracts remain
`RuntimeCase`. Anonymous event buses capture the complete synchronous delivery
policy. The async module passed 303 tests across 101 executions, and the complete
nine-test cohort passed. Keeping the filesystem test in `ConfigCase` is
intentional: its timed writer GenServers must share the SQL sandbox owner even
when a five-second flush fires.

After integration, the combined 61-test slice passed with 1.1 seconds of async
work and 0.7 seconds of serialized work at seed 424242. The useful result is not
the elapsed time alone. This wave removed ambient EventBus and projection
ownership, preserved the process-owned cases that could not honestly become
async, and exposed database locking that per-module repetition could not detect.

The first authoritative root gate also invalidated an older concurrency proof.
Its two scheduler-isolation tests rendezvoused through a registered barrier in
separate ExUnit modules. Under full-suite scheduling, one module could occupy a
worker more than 15 seconds before the other module started, so both tests timed
out even though the focused two-file repetition had been green. The proof is now
self-contained: one test explicitly starts two private sandbox owners and two
gated schedulers, confirms their identities differ, runs the primary scheduler,
rolls its owner back, and then persists the same identifiers through the peer
owner. The ordinary timer-reconciliation contract no longer coordinates with an
unrelated test module, and the global barrier process has been deleted. The
focused five-test scheduler cohort passed at the failing root seed, the complete
cohort passed 505 tests across 101 executions, and the self-contained overlap
proof passed another 101 executions after its final cleanup correction. A
load-sensitive 100-millisecond telemetry wait now uses the scheduler's
synchronous snapshot as a completion barrier before inspecting the mailbox.

The final root `mix precommit` passed: warnings-as-errors compilation, strict
Credo over 2,727 source files, workspace and architecture checks, all four plane
checks, 1,832 core tests, 27 catalog tests, 295 CCSDS tests, 136 simulator tests,
and 1,694 non-browser web tests. Browser tests remained intentionally excluded.

The remaining ranked design seams are now:

| Rank | Area | Current design question |
| ---: | --- | --- |
| 1 | Cache policy/default clients | Can anonymous composed caches own all policy, invalidation, and quiet-period behavior while retaining one serialized default-client compatibility proof? |
| 2 | Command-dispatch retry ownership | Can retry passage become an explicit dispatcher-owned trigger/settled boundary instead of a wall-clock test against a registered global dispatcher? |
| 3 | Contact-scheduler boot policy | Can scheduler policy be captured immutably at boot while named schedulers own their runtime dependencies? |
| 4 | Ordinary store and LiveView ownership | Which remaining serialized stores and LiveViews still hide tasks, subscriptions, runtime lookups, or shared database consumers? |

The next bounded batch should start with cache policy/default clients and command
dispatch retry ownership in separate worktrees; contact-scheduler policy can run
in parallel only if its production and test files do not overlap the dispatcher
reservation. Shared test support, root composition, configuration, and this
audit document remain integration-owned.

### Cache, command-owner, and scheduler-policy wave

This batch closed the first three items above in isolated worktrees and used a
separate agent to review each ownership claim before integration. The important
result is the dependency boundary each slow module exposed, not merely that more
tests now run concurrently.

The dashboard-cache module had combined three different owners. Eleven row,
query, and local-cache policy contracts now run as async `DataCase` tests. Every
write targets an explicit non-global event bus; invalidation tests own an
anonymous synchronous bus, fact consumer, and runtime cache. One activation
interval contract remains `RuntimeCase` because it intentionally applies the
registered mission runtime. Three fixed/default-client compatibility contracts
remain serialized `ConfigCase` tests and reset the application cache around the
test. The former 20-millisecond quiet-period assertion is now an immediate
mailbox assertion: `Engine.resolve/2` joins its source tasks before returning, so
no callback from that invocation remains in flight. The 11 async contracts and
the binding-history neighbor passed 2,323 tests over 101 executions with three
modules allowed to overlap; the four retained serialized contracts passed 84
tests over 21 executions.

The contact-scheduler outlier did not require a production rewrite. Boot
composition already captures scheduler configuration into the root composition,
passes it through mission-runtime child options, and stores it in the scheduler
state. The test smell was a module-wide application-configuration mutation.
Eleven ordinary scheduler contracts now use `RuntimeCase` without changing
global configuration; the sole default-boot policy contract is isolated in a
serialized `ConfigCase`. The ordinary and compatibility files passed 1,212
tests over 101 executions, and the historical scheduler-owner cohort passed 918
tests over 51 executions without SQL-owner exit logs.

The command retry profile also corrected the inventory's original diagnosis.
The test was not waiting for its safety timer: synchronous fact delivery already
caused contact persistence to wake and drain the registered lane before the
write returned. The real defect was owner routing. Enqueue, release retry,
release completion, contact facts, telemetry facts, and transport facts could
fall back to the application command dispatcher or verifier scheduler even when
they originated in a separately composed root. The dispatcher now owns the
lane policy used by external drains, and the command process namespace is
carried through every rescheduling and verifier-notification path. Root
composition force-injects that namespace into both control fact consumers,
overriding a conflicting nested default while preserving all default public
arities as compatibility boundaries.

The command outcome proof starts two complete roots over the same durable
mission identity. A selected-uplink contact wakes only the selected root's
dispatcher; nonempty telemetry and transport facts notify only that root's
verifier scheduler; neither path creates a default-owner lane. A separate test
proves that namespaced enqueue automatically starts the private lane, while a
first-start external drain cannot override the dispatcher's captured callback
or safety policy. The process-owner proof passed 303 tests over 101 executions,
and the full two-root lifecycle passed 20 consecutive executions. An independent
review found no remaining production routing blocker before integration.

One test-support smell is now explicit. `RootLifecycleTest` and some dispatcher
tests need a shared SQL sandbox owner for supervised child processes but do not
mutate application configuration. The former uses `UnitCase` plus manual sandbox
setup; the latter uses `ConfigCase`. Neither label states the real ownership
contract. A future generic process/database case should own the shared checkout,
supervised-child access, and deterministic teardown without implying global
configuration or application-runtime ownership.

After integration, the combined cache, contact-scheduler, command, composition,
and neighboring consumer cohort passed 63 tests at seed 424242 in 6.2 seconds
(2.2 seconds async and 3.9 seconds sync).

The final root `mix precommit` passed: warnings-as-errors compilation, strict
Credo over 2,730 source files, workspace and architecture checks, all four plane
checks, 1,833 core tests, 27 catalog tests, 295 CCSDS tests, 136 simulator tests,
and 1,694 non-browser web tests. Browser tests remained intentionally excluded.
The core run emitted one PostgreSQL client-exit log without an assertion failure.
That is retained as ownership evidence for the next inventory rather than being
treated as harmless merely because the suite stayed green.

The remaining ranked design seams are now:

| Rank | Area | Current design question |
| ---: | --- | --- |
| 1 | Shared process/database test ownership | Can a dedicated case replace manual shared-sandbox setup and misclassified `ConfigCase` modules while guaranteeing child-process teardown? |
| 2 | Ordinary store ownership | Which remaining serialized `DataCase` modules are row-only, and which actually lend their transaction to children or global consumers? |
| 3 | LiveView ownership | Which remaining serialized LiveViews still mount global dashboard/runtime owners instead of using deterministic per-view resolve and stop boundaries? |
| 4 | Default compatibility surfaces | Which zero-arity/default-client APIs are genuine public compatibility boundaries, and which are ambient ownership that should be removed from internal call paths? |

The next bounded batch should begin with an inventory of manual sandbox-owner
setup and serialized `ConfigCase` modules that do not read or write application
configuration. That creates the evidence for a generic process/database case
before converting further store or LiveView modules.

### Process/database and probe-ownership wave

The manual-sandbox inventory confirmed that SQL rollback and process lifecycle
need a case boundary distinct from both global configuration and the application
runtime. `Cadence.ProcessDataCase` now owns a shared sandbox checkout for
serialized tests whose supervised children use the database, and stops that
owner only after ExUnit has synchronously stopped the supervised children. It
does not mutate application configuration or perform RuntimeCase's global
runtime, ETS, or filesystem cleanup. The dispatcher integration, two-root
lifecycle proof, and path-journal instance-isolation proof now use this case;
their four test bodies and assertions are unchanged. Focused repetition passed
84 tests over 21 executions, and the dispatcher subset passed 202 tests over 101
executions without PostgreSQL owner/client-exit logs. The new `:process_data`
tag also makes this ownership class visible to selectors instead of hiding it
behind `UnitCase` or `ConfigCase`.

The remaining data-source backend modules exposed a second ambient owner.
Managed QuestDB provisioning and TSDB lifecycle completion persisted through
the application EventBus even when their callers had selected a private bus.
Those completion paths now propagate only an explicitly supplied `:event_bus`;
omitting the option preserves the existing application-default compatibility
behavior. The three lifecycle/provisioning modules use distinct database scopes
and private synchronous buses, assert the selected completion facts, and now run
as async `DataCase` tests. Their 23 contracts passed 2,323 tests over 101
executions and a 31-test neighbor cohort without owner/client-exit logs.

Instrumenting the intermittent PostgreSQL warning then revealed a production
design defect rather than another case-label problem. `ProbeScheduler` bounded
an entire `Control.DataSources.probe/3` call with
`Task.async_stream(..., on_timeout: :kill_task)`. That call included source and
credential reads, credential audit work, source-health persistence, drift
queries, and capability materialization as well as external adapter I/O. Under
contention at seed 398210, the timeout killed a task during a Repo transaction;
Postgrex disconnected the client, and the scheduler's owner-side timeout write
then encountered the damaged checkout.

Source probing is now an explicit three-stage operation:

1. preparation fetches and validates the durable source, resolves credentials
   and adapter policy, and returns an opaque prepared token in the scheduler
   owner;
2. only the adapter's observation-only `probe/2` call runs in a timeout-bound
   task; and
3. health, audit, drift, and capability results are persisted back in the
   scheduler owner.

The public synchronous `Control.DataSources.probe/3` compatibility boundary
composes the same stages. The legacy injected `:probe_fun` remains supported but
runs synchronously because an arbitrary callback cannot safely be killed while
it may own database work. The staged timed path does not accept an arbitrary
observation callback: it always calls `DataSourceControl.observe_probe/1`, and
the obsolete option is removed before adapter preparation. The built-in
Telemetry/QuestDB observation chain performs Req queries and pure result shaping
without Repo access. Prepared credentials stay out of task arguments, logs, and
summaries; compound exits, throws, and exceptions are reduced to bounded
classifications while simple atom exits retain their compatibility shape.

The scheduler cohort passed 909 tests over 101 executions, the explicit
contention regression passed 101 executions, and the previously failing full
core seed passed 1,834 tests without Postgrex, client-exit, owner-exit, or
credential-marker logs. After integration, the combined process-data, backend,
probe, and public-probe cohort passed 43 tests at seed 424242 in 1.7 seconds
(1.1 seconds async and 0.5 seconds sync).

The staged probe failure is the same *class* as the earlier intermittent
client-exit logs, but process-lineage tracing did not prove that it caused those
specific late log-only occurrences. They remain ownership evidence to monitor,
not a warning that may be declared solved from correlation alone.

The next ranked design seams are:

| Rank | Area | Current design question |
| ---: | --- | --- |
| 1 | Timed archive writers | Which ingress, protocol-record, and telemetry archive tests should move to `ProcessDataCase` so their writer processes always stop before the sandbox owner? |
| 2 | Row-only `ConfigCase` modules | Can ground-network mission-provider, provider-credential, and management-provider contracts become async `DataCase` tests once their identifiers are made collision-free? |
| 3 | Ambient EventBus and ETS stores | Which telemetry data-management, storage, catalog, and limits tests still use global buses or globally named ETS stores despite injectable policy/client APIs? |
| 4 | LiveView ownership | Which serialized LiveViews still mount global dashboard/runtime owners instead of deterministic per-view resolve and stop boundaries? |
| 5 | Intermittent client-exit lineage | If the late warning recurs after the probe fix, which supervised or timed database client remains alive past its case owner? |

The next bounded batch should start with the timed archive-writer modules. They
are the closest remaining match for the new process/database case and the most
plausible place for a timer-driven child to outlive SQL ownership. Row-only
provider modules can be audited in parallel because they do not overlap archive
production or test-support files.

### Archive-writer ownership follow-up

The archive audit found six modules whose existing production boundaries were
already correct but whose test-case labels were not. The ingress filesystem and
instance-isolation modules, protocol-record filesystem and instance-isolation
modules, filesystem telemetry-persistence contract, and combined telemetry
instance-isolation module all start their writers with `start_supervised!`.
Those writers own flush timers and perform Repo-backed segment indexing from the
writer GenServer. None of the six modules reads or mutates application
configuration, so `ConfigCase` added a misleading global-configuration contract
and its application-restart cleanup without owning the real resource.

All six modules now use serialized `ProcessDataCase`. This keeps the shared SQL
checkout required by writer processes and ensures ExUnit stops those supervised
processes before the sandbox owner is rolled back. No production code, fixture,
test body, or assertion changed, and the modules intentionally remain
synchronous. The 12 archive contracts passed directly at seed 424242, then
passed 1,212 tests over 101 executions with no Postgrex client-exit, sandbox
owner-exit, or ownership-error output. The complete `:process_data` selector now
contains 16 tests across nine modules and passed with 1,821 unrelated tests
excluded.

This tranche closes the known timed archive-writer classification list. It does
not prove that the earlier intermittent late client-exit warning can no longer
occur; it removes the most plausible remaining teardown ambiguity by making
writer-process ownership explicit.

The next ranked design seams are now:

| Rank | Area | Current design question |
| ---: | --- | --- |
| 1 | Row-only `ConfigCase` modules | Can ground-network mission-provider, provider-credential, and management-provider contracts become collision-free async `DataCase` tests? |
| 2 | Ambient EventBus and ETS stores | Which telemetry data-management, storage, catalog, and limits tests still use global buses or globally named ETS stores despite injectable policy/client APIs? |
| 3 | LiveView ownership | Which serialized LiveViews still mount global dashboard/runtime owners instead of deterministic per-view resolve and stop boundaries? |
| 4 | Default compatibility surfaces | Which remaining default clients genuinely specify compatibility, and which are ambient dependencies on the application root? |
| 5 | Intermittent client-exit lineage | If the late warning recurs, which database client remains alive past its explicitly classified owner? |

The next bounded batch should take the three row-only provider modules together.
They share no writer/runtime ownership and can become a small async overlap
cohort once their durable identifiers are checked for cross-module collisions.
