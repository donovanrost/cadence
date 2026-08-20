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
