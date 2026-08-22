---
title: Configuration Reference
tags: [reference, developer, config, env, profiles, runtime]
status: active
created: 2026-04-03
updated: 2026-08-21
---

# Configuration Reference

This document summarizes the main configuration surfaces used by Cadence
runtime, local tooling, and production deployment.

Use this as a quick reference when you need to answer:

- which backend is Cadence using by default?
- which env vars matter for the environment administrator and production?
- what fields exist in a dev profile?
- how do profiler tasks attach to a named node?

## 1. Runtime defaults in application-owned configuration

The main runtime defaults currently live in:

- [`apps/cadence/config/config.exs`](../../apps/cadence/config/config.exs)

The Phoenix composition root imports those core defaults and adds web policy in
[`apps/cadence_web/config/config.exs`](../../apps/cadence_web/config/config.exs).

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

- `Cadence.Telemetry.HistoryStore.ETS`

This keeps a bounded local recent-history window for runtime reads.

### Schedulers and background jobs

Defaults include enabled runtime workers for:

- mission-owned contact scheduling
- command dispatch
- command verifier scheduling
- background jobs

These are controlled through:

- `:contact_scheduler`
- `:contact_scheduler_global_safety`
- `:command_dispatcher`
- `:command_verifier_scheduler`
- `:background_jobs`
- `:start_background_jobs`

`:contact_scheduler` controls mission-scoped schedulers started under
`Cadence.Runtime.MissionRuntime`.

Mission schedulers emit `[:cadence, :contacts, :scheduler, event]` telemetry
for `:notification`, `:projection_rebuild`, `:timer_scheduled`,
`:timer_fired`, `:stale_timer`, `:reconcile`, and `:safety_reconcile`.

`:contact_scheduler_global_safety` controls the legacy no-mission global
contact scheduler. It is disabled by default; manual global reconciliation
remains available through `Cadence.Contacts.reconcile/1`.

`:command_dispatcher` controls durable command queue dispatch. Queue writes and
release-target contact changes kick affected lanes directly. Lane dispatchers
use timers for `not_before` delays, and `:safety_poll_interval_ms` /
`:lane_safety_poll_interval_ms` control slow durable recovery scans.

Command dispatch emits `[:cadence, :commanding, :dispatcher, event]` telemetry
for dispatcher reconcile events, and
`[:cadence, :commanding, :lane_dispatcher, event]` telemetry for
`:dispatch_attempt`, `:dispatch_result`, `:timer_scheduled`, and
`:stale_timer`.

`:command_verifier_scheduler` controls the command verifier timeout scheduler.
The default path keeps pending verifier timeout deadlines in memory, schedules
the next due timeout with a process timer, and uses `:safety_poll_interval_ms`
as a slow durable recovery scan.

Verifier schedulers emit
`[:cadence, :commanding, :verifier_scheduler, event]` telemetry for
`:notification`, `:projection_rebuild`, `:timer_scheduled`, `:timer_fired`,
`:stale_timer`, `:reconcile`, and `:safety_reconcile`.

`:start_background_jobs` enables or disables the background jobs supervisor.
`:background_jobs` configures the durable jobs dispatcher, including
`:max_concurrency` and `:safety_poll_interval_ms`. Job enqueue signals and
worker-exit monitors drive normal dispatch; the safety interval is only the
durable recovery scan.

Background jobs emit `[:cadence, :jobs, :dispatcher, event]` telemetry for
`:notification`, `:dispatch_attempt`, `:jobs_claimed`, `:worker_started`,
`:worker_start_failed`, `:safety_dispatch_scheduled`, and `:stale_timer`.

These telemetry events are the operational view of the BEAM-owned data plane.
Normal steady-state activity should show notifications, exact timers, dispatch
attempts, and worker transitions. Safety reconcile or safety dispatch events
should be present as a recovery signal, not as the dominant source of runtime
work. The architecture guard in
`apps/cadence/test/cadence/architecture_runtime_guard_test.exs` protects those
defaults from regressing back to tight database polling.

`Cadence.Telemetry.RuntimeHealth` is supervised with the application and
subscribes to the same scheduler and dispatcher telemetry events. Its
`snapshot/0` API exposes process-local counters by source, event, and reason,
plus stale-timer and safety-activity totals and a bounded recent-event list.
This view is intentionally in memory only; it is suitable for a runtime health
page or alert adapter, not as durable audit history.

## 2. Environment administrator in runtime configuration

The environment administrator is configured in:

- [`apps/cadence_web/config/runtime.exs`](../../apps/cadence_web/config/runtime.exs)

Primary env vars:

- `CADENCE_ADMIN_EMAIL`
- `CADENCE_ADMIN_PASSWORD`

Optional env vars:

- `CADENCE_ADMIN_DISPLAY_NAME`
- `CADENCE_ADMIN_MODE_TTL_SECONDS`

Behavior:

- email and password must be configured together
- the reserved administrator is available only while those credentials are configured
- it uses the normal browser sign-in flow and enters admin mode immediately
- durable platform administrators reauthenticate to enter time-bounded admin mode

## 3. Production environment composition

For `config_env() == :prod`, Cadence currently expects:

- `DATABASE_URL`
- `POOL_SIZE`
- `PHX_HOST`
- `PORT`
- `SECRET_KEY_BASE`

These configure:

- `Cadence.Repo`
- `CadenceWeb.Endpoint`

The web application is the production composition root, so
[`apps/cadence_web/config/runtime.exs`](../../apps/cadence_web/config/runtime.exs)
owns both core runtime settings and endpoint settings. Runtime configuration
cannot import another configuration file in an Elixir release.

Optional production settings:

- `CADENCE_DATA_SOURCE_CREDENTIAL_ENV_PROFILES`

