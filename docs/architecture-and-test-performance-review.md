---
title: Cadence Architecture and Test Performance Review
tags: [developer, architecture, refactoring, testing, performance]
status: active
created: 2026-07-18
updated: 2026-07-18
---

# Cadence Architecture and Test Performance Review

## Purpose

Cadence has reached the point where local refactoring alone will not keep the
system understandable or the development loop fast. This review records the
current structural and test-performance baseline, identifies the boundaries
that are already working, and proposes a staged path toward a more modular
system.

The recommendation is not to split the umbrella into many applications
immediately. The highest-leverage sequence is:

1. Remove the two largest test compilation bottlenecks.
2. Make test process and configuration ownership explicit.
3. Establish and enforce bounded-context dependencies inside `:cadence`.
4. Break the root `Cadence` facade and cross-context persistence coupling.
5. Modularize dashboard source resolution and the largest domain contexts.
6. Extract standalone libraries only after their APIs are dependency leaves.

This keeps the work incremental and measurable. Each phase should reduce
coupling or elapsed time before Cadence takes on the operational cost of more
OTP applications or repositories.

## Scope and method

This review covers the four umbrella applications, their production and test
code, Mix task configuration, xref dependency graphs, ExUnit support cases,
and representative large modules and test files.

Measurements were taken from the live `arch/review` checkout on 2026-07-18.
Counts include generated-looking fixture and test code when it is checked into
the application tree because the compiler and maintainers still pay its cost.
Warm compilation and test timings are local measurements, so they are useful
as a baseline and relative signal rather than as universal CI targets.

One test-timing caveat matters: `mix test --slowest` enables `--trace`, which
forces `max_cases` to one. Slow-test profiling is therefore not evidence of
normal parallel-suite performance unless the concurrency mode is recorded
alongside it.

## Executive findings

The umbrella-level dependency direction is healthy:

```text
cadence_web ──> cadence ──> cadence_ccsds
cadence_simulator ─────────> cadence_ccsds
```

`cadence_simulator` depends on `:cadence` only in tests. There are no compile
cycles in the core `:cadence` application. `cadence_ccsds` is already a good
example of a small dependency-leaf application.

The main problems are inside the applications:

- `:cadence` has recognizable domains, but the root `Cadence` module,
  horizontal persistence schemas, and several bidirectional context
  relationships bypass those boundaries.
- Dashboards have become a large product subsystem inside the core and web
  applications. A few modules combine registry, query, revision, evidence,
  transformation, and presentation responsibilities.
- `:cadence_web` has one large compile-connected component caused by broad
  imports and route verification injected through the global `CadenceWeb`
  macro.
- Default web test startup is dominated by compiling two very large test files,
  including one browser matrix whose tests are excluded only after compilation.
- The core data test case pays global runtime cleanup, shared sandbox ownership,
  and a fixed sleep for every database test. These patterns limit safe
  concurrency and obscure ownership.

The codebase does not need a broad rewrite. It needs dependency direction,
smaller compilation units, explicit runtime ownership, and automated
architecture constraints.

The target ownership and allowed dependency directions are now published in the
[context dependency policy](architecture/context-dependency-policy.md). The
policy keeps the ten domain contexts inside `:cadence`, treats the root facade
and horizontal persistence namespaces as transitional, and defines the
platform services that may remain shared leaves.

## Implementation progress

The first Phase 1 performance slices landed on 2026-07-18:

- The 93-case rendered viewport browser matrix now lives under
  `apps/cadence_web/browser_test`, outside default `mix test` discovery. The
  root and child `test.browser` and `test.browser.full` aliases explicitly
  select it from that location.
- The 6,573-line replay transport evidence test body and its shared fixtures
  now compile as `test/support` modules. The discovered LiveView test retains a
  compact ExUnit wrapper, so repeated test discovery does not rebuild that
  scenario.

On the same checkout, warm `cadence_web` require-time profiling fell from
139.16 seconds to 11.43 seconds, and the complete default web suite fell from
166.54 seconds to 49.7 seconds with 1,632 passing tests. These results satisfy
the Phase 1 timing exit conditions. Structural decomposition remains active:
the compiled replay scenario and several other source-family test bodies still
need to be split into smaller scenario and assertion units.

The Phase 2 ownership work now classifies every core test file by its strongest
resource owner: 91 files use `Cadence.UnitCase`, 57 use `Cadence.DataCase`, 24
use `Cadence.RuntimeCase`, and 22 use `Cadence.ConfigCase`. `UnitCase` adds no
per-test application or database setup. `DataCase` owns only a private SQL
sandbox transaction; it no longer stops missions, resets runtime stores, shares
its sandbox globally, or sleeps during teardown. Sandbox startup re-establishes
manual mode and verifies both the connection and Ecto query cache, retrying
only when a restarted Repo has not finished its ownership handoff.

Two complete core-suite runs with different seeds passed all 1,522 tests in
27.2 and 29.2 seconds, below the Phase 2 timing target. `RuntimeCase` now
snapshots the runtime registry and stops only mission runtimes that appeared
during the current test; it no longer stops every mission before and after
each test. Mission shutdown now waits for both the runtime process and its
registry entry to disappear, and runtime enumeration filters dead registry
PIDs. The core test helper still boots `:cadence` before ExUnit selects cases.
`ConfigCase` owns only the serial shared sandbox needed by configuration tests
and their supervised child processes. Of its 22 callers, only the
contact-scheduler suite also carries the `:runtime` tag and opts into owned
mission-runtime cleanup.

Global configuration ownership is now visible outside the core cases as well.
The 45 web test files that mutate application configuration carry the
`:config` tag while retaining their required `CadenceWeb.ConnCase` setup. Six
complete-workflow files across core, simulator, and web carry the
`:integration` tag.

The root aliases now expose the intended ownership lanes. On this checkout,
`mix test.fast` passed 1,129 core, 11 CCSDS, 80 simulator, and 1,492 web tests
in 62.85 seconds of wall time; `mix test.runtime` passed 183 runtime-tagged
core tests in 20.74 seconds of wall time; and `mix test.integration` passed 7
core, 15 simulator, and 3 web tests in 33.75 seconds of wall time. The
authoritative `mix precommit` gate continues to run every default test rather
than composing the selective lanes.

## Measured baseline

### Repository size

| Scope | Files or modules | Lines |
| --- | ---: | ---: |
| `apps/**.ex` | — | 274,932 |
| `apps/**.exs` | — | 256,643 |
| `apps/**.heex` | — | 571 |
| Production code under `apps/*/lib` | — | 272,626 |
| Test code under `apps/*/test` | — | 249,928 |
| Production files over 1,000 lines | 31 | 72,140 |
| Test files over 1,000 lines | 26 | 90,074 |

The current checkout is approximately 532,000 lines of Elixir and test Elixir,
not 460,000. Nearly half of that is test code. The issue is therefore both
production structure and the shape of the verification system.

