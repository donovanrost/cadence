---
title: Interface
aliases: [interfaces, connection, link]
tags: [glossary, core, interfaces, runtime]
related:
  - "[[target]]"
  - "[[mission]]"
  - "[[data-plane]]"
  - "[[domain-entity]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Interface

An **Interface** is a connection endpoint that Cadence uses to communicate with a [Target](target.md). Interfaces handle the physical transport layer (TCP, UDP, serial, etc.).

## Interface Types

| Type | Description | Use Case |
|------|-------------|----------|
| TCP Client | Connects to remote TCP server | Ground station equipment |
| TCP Server | Listens for incoming connections | Simulators, test equipment |
| UDP | Connectionless datagram transport | High-rate telemetry |
| Serial | RS-232/RS-422 serial port | Direct hardware connection |

## Relationship to Other Concepts

```
Mission
  └── Target (spacecraft)
        └── Interface (TCP connection to ground station)
              └── Protocol Chain (CCSDS framing, COP-1, etc.)
```

## Key Characteristics

| Aspect | Behavior |
|--------|----------|
| Runtime | GenServer in [Data Plane](data-plane.md) |
| Config | [Domain Entity](domain-entity.md) injected at startup |
| Status | Ephemeral (broadcast via PubSub, not persisted) |
| Protocols | Embedded list for ETS serialization |

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Interfaces` | Context facade |
| `Cadence.Interfaces.TcpClientInterface` | TCP client GenServer |
| `Cadence.Interfaces.TcpServerInterface` | TCP server GenServer |
| `Cadence.Interfaces.InterfaceSupervisor` | Lifecycle management |
| `Cadence.Domain.Interfaces.Entities.Interface` | Domain entity |

## Related Concepts

- [Target](target.md) - What interfaces connect to
- [Mission](mission.md) - Operational context containing interfaces
- [Data Plane](data-plane.md) - Where interfaces run
- [COP-1](cop-1.md) - Link-layer protocol that runs over interfaces

## See Also

- [Data Plane / Control Plane](../architecture/data-plane-control-plane.md)
