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

The first Phase 2 ownership slice now separates 64 database-only files on
`Cadence.DataCase` from 34 process-owning files on `Cadence.RuntimeCase`.
`DataCase` owns only a private SQL sandbox transaction; it no longer stops
missions, resets runtime stores, shares its sandbox globally, or sleeps during
teardown. Sandbox startup re-establishes manual mode and verifies both the
connection and Ecto query cache, retrying only when a restarted Repo has not
finished its ownership handoff.

Two complete core-suite runs with different seeds passed all 1,522 tests in
27.2 and 29.2 seconds, below the Phase 2 timing target. Runtime ownership is
still transitional: `RuntimeCase` retains compatibility-wide mission cleanup
until its callers start and track mission processes explicitly, and dedicated
`UnitCase` and `ConfigCase` templates remain to be introduced.

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