| Application | Production files | Production lines | Test files | Test lines |
| --- | ---: | ---: | ---: | ---: |
| `cadence` | 659 | 171,226 | 208 | 93,711 |
| `cadence_ccsds` | 14 | 1,864 | 8 | 434 |
| `cadence_simulator` | 45 | 10,728 | 35 | 6,350 |
| `cadence_web` | 386 | 89,379 | 469 | 149,433 |

The dashboard core domain contains 55,667 lines across 111 files, about 32.5%
of `:cadence` production code. The web `live` tree contains 78,769 lines across
297 files, about 88% of `:cadence_web` production code. The
`ops_dashboard_show_live` subtree alone contains 52,950 production lines and
114,619 test lines.

### Dependency graph

The `:cadence` xref graph contains 673 tracked files, 25 compile dependencies,
1,007 export dependencies, 1,646 runtime dependencies, and no compile cycles.
This is a useful foundation: core boundaries can be improved without first
untangling a compile-time knot.

With sibling applications included, `:cadence_web` has:

- 1,049 nodes;
- 202 compile dependencies;
- 2,718 export dependencies;
- 3,072 runtime dependencies; and
- one 190-file compile-connected component.

That component contains only two direct compile edges but 117 export edges.
The main fan-in point is `CadenceWeb`, with 168 incoming compile dependencies.
Its shared HTML helper macro imports twelve component modules and injects
`Phoenix.VerifiedRoutes`, which depends on `CadenceWeb.Endpoint` and
`CadenceWeb.Router`. The router then references the LiveViews and controllers.

Splitting the router file would make it easier to read but would not remove
this compile dependency. The fix is to narrow compile-time imports and verified
route dependencies.

### Current boundary pressure

The strongest bidirectional context relationships include:

| Context pair | Dependencies A to B | Dependencies B to A |
| --- | ---: | ---: |
| Contact Planning / Persistence | 48 | 20 |
| Dashboards / Persistence | 34 | 26 |
| Root `Cadence` / Dashboards | 33 | 49 |
| Root `Cadence` / Contacts | 31 | 34 |
| Contacts / Ground Networks | 30 | 6 |
| Ground Networks / Persistence | 23 | 9 |
| Root `Cadence` / Runtime | 19 | 17 |
| Root `Cadence` / Telemetry | 18 | 17 |
| Dashboards / Telemetry | 18 | 8 |

Seventy-four non-persistence modules directly reference
`Cadence.Persistence.Schemas.*`. This makes the schema tree a shared internal
API and allows one context to couple to another context's storage model.

The web boundary is notably better: production web code does not use
persistence schemas directly. The only web production module that references
the Repo is the scope loader used to permit test sandbox access.

### Large responsibility clusters

File size is not itself a defect, but the largest files reveal responsibilities
that change for different reasons.

| Module | Lines | Public/private functions | Responsibility pressure |
| --- | ---: | ---: | --- |
| `Dashboards.Sources.OperationalObservables` | 7,890 | 7 / 530 | Contract registry, product selection, revisions, reads, frame construction, evidence, and data-link creation across multiple operational families |
| `Dashboards.DataLinkResolver` | 4,532 | 3 / 362 | Target-specific data-link resolution behind one module |
| `Cadence` | 4,353 | 429 / — | Facade over nearly every context |
| `Contacts` | 3,670 | — | Configuration, scheduled and realized contacts, and runtime coordination |
| `Telemetry.DataManagement` | 3,572 | 34 / 303 | State transitions, jobs, recovery, correction authority, and late data |
| `Commanding` | 3,435 | — | Staging, approval, release, dispatch, and verification |
| `Dashboards.SourceRegistry` | 3,038 | — | Multiple registry and source concerns |
| `OpsDataSourcesLive` | 3,747 | 18 / 391 | LiveView orchestration, parsing, page modeling, and rendering helpers |
| `ControlPlaneParams` | 1,971 | 56 / — | Parameters for many API resources |
| `ControlPlaneJSON` | 1,297 | — | Serialization for many API resources |

`Cadence.Application` also starts control-plane services, data-plane services,
projections, integrations, dashboard caches, runtime supervision, mission
health, command dispatch and verification, contact scheduling, provider
ingestion, and jobs under one application supervisor. This works today, but it
does not expose restart domains or future extraction seams.

## Proposed bounded contexts

The following context map should become the default ownership model inside
`:cadence`:

1. **Identity and tenancy** — organizations, users, mission scope, and policy
   identity.
2. **Catalog and activation** — canonical telemetry and command definitions,
   revisions, imports, validation, governance, and activation.
3. **Comms configuration** — spacecraft profiles, configured transports,
   routing rules, and ground-station configuration.
4. **Ground-network provider integration** — provider accounts,
   capabilities, opportunities, provider contacts, and wire translation.
5. **Contact planning** — requirements, candidate generation, constraints,
   scoring, optimization, and proposed plans.
6. **Contact lifecycle** — committed scheduled contacts, realized contacts,
   state transitions, and runtime handoff.
7. **Commanding** — command stages, approval requests, release queues,
   dispatch, and verification.
8. **Mission runtime and capabilities** — runtime partitions, capability
   descriptors, execution, mission processes, and workload ownership.
9. **Telemetry, history, and projections** — ingress, decom, current values,
   history, archives, materialized views, and data-management workflows.
10. **Dashboards** — documents, lifecycle, planning, execution, source
    contracts, data links, and visualization-facing read models.

This map clarifies several current overlaps:

- Comms owns configured transports, routes, and ground stations.
- Ground Networks owns external provider accounts, capability discovery,
  opportunities, provider contacts, and API translation.
- Contact Planning owns proposals and optimization.
- Contacts owns the committed and realized lifecycle and runtime handoff.

Contexts should communicate through explicit public value types and application
services. They should not query one another's schemas or call the root facade.
Events are appropriate when the downstream work is asynchronous or a
projection; direct application-service calls are appropriate when one
transactional outcome is required immediately.

## Proposed production refactors

### 1. Retire the root `Cadence` facade

The root module has 429 public functions and is called by 102 web production
files. It makes the application convenient to call but hides which domain a
consumer depends upon and allows core modules to loop back through a global
entry point.

Proposed solution:

- Have web modules call bounded application services such as
  `Cadence.Contacts`, `Cadence.Commanding`, or a narrower service within those
  namespaces.
- Forbid internal `:cadence` modules from calling the root `Cadence` module.
- Move cross-context workflows to explicitly named orchestration modules.
- Gradually remove root delegates. Because Cadence is still in early
  development, do not preserve a large compatibility facade by default.
- If an external convenience API is eventually useful, keep it deliberately
  small and make it depend one-way on stable context APIs.

Acceptance criteria:

- No production module under `apps/cadence/lib` calls `Cadence.*` as a facade.
- New web code imports or aliases its owning context explicitly.
- An architecture guard prevents new root-facade dependencies.

### 2. Move persistence ownership into contexts

`Cadence.Persistence` is currently a horizontal layer shared by nearly every
domain. A standalone persistence application would formalize the wrong
boundary: storage is an implementation detail of each context, not a business
capability.

Proposed solution:

