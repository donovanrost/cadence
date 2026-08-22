---
title: Interfaces and Transports Architecture
tags: [architecture, interfaces, transports, runtime]
created: 2026-01-29
updated: 2026-01-29
status: active
---

# Interfaces and Transports Architecture

## Overview

Transport interfaces are GenServer-based endpoints that own socket lifecycle and byte I/O. They handle physical connectivity while higher layers handle protocol framing.

**Location:** `lib/cadence/runtime/interfaces/`

## Transport Types

| Type | Module | Status |
|------|--------|--------|
| TCP Client | `TcpClientInterface` | Implemented |
| TCP Server | `TcpServerInterface` | Implemented |
| UDP Client | - | Planned |
| UDP Server | - | Planned |
| Serial | - | Planned |
| File/S3/Replay | - | Planned |

## High-Level Flow

### Downlink (Transport → Pipeline)

```
Socket receives bytes
       ↓
handle_info({:tcp, socket, data})
       ↓
Router.ingest(mission_id, transport_id, bytes, metadata)
       ↓
LinkController.route_downlink(mission_id, scid, transport_id, bytes)
       ↓
ChannelService (protocol decoding)
       ↓
Telemetry Pipeline
```

### Uplink (Pipeline → Transport)

```
UplinkDispatcher
       ↓
Transport.send_bytes(mission_id, transport_id, bytes)
       ↓
Registry.lookup({:transport, mission_id, transport_id})
       ↓
GenServer.cast(pid, {:send, bytes})
       ↓
:gen_tcp.send(socket, data)
```

## Supervision Structure

```
MissionInstance (one_for_one)
├── InterfaceSupervisor (DynamicSupervisor)
│   ├── TcpClientInterface (GenServer)
│   ├── TcpClientInterface (GenServer)
│   └── TcpServerInterface (GenServer)
├── LinksSupervisor
│   └── LinkController per SCID
└── ...
```

## TCP Client Interface

**File:** `interfaces/tcp_client_interface.ex`

### State

```elixir
%{
  transport: TransportInterface,
  host: charlist,
  port: integer,
  socket: :gen_tcp.socket() | nil,
  connected: boolean,
  reconnect_interval: 5000,
  bytes_received: integer,
  bytes_sent: integer
}
```

### Connection Lifecycle

```
start_link(transport)
       ↓
Schedule :connect
       ↓
:gen_tcp.connect(host, port, opts)
  ├─ Success → Store socket, notify Router.transport_connected()
  └─ Failure → Schedule retry after reconnect_interval
       ↓
Socket active messages:
  ├─ {:tcp, socket, data} → Router.ingest()
  ├─ {:tcp_closed, socket} → handle_disconnect(), schedule reconnect
  └─ {:tcp_error, socket, _} → handle_disconnect(), schedule reconnect
```

### API

- `send_data/2` - Synchronous byte transmission
- `stats/1` - Returns `{connected, host, port, bytes_received, bytes_sent}`

## TCP Server Interface

**File:** `interfaces/tcp_server_interface.ex`

### State

```elixir
%{
  transport: TransportInterface,
  listen_socket: :gen_tcp.socket(),
  clients: %{socket => ClientState},
  connected: boolean,
  max_clients: 100,
  client_timeout: 300_000
}
```

### Connection Lifecycle

```
start_link(transport)
       ↓
Schedule :listen
       ↓
:gen_tcp.listen(bind_port, opts)
       ↓
Schedule :accept loop
       ↓
:gen_tcp.accept(listen_socket, 100ms)
  ├─ Client socket → Add to clients, enable active mode
  │                  If first client: Router.transport_connected()
  ├─ Timeout → Continue accept loop
  └─ Error → Backoff 1s, retry
       ↓
Client data:
  ├─ {:tcp, socket, data} → Router.ingest() with client metadata
  ├─ {:tcp_closed, socket} → Remove from clients
  │                          If last client: Router.transport_disconnected()
  └─ {:tcp_error, socket, _} → Remove from clients
```

### API

- `broadcast/2` - Send to all connected clients
- `send_to_client/3` - Unicast to specific client
- `list_clients/1` - Enumerate connected clients
- `stats/1` - Aggregated metrics

## Factory

**File:** `interfaces/factory.ex`

Maps transport configuration to GenServer module:

```elixir
def module_for_connection_type(:tcp, %{mode: :server}), do: TcpServerInterface
def module_for_connection_type(:tcp, _), do: TcpClientInterface
```

## InterfaceSupervisor

**File:** `transport/interface_supervisor.ex`

DynamicSupervisor managing transport lifecycle:

```elixir
ensure_started(mission_id, transport_id, %TransportInterface{})
ensure_stopped(mission_id, transport_id)
```

## ConfigReconciler Integration

**File:** `links/config_reconciler.ex`

On configuration update:

1. Fetch ConfigBundle from cache
2. For each transport:
   - If enabled: `InterfaceSupervisor.ensure_started()`
   - If disabled: `InterfaceSupervisor.ensure_stopped()`
3. Apply bindings to LinkControllers
4. Sync connected state to Router

## Registry Keys

All registered in `Cadence.MissionRegistry`:

| Key | Process |
|-----|---------|
| `{:transport, mission_id, transport_id}` | Interface GenServer |
| `{:interface_supervisor, mission_id}` | InterfaceSupervisor |
| `{:link_controller, mission_id, scid}` | LinkController per SCID |
| `{:link_binding, mission_id, scid, transport_id}` | Binding lookup |

## Transport Schema

**File:** `lib/cadence/transports/interface.ex`

```elixir
schema "transport_interfaces" do
  field :name, :string
  field :type, Ecto.Enum, values: [:tcp, :udp, :serial, :file, :s3, :replay]
  field :endpoint, :map          # host, port, mode
  field :auth, :map              # Optional credentials
  field :tags, {:array, :string}
  field :allowed_directions, {:array, Ecto.Enum}  # [:uplink, :downlink, :both]
  field :enabled, :boolean, default: true
end
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Connection failure | Retry with fixed interval |
| Socket I/O error | Log, disconnect, trigger reconnect |
| Max clients reached | Reject new connections |
| Transport disconnect | Notify LinkController; bindings remain |

## Key Design Points

1. **I/O Only** - Interfaces own sockets; protocol framing elsewhere
2. **Isolation** - Per-mission via MissionInstance supervisor
3. **Registry Discovery** - No global coordinator; Registry lookups
4. **Graceful Degradation** - Disconnect notifications; bindings persist
5. **Multi-Client** - TCP server supports multiple simultaneous clients
