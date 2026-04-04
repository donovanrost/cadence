---
title: Configuration Reference
tags: [reference, developer, config, env, profiles, runtime]
status: active
created: 2026-04-03
updated: 2026-04-03
---

# Configuration Reference

This document summarizes the main configuration surfaces used by Cadence
runtime, local tooling, and production deployment.

Use this as a quick reference when you need to answer:

- which backend is Cadence using by default?
- which env vars matter for bootstrap admin and production?
- what fields exist in a dev profile?
- how do profiler tasks attach to a named node?

## 1. Runtime defaults in `config/config.exs`

The main runtime defaults currently live in:

- [`config/config.exs`](../../config/config.exs)

Important keys:

### `:ingress_archive`

Default:

- `Cadence.IngressArchive.FileSystem`

Default options:

- `base_path: var/ingress_archive`
- `flush_interval_ms: 250`
- `flush_count: 100`

### `:protocol_record_archive`

Default:

- `Cadence.Protocol.RecordArchive.FileSystem`

Default options:

- `base_path: var/protocol_record_archive`
- `flush_interval_ms: 250`
- `flush_count: 250`

### `:telemetry_current_value_store`

Default:

- `Cadence.Telemetry.CurrentValueStore.ETS`

This is the hot-path-safe latest-value backend.

### `:telemetry_history_store`

Default:

- `Cadence.Telemetry.HistoryStore.Noop`

This keeps sample-history persistence off the default runtime hot path.

### Schedulers and background jobs

Defaults include enabled schedulers for:

- contact scheduling
- command dispatch
- command verifier scheduling
- background jobs

These are controlled through:

- `:contact_scheduler`
- `:command_dispatcher`
- `:command_verifier_scheduler`
- `:start_background_jobs`

## 2. Bootstrap admin env in `config/runtime.exs`

Bootstrap admin is configured in:

- [`config/runtime.exs`](../../config/runtime.exs)

Primary env vars:

- `CADENCE_BOOTSTRAP_ADMIN_ENABLED`
- `CADENCE_BOOTSTRAP_ADMIN_EMAIL`
- `CADENCE_BOOTSTRAP_ADMIN_PASSWORD`

Optional env vars:

- `CADENCE_BOOTSTRAP_ADMIN_USER_ID`
- `CADENCE_BOOTSTRAP_ADMIN_DISPLAY_NAME`
- `CADENCE_BOOTSTRAP_ADMIN_SESSION_TTL_SECONDS`

Behavior:

- when enabled, Cadence ensures a real persisted bootstrap admin user exists
- when disabled, that bootstrap login path is not available

## 3. Production env in `config/runtime.exs`

For `config_env() == :prod`, Cadence currently expects:

- `DATABASE_URL`
- `POOL_SIZE`
- `PHX_HOST`
- `PORT`
- `SECRET_KEY_BASE`

These configure:

- `Cadence.Repo`
- `CadenceWeb.Endpoint`

## 4. Dev profile structure

Profile-driven local tooling is loaded through:

- [`Cadence.DevProfile`](../../apps/cadence/lib/cadence/dev_profile.ex)

Profiles live under:

- [`dev/profiles`](../../dev/profiles)

Current example:

- [`demo_spacecraft.yaml`](../../dev/profiles/demo_spacecraft.yaml)

The loader expects a YAML map and currently understands three main sibling
sections:

- `bootstrap`
- `simulator`
- `profiler`

### `bootstrap`

Common fields include:

- `cadence_url`
- `organization_id`
- `organization_slug`
- `organization_display_name`
- `mission_id`
- `mission_slug`
- `mission_display_name`
- `spacecraft_id`
- `spacecraft_display_name`
- `source_endpoint_id`
- `source_ref`
- `source_endpoint_display_name`
- `definitions_path`
- `downlink_provider_port`
- `contact_start_delay_seconds`
- `contact_duration_seconds`
- `issue_mission_token`

### `simulator`

Common fields include:

- `runtime_mode`
- `definitions`
- `target`
- `rate`
- `provider`
- `parallel`
- `output.protocol`
- `output.host`
- `output.port`
- `frame.tm_frame_size`
- `frame.scid`
- `frame.vcid`

Relative paths in profiles are resolved relative to the profile file.

### `profiler`

Common fields include:

- `node`
- `mission_id`

These provide defaults for:

- `mix cadence.profile`
- `mix cadence.profile_sweep`

## 5. Named-node attachment and cookies

The live profiler tasks attach to a running named Cadence node.

Typical local startup:

```bash
iex --sname cadence -S mix phx.server
```

The profiler tasks will use the local cookie by default. If you need to
override it, use:

- `CADENCE_NODE_COOKIE`

They also respect:

- `ERL_COOKIE`

This matters for:

- `mix cadence.profile`
- `mix cadence.profile_sweep`

## 6. Simulator performance flags commonly used in docs

These are not app env vars, but they are common operational knobs in the local
docs bundle:

- `--metrics-sample-rate N`
- `--tm-parallel-framing`
- `--tm-worker-fast-path`
- `--sink-port <port>`

These are primarily used by:

- `mix cadence.profile_sweep`
- `mix cadence.sink_sweep`

Use them as task-level overrides, not application config.

## 7. Where to add new config

Use this rule of thumb:

- durable application/runtime defaults -> `config/config.exs`
- environment-sensitive production settings -> `config/runtime.exs`
- local developer workflow defaults -> `dev/profiles/*.yaml`
- one-off experiment knobs -> task or CLI flags

If a new setting only matters to one local workflow, prefer a dev profile or
task flag over another environment variable.

## 8. Quick checklist

When adding new configuration, decide:

- is this a runtime backend default?
- is it environment-sensitive?
- is it only for local dev workflow?
- is it only for a single experiment or benchmark?

Then place it in:

- `config/config.exs`
- `config/runtime.exs`
- `dev/profiles/*.yaml`
- or a task/CLI flag

Do not scatter the same concern across all four unless there is a strong reason.
