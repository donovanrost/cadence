---
title: Run the Local Development Loop
tags: [how-to, developer, simulator, profiler, provider]
status: active
created: 2026-04-03
updated: 2026-04-03
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

## 1. Prepare bootstrap admin env

For local development, it is convenient to keep the bootstrap admin env in
`mise.toml` or your shell profile.

Required:

```toml
[env]
CADENCE_BOOTSTRAP_ADMIN_ENABLED = "true"
CADENCE_BOOTSTRAP_ADMIN_EMAIL = "bootstrap@example.com"
CADENCE_BOOTSTRAP_ADMIN_PASSWORD = "change-me"
```

Optional:

```toml
CADENCE_BOOTSTRAP_ADMIN_USER_ID = "bootstrap-admin"
CADENCE_BOOTSTRAP_ADMIN_DISPLAY_NAME = "Bootstrap Admin"
CADENCE_BOOTSTRAP_ADMIN_SESSION_TTL_SECONDS = "86400"
```

This creates a real persisted bootstrap admin user for first-boot setup.

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
export CADENCE_SIMULATOR_API_TOKEN=local-simulator-token
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