- Each context owns its schemas, queries, repositories, mappers, and
  transactions.
- Keep only genuinely shared infrastructure under `Cadence.Persistence`, such
  as the Repo, tenant-scoping helpers, migration support, JSON normalization,
  and low-level database utilities.
- Expose domain structs and result types at context boundaries, not Ecto
  schemas.
- Use an explicit context API or projection for cross-context reads.
- Add an xref rule forbidding references to another context's schema namespace.

Do not extract `cadence_persistence` as a standalone application.

### 3. Modularize dashboards within `:cadence`

Dashboards are large enough to need internal sub-boundaries but are not yet a
dependency leaf. Extracting them into another OTP application now would carry
their dependencies on telemetry, contacts, runtime, and persistence across the
new boundary without making those dependencies cleaner.

Organize the subsystem around these responsibilities:

```text
Cadence.Dashboards.Model
Cadence.Dashboards.Lifecycle
Cadence.Dashboards.Planning
Cadence.Dashboards.Execution
Cadence.Dashboards.Runtime
Cadence.Dashboards.DataSources
```

Split `OperationalObservables` by product family:

```text
DataSources.OperationalObservables.Contacts
DataSources.OperationalObservables.Connection
DataSources.OperationalObservables.LinkRF
DataSources.OperationalObservables.Transport
DataSources.OperationalObservables.ManagedRuntime
DataSources.OperationalObservables.Commanding
DataSources.OperationalObservables.IngressLatency
```

Keep a small declarative registry for contracts and dispatch. A family module
should own selection, reads, revisions, evidence, and frame production only for
its family. Shared primitives should be pure transformations with focused
tests.

Split `DataLinkResolver` into target-specific resolver modules behind one
dispatch protocol or function. The central module should select a resolver,
not implement every target.

Acceptance criteria:

- Product-family source behavior is testable without booting a LiveView.
- Adding a source family does not require editing a multi-thousand-line
  conditional module.
- The registry describes and dispatches contracts but does not execute every
  source.
- Exceptions to a 1,000-line production-file guideline are explicit and rare.

### 4. Split the large domain contexts by workflow

Recommended seams:

- `Contacts`: configuration, scheduled contacts, realized contacts, scheduler
  coordination.
- `Commanding`: stages, requests and approval, release queue, dispatch,
  verification.
- `Telemetry.DataManagement`: transitions, jobs and recovery, correction
  authority, late-data handling.
- `OpsDataSourcesLive`: LiveView orchestration, form parameter parsing, page
  model, and function components.
- `ControlPlaneParams` and `ControlPlaneJSON`: one parameter/serialization
  module per API resource family.

The goal is not to replace one large public module with dozens of public
modules. Keep a narrow context entry point where it represents a cohesive
business capability, while moving implementation workflows into owner modules.

### 5. Expose supervision and restart domains

Before creating more umbrella applications, group children under internal
supervisors:

```text
Cadence.ControlPlane.Supervisor
Cadence.DataPlane.Supervisor
Cadence.Projections.Supervisor
Cadence.Integrations.Supervisor
```

This makes ownership, startup order, and restart behavior visible while keeping
deployment simple. A future `cadence_runtime` application becomes justified
only when runtime and data-plane modules form a one-way dependency leaf with a
clear lifecycle and independent operational reason to start or deploy.

### 6. Reduce `CadenceWeb` compile coupling

Proposed solution:

- Make `CadenceWeb` use macros minimal. Avoid globally importing component
  modules that only a subset of views use.
- Import context-specific component modules in their owning LiveViews.
- Keep common primitives global only when nearly every page uses them and they
  have a small dependency surface.
- Introduce small context-specific verified path modules. These modules can
  use `Phoenix.VerifiedRoutes`; most LiveViews can call the path functions at
  runtime instead of compiling directly against the router.
- Re-measure the compile-connected graph after each change.

The router should remain the source of route truth. This proposal does not
change route authentication scopes or pipelines, and a mechanical router split
alone is not considered an architectural fix.

Acceptance criteria:

- The web compile-connected component is materially smaller than 190 files.
- Editing an unrelated route does not recompile most LiveViews.
- `CadenceWeb` no longer has broad component fan-in.

## Test-performance findings

### Current suite timings

| Command/scope | Result | Local elapsed time |
| --- | --- | ---: |
| Warm root compile with warnings as errors | Passed | 1.86s |
| Root Credo strict | Passed, 1,825 files | 27.41s |
| `cadence` normal test run | 1,522 passed | 71.61s |
| `cadence` serial/profile-style run | One transient failure; failed test passed alone | about 60s |
| `cadence_ccsds` | 11 passed | 0.50s |
| `cadence_simulator` second full run | 106 passed | 10.19s |
| `cadence_web` normal test run | 1,632 passed, 93 excluded | 166.54s |

The measured commands imply a warm local root precommit cost of roughly 4.4
minutes. This is an estimate assembled from the component commands, not a
claim that one single precommit invocation produced that exact number.

Normal parallelism did not make the core suite faster in this sample. The
suite contains enough synchronous database/runtime work and global state that
simply removing a root `--max-cases 1` constraint is unlikely to produce a
reliable win. Isolation must improve first.

### Test compilation dominates the web suite

Web require-time profiling took 139.16 seconds for 463 test modules, with a
summed compile time of 229,187 milliseconds. Two files dominate:

| Test file | Lines | Tests | Helpers | Compile time |
| --- | ---: | ---: | ---: | ---: |
| `runtime_replay_source_family_live_test.exs` | 15,016 | 23 | 48 | 129.79s |
| `dashboard_rendered_viewport_smoke_test.exs` | 21,033 | 93 | 101 | 34.82s |

One test in the replay file spans 6,575 lines. The resulting giant BEAM
function is expensive to compile even though its test body is not proportionally
slow.

The viewport browser matrix is excluded in `test_helper.exs`, but ExUnit tags
are evaluated after the file is compiled. The default web suite therefore pays
about 35 seconds to compile tests it will not execute.

### Core database tests have global cleanup costs

`Cadence.DataCase` is used by 98 files containing 689 tests. Those tests are
synchronous. The shared setup:

- ensures the application is running;
- stops all missions before and after non-async tests;
- checks out shared sandbox ownership;
- resets runtime state;
- stops sandboxed processes; and
- sleeps for 25 milliseconds during cleanup.

The fixed sleep alone creates a theoretical floor of 17.225 seconds across
689 tests. Stopping all missions twice per test can execute 1,378 global cleanup
operations. More importantly, this setup makes each data test responsible for
global runtime state even when it only needs a database transaction.

Twenty-two core test files and 47 web test files mutate application
configuration with `Application.put_env/3` or `Application.delete_env/2`.
Global configuration mutation prevents safe concurrency and makes cleanup
correctness part of every affected test.

### Slow execution is secondary but still actionable

After compilation, most individual tests are reasonable. Representative slow
test bodies include:

- replay transport runtime action evidence: 4.49s;
- viewport browser smoke: 2.52s;
- provider account cursor health: 1.79s; and
- control-plane API coverage: about 1.9s.

