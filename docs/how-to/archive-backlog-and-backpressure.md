---
title: Archive Backlog and Backpressure
tags: [how-to, operations, archive, backpressure, runtime, profiling]
status: active
created: 2026-04-03
updated: 2026-04-03
---

# Archive Backlog and Backpressure

This guide explains how to inspect and reason about archive backlog and
backpressure in the live Cadence runtime.

Use it when:

- throughput plateaus unexpectedly
- archive queue age starts climbing
- you suspect the provider, executor, or projector is falling behind
- you need to decide whether the bottleneck is Cadence or the simulator

## 1. Know the moving parts

The relevant path-local workers are:

- provider runtime
- [`Cadence.Runtime.ProviderIngressExecutor`](../../apps/cadence/lib/cadence/runtime/provider_ingress_executor.ex)
- [`Cadence.Runtime.IngressPersistenceProjector`](../../apps/cadence/lib/cadence/runtime/ingress_persistence_projector.ex)
- archive backend workers behind:
  - [`Cadence.IngressArchive`](../../apps/cadence/lib/cadence/ingress_archive.ex)
  - [`Cadence.Protocol.RecordArchive`](../../apps/cadence/lib/cadence/protocol/record_archive.ex)

The intended flow is:

1. provider adapts transport into ingress units
2. executor performs ordered live work
3. projector performs async durable writes
4. archive workers batch and flush archive segments

Backpressure should prefer bounded flow and queue growth limits over unbounded
memory growth.

## 2. Start with the profiler

The fastest first check is:

```bash
mix cadence.profile demo_spacecraft --snapshot
```

Or a stepped sweep:

```bash
mix cadence.profile_sweep demo_spacecraft --rates 100,200,400 --sample-seconds 30 -- --metrics-sample-rate 0
```

The most important archive column is:

- `arch(q/old_ms/fl_ms/seg_kb/fail)`

Interpret it as:

- `q`
  current archive queue depth
- `old_ms`
  age of the oldest buffered archive item
- `fl_ms`
  average archive flush time
- `seg_kb`
  average segment size
- `fail`
  archive flush failures

## 3. What healthy looks like

Healthy steady-state usually looks like:

- `fail = 0`
- `q` stays modest or oscillates within a bounded range
- `old_ms` stays low and stable
- `fl_ms` and `seg_kb` rise gradually with load, not catastrophically

A little queueing is normal. Flat, bounded queueing is not the same thing as a
broken pipeline.

## 4. What unhealthy looks like

Common bad patterns:

### Archive wedge

- `fail` rises
- `q` keeps growing
- `old_ms` keeps growing
- `fl_ms` may collapse to zero if almost no flushes succeed

This usually means archive flush failures or a poisoned queue.

### Executor saturation

- Cadence ingress throughput plateaus
- archive still looks mostly healthy
- path-local executor queue grows
- projector queue may stay modest

This usually means the ordered live lane is the bottleneck.

### Projector saturation

- projector queue grows faster than it drains
- `persist` stage time rises
- archive may remain healthy if the projector is the limiting step before the
  archive workers

### Simulator-limited test

- Cadence-side queues stay healthy
- simulator-side Mbps is flat
- archive stays healthy

In that case, Cadence may not be the bottleneck at all.

## 5. Inspect the path runtime snapshot

When the profiler is not enough, inspect the realized-contact path runtime.

The low-level runtime endpoint is:

```bash
curl -sS \
  -H "authorization: Bearer $API_TOKEN" \
  http://127.0.0.1:4001/api/organizations/<org>/missions/<mission>/realized_contacts/<contact>/paths/<path>/runtime
```

The response includes provider runtime snapshots. For the TCP provider, those
snapshots include:

- `reads_paused?`
- provider ingress counters
- `ingress_executor`
- `ingress_persistence_projector`

Important nested fields to inspect:

### Provider

- `connected?`
- `downlink_message_count`
- `tcp_read_count`
- `avg_tcp_read_bytes`
- `reads_paused?`
- `last_ingress_error`

### Ingress executor

- `queue_depth`
- `processing?`
- `projector_backpressured?`
- `pending_persistence_batch_count`
- `processed_count`
- `failed_count`
- `last_error`

### Persistence projector

- `queue_depth`
- `processing?`
- `persisted_count`
- `failed_count`
- `last_error`

## 6. Interpret the runtime snapshot

Use these rules of thumb.

### `reads_paused? = true`

The provider is deliberately stopping reads because downstream pressure crossed
the executor watermark.

That means the provider is not the root bottleneck. It is responding to it.

### Executor queue grows, projector queue stays small

The ordered live lane is slower than provider ingress.

Look at:

- mission runtime work
- partition owner work
- executor batching

### Projector queue grows, executor queue stays small

The async persistence lane is slower than the live lane.

Look at:

- persistence batch sizing
- archive writes
- low-rate Postgres projections

### `last_error` is non-nil

Treat that as a real signal, not noise. It often tells you whether you have:

- archive flush failures
- bad persistence assumptions
- provider runtime disconnects

## 7. Distinguish Cadence pressure from simulator pressure

Use the sink benchmark when needed:

```bash
mix cadence.sink_sweep demo_spacecraft --rates 800,1600,3200 --sample-seconds 30 --sink-port 4200 -- --metrics-sample-rate 0
```

If the simulator can deliver much higher Mbps to a dumb sink than Cadence sees,
then the bottleneck is in the Cadence-coupled path.

If the simulator plateaus in the same range even against the dumb sink, the
simulator is the limiting factor.

## 8. Common corrective actions

Choose the action that matches the failing layer.

### Archive failures

- inspect `last_flush_error`
- verify archive index/schema assumptions
- verify segment write path and base path permissions
- confirm flushes recover after error

### Executor pressure

- reduce synchronous work in the ordered lane
- batch executor work where possible
- move derived persistence off the hot path

### Projector pressure

- batch persistence more aggressively
- stop persisting high-rate derived data as OLTP rows
- reduce retained payload size per batch item

### Simulator pressure

- use sink benchmarking
- inspect simulator tx Mbps and queue columns
- avoid blaming Cadence before the sink comparison

## 9. A practical escalation order

When investigating a throughput problem, use this order:

1. run `mix cadence.profile ... --snapshot`
2. run `mix cadence.profile_sweep ...`
3. inspect the path runtime snapshot
4. compare against `mix cadence.sink_sweep ...`
5. only then move to live BEAM process profiling

That keeps the investigation grounded in the existing observability surfaces
before dropping to process-level tooling.
