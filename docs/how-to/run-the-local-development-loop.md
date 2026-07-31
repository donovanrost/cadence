---
title: Run the Local Development Loop
tags: [how-to, developer, simulator, profiler, provider]
status: active
created: 2026-04-03
updated: 2026-07-30
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

## 1. Prepare the environment administrator

For local development, it is convenient to keep the administrator credentials in
`mise.toml` or your shell profile.

Required:

```toml
[env]
CADENCE_ADMIN_EMAIL = "admin@example.com"
CADENCE_ADMIN_PASSWORD = "change-me"
```

Optional:

```toml
CADENCE_ADMIN_DISPLAY_NAME = "Cadence Administrator"
CADENCE_ADMIN_MODE_TTL_SECONDS = "3600"
```

This makes the reserved environment administrator available through the normal
sign-in page and enters admin mode immediately. Removing both required variables
removes that access the next time Cadence starts.

## 2. Prepare the database

If you are starting from a fresh local database, run migrations first:

```bash
mix ecto.migrate
```

If you also need seed/setup work in your local environment, do that before
starting the server.

## 3. Start Cadence as a named node

For local profiling tasks, start Cadence with a distributed node name:

```bash
iex --sname cadence -S mix phx.server
```

Using `--sname cadence` lets the profiler tasks attach to the live node.

## 4. Start the simulator independently

From a second shell, start the external provider simulator:

```bash
cd apps/cadence_simulator
export CADENCE_SIMULATOR_HTTP_ENABLED=true
export CADENCE_SIMULATOR_PORT=4101
export CADENCE_SIMULATOR_ADMIN_API_TOKEN=local-simulator-admin-token
export CADENCE_SIMULATOR_PROVIDER_API_TOKEN=local-simulator-provider-token
mix run --no-halt
```

The simulator has its own configuration and supervision tree. Starting it does
not create a mission, contact, or runtime inside Cadence.

## 5. Configure the mission

In Cadence, create an ordinary provider profile under **Comms → Providers** and
enable its external scheduling integration. Point it at the simulator URL and
token, then configure the normal telemetry listener and mission paths.

Follow [Simulator Provider Integration Flow](../simulator_provider_integration_flow.md)
for the complete setup.

## 6. Inspect the live ingress path

To sample the live profiler while the simulator is running:

```bash
mix cadence.profile demo_spacecraft
```

To reset the profiler first:

```bash
mix cadence.profile demo_spacecraft --reset
```

To print one cumulative snapshot:

```bash
mix cadence.profile demo_spacecraft --snapshot
```

## 7. Run a stepped rate sweep

Create or update simulator scenarios and runs through its provider API, then
sample Cadence after each selected rate:

```bash
mix cadence.profile demo_spacecraft --reset
mix cadence.profile demo_spacecraft --snapshot
```

Keep contact scheduling and scenario control separate: Cadence reserves the
provider contact, while the simulator owns scenario/run administration.

## 8. Exercise the external provider boundary

To run the simulator independently and configure it through the same mission
provider surface used by a commercial ground-station provider, use:

- [Simulator Provider Integration Flow](../simulator_provider_integration_flow.md)

The simulator does not create or administer Cadence mission resources.

## 9. Run commit checks

The default hk pre-commit hook runs the shared quality checks and tests only
the Mix projects affected by the staged changes:

```bash
mix precommit.affected
```

Workspace follows the declared path dependencies transitively. For
example, a `cadence_ccsds` change also tests `cadence`, `cadence_simulator`, and
`cadence_web`, while a `cadence_web`-only change tests only `cadence_web`.
Changes to the root `mix.exs`, `mix.lock`, or shared `config` affect every
project.

Inspect the current selection and package graph with:

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
