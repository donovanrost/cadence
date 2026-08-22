---
title: Control Plane
aliases: [control plane, configuration layer]
tags: [glossary, architecture, configuration]
related:
  - "[[data-plane]]"
  - "[[domain-entity]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Control Plane

The **Control Plane** is the configuration management layer that handles CRUD operations, persistence, and user interactions. It pushes configuration to the [Data Plane](data-plane.md) via PubSub.

## Characteristics

| Aspect | Control Plane Behavior |
|--------|------------------------|
| State source | PostgreSQL database |
| Config updates | Pushes to Data Plane via PubSub |
| User interaction | LiveView forms, API endpoints |
| Persistence | Ecto schemas, repositories |

## Components

| Module | Purpose |
|--------|---------|
| `Cadence.Interfaces` | Context facade for interface CRUD |
| `Cadence.Missions` | Context facade for mission CRUD |
| `Cadence.Application.Interfaces.InterfaceOperations` | Business logic for interfaces |
| `Cadence.Adapters.Persistence.Ecto.*` | Database adapters |
| `CadenceWeb.*Live` | LiveView user interfaces |

## Config Push Pattern

When configuration changes in the Control Plane:

```elixir
# In InterfaceOperations after successful DB update
Phoenix.PubSub.broadcast(
  Cadence.PubSub,
  "mission:#{mission_id}:interface_config",
  {:interface_updated, interface_entity}
)
```

The [Data Plane](data-plane.md) subscribes and reacts:

```elixir
# In InterfaceSupervisor
def handle_info({:interface_updated, interface}, state) do
  restart_interface(interface)
  {:noreply, state}
end
```

## Related Concepts

- [Data Plane](data-plane.md) - Runtime processing layer
- [Domain Entity](domain-entity.md) - Objects passed from Control to Data Plane

## See Also

- [Data Plane / Control Plane Architecture](../architecture/data-plane-control-plane.md)
