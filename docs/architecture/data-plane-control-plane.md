---
title: Data Plane / Control Plane Architecture
aliases: [DP/CP, data plane control plane]
tags: [architecture, data-plane, control-plane, runtime]
related:
  - "[[data-plane]]"
  - "[[control-plane]]"
  - "[[domain-entity]]"
  - "[[001-no-db-in-data-plane]]"
created: 2024-12-21
updated: 2025-01-27
status: active
---

# Data Plane / Control Plane Architecture

## Overview

This document tracks the evolution toward a [Data Plane](../glossary/data-plane.md) / [Control Plane](../glossary/control-plane.md) separation for Cadence's telemetry processing pipeline. The goal is to eliminate database calls from the hot path of telemetry processing while maintaining a clean separation between configuration management and runtime data flow.

**Status:** Living document - updated as work progresses

> **Key Decision:** [ADR-001: No Database Calls in Data Plane](../decisions/001-no-db-in-data-plane.md)

---

## Motivation

The telemetry processing pipeline currently makes database calls for:
- Interface configuration lookup
- Protocol chain configuration
- Target routing
- Packet identification
- Limits checking

While some of these are already cached (PacketIdentifier, Limits), the Interfaces layer sits at the edge of the pipeline and still fetches configuration from the database when GenServers start.

### Goals

1. **No DB calls in hot path** - Telemetry processing should use only in-memory state
2. **Push-based config updates** - [Control Plane](../glossary/control-plane.md) pushes changes, [Data Plane](../glossary/data-plane.md) reacts
3. **Runtime state is ephemeral** - Status (connected/disconnected) is not persisted during operation
4. **ETS-friendly entities** - [Domain Entities](../glossary/domain-entity.md) can be serialized to ETS for O(1) lookup

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CONTROL PLANE                                │
│  ┌─────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │   Web UI    │  │  Application    │  │      Database           │  │
│  │  (LiveView) │──│   Services      │──│   (PostgreSQL)          │  │
│  └─────────────┘  └────────┬────────┘  └─────────────────────────┘  │
│                            │                                         │
│                     PubSub Events                                    │
│                   (config changes)                                   │
└────────────────────────────┼────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          DATA PLANE                                  │
│  ┌─────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │  Interface  │  │   Telemetry     │  │      ETS Cache          │  │
│  │  GenServers │──│   Pipeline      │──│   (config + derived)    │  │
│  └─────────────┘  └─────────────────┘  └─────────────────────────┘  │
│                                                                      │
│                     PubSub Events                                    │
│                   (status, metrics)                                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Interfaces Module

### Current State (Hexagonal Layer Complete)

The hexagonal architecture migration for Interfaces is complete:

| Component | Location | Status |
|-----------|----------|--------|
| Value Objects | `lib/cadence/domain/interfaces/value_objects/` | Done |
| Domain Entities | `lib/cadence/domain/interfaces/entities/` | Done |
| Repository Ports | `lib/cadence/ports/repository/interfaces/` | Done |
| Ecto Adapters | `lib/cadence/adapters/persistence/ecto/interfaces/` | Done |
| In-Memory Adapters | `test/support/adapters/` | Done |
| Application Services | `lib/cadence/application/interfaces/` | Done |
| Context Facade | `lib/cadence/interfaces.ex` | Done |

#### Key Design Decisions

1. **No status in domain entity** - `Interface` entity has no `status` field. Status is runtime-only state managed by GenServers.

2. **Embedded protocols** - Protocols are embedded in the Interface entity as a list, not lazy-loaded. This makes the entity ETS-serializable.

3. **Denormalized target_ids** - Target IDs are stored directly in the entity for O(1) lookup at runtime.

4. **Event emission** - All write operations in `InterfaceOperations` broadcast PubSub events:
   - `:interface_created`
   - `:interface_updated`
   - `:interface_deleted`
   - `:interface_protocols_updated`

### Remaining Work: Runtime GenServer Refactoring

The runtime GenServers (`TcpClientInterface`, `TcpServerInterface`) currently fetch configuration from the database:

```elixir
# CURRENT: GenServer fetches from DB
def start_link(mission_id, transport_id, _config) do
  interface = Interfaces.get_interface!(transport_id)  # DB call
  ...
end
```

The target architecture has GenServers receive domain entities via injection:

```elixir
# TARGET: GenServer receives entity
def start_link(%Interface{} = interface) do
  # No DB call - config is injected
  GenServer.start_link(__MODULE__, interface, name: via_tuple(interface.id))
end
```

#### Files to Modify

