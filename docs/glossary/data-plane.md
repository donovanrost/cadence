---
title: Data Plane
aliases: [data plane, runtime layer, hot path]
tags: [glossary, architecture, runtime]
related:
  - "[[control-plane]]"
  - "[[domain-entity]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Data Plane

The **Data Plane** is the runtime layer that processes telemetry and executes commands. It operates entirely from in-memory state with no database calls in the hot path.

## Characteristics

| Aspect | Data Plane Behavior |
|--------|---------------------|
| State source | In-memory (ETS, GenServer state) |
| Config updates | Receives via PubSub push |
| Database access | **None** during operation |
| Status persistence | Ephemeral (broadcast via PubSub) |

## Key Principle

> Data Plane components receive configuration at startup via dependency injection and react to config change events via PubSub. They never call the database directly.

See [ADR-001: No Database Calls in Data Plane](../decisions/001-no-db-in-data-plane.md) for rationale.

## Components

| Module | Purpose |
|--------|---------|
| `Cadence.Runtime.Missions.MissionInstance` | Per-mission supervisor |
| `Cadence.Interfaces.TcpClientInterface` | TCP client GenServer |
| `Cadence.Interfaces.TcpServerInterface` | TCP server GenServer |
| `Cadence.Interfaces.InterfaceSupervisor` | Interface lifecycle management |
| `Cadence.Telemetry.Pipeline` | Telemetry processing |

## Data Flow

```
Control Plane (config changes)
        │
        ▼ PubSub Events
┌─────────────────────────────────────────┐
│              DATA PLANE                 │
│  Interface GenServers                   │
│  Telemetry Pipeline                     │
│  ETS Cache (config + derived data)      │
└─────────────────────────────────────────┘
        │
        ▼ PubSub Events
Control Plane (status updates for UI)
```

## Related Concepts

- [Control Plane](control-plane.md) - Configuration management layer
- [Domain Entity](domain-entity.md) - Pure business objects injected into Data Plane

## See Also

- [Data Plane / Control Plane Architecture](../architecture/data-plane-control-plane.md)
