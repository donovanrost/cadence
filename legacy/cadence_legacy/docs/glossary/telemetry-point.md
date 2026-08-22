---
title: Telemetry Point
aliases: [telemetry points, telemetry item, mnemonic]
tags: [glossary, telemetry, core]
related:
  - "[[cvt]]"
  - "[[target]]"
  - "[[mission]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Telemetry Point

A **Telemetry Point** is a monitored data item from a [Target](target.md). Telemetry points are identified by a mnemonic (name) and have associated metadata like conversion, limits, and display formatting.

## Lifecycle

```
Raw Bytes (from interface)
    ↓ Identify (packet type, APID)
    ↓ Decommutate (extract raw value)
    ↓ Convert (engineering units)
    ↓ Derive (computed values)
    ↓ Limits Check (alarm thresholds)
    ↓
CVT (live cache) + Durable Storage
```

## Key Properties

| Property | Description |
|----------|-------------|
| Mnemonic | Unique name (e.g., `HEALTH.cpu_temp`) |
| Raw Type | Binary extraction type (uint16, float32, etc.) |
| Conversion | Raw to engineering units transformation |
| Units | Display units (e.g., "°C", "V", "mA") |
| Limits | Alarm thresholds (yellow, red) |

## Telemetry Types

| Type | Description |
|------|-------------|
| Housekeeping | Regular health/status data |
| Payload | Science or mission data |
| Event | Discrete state changes |
| Derived | Computed from other points |

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Telemetry.PacketIdentifier` | Identifies packet types |
| `Cadence.Telemetry.Decom` | Extracts raw values |
| `Cadence.Telemetry.Convert` | Applies conversions |
| `Cadence.Telemetry.Derive` | Computes derived items |

## Related Concepts

- [CVT](cvt.md) - Where latest values are cached
- [Target](target.md) - Source of telemetry
- [Mission](mission.md) - Contains telemetry configuration

## See Also

- [Telemetry Pipeline Redesign](../architecture/telemetry_pipeline_redesign_plan.md)
