---
title: "ADR-001: No Database Calls in Data Plane"
aliases: [no db in hot path, data plane isolation]
tags: [adr, architecture, data-plane, performance]
status: accepted
created: 2024-12-21
updated: 2025-01-27
---

# ADR-001: No Database Calls in Data Plane

## Status

Accepted

## Context

The telemetry processing pipeline was making database calls for:

- Interface configuration lookup
- Protocol chain configuration
- Target routing
- Packet identification
- Limits checking

This created several problems:

1. **Latency** - Database round-trips in the hot path added unpredictable latency
2. **Coupling** - Runtime components were tightly coupled to persistence layer
3. **Testing** - Difficult to test runtime behavior without a database
4. **Scaling** - Database became a bottleneck under high telemetry load

## Decision

[Data Plane](../glossary/data-plane.md) components receive configuration via dependency injection at startup and react to config change events via PubSub. They never call the database directly.

### Implementation

1. **Startup injection** - GenServers receive [Domain Entities](../glossary/domain-entity.md) at start:
   ```elixir
   def start_link(%Interface{} = interface) do
     GenServer.start_link(__MODULE__, interface)
   end
   ```

2. **Config push via PubSub** - [Control Plane](../glossary/control-plane.md) broadcasts changes:
   ```elixir
   Phoenix.PubSub.broadcast(Cadence.PubSub, topic, {:interface_updated, entity})
   ```

3. **Status broadcast (no DB writes)** - Runtime status is ephemeral:
   ```elixir
   defp broadcast_status(status, interface) do
     Phoenix.PubSub.broadcast(Cadence.PubSub, topic, {:status_changed, status})
   end
   ```

4. **ETS for derived data** - Packet identification, limits, derived items cached in ETS

## Consequences

### Positive

- **Predictable latency** - Telemetry processing uses only in-memory state
- **Clear separation** - Runtime and persistence are decoupled
- **Testable** - Can test runtime with in-memory adapters
- **Scalable** - No database bottleneck in hot path

### Negative

- **Startup complexity** - Must load all config before starting GenServers
- **Event handling** - Must handle config change events for hot reload
- **Potential staleness** - Config can diverge if PubSub events are missed
- **Recovery questions** - Where does a crashed GenServer get config from?

### Open Questions

1. **Config versioning** - How to handle stale config in ETS when DB is updated directly?
2. **Multi-node** - How does config propagation work in a cluster?
3. **Recovery** - When a GenServer crashes, where does it get config from?

## Key Modules

| Module | Role |
|--------|------|
| `Cadence.Runtime.Missions.MissionInstance` | Loads config at startup |
| `Cadence.Interfaces.InterfaceSupervisor` | Subscribes to config events |
| `Cadence.Interfaces.TcpClientInterface` | Receives entity, no DB calls |
| `Cadence.Application.Interfaces.InterfaceOperations` | Broadcasts config changes |

## See Also

- [Data Plane / Control Plane Architecture](../architecture/data-plane-control-plane.md)
- [Data Plane](../glossary/data-plane.md) glossary entry
- [Control Plane](../glossary/control-plane.md) glossary entry
