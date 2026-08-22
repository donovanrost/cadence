---
title: Domain Entity
aliases: [domain entity, entity, pure entity]
tags: [glossary, architecture, hexagonal]
related:
  - "[[data-plane]]"
  - "[[control-plane]]"
created: 2025-01-27
updated: 2025-01-27
status: active
---

# Domain Entity

A **Domain Entity** is a pure business object with no database or persistence concerns. It can be serialized to ETS and passed between [Control Plane](control-plane.md) and [Data Plane](data-plane.md).

## Characteristics

| Aspect | Domain Entity |
|--------|---------------|
| Dependencies | None (pure Elixir structs) |
| Persistence | None - adapters handle that |
| Serialization | ETS-friendly (no lazy-loaded associations) |
| Location | `lib/cadence/domain/*/entities/` |

## Design Principles

1. **No status field** - Runtime status is managed by GenServers, not persisted in entities
2. **Embedded associations** - Related data is embedded as lists, not lazy-loaded
3. **Denormalized IDs** - Foreign keys stored directly for O(1) lookup
4. **Immutable** - Create new entities rather than mutating

## Example

```elixir
defmodule Cadence.Domain.Interfaces.Entities.Interface do
  defstruct [
    :id,
    :name,
    :type,
    :host,
    :port,
    :mission_id,
    :target_ids,      # Denormalized for O(1) lookup
    protocols: []     # Embedded, not lazy-loaded
  ]
end
```

## Usage Pattern

```elixir
# Control Plane: Load from DB, convert to entity
interface = InterfaceRepository.get(id) |> InterfaceMapper.to_entity()

# Pass to Data Plane via PubSub or direct injection
GenServer.start_link(TcpClientInterface, interface)

# Data Plane: Uses entity directly, no DB calls
def init(%Interface{} = interface) do
  {:ok, %{interface: interface, status: :disconnected}}
end
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Cadence.Domain.Interfaces.Entities.Interface` | Interface entity |
| `Cadence.Domain.Missions.Entities.Mission` | Mission entity |
| `Cadence.Domain.Targets.Entities.Target` | Target entity |

## Related Concepts

- [Data Plane](data-plane.md) - Receives entities at startup
- [Control Plane](control-plane.md) - Creates and persists entities

## See Also

- [Data Plane / Control Plane Architecture](../architecture/data-plane-control-plane.md)