| File | Change |
|------|--------|
| `lib/cadence/interfaces/factory.ex` | Accept `Interface` entity, not schema |
| `lib/cadence/interfaces/tcp_client_interface.ex` | Receive entity in `start_link/1` |
| `lib/cadence/interfaces/tcp_server_interface.ex` | Receive entity in `start_link/1` |
| `lib/cadence/interfaces/interface_supervisor.ex` | Load entities once, subscribe to config events |

#### InterfaceSupervisor Changes

```elixir
defmodule Cadence.Interfaces.InterfaceSupervisor do
  def init(mission_id) do
    # Load all interfaces for mission at supervisor start
    interfaces = InterfaceQueries.list_for_mission(mission_id, preload_protocols: true)

    children = Enum.map(interfaces, fn interface ->
      {Factory.module_for(interface), interface}
    end)

    # Subscribe to config changes for hot reload
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:interface_config")

    Supervisor.init(children, strategy: :one_for_one)
  end

  def handle_info({:interface_created, interface}, state) do
    # Start new interface GenServer
    start_interface(interface)
    {:noreply, state}
  end

  def handle_info({:interface_updated, interface}, state) do
    # Restart interface with new config
    restart_interface(interface)
    {:noreply, state}
  end

  def handle_info({:interface_deleted, interface}, state) do
    # Stop interface GenServer
    stop_interface(interface.id)
    {:noreply, state}
  end
end
```

#### Status Broadcasting (No DB Writes)

GenServers should broadcast status via PubSub, not write to DB:

```elixir
# CURRENT: Writes to DB
def handle_info({:tcp_connected, socket}, state) do
  Interfaces.mark_connected(state.interface)  # DB call
  {:noreply, %{state | socket: socket}}
end

# TARGET: Broadcasts event
def handle_info({:tcp_connected, socket}, state) do
  broadcast_status(:connected, state.interface)  # PubSub only
  {:noreply, %{state | socket: socket, status: :connected}}
end

defp broadcast_status(status, interface) do
  Phoenix.PubSub.broadcast(
    Cadence.PubSub,
    "interface:#{interface.id}:status",
    {:interface_status_changed, interface.id, status}
  )
end
```

Dashboard LiveViews subscribe to status events for real-time updates.

---

## Missions Module

### Current State (Hexagonal Layer + Runtime Separation Complete)

The Missions context migration is complete:

| Component | Location | Status |
|-----------|----------|--------|
| Domain Entities | `lib/cadence/domain/missions/entities/` | Done |
| Value Objects | `lib/cadence/domain/missions/value_objects/` | Done |
| Repository Port | `lib/cadence/ports/repository/missions/` | Done |
| Ecto Adapter | `lib/cadence/adapters/persistence/ecto/missions/` | Done |
| Application Services | `lib/cadence/application/missions/` | Done |
| Runtime Modules | `lib/cadence/runtime/missions/` | Done |
| Form Schemas | `lib/cadence_web/schemas/mission_form.ex` | Done |
| Context Facade | `lib/cadence/missions.ex` | Done |

### Key Design Decisions

1. **Runtime modules in `lib/cadence/runtime/`** - Clear Data Plane separation
   - `MissionSupervisor` - Dynamic supervisor for mission instances
   - `MissionInstance` - Per-mission supervisor managing CVT, interfaces, pipelines

2. **No DB calls in runtime hot path** - GenServers receive domain entities at startup

3. **Embedded schemas for forms** - `CadenceWeb.Schemas.MissionForm` uses `embedded_schema` for LiveView forms without database coupling

4. **Backwards compatibility aliases** - Old module names delegate to new locations

### Runtime Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                          CONTROL PLANE                                  │
│  ┌─────────────┐  ┌─────────────────┐  ┌────────────────────────────┐  │
│  │   LiveView  │  │  MissionOps     │  │   MissionsRepository       │  │
│  │  (Forms)    │──│  (Application)  │──│   (Ecto Adapter)           │  │
│  └─────────────┘  └────────┬────────┘  └────────────────────────────┘  │
│                            │                                            │
│                     Domain Entity                                       │
│                   (injected at start)                                   │
└────────────────────────────┼───────────────────────────────────────────┘
                             │
                             ▼
┌────────────────────────────────────────────────────────────────────────┐
│                           DATA PLANE                                    │
│  ┌─────────────────────┐  ┌─────────────────────────────────────────┐  │
│  │  MissionSupervisor  │──│  MissionInstance (per mission)          │  │
│  │  (DynamicSupervisor)│  │    ├── CVT                              │  │
│  └─────────────────────┘  │    ├── InterfaceSupervisor              │  │
│                           │    ├── TelemetryPipeline                │  │
│                           │    ├── CommandQueue                     │  │
│                           │    └── LimitsMonitor                    │  │
│                           └─────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