These deserve focused optimization, especially where real retries or backoffs
are involved, but test compilation and ownership offer the larger first wins.

## Proposed test architecture

### 1. Remove opt-in browser tests from default discovery

Move the full viewport matrix to a directory or filename that the default
`mix test` discovery pattern does not load. Keep aliases that explicitly run:

- a small browser smoke lane; and
- the full browser matrix.

The existing semantic distinction between smoke and full browser verification
should remain. The important change is that excluded tests are not parsed and
compiled by the default web suite.

Acceptance criteria:

- Default `cadence_web` tests do not compile the full viewport matrix.
- `mix test.browser` still runs the supported smoke checks.
- `mix test.browser.full` still runs the full matrix.
- Default-suite coverage is unchanged apart from the intentionally opt-in
  browser cases.

### 2. Decompose the replay source-family test

Replace the 6,575-line test function and repeated inline documents with:

- scenario and fixture builders in compiled `test/support` modules;
- compact JSON or term fixtures when literal payload fidelity matters;
- data-driven lower-layer tests for source, evidence, and product-family
  combinations; and
- a small number of representative LiveView tests proving the route and
  rendering seam.

The test pyramid for each source family should be:

```text
many pure contract/transformation cases
        ↓
some context integration cases
        ↓
few complete LiveView route cases
```

Acceptance criteria:

- No individual test function is hundreds or thousands of lines.
- Require-time profiling for the web application is below 30 seconds.
- The source-family behavior matrix remains represented and reviewable.
- The full web suite is below 60 seconds on the same local baseline.

### 3. Separate test cases by resource ownership

Introduce explicit cases with progressively stronger setup:

- `UnitCase`: no application boot and no database.
- `DataCase`: SQL sandbox only, with per-test database ownership.
- `RuntimeCase`: explicitly starts and owns mission/runtime processes required
  by the test.
- `ConfigCase`: serial case for the small number of unavoidable global
  configuration tests.

`DataCase` should not stop all missions, reset unrelated ETS tables, or sleep.
`RuntimeCase` should track the processes it starts and use monitors or
supervisor termination acknowledgements instead of fixed sleeps.

Acceptance criteria:

- Plain database tests are eligible for `async: true` where their schemas and
  process ownership permit it.
- No unconditional `Process.sleep/1` remains in common test teardown.
- Runtime tests clean up processes they own rather than all mission processes.
- Repeated runs across multiple seeds do not produce sandbox, ETS, or process
  leakage failures.
- The core suite is below 45 seconds on the same local baseline.

### 4. Replace global configuration mutation with explicit dependencies

Pass testable dependencies through options, execution contexts, or child specs:

- clocks and current-time functions;
- retry and backoff strategies;
- provider/client modules;
- feature and behavior policies; and
- process or registry names.

Keep true application-configuration tests in `ConfigCase` and run them
synchronously. This both improves concurrency and makes production dependency
ownership visible.

### 5. Eliminate real waiting from deterministic tests

Inject clocks, retry policies, and backoff functions. Tests should advance a
fake clock or return a zero-delay policy instead of waiting for production
timeouts. Where OTP timing itself is the behavior under test, use monitors and
bounded assertions and keep those tests in the runtime or integration lane.

### 6. Add intentional local and CI lanes

Recommended aliases:

```text
mix test.fast          # unit and isolated data tests
mix test.runtime       # owned OTP/runtime integration
mix test.integration   # external boundaries and complete workflows
mix test.browser       # representative browser smoke
mix test.browser.full  # complete browser matrix
mix precommit          # authoritative aggregate gate
```

Only after isolation is improved should Cadence increase in-VM ExUnit
concurrency. CI can then use OS-process partitions with `MIX_TEST_PARTITION`
and separate test databases. Process-level partitioning is safer than forcing
more concurrency through shared application state.

Target outcome:

- `cadence_web` default suite: 45–60 seconds;
- `cadence` default suite: 35–45 seconds;
- warm local `mix precommit`: near two minutes; and
- CI wall time lower through safe application or file partitions.

## Standalone library candidates

Extraction should follow dependency direction. A library is ready when it can
be a small leaf with a stable public model, no Repo or Phoenix dependency, no
application boot requirement, and a fast focused test suite.

### Ready or close

#### `cadence_ccsds`

This is already the strongest library boundary. It is small, shared by core and
simulator, and dependency-light. It can remain an umbrella application now and
later move to its own repository or Hex package if release cadence or external
consumers justify that cost.

#### `cadence_capability_api`

Extract the first-party capability ABI into a dependency leaf containing:

- capability behaviors;
- descriptors;
- execution context and result types; and
- action-request value types.

Implementation modules remain in core. Before extraction, remove ABI type
dependencies on runtime implementation details such as
`Cadence.Runtime.PartitionKey`.

#### `cadence_provider_contract`

Create a pure, versioned provider contract shared by Cadence and the simulator:

- wire schemas and codecs;
- validation and sanitization;
- fixtures; and
- conformance tests.

Do not put Plug routers, Req clients, Repo code, provider-account persistence,
or simulator behavior in this package. The current simulator contract is
Plug-bound, while several useful pure value types live in Ground Networks; the
new package should contain only the common wire contract.

### Likely after internal cleanup

#### `cadence_catalog_model`

A pure catalog model could own canonical telemetry and command definitions,
diagnostics, normalization, and compilers. It is not ready while catalog
parsing also performs persistence and governance activation. First separate
parse/normalize/compile from storing and activating revisions.

#### `cadence_contact_planner`

The optimizer, constraints, scoring, evaluator, schedule, and narrowing logic
are plausible dependency-leaf code. Define a small stable set of planner input
and output structs instead of depending on the full Cadence contact and
delivery policy models.

### Not current library candidates

Do not extract these yet:

- Dashboards;
- Commanding;
- Contacts;
- Telemetry Data Management; or
- Persistence.

Their current value comes from application workflows and state ownership, and
their dependency graphs are not leaf-shaped. Internal boundaries should come
first.

## Enforcement

Architecture intentions should be executable. Add a custom Mix task or
architecture test that consumes `mix xref graph --format json` and checks:

- the allowed dependency matrix between bounded contexts;
- no internal calls through the root `Cadence` facade;
- no references to another context's schema namespace;
- approved dependency direction for extracted libraries; and
- documented exceptions with owners and expiry conditions.

Add source-size diagnostics as a change-pressure signal:

- warn or fail when an individual test function exceeds 200–300 lines;
- warn when a test file exceeds 1,500 lines;
- warn when a production module exceeds 1,000 lines; and
- permit explicit exceptions for generated or opt-in assets.

Size thresholds are not a substitute for design review. They create an early
conversation before another 6,000-line function or 8,000-line multi-family
module becomes normal.

