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

## 1. Use the sink sweep task

The simplest path is:

```bash
mix cadence.sink_sweep demo_spacecraft --rates 800,1600,3200 --sample-seconds 30 --sink-port 4200 -- --metrics-sample-rate 0
```

This task:

- loads the simulator config from the named profile
- overrides the TCP output to point at a local dumb sink
- starts the sink locally
- starts the simulator locally
- steps through the requested rates
- prints simulator-side and sink-side throughput

Cadence does not need to be running for this benchmark.

## 2. Compare the current simulator to Cadence-coupled runs

The most useful comparison is:

Cadence-coupled sweep:

```bash
mix cadence.profile_sweep demo_spacecraft --rates 800,1600,3200 --sample-seconds 30 -- --metrics-sample-rate 0
```

Simulator-only sink sweep:

```bash
mix cadence.sink_sweep demo_spacecraft --rates 800,1600,3200 --sample-seconds 30 --sink-port 4200 -- --metrics-sample-rate 0
```

If sink throughput is much higher than Cadence-coupled throughput, the current
bottleneck is on the Cadence side. If both plateau together, the simulator is
still the likely limiter.

## 3. Read the output

The sink sweep prints:

- `sim(tx/s/mbps/q/fl/sz_kb)`
  simulator-side transmit rate, wire Mbps, queue depth, flushes per second, and
  average KB per flush
- `sink(rx/mbps/ch_s/acc/open)`
  sink-side receive Mbps, chunks per second, accepted connections, and open
  connections
- `sim_ms(gen/fr/send)`
  simulator generation, framing, and send timing

The key comparison is:

- `sim(mbps)` versus `sink(rx/mbps)`

If those match closely, the sink is receiving everything the simulator is
actually sending.

## 4. Keep measurement overhead low

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

## 5. Try simulator variants explicitly

You can still pass simulator overrides after `--`.

For example:

```bash
mix cadence.sink_sweep demo_spacecraft \
  --rates 800,1600,3200 \
  --sample-seconds 30 \
  --sink-port 4200 -- \
  --metrics-sample-rate 0 \
  --provider database
```

If you are testing a simulator-specific throughput mode, pass that mode
explicitly there as well.

## 6. Use this benchmark for architecture decisions

The sink benchmark is not just a low-level optimization tool. It is also a
useful architecture discriminator:

- if the simulator is slow against the sink, improve the simulator first
- if the simulator is fast against the sink but slow against Cadence, improve
  Cadence-side runtime boundaries first
- if both are fast and the system is still slow end to end, the issue is
  probably elsewhere in the workflow
