---
title: "ADR-021: Monorepo Poncho Project and Package Layout"
aliases:
  [poncho, workspace, monorepo, project layout, package layout, mix projects]
tags: [adr, architecture, workspace, poncho, monorepo, dependencies, releases]
status: accepted
created: 2026-08-21
updated: 2026-08-21
---

# ADR-021: Monorepo Poncho Project and Package Layout

## Status

Accepted

Implemented on 2026-08-21. The five child projects now own independent build,
dependency, lock, formatting, and configuration state; the root retains only
Workspace tooling and aggregate orchestration. Standalone child suites, the
simulator production escript, the web production release, Workspace and
architecture checks, and the authoritative root precommit gate all pass.

This ADR amends [ADR-014](014-shared-ccsds-library-boundary.md) by classifying
`ccsds` as a package rather than an umbrella application. It does not
change ADR-014's protocol ownership or dependency direction.

## Context

Cadence was originally organized as a Mix umbrella. The repository later
removed `apps_path`, replaced `in_umbrella` dependencies with explicit path
dependencies, and introduced a code-free Elixir Workspace root. That change
gave Cadence a visible project graph, affected-project testing, and enforceable
foundation, domain, and application layers.

The current repository is nevertheless a hybrid. Most child projects still
point to root-owned build and dependency state:

```elixir
build_path: "../../_build"
config_path: "../../config/config.exs"
deps_path: "../../deps"
lockfile: "../../mix.lock"
```

Those shared paths preserve the defining coupling of an umbrella even though
the root is no longer an umbrella project. A change to the shared configuration
or lockfile affects every project. A child project does not fully own the inputs
needed to build, test, configure, or release itself.

The existing projects also have two different architectural roles:

- `cadence`, `cadence_web`, and `cadence_simulator` own runtime behavior,
  supervision, persistence, endpoints, or an independently running process;
- `cadence_catalog` and `ccsds` are reusable dependency leaves with no
  application callback or supervision tree.

Keeping both roles under one `apps/` directory obscures the distinction between
a runtime-bearing application and a package intended to be consumed by other
applications.

Cadence needs stronger project ownership without losing the advantages of one
repository, one dependency graph, affected-project checks, and an authoritative
aggregate precommit gate. It does not currently need a network boundary between
the Phoenix interface and the core runtime, a separate repository for every
project, or a service for every bounded context.

## Decision

Cadence will use a **monorepo poncho** architecture: independently owned Mix
projects connected by explicit path dependencies and coordinated by one
code-free Elixir Workspace root.

The target layout is:

```text
cadence/
├── apps/
│   ├── cadence/
│   ├── cadence_web/
│   └── cadence_simulator/
├── packages/
│   ├── cadence_catalog/
│   └── ccsds/
├── .workspace.exs
└── mix.exs
```

The `apps/` and `packages/` names express ownership rather than changing Mix or
OTP semantics. Every child remains a Mix project and produces an OTP
application specification. The distinction is whether the project owns runtime
or deployment behavior or is a reusable dependency leaf.

### 1. The Workspace Root Is Orchestration Only

The repository root will remain a code-free Workspace project with
`elixirc_paths: []` and no `apps_path`.

It may own repository-wide developer tooling and orchestration, including:

- dependency-graph and boundary checks;
- affected-project selection;
- formatting and static analysis;
- aggregate test lanes;
- the authoritative `mix precommit` alias; and
- cross-project integration-test orchestration.

It will not be a production release root, own production configuration, or
implicitly start Cadence applications. Root dependencies required only for
tooling will use `runtime: false` where applicable.

The root may import an application composition's build-time configuration when
Mix needs it to validate tooling-only path dependencies. Such a shim defines no
settings of its own, has no runtime counterpart, and does not make the root a
release entry point.

Ordinary application commands will run from the owning project. In particular,
the Phoenix server will run from `apps/cadence_web`, and the simulator will run
from `apps/cadence_simulator`. The root `mix test` command is an aggregate
Workspace gate; it does not translate root-relative child test paths. Focused
tests run from the owning application or package with paths relative to that
project.

### 2. Applications Live Under `apps/`

A project belongs under `apps/` when it owns one or more of:

- an application callback or supervision tree;
- a database or durable runtime lifecycle;
- a network endpoint;
- a release entry point;
- a separately running operating-system process; or
- application-specific runtime configuration.

The initial application set is:

#### `apps/cadence`

`cadence` owns the core domain, Postgres repository, management, control,
runtime, projection, and job supervision trees. It remains independently
startable and testable even when it is normally composed into the web release.

#### `apps/cadence_web`