`mix cadence.architecture.check` now implements these source-size diagnostics
in warning mode. It scans production, default-test, test-support, and opt-in
browser source; reports files and individual `test` blocks over the thresholds;
and emits a compact summary from `mix precommit`. `--strict` is available once
the current pressure has been reduced or explicitly baselined. The initial
diagnostic reports 31 production files, 21 test files, and 35 test functions
over their respective limits. Extracting uplink-gateway configuration
normalization and validation from the 1,016-line transport extension reduced
the current production-file pressure to 30 without changing the test-file or
test-function counts. Extracting evidence-panel metadata parsing from the
1,052-line dashboard data-link selection module reduced the production-file
pressure again to 29. Extracting provider-ingress tracing, telemetry emission,
and error logging from the 1,165-line executor reduced that count to 28 while
keeping queue ownership and processing order in the GenServer. Extracting
provider, frame, scheduling, and parallel-mode configuration from the
1,165-line simulator coordinator reduced the count to 27 while leaving
generation and ordered emission coordinator-owned. Moving the governed packet
definition, binding-set, capability-instance, and binding-rule write steps out
of the 1,164-line Governance context reduced the count to 26 while preserving
the context-owned transaction, validation, and hydration boundaries. Extracting
correction-task and replacement-job parsing plus derived summaries from the
1,203-line historical-workflow recovery module reduced the count to 25 while
leaving action selection and closure-readiness policy in the parent. Moving
spacecraft, contact, mission-event, and mission-health response shaping out of
the 1,297-line control-plane JSON module reduced the count to 24 while
preserving its public serializer functions as delegates. Extracting credential
verification, bootstrap administration, durable-user lookup, and browser-session
persistence from the 1,334-line Accounts context reduced the count to 23 while
keeping its public authentication API on the context facade and leaving
membership and invitation workflows context-owned. Extracting corrected
replacement work, job diagnostics, and closure-readiness rendering from the
1,340-line historical workflow group-status component reduced the count to 22
while preserving the existing LiveView events, form IDs, and evidence
attributes. Moving the telemetry explorer page, provenance formatting, and
filter-option rendering out of the 1,345-line LiveView reduced the count to 21
while leaving parameter canonicalization, sample loading, and socket-event
ownership in the LiveView. Separating event-store queries and operational
observable state, connection, link-RF, and metric projections from the
1,419-line OperationalEvents context reduced the count to 20 while preserving
the context's public read API and keeping event persistence in the facade.
Separating command, telemetry, limits, source, contact, and interval evidence
reference builders from the 1,478-line dashboard DataLinks module reduced the
count to 19 while leaving navigation-link construction and request-context
ownership in the parent. Extracting runtime partition construction,
managed-application initialization and snapshotting, and managed-runtime record
shaping from the 1,547-line partition owner reduced the count to 18 while
keeping GenServer callbacks, decoding, dispatch, timers, and reconciliation in
the owner. Moving lifecycle-event persistence, comparison-review workflows,
health snapshots, and publish-readiness history out of the 1,556-line dashboard
document store reduced the count to 17 while leaving document/version
transactions and runtime invalidation in the parent. Extracting effective-time
historical binding resolution, range segmentation, interval diagnostics, and
source-adapter facts execution from the 1,573-line data-source registry reduced
the count to 16 while leaving current health-aware binding selection and
registry loading in the parent. Extracting artifact validation and parsing,
compiled snapshot and runtime-artifact persistence, and result-document
summarization from the 1,626-line Cadence YAML database importer reduced the
count to 15 while keeping telemetry and command model conversion in the parent.
Extracting dedicated TSDB lifecycle transitions, active source probing,
credential resolution, health recording, and capability materialization from
the 1,683-line dashboard data-source context reduced the count to 14 while
keeping the public persistence API and durable writes on the context facade.
Extracting command-workflow parameter assembly and shared typed-value parsing
from the 1,971-line control-plane parameter module reduced the count to 13
while preserving `ControlPlaneParams` as the controller-facing facade for all
parameter families.
Separating runtime and operational-observable conversion, dashboard and source
lifecycle conversion, and enum-independent normalization from the 2,289-line
operational-event model reduced the count to 12 while leaving the canonical
event struct, types, `new/1`, and public converter entry points on `Event`.
Extracting product selection, time and scope normalization, request limits,
source-binding metadata, and request warnings from the 2,456-line events
source reduced the adapter to 2,146 lines; its new request-planning boundary is
352 lines. Extracting read-option filters, replay/live reader selection,
canonical-event filtering, cursors, and source-capability matching then reduced
the adapter to 1,569 lines. Finally, isolating contact interval projection and
event presentation reduced the adapter to 989 lines and production-file
pressure to 11. The resulting request-planning, read, contact, and presentation
boundaries are 385, 653, 397, and 180 lines.
Moving telemetry-backfill lifecycle source cases and their local fixtures out
of the 1,580-line events-source test reduced test-file pressure from 21 to 20;
the original source-family test is now 1,339 lines and the focused backfill
test is 319 lines, with the test-function count unchanged.
Moving replay request, event, and frame builders out of the 1,511-line
operational-observables replay integration test reduced test-file pressure to
19. Replacing its inline metric seed matrix with one fixture call also reduced
the overlong-test count from 35 to 34; the test file is now 913 lines and its
shared support module is 617 lines.
Moving compare-mode and observed analysis-bucket cases out of the 1,601-line
limits-source test reduced test-file pressure to 18; the source-family file is
now 1,408 lines and the focused analysis-buckets file is 325 lines.
Moving operational-observable, transport, and managed-runtime envelope cases
out of the 1,676-line operational-event test reduced test-file pressure to 17
and mirrored the production runtime-family boundary; the canonical envelope
test is now 954 lines and the runtime-family test is 727 lines.
Moving selected-interval evidence enrichment cases out of the 2,054-line
source-registry test and sharing its request/binding/evidence fixtures reduced
test-file pressure to 16; the registry files are now 813 and 865 lines, backed
by a 399-line support module.
Moving provider, mission, routing, reconciliation, and event-processing helpers
out of the 1,644-line simulator contact-scheduling integration test reduced
test-file pressure to 15; the scenario file is now 912 lines and its shared
scheduling fixture module is 759 lines.
Moving comparison-review, health-snapshot, and publish-readiness lifecycle
audit cases out of the 1,871-line document-store test reduced test-file
pressure to 14; the document and lifecycle files are now 1,159 and 574 lines,
with 164 lines of shared fixtures.
Moving latest-value and archive-bound cases out of the 1,890-line telemetry
source test reduced test-file pressure to 13; the source-family and focused
latest-value files are now 1,461 and 268 lines, backed by 188 lines of shared
request, sample, and binding fixtures.
Moving operational-observable state, RF-state, connection-state, and metric
projection cases out of the 2,323-line operational-events context test reduced
test-file pressure to 12; the context and observable-family files are now
1,161 and 782 lines, backed by 407 lines of shared event and scope builders.
Moving catalog, telemetry-ingress, and commanding workflows out of the
2,857-line control-plane API test reduced test-file pressure to 11; the
resource-management and mission-data API files are now 1,358 and 1,226 lines,
backed by 325 lines of shared authenticated API fixtures. Running the split
files alone also exposed and removed an atom-loading order dependency:
provider adapter keys now resolve through the provider-adapter registry instead
of succeeding only when another test happened to load the atom first.
Replacing four duplicated RF metric copied-route LiveView cases with a shared
table-driven scenario contract reduced the link-scope test from 1,701 to 909
lines and reduced test-file pressure to 10 while preserving four independently
named metric cases.
Separating group transitions, job recovery, and correction-authority workflows
from the 3,837-line telemetry data-management test reduced test-file pressure
to 9. The policy/base, group, recovery, and correction files are now 1,298,
1,052, 970, and 372 lines, backed by 303 lines of shared workflow fixtures.
Separating dedicated TSDB lifecycle, binding history, and cache/policy cases
from the 3,625-line dashboard data-sources test reduced test-file pressure to
8. The source/probe, backend, binding-history, and cache/policy files are now
1,051, 557, 849, and 838 lines, backed by 403 lines of shared source fixtures.
Separating runtime planning, frame resolution, cache/execution policy, and live
resolution from the 3,642-line dashboard engine test reduced test-file pressure
to 7. Those five engine test files are now 1,001, 673, 355, 657, and 758 lines,
backed by 277 lines of shared engine fixtures.
Separating projected operational intervals, mission and runtime operational
events, telemetry and source lifecycle, and recovery diagnostics from the
4,489-line dashboard data-link resolver test reduced test-file pressure to 6.
Those five resolver test files are now 939, 755, 1,015, 959, and 499 lines,
backed by 375 lines of shared resolver fixtures.
Separating connection and interval state, replay runtime activity, RF latest
and history, transport and queue metrics, and ingress latency from the
6,541-line operational-observables source test reduced test-file pressure to
5. The seven source-family files are now 1,164, 980, 596, 724, 944, 798, and
1,024 lines, backed by 367 lines of shared operational-observable fixtures.
Separating replay source-family LiveView proofs by metric, ingress/transport,
managed runtime, transport runtime, connection, and interval evidence reduced
test-file pressure to 3. The original 6,323-line test is now seven files of
634, 1,051, 769, 1,137, 1,019, 951, and 858 lines; its 2,150-line support
module is now two fixture modules of 1,075 and 1,078 lines. All 23 copied-route
and rendered-evidence proofs remain in the focused app-local run.
Decomposing the 6,587-line replay transport-evidence scenario into setup,
release, failed-verifier cycles, verifier evidence, and transport-record phases
reduced test-file pressure to 2. Its public scenario is now a 25-line
orchestrator over eight phase modules of 388, 1,222, 889, 653, 654, 685,
1,093, and 1,238 lines; all five transport-evidence LiveView tests remain
green in the focused app-local run.
Decomposing the 2,190-line source-endpoint command-queue test into queue,
release-resource, verifier, transport-action, and back-link phases reduced the
2,939-line LiveView test to 426 lines, test-file pressure to 1, and overlong
test pressure from 34 to 33. The 19-line scenario orchestrates phase modules of
517, 603, 467, 499, and 292 lines, backed by 344 lines of shared fixtures; all
three source-endpoint scope proofs remain green.
Splitting the 21,037-line opt-in rendered-viewport matrix into 20 focused test
files reduced test-file pressure to zero; the largest browser test file is now
1,359 lines. Decomposing its 2,359-line authenticated smoke workflow into a
28-line scenario over setup, recovery, worker-evidence, replacement-evidence,
and mixed-evidence phases reduced overlong-test pressure from 33 to 32; the
largest shared browser support file is 932 lines. The child and root
`test.browser` aliases still select the compact three-test smoke file, while
`test.browser.full` selects the complete browser-test directory. Compile-only
full-matrix discovery finds all 93 cases with none entering the default suite,
and the real smoke lane passes all three cases in 58.5 seconds. That run also
refreshed the browser contract for the current telemetry-first toolbar and
shared overlays, and fixed repeated warning popover IDs plus narrow dashboard
title wrapping.
Extracting runtime invalidation event and durable decision setup from the
operator-diagnostics LiveView case reduced that test from 305 to 191 lines and
overlong-test pressure from 32 to 31 while preserving the rendered diagnostic
and no-refresh blocker assertions.
Extracting the data-source binding change interaction and persisted audit
assertions reduced the mission data-sources listing test from 307 to 280 lines
and overlong-test pressure from 31 to 30.
Extracting antenna-pointing copied-route assertions reduced that operational
observable rendering test from 310 to 299 lines and overlong-test pressure from
30 to 29.
Extracting failed historical-workflow lifecycle and job setup reduced the
non-retryable correction LiveView test from 315 to 264 lines and overlong-test
pressure from 29 to 28.
Extracting the degraded workflow-dispatch outcome metadata contract reduced
that data-link panel component test from 317 to 264 lines and overlong-test
pressure from 28 to 27.
Extracting replay ground-station connection, interval, and source-health setup
reduced that interval-evidence LiveView test from 322 to 292 lines and
overlong-test pressure from 27 to 26.
Extracting replay transport-execution interval setup and table-driven
reopened-inspector detail assertions reduced its sibling test from 344 to 244
lines and overlong-test pressure from 26 to 25.
Moving the resolvable evidence-inspector fixture out of its component test body
reduced that handoff test from 345 to 196 lines while preserving every rendered
detail and data-link attribute assertion, reducing overlong-test pressure from
25 to 24.
Extracting the repeated bulk-request and request-group stage submissions from
the grouped historical backfill proof reduced that test from 333 to 282 lines
while retaining its storage-event, rendered-state, no-op, and queued-job
assertions, reducing overlong-test pressure from 24 to 23.
Moving live transport-execution endpoint, transport, capability-record,
interval, and dashboard setup into a fixture helper reduced that copied-route
proof from 328 to 242 lines while retaining its evidence navigation, route
reopen, and inspector-detail assertions, reducing overlong-test pressure from
23 to 22.
Centralizing the managed-runtime inspector field selector reduced the live
capability-record copied-route proof from 336 to 264 lines while keeping its
explicit field-value, route, and reopen assertions, reducing overlong-test
pressure from 22 to 21.
Moving connection-state endpoint, transport, snapshot, interval, and dashboard
setup into a fixture helper reduced that rendering proof from 346 to 271 lines
while retaining its row presentation, evidence, copied-route, reopened-event,
and transport-link assertions, reducing overlong-test pressure from 21 to 20.
Reusing the managed-runtime inspector field selector and extracting the live
action/timer dashboard fixture reduced that copied-route proof from 351 to 296
lines while retaining both event-navigation and reopened-inspector contracts,
reducing overlong-test pressure from 20 to 19.
Extracting the comparison-review request document and repeated request-group
stage submissions reduced that historical workflow proof from 356 to 290 lines
while retaining its prefilled form, lifecycle navigation, review-origin,
orchestration, and queued-job assertions, reducing overlong-test pressure from
19 to 18.
Extracting BYO probe configuration, managed seed source/binding setup, and the
customer-source registration submission reduced that lifecycle proof from 358
to 294 lines while retaining credential rotation, probe/drift, health,
disable/enable, and binding-option assertions, reducing overlong-test pressure
from 18 to 17.
Extracting QuestDB connection and schema probing, diagnostic classification,
credential headers, and endpoint selection from the 2,882-line telemetry
source reduced the adapter to 2,578 lines. The new 317-line probe module keeps
backend health checks separate from telemetry fact and frame resolution;
production-file pressure remains 11 while the remaining telemetry
responsibilities are split.
Moving active and terminal backfill/import lifecycle selection, frame matching,
badge metadata, and evidence merging out of the telemetry source reduced the
adapter again to 2,376 lines. The 204-line historical-workflow module consumes
the scoped lookup options assembled by the source and owns only
visualization-facing workflow annotation.
Extracting observation-identity loading, revision summaries, evidence,
warnings, and cache dependency aggregation reduced the telemetry adapter to
2,215 lines. The 230-line revision-state module receives tenant- and
binding-scoped lookup options from the adapter and owns the full
visualization-facing revision policy.
Moving latest, history, and decimated frame shapes, field metadata, evidence,
links, actions, and request-facing presentation context out of the telemetry
source reduced the adapter to 1,758 lines. The 447-line frame builder and
149-line frame-context module are both below the production threshold; source
pressure remains 11 until another adapter responsibility is separated.
Consolidating selection policy, live and archive time windows, backend
connection material, contact-derived source-endpoint scope, and all
latest/history/decimated/watermark query options reduced the telemetry adapter
again to 1,342 lines. The 486-line query-options module keeps those backend
scope rules consistent; production pressure remains 11 while the adapter is
above the 1,000-line limit.
Extracting coverage detection, frame warning annotation, watermark and source
failure detail, data-view notices, linked actions, and degraded-state policy
reduced the telemetry adapter to 936 lines. The 447-line warnings module keeps
that presentation policy together, and production source-size pressure drops
from 11 to 10 with the telemetry adapter now below the 1,000-line limit.
Moving planned-request scope checks, source-capability matching, capability
provenance, and placement warning construction out of the dashboard engine
reduced the engine from 2,662 to 2,340 lines. The new 387-line validation module
owns that policy while the engine retains request assembly and orchestration;
production source-size pressure remains 10 until another engine responsibility
is separated.
Extracting runtime-context resolution, overlay and primary sampling, live versus
snapshot time policy, source-binding windows, and placement sizing reduced the
engine again to 1,808 lines. The 614-line source-request planner owns those
request derivations without executing providers; production source-size
pressure remains 10 while the engine is still above the 1,000-line limit.
Moving freshness-policy composition, watermark annotation, capability
provenance, and source-dependency metadata out of the runtime path reduced the
engine to 1,634 lines. The new 249-line source-result annotation module owns the
consumer-facing evidence added before caching and materialization; production
source-size pressure remains 10.
Extracting provider execution policy, timeout and failure conversion,
source-result caching, cache-key identity, and source-selection metadata reduced
the dashboard engine to 965 lines. The 745-line source-request execution service
returns resolved results and cache provenance to the engine for frame
materialization, reducing production source-size pressure from 10 to 9.
Moving target-definition selection, synthetic event evaluation,
observed-versus-recomputed comparison, bucket aggregation, and divergence
warnings out of the limits source reduced that adapter from 2,682 to 2,272
lines. The new 541-line recomputed-analysis module owns that policy; production
source-size pressure remains 9 while the adapter is above the 1,000-line limit.
Extracting scalar, event, analysis-bucket, and definition-interval frame shapes
and field columns reduced the limits adapter again to 1,953 lines. The 375-line
frame builder receives already-assembled evidence metadata, so source-binding
policy remains in the adapter; production source-size pressure remains 9.
Moving frame evidence, links, source counts, divergence metadata, and selected
limit-definition activation details out of the limits adapter reduced it to
1,685 lines. The 400-line metadata module receives the adapter's resolved source
identity rather than selecting providers itself; production source-size
pressure remains 9.
Extracting provider query options, telemetry-source context resolution,
time-range warnings, selected definition intervals, and watermark aggregation
reduced the limits adapter to 1,234 lines. The new 561-line query-context module
owns the translation from planned dashboard requests to bounded provider
queries; production source-size pressure remains 9 while the adapter is still
above the 1,000-line limit.
Moving request validation, product and capability selection, and adapter warning
policy into a 362-line request-policy module reduced the limits adapter to 945
lines. This preserves the existing validation order and warning payloads while
leaving provider orchestration in the adapter, reducing production source-size
pressure from 9 to 8.
Extracting product-to-family data-revision routing, provider callback selection,
and multi-family cache fingerprints reduced the operational-observables source
from 7,892 to 7,167 lines. The new 279-line revision-policy module preserves
the existing product-specific fingerprint keys while the adapter retains its
provider readers and row normalization; production source-size pressure remains
8.
Moving source-backed observable catalogs, sampling-to-product selection,
capability contracts, and unsupported-request warnings into a 559-line product
policy reduced the operational-observables source again to 6,640 lines. Its
existing public backing-contract API remains as delegates and resolution now
receives an already-selected product; production source-size pressure remains
8.
Extracting latest and historical connection-state frame fields, freshness
metadata, operational links, and interval evidence reduced the
operational-observables source from 6,640 to 6,492 lines. The new 160-line
connection frame module receives resolved rows and source identity while
provider reads and row normalization remain in the adapter; production
source-size pressure remains 8.
Moving connection snapshot normalization, transport and ground-station row
joins, request-scope filtering, time windows, ordering, and limits into a
391-line connection-row module reduced the operational-observables source from
6,492 to 6,235 lines. Shared transport helpers still used by RF and metric
products remain in the adapter; production source-size pressure remains 8.
Extracting ground-station antenna-pointing snapshot joins, state normalization,
scope and time filtering, plus latest and historical frame presentation reduced
the operational-observables source from 6,235 to 5,915 lines. The new 255-line
row module and 160-line frame module own that product family while the adapter
retains provider selection; production source-size pressure remains 8.

