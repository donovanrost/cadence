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

### A4. The core suite is globally serialized

The `cadence` test alias defaults to `--max-cases 1` because the application owns
global runtimes and a shared database sandbox. This is useful containment, but it
also hides which tests are independently isolated and makes the suite slower
than its test count alone would require.

Desired direction is not to remove serialization immediately. First separate
pure tests, repository tests, and supervised-runtime tests; then enable
concurrency only for groups with proved isolation.

### A5. SQL-sandbox coordination is visible in production modules

`CadenceWeb.ScopeLoader` and dashboard resolve workers contain browser-test
sandbox ownership coordination. This keeps real asynchronous execution in tests,
but it also makes test infrastructure part of the production dependency path.

Desired direction is a narrower test adapter or boundary that preserves the
production process topology without making authentication and scope loading
responsible for Ecto sandbox ownership.

### A6. Async workflow completion and process-tree ownership are misaligned

Three deterministic PostgreSQL client-exit logs remain after the dashboard
lifecycle cleanup. They occur when a test has observed its intended outcome but
the responsible process tree has not yet become idle:

- the contact scheduler can reconcile a contact and activate descendants in the
  global mission runtime after the test-owned scheduler reports reconciliation;
- a command lane dispatcher schedules a zero-delay follow-up database pass after
  reporting a successful release;
- simulator traffic can already be inside the TCP ingress executor or async
  persistence projector when the producer is stopped and the global mission
  runtime is torn down.

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

## Audit sequence

1. Finish replacing duplicated dashboard LiveView teardown helpers with the
   shared deterministic lifecycle helper.
2. Attribute any remaining PostgreSQL client-exit or ownership logs to the exact
   process and test owner before changing domain code.
3. Identify `ConnCase`/`DataCase` tests whose contracts can be proved below the
   database layer and move those proofs to unit cases.
4. Evaluate the dashboard hydration/planning split as a bounded architecture
   change with contract tests on both sides.
5. Revisit serialized test groups and global configuration only after their
   dependencies can be started and stopped per test.

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
- At this checkpoint the inline-resolution switch remains in six test/support
  files with 18 application-environment mutations, down from 15 files and 45
  mutations at the start of this audit. The intentional delayed-cancellation test
  remains separate because its test control needs an owner-scoped design rather
  than mechanical removal.

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