`cadence_web` owns Phoenix, HTTP, LiveView, assets, mail delivery, and the
operator-facing release entry point. It depends directly on `cadence` and may
configure that dependency as part of composing the Cadence server release.

`cadence_web` and `cadence` will continue to run in one BEAM by default. This
ADR does not introduce an HTTP, RPC, or message-broker boundary between them.

#### `apps/cadence_simulator`

`cadence_simulator` owns its provider API, scenario runtime, persistence, and
configuration. It runs in a process separate from the Cadence server and has no
production dependency on `cadence`.

Explicit test-only dependencies may support workspace integration tests, but
they must not leak Cadence configuration or startup requirements into the
simulator's unit tests, production dependency graph, or production release.

### 3. Reusable Dependency Leaves Live Under `packages/`

A project belongs under `packages/` when all of the following are true:

- it exposes a focused public API;
- it is a one-way dependency leaf within the Cadence graph;
- it has no Phoenix or Cadence Repo dependency;
- its focused tests do not require Cadence application boot;
- it owns no product deployment lifecycle; and
- callers provide effects and deployment-specific policy explicitly.

Packages should prefer explicit function arguments, typed options, behaviors,
and caller-owned adapters over global application configuration. A package may
use ordinary library dependencies and OTP facilities without becoming an
`apps/` project, provided it does not take ownership of a Cadence product
runtime.

The initial package set is:

#### `packages/ccsds`

`ccsds` owns protocol codecs, validation, segmentation, reassembly,
state machines, and caller-owned CCSDS effects as established by ADR-014.

#### `packages/cadence_catalog`

`cadence_catalog` owns source-format parsing, Mission Model declarations and
compilation, deterministic target plans, and catalog validation. Cadence
activation, persistence, authorization, deployment bindings, and runtime
execution remain application concerns.

Moving a context into `packages/` is not a generic modularization technique.
New packages require a stable leaf API and evidence that the extraction removes
dependency pressure rather than relocating it.

### 4. Every Child Project Owns Its Mix State

Each application and package will own:

- its `mix.exs`;
- its lockfile;
- its build directory;
- its fetched dependency directory;
- its compile and test support paths; and
- its configuration files when configuration is required.

Child projects will remove `build_path`, `config_path`, `deps_path`, and
`lockfile` overrides that point at repository-root state. Internal dependencies
will remain explicit relative `path:` dependencies.

Independent ownership means a contributor or CI job can enter any child
project, fetch its dependencies, compile it, and run its focused tests without
first building another repository project unless that project is an explicit
dependency.

Separate lockfiles may resolve different compatible transitive versions for
different application or package roots. Cadence will manage that cost through
automated dependency updates and workspace checks rather than recreating a
hidden shared lockfile contract.

### 5. Configuration Follows the Composition Root

Configuration will be owned by the project that constructs the running system:

- `cadence` owns standalone core defaults, repository configuration, and its
  focused test configuration;
- `cadence_web` owns Phoenix configuration and the production Cadence server
  composition, including explicit overrides for its `cadence` dependency;
- `cadence_simulator` owns all simulator configuration; and
- packages avoid deployment configuration and provide code-level defaults or
  explicit configuration contracts.

A child project will not import the repository-root production configuration.
Cross-project integration tests will construct the configuration they need
explicitly or use a dedicated integration harness. They will not make shared
root configuration an undocumented prerequisite of focused child tests.

Application dependencies do not load their own Mix configuration when consumed
by another project. Consequently, application-owned defaults must either be
code-level defaults or be deliberately supplied by the composing application.
The migration must test both standalone and composed startup so configuration
does not disappear accidentally when shared root files are removed.

### 6. Project Dependencies Remain Explicit And One-Way

The initial production dependency direction remains:

```text
apps/cadence_web
    ├──> apps/cadence
    └──> packages/cadence_catalog

apps/cadence
    ├──> packages/cadence_catalog
    └──> packages/ccsds

apps/cadence_simulator
    ├──> packages/cadence_catalog
    └──> packages/ccsds
```

`cadence_simulator` may retain an explicit test-only dependency on `cadence`
while integration tests require it. That edge is not part of the production
graph and should be removed if a dedicated integration project becomes the
clearer owner.

Workspace layer checks remain the coarse project boundary. Cadence's plane and
context architecture checks remain responsible for finer dependencies inside
`apps/cadence`. The poncho layout does not authorize arbitrary cross-project
calls or replace context-owned public APIs.

### 7. Project Separation Does Not Imply Service Separation

This decision separates build, dependency, configuration, test, and release
ownership. It does not require:

- separate repositories;
- separately deployed `cadence` and `cadence_web` services;
- network APIs between sibling projects;
- independent release versions for every project;
- a package for every bounded context; or
- changing in-process calls that correctly cross a declared public boundary.