### Future Work

- [ ] Subscribe to config change events via PubSub for hot reload
- [ ] Broadcast mission status via PubSub (not DB writes)
- [ ] Update dashboard LiveViews to use PubSub for status

---

## Future Modules

As other modules are migrated, they should follow the same pattern:

### Telemetry Pipeline

| Component | DP/CP Consideration |
|-----------|---------------------|
| PacketIdentifier | Already uses ETS cache |
| Limits | Already uses ETS cache |
| Derived Items | Already uses ETS cache |
| Protocol Chain | Config should be pushed, not fetched |

### Commanding

| Component | DP/CP Consideration |
|-----------|---------------------|
| Command Queue | Status is runtime, commands are persisted |
| Command Router | Routing config should be pushed |

---

## Implementation Phases

### Phase 1: Interfaces Runtime (COMPLETE)
- [x] Refactor `Factory` to accept domain entities
- [x] Refactor `TcpClientInterface` to receive entity
- [x] Refactor `TcpServerInterface` to receive entity
- [x] Update `InterfaceSupervisor` to:
  - Load entities at startup via `InterfaceQueries.list_for_mission(mission_id, preload_protocols: true)`
  - Subscribe to config events on `mission:{mission_id}:interface_config`
  - Handle hot reload (`:interface_created`, `:interface_updated`, `:interface_deleted`, `:interface_protocols_updated`)
- [x] GenServers receive domain entities at startup (no DB calls in runtime)
- [x] Status broadcasting via `InterfaceConnectionEvent` (not DB writes)
- [ ] Update dashboard LiveViews to use PubSub for status (future work)

### Phase 2: Protocol Chain Runtime (COMPLETE)
- [x] Update Processor to accept domain entities (atom types, `.config` field)
- [x] ProtocolChainSupervisor requires protocols in `start_chain/3`
- [x] ProtocolChain requires protocols (no DB fallback)
- [x] TcpClientInterface passes `interface.protocols` to protocol chain
- [x] TcpServerInterface passes `interface.protocols` to protocol chain
- [x] Hot-reload protocol chain on config change via PubSub
  - ProtocolChainSupervisor converted to GenServer wrapping DynamicSupervisor
  - Subscribes to `mission:{mission_id}:interface_config` for protocol updates
  - Handles `:interface_protocols_updated` events by calling `ProtocolChain.update_protocols/2`
  - ProtocolChain.update_protocols/2 reinitializes chains in-place without restart

### Phase 3: Telemetry Pipeline
- [ ] Audit remaining DB calls in hot path
- [ ] Push remaining config to ETS
- [ ] Implement config versioning for cache invalidation

---

## Testing Strategy

1. **Unit tests** - Domain entities with `PureCase`
2. **Integration tests** - Full flow with in-memory adapters
3. **PubSub tests** - Verify event emission and handling
4. **Hot reload tests** - Config change propagation

---

## Open Questions

1. **Config versioning** - How do we handle stale config in ETS when DB is updated directly (migration, manual fix)?

2. **Startup ordering** - If InterfaceSupervisor starts before config is loaded, how do we handle that?

3. **Multi-node** - How does config propagation work in a clustered deployment?

4. **Recovery** - When a GenServer crashes and restarts, where does it get config from?

---

## Changelog

| Date | Change |
|------|--------|
| 2024-12-21 | Initial document created |
| 2024-12-21 | Hexagonal layer for Interfaces completed |
| 2024-12-22 | Missions module: hexagonal layer + runtime separation complete |
| 2024-12-22 | Runtime modules moved to `lib/cadence/runtime/missions/` |
| 2024-12-22 | Added embedded schema pattern for LiveView forms |
| 2024-12-22 | **Phase 1 Complete**: Interface runtime refactoring - Factory, TcpClientInterface, TcpServerInterface, and InterfaceSupervisor now use domain entities. Hot reload via PubSub implemented. |
| 2024-12-22 | **Phase 2 Complete**: Protocol chain runtime refactoring - Processor accepts domain entities, ProtocolChain requires protocols (no DB fallback), interfaces pass protocols from entity. |
| 2024-12-22 | **Protocol Chain Hot Reload**: ProtocolChainSupervisor converted to GenServer, subscribes to PubSub for `:interface_protocols_updated` events, updates chains in-place without restart. |
