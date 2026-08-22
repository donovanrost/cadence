---
title: Profile Cadence Telemetry Ingress
tags: [how-to, profiling, telemetry, runtime, simulator]
status: active
created: 2026-04-03
updated: 2026-08-21
---

# Profile Cadence Telemetry Ingress

This guide shows how to use the built-in profiler tasks to understand where
Cadence spends time in the live telemetry ingress path.

## 1. Start the server as a named node

The profiler task connects to a running Cadence node, so start the server like
this:

```bash
cd apps/cadence_web
iex --sname cadence -S mix phx.server
```

## 2. Start a traffic source

Start the external provider simulator in another shell, then schedule a contact
from Cadence using its configured provider profile:

```bash
cd apps/cadence_simulator
CADENCE_SIMULATOR_HTTP_ENABLED=true mix run --no-halt
```

See [Simulator Provider Integration Flow](../simulator_provider_integration_flow.md)
for provider and mission setup.

## 3. Watch the live profiler

Use the profile-driven profiler task:

```bash
mix cadence.profile demo_spacecraft
```

Useful variants:

Reset first:

```bash
mix cadence.profile demo_spacecraft --reset
```

Print one snapshot and exit:

```bash
mix cadence.profile demo_spacecraft --snapshot
```

Adjust sampling duration and interval:

```bash
mix cadence.profile demo_spacecraft --duration 20 --interval 500
```

## 4. Compare selected rates

Update the simulator-owned scenario/run rate, reset the profiler, and capture a
snapshot for each selected rate:

```bash
mix cadence.profile demo_spacecraft --reset
mix cadence.profile demo_spacecraft --snapshot
```

Record the simulator run ID and rate with each sample so comparisons remain
reproducible.

## 5. Read the output

Important columns:

- `ingress/s`
  Cadence-side ingress messages per second
- `packets/s`
  extracted packet throughput
- `samples/s`
  telemetry sample throughput
- `avg_ms(resolve/runtime/persist/e2e)`
  average stage timings
- `db_q/ing`, `db_ms/ing`
  live database cost per ingress
- `arch(q/old_ms/fl_ms/seg_kb/fail)`
  archive queue depth, age, flush behavior, and failures
- `sim(tx/s/mbps/q/fl/sz_kb)`
  simulator-side send statistics

Interpret the columns carefully:

- `e2e` is the ordered live lane
- `persist` is async projector work and can be larger than `e2e`
- a flat `db_q/ing` with healthy archive stats usually means the bottleneck is
  elsewhere
- if simulator-side Mbps is flat while Cadence-side queues stay healthy, the
  simulator is likely the limiter

## 6. When to use sink benchmarking instead

If you need to separate simulator throughput from Cadence throughput, use the
[standalone sink benchmark](benchmark-simulator-throughput.md). That removes
Cadence from the loop.

## 7. When you need deeper inspection

The profiler tasks are good for steady-state measurement. When you need BEAM
process-level hot spots, use live node inspection and standard BEAM tools
against the named node.

That is the right next step when:

- profiler stage timings are flat but throughput still plateaus
- queue growth suggests one runtime process is saturated
- you need to tell whether a bottleneck is in a provider, executor, or
  projector
