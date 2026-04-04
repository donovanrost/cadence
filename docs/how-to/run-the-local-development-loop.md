---
title: Run the Local Development Loop
tags: [how-to, developer, simulator, profiler, bootstrap]
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

The simulator and profiler are intentionally not run inside the Cadence server
process.

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

This gives the tooling a real persisted bootstrap admin user for first-boot
setup and profile bootstrap flows.

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

## 4. Start the simulator from a dev profile

The normal simulator entrypoint is profile-driven:

```bash
mix cadence.simulator demo_spacecraft
```

This task:

- loads `dev/profiles/demo_spacecraft.yaml`
- ensures the profile’s dev mission/contact/runtime exists
- resolves the simulator runtime settings
- starts the simulator in its own local BEAM process

You can pass normal simulator overrides after the profile name, for example:

```bash
mix cadence.simulator demo_spacecraft --rate 25.0
```

## 5. Inspect the live ingress path

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

## 6. Run a stepped rate sweep

To sweep simulator rates against the live Cadence runtime:

```bash
mix cadence.profile_sweep demo_spacecraft --rates 100,200,400 --sample-seconds 30 -- --metrics-sample-rate 0
```

This task:

- starts the simulator locally
- changes rates step by step
- resets and samples the live Cadence profiler
- prints Cadence-side and simulator-side summary metrics

## 7. Use the lower-level bootstrap flow only when needed

If you need to debug raw control-plane behavior, provider profiles, path
templates, or realized contact runtime state directly, use:

- [Simulator Contact Bootstrap Flow](../simulator_contact_bootstrap_flow.md)

That guide is for low-level debugging. It is not the preferred inner-loop
workflow.
