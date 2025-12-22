# Data Plane / Control Plane Architecture

## Overview

This document tracks the evolution toward a Data Plane / Control Plane separation for Cadence's telemetry processing pipeline. The goal is to eliminate database calls from the hot path of telemetry processing while maintaining a clean separation between configuration management and runtime data flow.

**Status:** Living document - updated as work progresses

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
2. **Push-based config updates** - Control Plane pushes changes, Data Plane reacts
3. **Runtime state is ephemeral** - Status (connected/disconnected) is not persisted during operation
4. **ETS-friendly entities** - Domain objects can be serialized to ETS for O(1) lookup

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
def start_link(mission_id, interface_id, _config) do
  interface = Interfaces.get_interface!(interface_id)  # DB call
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

### Phase 1: Interfaces Runtime (Current Focus)
- [ ] Refactor `Factory` to accept domain entities
- [ ] Refactor `TcpClientInterface` to receive entity
- [ ] Refactor `TcpServerInterface` to receive entity
- [ ] Update `InterfaceSupervisor` to:
  - Load entities at startup
  - Subscribe to config events
  - Handle hot reload
- [ ] Remove status DB writes from GenServers
- [ ] Add status PubSub broadcasting
- [ ] Update dashboard to use PubSub for status

### Phase 2: Protocol Chain Runtime
- [ ] Push protocol config to GenServers
- [ ] Hot-reload protocol chain on config change

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
