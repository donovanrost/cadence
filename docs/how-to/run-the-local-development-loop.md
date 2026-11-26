---
title: Run the Local Development Loop
tags: [how-to, developer, simulator, profiler, provider]
status: active
created: 2026-04-03
updated: 2026-08-21
---

# Run the Local Development Loop

This guide describes the normal local workflow for working on Cadence with the
external simulator and the live profiler.

The intended process model is:

- one Cadence server BEAM
- one simulator BEAM
- one short-lived profiler task process

The simulator is never run inside the Cadence server process. The profiler is a
short-lived Cadence developer task.

## 1. Start the worktree stack

Follow [Per-worktree development environment](../dev-environment.md) and run `dev/stack up`.
It creates this worktree's credentials, database, QuestDB, simulator, Phoenix server, and console.
The stack starts Phoenix as a named node with the slot's private cookie, so profiler tasks can
attach to it.

## 2. Configure the mission

In Cadence, create an ordinary provider profile under **Comms → Providers** and
enable its external scheduling integration. Point it at the simulator URL and
token, then configure the normal telemetry listener and mission paths.

Follow [Simulator Provider Integration Flow](../simulator_provider_integration_flow.md)
for the complete setup.

## 3. Inspect the live ingress path

To sample the live profiler while the simulator is running:

```bash
mise exec -- mix cadence.profile demo_spacecraft
```

To reset the profiler first:

```bash
mise exec -- mix cadence.profile demo_spacecraft --reset
```

To print one cumulative snapshot:

```bash
mise exec -- mix cadence.profile demo_spacecraft --snapshot
```

## 4. Run a stepped rate sweep

Create or update simulator scenarios and runs through its provider API, then
sample Cadence after each selected rate:

```bash
mise exec -- mix cadence.profile demo_spacecraft --reset
mise exec -- mix cadence.profile demo_spacecraft --snapshot
```

Keep contact scheduling and scenario control separate: Cadence reserves the
provider contact, while the simulator owns scenario/run administration.

## 5. Exercise the external provider boundary

To run the simulator independently and configure it through the same mission
provider surface used by a commercial ground-station provider, use:

- [Simulator Provider Integration Flow](../simulator_provider_integration_flow.md)

The simulator does not create or administer Cadence mission resources.

## 6. Run commit checks

Run focused tests from the project that owns them. Test paths are relative to
that project:

```bash
cd apps/cadence_web
mix test test/cadence_web/live/user_session_live_test.exs
```

Return to the repository root for aggregate Workspace gates. Root `mix test`
runs every project's default suite and intentionally does not route
`apps/<child>/...` or `packages/<child>/...` paths to child projects.

The default hk pre-commit hook runs the shared quality checks (format, compile
with warnings as errors, credo, workspace, extensions and architecture checks)
and no tests. Full suites run in CI; run the tests for the area you touched:

```bash
cd ../..
mix precommit.checks
```

To see which projects a change affects, and the package graph:

```bash
mix workspace.run -t test --affected
mix workspace.status
mix workspace.graph
mix workspace.check
```

`mix workspace.check` enforces the package-level foundation, domain, and
application dependency boundaries. The existing `mix
cadence.architecture.check` remains responsible for the finer module-level
plane and context boundaries inside the core application.

Before merging, run the authoritative aggregate gate explicitly:

```bash
mix precommit
```

To make hk run that full gate instead of the affected gate, enable its `full`
profile:

```bash
hk run pre-commit --profile full
```
