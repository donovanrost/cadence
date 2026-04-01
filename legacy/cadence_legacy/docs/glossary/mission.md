---
title: Mission
aliases: [missions]
tags: [glossary, core, missions]
related:
  - "[[target]]"
  - "[[interface]]"
  - "[[data-plane]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Mission

A **Mission** is an operational context that groups [Targets](target.md), [Interfaces](interface.md), telemetry configuration, and procedures. Missions are the primary unit of multi-tenancy in Cadence.

## What a Mission Contains

| Component | Description |
|-----------|-------------|
| Targets | Spacecraft and ground systems |
| Interfaces | Connections to targets |
| Telemetry Points | Data items to monitor |
| Commands | Operations to send to targets |
| Procedures | Operational sequences and automations |
| Limits | Alarm thresholds |

## Runtime Architecture

Each running mission has a `MissionInstance` supervisor in the [Data Plane](data-plane.md):

```
MissionSupervisor (DynamicSupervisor)
  └── MissionInstance (per mission)
        ├── CVT (Current Value Table)
        ├── InterfaceSupervisor
        ├── TelemetryPipeline
        ├── CommandQueue
        └── LimitsMonitor
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Missions` | Context facade |
| `Cadence.Domain.Missions.Entities.Mission` | Domain entity |
| `Cadence.Runtime.Missions.MissionSupervisor` | Dynamic supervisor |
| `Cadence.Runtime.Missions.MissionInstance` | Per-mission supervisor |

## Related Concepts

- [Target](target.md) - Spacecraft within missions
- [Interface](interface.md) - Connections within missions
- [Data Plane](data-plane.md) - Where mission instances run

## See Also

- [Data Plane / Control Plane](../architecture/data-plane-control-plane.md)