The same task now consumes a fresh core `mix xref graph --format json` result
and ratchets three dependency boundaries. The initial graph contained 8 internal
callers of the root `Cadence` facade and 205 direct dependencies from
non-persistence code to `Cadence.Persistence.Schemas.*`. The first production
cleanup routed all eight internal callers through their owning contexts, so the
current baseline contains zero root-facade edges. `OrganizationRow` and
`MissionRow` then moved from the horizontal persistence namespace into their
owning `Organizations` and `Missions` contexts. The comms ground-station,
transport, routing-rule, and routing-rule-event rows likewise moved under
`Cadence.Comms`. The user, local-credential, session-token, organization
membership, and organization-invitation rows now live under `Cadence.Accounts`,
and the artifact, database, import-run, revision, command-snapshot, and
telemetry-snapshot rows now live under `Cadence.Catalog`, reducing schema edges
from 205 to 187. The active-binding-set and binding-set-activation rows now
live under `Cadence.Activations`, and the service-identity row now lives under
`Cadence.Auth`. Six Governance-exclusive binding and definition rows also now
live under `Cadence.Governance`, reducing that baseline again to 178. The
governed limit-definition row and persistence entrypoint now live under
`Cadence.Limits`; Reads and Dashboards use its public domain APIs instead of
the row. The background-job row now lives under `Cadence.Jobs`, reducing the
baseline to 173. The notification row likewise now lives under
`Cadence.Notifications`, reducing the baseline to 172. Spacecraft and
spacecraft-type rows now live under their identity stores,
reducing the baseline to 170. Limits evaluation-run and active-definition rows
now live under `Cadence.Limits`, reducing the baseline to 168. The
limit-definition lifecycle-event row now also lives under `Cadence.Limits`;
Dashboards resolves it through scoped domain APIs, reducing the baseline to 166.
Four projection rebuild-run rows now live beside their owning projection
modules, reducing the baseline to 162.
Four dashboard data-source and binding rows now live under
`Cadence.Dashboards.DataSources`, reducing the baseline to 157.
Canonical dashboard, version, lifecycle-event, and investigation-preset rows
now live under their owning dashboard stores, reducing the baseline to 152.
Dashboard source-health and source-watermark event/status rows now live under
their owning stores, reducing the baseline to 146.
Source-credential reference/event and runtime-invalidation decision-event rows
now live under their owning dashboard stores, reducing the baseline to 143.
The application-binding row now lives under its owning Applications store,
reducing the baseline to 141.
Provider-account, account-version, and account-grant rows now live under their
owning Ground Networks stores, reducing the baseline to 138.
Provider-credential, event-cursor, event-inbox, and evidence rows now also live
under their owning Ground Networks stores, reducing the baseline to 134.
Contacts now resolves exact mission-provider versions through the existing
Ground Networks API, and the provider row lives under `MissionProviders`,
reducing the baseline to 132.
Contacts now appends provider audit entries through `ProviderAudit`, preserving
its outer transaction, and the audit row lives under that context, reducing
the baseline to 130.
Dashboards now uses scoped Operational Events fetch/list APIs, and the mission
event projection uses an explicit rebuild feed. The operational-event row now
lives under its owning context, reducing the baseline to 127.
The derived-telemetry evaluation-run row now lives under its owning context,
reducing the baseline to 126.
Telemetry backfill lifecycle and observation-identity decision-event rows now
live under their owning storage boundaries, reducing the baseline to 124.
Filesystem ingress-evidence and protocol-record manifest rows now live under
their owning archive backends, reducing the baseline to 122.
New edges fail, removed edges must be deleted from the baseline in the
same change, and the baseline has an explicit owner and review-by date.
Context-owned row modules are also protected from new callers outside their
bounded context. The initial
`Persistence.OrganizationScope -> Missions.MissionRow` exception was removed
by exposing mission ownership through the `Missions` context, leaving the
cross-context row baseline at zero. The public root facade still exists for
external callers and remains a later decomposition target.

