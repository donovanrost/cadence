---
title: CVT
aliases: [Current Value Table, current value table, live cache]
tags: [glossary, telemetry, runtime]
related:
  - "[[telemetry-point]]"
  - "[[data-plane]]"
  - "[[mission]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# CVT (Current Value Table)

The **CVT** (Current Value Table) is an in-memory cache holding the latest value of each [Telemetry Point](telemetry-point.md). It provides O(1) lookup for real-time displays and procedure execution.

## Characteristics

| Aspect | Behavior |
|--------|----------|
| Storage | ETS table per [Mission](mission.md) |
| Updates | Batched from telemetry pipeline |
| Reads | Direct ETS lookup, O(1) |
| Persistence | None (ephemeral, rebuilt from telemetry stream) |
| Notifications | PubSub broadcasts for UI updates |

## Architecture

```
Telemetry Pipeline
    ↓ (processed telemetry)
Durable Sink (append log)
    ↓
CVT Consumer
    ↓ (batch updates)
CVT (ETS)
    ↓ (PubSub broadcasts)
LiveView Dashboards
```

The CVT is a **consumer** of the durable sink, not part of the hot ingest path. This allows replay and ensures the CVT can be rebuilt.

## Usage

```elixir
# Read a single value
{:ok, value} = CVT.get(mission_id, "HEALTH.cpu_temp")

# Read multiple values
values = CVT.get_many(mission_id, ["HEALTH.cpu_temp", "POWER.voltage"])

# In procedures (via Lua API)
cadence.telemetry.get("HEALTH.cpu_temp")
cadence.telemetry.wait_for("HEALTH.cpu_temp", "<", 80, timeout_ms)
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Telemetry.CurrentValueTable` | ETS operations |
| `Cadence.Runtime.Telemetry.CVTConsumer` | Reads from sink, updates CVT |
| `Cadence.Runtime.Telemetry.CVTBatcher` | Batches updates for efficiency |

## Related Concepts

- [Telemetry Point](telemetry-point.md) - What the CVT stores
- [Data Plane](data-plane.md) - CVT is a Data Plane component
- [Mission](mission.md) - Each mission has its own CVT

## See Also

- [Telemetry Pipeline Redesign](../architecture/telemetry_pipeline_redesign_plan.md)