`CADENCE_DATA_SOURCE_CREDENTIAL_ENV_PROFILES` enables the default BYO Data
Source secret-backend path. Runtime config wires
`Cadence.Management.DataSources.Credentials.SecretMaterialResolver` to
`Cadence.Management.DataSources.Credentials.EnvSecretBackend`; the older
`EnvMaterialResolver` remains a compatibility entry point. The value is a JSON
object keyed by non-secret credential material profile name. Each profile maps
material fields to environment variable names, not to secret values:

```json
{
  "customer-rehearsal": {
    "http_endpoint_env": "CUSTOMER_REHEARSAL_QUESTDB_HTTP_ENDPOINT",
    "bearer_token_env": "CUSTOMER_REHEARSAL_QUESTDB_BEARER",
    "headers_env": {
      "x-cadence-tenant": "CUSTOMER_REHEARSAL_QUESTDB_TENANT"
    }
  }
}
```

Credential metadata may then store
`{"material_env_profile": "customer-rehearsal"}`. Cadence reads the referenced
environment variables only while resolving ephemeral adapter material and keeps
the values out of persisted source, event, health, dashboard, and UI payloads.
Mission-scoped material-resolution attempts are still audited as canonical
security events; those events record only authorizer/resolver identity, actor,
credential reference, result, material field names, and redacted failure or
denial classes. The
generic resolver also validates backend material before adapter handoff,
including endpoint userinfo rejection and ambiguous bearer/basic auth rejection.

Deployments can also configure a `:material_authorizer` under
`:data_source_credentials`, or pass `:credential_material_authorizer` per
call. The authorizer sees the resolved non-secret credential descriptor and
scope context, and can deny material access before the secret backend is called.
Denials are audited as redacted security events. The default path is currently
permissive and marked `todo(authz)` until the broader RBAC model exists.

External secret-manager URLs must use HTTPS by default. Local or test-only
deployments that intentionally use plain HTTP must set
`allow_insecure_secret_manager_http?: true` in the credential resolution opts or
`:data_source_credentials` config; otherwise material resolution fails
closed before any request is sent.

For early BYO setup flows, credential metadata may also store non-secret
environment variable names directly, for example
`{"material_env_profile": "customer-rehearsal", "http_endpoint_env": "CUSTOMER_REHEARSAL_QUESTDB_HTTP_ENDPOINT"}`.
The UI stores only those env names and endpoint/profile references; the endpoint,
token, password, and header values still come from process environment at probe
or adapter execution time.

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
- `frame.fecf`

`frame.fecf: true` enables the managed two-octet CCSDS Frame Error Control
Field on generated TM transfer frames. In `cop1_loopback` profiles, the
top-level `fecf: true` setting validates and removes the managed FECF from TC
transfer frames before reassembly.

`cop1_loopback` profiles also accept a `farm` map with these managed FARM-1
receiver settings:

- `initial_vr` (default `0`)
- `positive_window_width` (default `127`)
- `negative_window_width` (default `127`)
- `retransmission_allowed` (default `true`)

With Cadence bootstrap, `initial_vr` is derived from the selected uplink
gateway runtime's current `next_frame_seq`. FARM-1 state is then maintained
independently for each received TC virtual channel and is not reset by a TCP
reconnect.

### Uplink gateway COP-1

An uplink gateway transport binding enables the shared FOP-1B sender with
`cop1_mode: "fop"`. Its managed settings are:

- `initial_frame_seq` (default `0`): initial V(S) and NN(R);
- `cop1_timeout_ms` (default `5000`): T1 initial duration;
- `cop1_max_retransmit` (default `3`): retransmissions after the initial
  transmission, so the standard Transmission_Limit is this value plus one;
- `cop1_window_size` (default `1`): FOP sliding-window K in `1..255`; it must
  not exceed the peer FARM positive-window width; and
- `cop1_timeout_type` (default `0`): `0` raises Alert[T1] at the transmission
  limit, while `1` suspends AD service for later management recovery.

Cadence initializes AD service without a CLCW check and uses one replaceable T1
timer per TC virtual channel. The standard initialize-with-check, Unlock, Set
V(R), terminate, resume, and setup directives are available from the shared
`Cadence.CCSDS.Transport.COP1.FOP` library for runtimes that expose a COP
management boundary.

Relative paths in profiles are resolved relative to the profile file.

### `profiler`

Common fields include:

- `node`
- `mission_id`

These provide defaults for:

- `mix cadence.profile`

## 5. Named-node attachment and cookies

The live profiler tasks attach to a running named Cadence node.

Typical local startup:

```bash
cd apps/cadence_web
iex --sname cadence -S mix phx.server
```

The profiler tasks will use the local cookie by default. If you need to
override it, use:

- `CADENCE_NODE_COOKIE`

They also respect:

- `ERL_COOKIE`

This matters for:

- `mix cadence.profile`

## 6. Simulator performance flags commonly used in docs

These are not app env vars, but they are common operational knobs in the local
docs bundle:

- `--metrics-sample-rate N`
- `--tm-parallel-framing`
- `--tm-worker-fast-path`
- `--sink-port <port>`

Use these as direct `cadence_simulator` CLI options, not Cadence application
configuration.

## 7. Where to add new config

Use this rule of thumb:

- durable core defaults -> `apps/cadence/config/config.exs`
- environment-sensitive product settings -> `apps/cadence_web/config/runtime.exs`
- Phoenix and server composition -> `apps/cadence_web/config/`
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

- `apps/cadence/config/config.exs`
- `apps/cadence_web/config/runtime.exs`
- another application-owned `config/` directory
- `dev/profiles/*.yaml`
- or a task/CLI flag

Do not scatter the same concern across all four unless there is a strong reason.