When a dependency exception is introduced, update the context map or decision
record in the same change. The current runtime architecture guard demonstrates
the pattern but should be broadened beyond polling-related rules.

## Phased implementation plan

### Phase 0: Baseline and guardrails — 1–2 days

- Adopt this review as the working architecture record.
- Save repeatable line-count, xref, and require-time profiling commands.
- Define the context dependency matrix.
- Add size diagnostics in warning mode.

Exit condition: the team can reproduce the baseline and see new boundary or
size regressions in review.

### Phase 1: Test compiler bottlenecks — week 1

- Move the browser matrix outside default test discovery.
- Decompose the replay source-family test.
- Preserve the browser smoke/full aliases and source-family behavior coverage.

Exit conditions:

- web require-time profiling is below 30 seconds; and
- the default web suite is below 60 seconds on the same machine.

### Phase 2: Test ownership and isolation — weeks 1–2

- Introduce Unit, Data, Runtime, and Config cases.
- Remove global runtime cleanup and sleeps from DataCase.
- Inject configuration, clocks, retry, and process names where practical.
- Mark only truly isolated tests async.

Exit conditions:

- the core suite is below 45 seconds;
- repeated seeded runs are stable; and
- no common teardown sleeps or global mission stops remain.

### Phase 3: Context boundaries — weeks 2–4