A future service split requires an independent operational reason such as
failure isolation, scaling, security, deployment cadence, or resource
ownership. Directory placement alone is not sufficient evidence.

## Migration Sequence

The repository will migrate in verified slices rather than through one layout
rewrite.

1. Add this ADR and correct documentation that still calls the live Workspace
   root an umbrella.
2. Move and detach `ccsds`, then verify its focused suite and every
   consuming project.
3. Move and detach `cadence_catalog`, including removal of deployment-specific
   global configuration from the package boundary.
4. Complete `cadence_simulator` ownership of configuration, dependencies,
   builds, and tests while preserving its separate-process contract.
5. Give `cadence` independent configuration, dependency, build, migration, and
   test ownership.
6. Detach `cadence_web` last, make it the explicit Cadence server release root,
   and prove that it composes and starts `cadence` correctly.
7. Reduce the root project to tooling dependencies and aggregate orchestration,
   then update developer and deployment documentation.

Each slice must preserve the current public behavior and pass focused tests for
the changed project, focused tests for direct consumers, workspace boundary
checks, and the authoritative root precommit gate before completion.

## Acceptance Criteria

The migration is complete when:

- `apps/cadence`, `apps/cadence_web`, `apps/cadence_simulator`,
  `packages/cadence_catalog`, and `packages/ccsds` each build and run
  focused tests from their own directory;
- no child points `build_path`, `config_path`, `deps_path`, or `lockfile` at
  repository-root state;
- packages can run their tests without booting Cadence, Phoenix, or the
  simulator;
- `cadence_web` starts the Cadence server in one BEAM without starting the
  simulator;
- `cadence_simulator` starts independently without loading Cadence database,
  web, or background-job configuration;
- the root contains no product code or production release configuration;
- Workspace affected-project selection follows every internal path dependency;
- Workspace layer checks and Cadence context and plane checks remain clean; and
- the authoritative root `mix precommit` gate passes from an independently
  fetched checkout.

## Consequences

### Positive

- Application and package ownership becomes visible in the repository layout.
- Each child can evolve configuration and compatible dependency versions
  without an implicit root-wide contract.
- Package boundaries become honest enough for later Hex or repository
  extraction if external consumers or release cadence justify it.
- Application releases become explicit composition roots.
- Focused builds and tests exercise the same ownership boundaries expected in
  CI and deployment.
- The repository keeps one graph, affected checks, architecture enforcement,
  and aggregate validation.

### Costs

- Dependency downloads and compiled artifacts may be duplicated across child
  projects.
- Multiple lockfiles require coordinated security and dependency maintenance.
- A full workspace gate may compile the same transitive dependency for more
  than one project root.
- Configuration currently inherited from the root must be identified,
  classified, and moved deliberately.
- Cross-project integration fixtures and test support can no longer depend on
  accidental shared load paths or configuration.
- Local commands must be run from the owning application unless the root
  explicitly orchestrates them.

These costs are accepted because they make project independence real and
observable instead of relying on directory names and unenforced intent.

## Alternatives Rejected

### Retain The Hybrid Workspace With Shared Umbrella Mechanics

Rejected because explicit path dependencies alone do not provide independent
build, lock, configuration, or release ownership while every child points to
root state.

### Return To A Mix Umbrella

Rejected because the convenience of one recursive Mix project does not justify
coupling all applications and packages to one configuration and dependency
resolution lifecycle.

### Collapse Cadence Into One Mix Project

Rejected because the CCSDS, catalog, simulator, core, and web boundaries have
different consumers and runtime responsibilities. Collapsing them would remove
useful, already enforced dependency direction.

### Split Every Project Into A Separate Repository

Rejected because Cadence benefits from atomic cross-project changes, one
architecture graph, affected testing, and one authoritative gate. Repository
separation can be reconsidered for an individual package when independent
consumers or release cadence provide concrete evidence.

### Deploy Every Application As A Separate Service

Rejected because build-time modularity does not itself justify distributed
failure modes, network contracts, deployment coordination, or operational
overhead. The Cadence server remains one BEAM by default.

### Create A Package For Every Bounded Context

Rejected because many Cadence contexts still share persistence, runtime, and
application lifecycle concerns. Context boundaries should be made one-way and
explicit inside `apps/cadence`; only proven dependency leaves belong under
`packages/`.

## References

- [Mix.Project: Umbrella Projects](https://hexdocs.pm/mix/Mix.Project.html#module-umbrella-projects)
- [Mix.Project: Undoing Umbrellas](https://hexdocs.pm/mix/Mix.Project.html#module-undoing-umbrellas)
- [Workspace](https://hexdocs.pm/workspace/Workspace.html)
