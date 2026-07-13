---
title: Benchmark Simulator Throughput Against a Dumb Sink
tags: [how-to, simulator, benchmarking, sink, throughput]
status: active
created: 2026-04-03
updated: 2026-04-03
---

# Benchmark Simulator Throughput Against a Dumb Sink

This guide shows how to measure simulator throughput without Cadence in the
loop.

Use this when you need to answer:

- is the simulator itself the limiter?
- how much throughput can the simulator drive into a dumb TCP receiver?
- did a simulator-only optimization change real wire throughput?

## 1. Start a dumb TCP sink

For a quick local measurement, listen on a dedicated port and discard the
received bytes:

```bash
nc -l 4200 > /dev/null
```

Use a production-grade traffic sink or packet counter when you need exact byte
and connection metrics; `nc` is only a convenient smoke benchmark.

## 2. Run the simulator directly

Build and run the simulator from its own application directory:

```bash
cd apps/cadence_simulator
mix escript.build
./cadence_simulator telemetry \
  --definitions ../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml \
  --tcp 127.0.0.1:4200 \
  --rate 800 \
  --metrics-sample-rate 0
```

Repeat the command at the rates you want to compare. This path:

- runs only the simulator application and its shared CCSDS dependency;
- sends directly to the selected sink;
- does not start or compile Cadence in production mode.

Cadence does not need to be running for this benchmark.

## 3. Compare against Cadence-coupled runs

Run the same scenario/rate through a provider reservation and capture a Cadence
profiler snapshot:

```bash
mix cadence.profile demo_spacecraft --reset
mix cadence.profile demo_spacecraft --snapshot
```

If sink throughput is much higher than Cadence-coupled throughput, the current
bottleneck is on the Cadence side. If both plateau together, the simulator is
still the likely limiter.

## 4. Read the output

Compare:

- simulator transmit telemetry;
- sink-side received bytes or Mbps;
- Cadence ingress, packet, sample, and queue rates from the profiler snapshot.

The key comparison is:

- `sim(mbps)` versus `sink(rx/mbps)`

If those match closely, the sink is receiving everything the simulator is
actually sending.

## 5. Keep measurement overhead low

For throughput runs, prefer sampled or disabled timing metrics:

```bash
--metrics-sample-rate 100
```

or fully disabled:

```bash
--metrics-sample-rate 0
```

When metrics are sampled or disabled, the throughput numbers are more important
than the `sim_ms(...)` timings.

## 6. Try simulator variants explicitly

Pass variants directly to the simulator CLI. For example:

```bash
./cadence_simulator telemetry \
  --definitions ../../legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml \
  --tcp 127.0.0.1:4200 \
  --rate 1600 \
  --metrics-sample-rate 0 \
  --provider database
```

If you are testing a simulator-specific throughput mode, pass that mode
explicitly there as well.

## 7. Use this benchmark for architecture decisions

The sink benchmark is not just a low-level optimization tool. It is also a
useful architecture discriminator:

- if the simulator is slow against the sink, improve the simulator first
- if the simulator is fast against the sink but slow against Cadence, improve
  Cadence-side runtime boundaries first
- if both are fast and the system is still slow end to end, the issue is
  probably elsewhere in the workflow