- Publish the allowed context dependency matrix.
- Remove internal root-facade calls.
- Move schema ownership into contexts.
- Add xref-based boundary enforcement.
- Introduce the internal supervisor groups.

Exit conditions:

- context dependencies are one-way or explicitly orchestrated;
- cross-context schema access is rejected automatically; and
- the root `Cadence` module is removed or intentionally small.

### Phase 4: Dashboard and large-context modularization — weeks 4–8

- Split operational observables by product family.
- Split data-link resolution by target.
- Move behavior matrices to lower-layer tests.
- Thin LiveViews into orchestration plus components/page models.
- Split Contacts, Commanding, and Data Management by workflow.

Exit conditions:

- no central module implements every dashboard source family;
- full LiveView tests are representative rather than combinatorial; and
- production files over 1,000 lines are rare, justified exceptions.

### Phase 5: Library extraction — after APIs stabilize

Extract in this likely order:

1. capability API;
2. provider contract;
3. catalog model; and
4. contact planner.

Each candidate must pass these checks before extraction:

- one-way dependency leaf;
- no Repo, Phoenix, or application boot requirement;
- explicit versioned public types;
- no dependence on another Cadence implementation namespace; and
- focused test suite that runs in seconds.

## Decision summary

| Question | Recommendation |
| --- | --- |
| Where should Cadence refactor first? | Test compilation, test ownership, root facade, persistence ownership, then dashboard/source and domain workflow modules |
| How should test time improve? | Stop compiling opt-in matrices, break giant test functions, separate test cases by resources, inject global dependencies, then partition safely |
| What deserves a standalone library? | CCSDS now; capability API and provider contract next; catalog model and planner after cleanup |
| What should not be extracted yet? | Persistence, Dashboards, Contacts, Commanding, and Telemetry Data Management |
| Where are the cleaner boundaries? | The ten bounded contexts above, with context-owned schemas and explicit application services/events |
| Should the umbrella split immediately? | No. Establish one-way internal dependencies and restart domains first |

## Reproduction commands

Run from the umbrella root unless an application path is shown:

```bash
# Production and test line counts
find apps -type f \( -name '*.ex' -o -name '*.exs' -o -name '*.heex' \) \
  -print0 | xargs -0 wc -l

# Compile dependency shape
mix xref graph --format stats --label compile-connected --include-siblings
mix xref graph --format cycles --label compile-connected --include-siblings

# Architecture source-size pressure
mix cadence.architecture.check

# Test-module compile and require cost
cd apps/cadence_web
mix test --profile-require time

# Normal application suite
mix test

# Authoritative repository gate
cd ../..
mix precommit
```

When profiling slow test bodies, record that `--slowest` turns on trace mode
and serial execution. Use normal `mix test` separately for actual default-suite
elapsed time.
