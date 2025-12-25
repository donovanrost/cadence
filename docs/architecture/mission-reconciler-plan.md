# Mission Reconciler Architecture Plan

## Overview

Implement a Kubernetes-style level-triggered reconciliation pattern for mission lifecycle management. The data plane becomes self-describing via Phoenix.Tracker, while per-organization reconcilers in the control plane handle reconciliation logic.

**Key architectural decisions:**
- Control plane and data plane run in the same BEAM cluster (Phoenix.Tracker viable)
- Per-org sharding of reconcilers for tenant isolation
- Periodic reconciliation pattern at all levels (reconcilers manage reconcilers)
- Task-based parallel mission reconciliation within each org

## Goals

1. **Decouple control plane from data plane** - No direct imperative calls from control plane to data plane
2. **Self-healing** - Missed events don't matter; periodic reconciliation corrects drift
3. **Observable** - Rich status reporting via Phoenix.Tracker
4. **Static stability** - Data plane continues running if control plane is down

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CONTROL PLANE                                    │
│                                                                          │
│  ┌─────────────┐    ┌─────────────────────────────────────────────┐     │
│  │  Database   │    │ ReconcilerManager                           │     │
│  │ (desired)   │    │   (periodic reconcile of reconcilers)       │     │
│  │ gen: 7      │    └──────────────────┬──────────────────────────┘     │
│  └─────────────┘                       │                                 │
│        ▲              ┌────────────────┼────────────────┐               │
│        │              ▼                ▼                ▼               │
│        │    ┌─────────────────┐ ┌─────────────────┐                     │
│        │    │ OrgReconciler   │ │ OrgReconciler   │  ...                │
│        └────│ (org_a)         │ │ (org_b)         │                     │
│             │                 │ │                 │                     │
│             │ ┌─────────────┐ │ │ ┌─────────────┐ │                     │
│             │ │Task│Task│...│ │ │ │Task│Task│...│ │                     │
│             │ └─────────────┘ │ │ └─────────────┘ │                     │
│             └────────┬────────┘ └────────┬────────┘                     │
│                      │                   │                               │
│                      │ Observes Phoenix.Tracker                         │
│                      │ Issues: start/stop/reload                        │
└──────────────────────┼───────────────────┼──────────────────────────────┘
                       ▼                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          DATA PLANE                                      │
│                                                                          │
│  MissionSupervisor (DynamicSupervisor)                                  │
│  ├── MissionInstance (mission_1, org_a)                                 │
│  │     observed_generation: 7                                           │
│  │     status: :ready                                                   │
│  │     conditions: [{:interfaces, :ready}, {:caches, :ready}, ...]      │
│  ├── MissionInstance (mission_2, org_a)                                 │
│  ├── MissionInstance (mission_3, org_b)                                 │
│  └── ...                                                                │
│                                                                          │
│  All MissionInstances report state via Phoenix.Tracker                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Foundation - Generation Tracking

**Goal**: Add generation/version tracking to missions and related configs.

### 1.1 Add `config_generation` to Mission Entity

**File**: `lib/cadence/domain/missions/entities/mission.ex`

- Add `config_generation` field (integer, starts at 1)
- Increment on any config-affecting change

### 1.2 Add Generation to Mission Schema

**File**: `lib/cadence/missions/mission.ex` (Ecto schema)

- Add migration for `config_generation` column
- Default to 1

### 1.3 Extend VersionRegistry for Mission-Level Generation

**File**: `lib/cadence/config/version_registry.ex`

- Add `:mission` config type
- Add `compute_mission_generation/1` that aggregates:
  - Mission.updated_at
  - Max(Targets.updated_at) for mission
  - Max(Interfaces.updated_at) for mission
  - DefinitionSet versions
- Broadcast `{:mission_generation_changed, mission_id, new_generation}` on PubSub

### 1.4 Bump Generation on Config Changes

**Files**:
- `lib/cadence/application/interfaces/interface_operations.ex`
- `lib/cadence/application/targets/target_operations.ex` (or equivalent)
- `lib/cadence/mission_database/importer.ex`

After any config mutation, call `VersionRegistry.invalidate(:mission, mission_id)`.

---

## Phase 2: Phoenix.Tracker Infrastructure

**Goal**: Set up Phoenix.Tracker for data plane state advertisement.

### 2.1 Create MissionTracker Module

**New File**: `lib/cadence/runtime/missions/mission_tracker.ex`

```elixir
defmodule Cadence.Runtime.Missions.MissionTracker do
  use Phoenix.Tracker

  def start_link(opts) do
    Phoenix.Tracker.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    server = Keyword.fetch!(opts, :pubsub_server)
    {:ok, %{pubsub_server: server, node_name: node()}}
  end

  def handle_diff(diff, state) do
    # Broadcast diffs to reconciler
    for {topic, {joins, leaves}} <- diff do
      Phoenix.PubSub.broadcast(state.pubsub_server, "mission_tracker:diff",
        {:tracker_diff, topic, joins, leaves})
    end
    {:ok, state}
  end
end
```

### 2.2 Add Tracker to Application Supervision Tree

**File**: `lib/cadence/application.ex`

Add `MissionTracker` to children list.

### 2.3 Define Status Schema

**New File**: `lib/cadence/runtime/missions/mission_status.ex`

```elixir
defmodule Cadence.Runtime.Missions.MissionStatus do
  defstruct [
    :mission_id,
    :config_generation,
    :observed_generation,
    :started_at,
    :status,  # :starting, :ready, :degraded, :stopping
    :conditions  # [{type, status, message}, ...]
  ]
end
```

---

## Phase 3: MissionInstance State Reporting

**Goal**: Make MissionInstance report its state via Phoenix.Tracker.

### 3.1 Update MissionInstance to Track State

**File**: `lib/cadence/runtime/missions/mission_instance.ex`

- Convert from pure Supervisor to Supervisor + GenServer (or use :extra_arguments)
- Track `observed_generation` in state
- Join Phoenix.Tracker on init with initial status
- Update tracker when status changes

### 3.2 Add Component Readiness Reporting

Each child component reports readiness back to MissionInstance:

**Pattern**:
```elixir
# In InterfaceSupervisor after loading interfaces
send(parent, {:component_ready, :interfaces, %{count: 5, generation: gen}})
```

**File changes**:
- `lib/cadence/runtime/interfaces/interface_supervisor.ex`
- `lib/cadence/runtime/commands/meta_command_cache.ex`
- `lib/cadence/runtime/telemetry/packet_identifier.ex`
- `lib/cadence/runtime/missions/cache_warmer.ex`

### 3.3 Aggregate Conditions in MissionInstance

MissionInstance collects component readiness and updates tracker:
- All components ready → status: :ready
- Some components not ready → status: :starting
- Component failure → status: :degraded

---

## Phase 4: Reconciler Infrastructure

**Goal**: Build the control plane reconciler with per-org sharding and periodic reconciliation.

### 4.1 Create ReconcilerManager

The ReconcilerManager uses the same reconciliation pattern to manage OrgReconcilers—reconcilers all the way down.

**New File**: `lib/cadence/runtime/reconciliation/manager.ex`

```elixir
defmodule Cadence.Runtime.Reconciliation.Manager do
  @moduledoc """
  Manages OrgReconciler processes using periodic reconciliation.

  Rather than event-driven creation (on org create), we periodically
  reconcile the set of running OrgReconcilers against the set of orgs
  in the database. This provides self-healing and avoids coupling
  org creation to runtime process management.
  """
  use GenServer

  @reconcile_interval :timer.seconds(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    send(self(), :reconcile)  # Immediate first reconcile on boot
    {:ok, %{}}
  end

  def handle_info(:reconcile, state) do
    reconcile_org_reconcilers()
    schedule_reconcile()
    {:noreply, state}
  end

  defp reconcile_org_reconcilers do
    desired = MapSet.new(Organizations.list_org_ids())
    actual = MapSet.new(list_running_reconciler_org_ids())

    # Start missing reconcilers
    for org_id <- MapSet.difference(desired, actual) do
      start_org_reconciler(org_id)
    end

    # Stop orphaned reconcilers (org was deleted)
    for org_id <- MapSet.difference(actual, desired) do
      stop_org_reconciler(org_id)
    end
  end

  defp schedule_reconcile do
    Process.send_after(self(), :reconcile, @reconcile_interval)
  end
end
```

### 4.2 Create OrgReconciler

Each organization gets its own reconciler for tenant isolation. Crash in org A doesn't affect org B.

**New File**: `lib/cadence/runtime/reconciliation/org_reconciler.ex`

```elixir
defmodule Cadence.Runtime.Reconciliation.OrgReconciler do
  @moduledoc """
  Reconciles missions for a single organization.

  Uses Task.Supervisor for parallel mission reconciliation within the org,
  with configurable concurrency limits.
  """
  use GenServer

  @reconcile_interval :timer.seconds(10)
  @max_concurrent_reconciles 5

  defstruct [:org_id, :reconcile_timer]

  def start_link(opts) do
    org_id = Keyword.fetch!(opts, :org_id)
    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {Cadence.ReconcilerRegistry, org_id}})
  end

  def init(opts) do
    org_id = Keyword.fetch!(opts, :org_id)

    # Subscribe to tracker diffs for this org's missions
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission_tracker:org:#{org_id}")

    send(self(), :reconcile)
    {:ok, %__MODULE__{org_id: org_id}}
  end

  # Periodic full reconcile
  def handle_info(:reconcile, state) do
    reconcile_all_missions(state.org_id)
    schedule_reconcile()
    {:noreply, state}
  end

  # Tracker diff triggers targeted reconcile (optimization, not required)
  def handle_info({:tracker_diff, _topic, joins, leaves}, state) do
    mission_ids = extract_mission_ids(joins ++ leaves)
    reconcile_missions(state.org_id, mission_ids)
    {:noreply, state}
  end

  defp reconcile_all_missions(org_id) do
    mission_ids = Missions.list_mission_ids_for_org(org_id)
    reconcile_missions(org_id, mission_ids)
  end

  defp reconcile_missions(org_id, mission_ids) do
    Task.Supervisor.async_stream_nolink(
      Cadence.ReconcilerTaskSupervisor,
      mission_ids,
      fn mission_id -> reconcile_mission(org_id, mission_id) end,
      max_concurrency: @max_concurrent_reconciles,
      timeout: :timer.seconds(30)
    )
    |> Stream.run()
  end

  defp reconcile_mission(_org_id, mission_id) do
    with {:ok, desired} <- get_desired_state(mission_id),
         {:ok, actual} <- get_actual_state(mission_id) do
      case {desired.status, actual} do
        {:active, nil} ->
          start_mission(mission_id, desired)

        {status, %{pid: pid}} when status != :active and is_pid(pid) ->
          stop_mission(mission_id)

        {:active, %{observed_generation: gen}} when gen != desired.config_generation ->
          reload_mission(mission_id, desired)

        _ ->
          :ok  # Already converged
      end
    end
  end

  defp schedule_reconcile do
    Process.send_after(self(), :reconcile, @reconcile_interval)
  end
end
```

### 4.3 Add Reconciler Supervision Tree

**New File**: `lib/cadence/runtime/reconciliation/supervisor.ex`

```elixir
defmodule Cadence.Runtime.Reconciliation.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      # Registry for OrgReconciler lookup by org_id
      {Registry, keys: :unique, name: Cadence.ReconcilerRegistry},

      # Task supervisor for parallel mission reconciliation
      {Task.Supervisor, name: Cadence.ReconcilerTaskSupervisor},

      # Dynamic supervisor for OrgReconcilers
      {DynamicSupervisor, name: Cadence.OrgReconcilerSupervisor, strategy: :one_for_one},

      # Manager that reconciles the reconcilers
      {Cadence.Runtime.Reconciliation.Manager, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### 4.4 Move Start/Stop Logic from MissionOperations

**File**: `lib/cadence/application/missions/mission_operations.ex`

- Remove direct `MissionSupervisor.start_mission/1` call from `start/2`
- Instead, just update DB status to `:active`
- OrgReconciler notices the drift and starts the mission

```elixir
# Before (imperative)
def start(mission_id, org_id) do
  with {:ok, mission} <- update_status(mission_id, :active),
       {:ok, _pid} <- MissionSupervisor.start_mission(mission) do
    {:ok, mission}
  end
end

# After (declarative)
def start(mission_id, _org_id) do
  # Just update desired state; reconciler handles the rest
  update_status(mission_id, :active)
end
```

---

## Phase 5: Config Injection (Pure OTP State Model)

**Goal**: Pass full config at startup, hold in GenServer state. No ETS for config data.

### 5.1 Design Principle: Config in Process State

Instead of ETS tables for config lookup, each component holds its config slice in GenServer state:

```
┌─────────────────────────────────────────────────────────────────┐
│ Traditional (ETS-based)           │ New (State-based)           │
├───────────────────────────────────┼─────────────────────────────│
│ Pipeline calls                    │ Pipeline uses               │
│   PacketIdentifier.identify()     │   state.packet_defs         │
│     → ETS lookup                  │   (already in heap)         │
│     → copies data to caller heap  │   → no copy, direct access  │
│     → creates GC pressure         │   → config in old heap      │
└───────────────────────────────────┴─────────────────────────────┘
```

**Benefits:**
- No ETS table management for config
- No copy-on-read (data already in process heap)
- Long-lived config moves to old heap, minimal GC impact
- Pure OTP: message passing and process state

**Exception:** CVT (CurrentValueTable) still uses ETS—it's genuine shared runtime state with multiple writers/readers.

### 5.2 Create MissionConfig Struct

**New File**: `lib/cadence/application/missions/mission_config.ex`

```elixir
defmodule Cadence.Application.Missions.MissionConfig do
  @moduledoc """
  Complete configuration snapshot for a mission.

  Loaded by OrgReconciler from the database, then injected into
  MissionInstance and its children. Each component receives its
  relevant slice and holds it in GenServer state.
  """

  defstruct [
    :mission_id,
    :organization_id,
    :config_generation,
    :mission,           # Mission entity
    :interfaces,        # List of Interface entities with protocols
    :targets,           # List of Target entities
    :packet_defs,       # Map of packet definitions by {ds_id, apid}
    :command_defs,      # Map of command definitions by {ds_id, name}
    :limit_defs,        # Map of limit definitions by item_name
    :derived_item_defs, # Map of derived item definitions
    :alarm_rules,       # List of alarm rules
    :automations        # List of automation definitions
  ]

  def load(mission_id) do
    # Single function that loads ALL config from DB
    # Returns {:ok, %MissionConfig{}} or {:error, reason}
    with {:ok, mission} <- load_mission(mission_id),
         {:ok, interfaces} <- load_interfaces(mission_id),
         {:ok, targets} <- load_targets(mission_id),
         {:ok, packet_defs} <- load_packet_definitions(mission_id),
         {:ok, command_defs} <- load_command_definitions(mission_id),
         {:ok, limit_defs} <- load_limit_definitions(mission_id),
         {:ok, derived_item_defs} <- load_derived_items(mission_id),
         {:ok, alarm_rules} <- load_alarm_rules(mission_id),
         {:ok, automations} <- load_automations(mission_id) do
      {:ok, %__MODULE__{
        mission_id: mission_id,
        organization_id: mission.organization_id,
        config_generation: mission.config_generation,
        mission: mission,
        interfaces: interfaces,
        targets: targets,
        packet_defs: packet_defs,
        command_defs: command_defs,
        limit_defs: limit_defs,
        derived_item_defs: derived_item_defs,
        alarm_rules: alarm_rules,
        automations: automations
      }}
    end
  end
end
```

### 5.3 Update OrgReconciler to Load and Inject Config

```elixir
defp start_mission(mission_id) do
  with {:ok, config} <- MissionConfig.load(mission_id),
       {:ok, _pid} <- MissionSupervisor.start_mission(config) do
    :ok
  end
end
```

### 5.4 Update MissionInstance to Distribute Config

**File**: `lib/cadence/runtime/missions/mission_instance.ex`

MissionInstance receives full config and passes relevant slices to each child:

```elixir
defp do_init(%MissionConfig{} = config) do
  children = [
    # CVT still uses ETS - genuine shared runtime state
    {CurrentValueTable, mission_id: config.mission_id},

    # Pipeline holds packet_defs in its state
    {Pipeline,
      mission_id: config.mission_id,
      packet_defs: config.packet_defs,
      targets: config.targets},

    # TargetPipelineSupervisor holds command_defs
    {TargetPipelineSupervisor,
      mission_id: config.mission_id,
      command_defs: config.command_defs,
      targets: config.targets},

    # StateTracker holds limit_defs
    {StateTracker,
      mission_id: config.mission_id,
      limit_defs: config.limit_defs},

    # AlarmManager holds alarm_rules
    {AlarmManager,
      mission_id: config.mission_id,
      alarm_rules: config.alarm_rules},

    # InterfaceSupervisor holds interface configs
    {InterfaceSupervisor,
      mission_id: config.mission_id,
      interfaces: config.interfaces},

    # ... etc
  ]

  Supervisor.init(children, strategy: :one_for_one)
end
```

### 5.5 Update Components to Hold Config in State

Each component stores its config slice in GenServer state:

```elixir
defmodule Cadence.Runtime.Telemetry.Pipeline do
  use GenServer

  defstruct [:mission_id, :packet_defs, :targets]

  def init(opts) do
    state = %__MODULE__{
      mission_id: Keyword.fetch!(opts, :mission_id),
      packet_defs: Keyword.fetch!(opts, :packet_defs),
      targets: Keyword.fetch!(opts, :targets)
    }
    {:ok, state}
  end

  def handle_info({:raw_packet, binary}, state) do
    # Direct access to state.packet_defs - no ETS lookup
    case identify_packet(binary, state.packet_defs) do
      {:ok, packet_def} -> process_packet(binary, packet_def, state)
      {:error, :unknown} -> log_unknown_packet(binary)
    end
    {:noreply, state}
  end

  # Pure function - no external dependencies
  defp identify_packet(<<apid::16, _rest::binary>>, packet_defs) do
    case Map.get(packet_defs, apid) do
      nil -> {:error, :unknown}
      def -> {:ok, def}
    end
  end
end
```

### 5.6 Remove ETS-Based Caches

The following modules become simpler or are eliminated:

| Before | After |
|--------|-------|
| `MetaCommandCache` (GenServer + ETS) | Config held in `TargetQueue` state |
| `PacketIdentifier` (GenServer + ETS) | Config held in `Pipeline` state |
| `Limits.Cache` (GenServer + ETS) | Config held in `StateTracker` state |
| `DerivedItems.Cache` (GenServer + ETS) | Config held in processor state |
| `CacheWarmer` (loads caches on startup) | **Eliminated** - config injected directly |

### 5.7 Files to Modify

**Remove or simplify:**
- `lib/cadence/runtime/commands/meta_command_cache.ex` - Eliminate
- `lib/cadence/runtime/telemetry/packet_identifier.ex` - Eliminate
- `lib/cadence/runtime/telemetry/limits/cache.ex` - Eliminate
- `lib/cadence/runtime/telemetry/derived_items/cache.ex` - Eliminate
- `lib/cadence/runtime/missions/cache_warmer.ex` - Eliminate

**Modify to accept config in opts:**
- `lib/cadence/runtime/telemetry/pipeline.ex` - Add packet_defs to state
- `lib/cadence/runtime/commands/target_queue.ex` - Add command_defs to state
- `lib/cadence/runtime/telemetry/limits/state_tracker.ex` - Add limit_defs to state
- `lib/cadence/runtime/alarms/alarm_manager.ex` - Add alarm_rules to state
- `lib/cadence/runtime/interfaces/interface_supervisor.ex` - Add interfaces to state

---

## Phase 6: Hot Reload via Config Push

**Goal**: Config changes trigger seamless component updates without mission restart.

### 6.1 Design Principle: Push Config, Components Self-Reconcile

Instead of computing diffs centrally, the reconciler simply pushes new config to components. Each component handles its own update logic:

```
┌─────────────────────────────────────────────────────────────────┐
│ Complex (central diff)            │ Simple (push + self-reconcile) │
├───────────────────────────────────┼─────────────────────────────────│
│ Reconciler computes ConfigDiff    │ Reconciler loads new config     │
│ Reconciler calls update_X() for   │ Reconciler sends {:apply_config}│
│   each changed component          │ Each component diffs internally │
│ Central code knows all configs    │ Components own their logic      │
└───────────────────────────────────┴─────────────────────────────────┘
```

### 6.2 Config Change Flow

1. User updates config (e.g., adds a limit)
2. `LimitOperations.create/3` saves to DB
3. `VersionRegistry.invalidate(:mission, mission_id)` bumps generation
4. OrgReconciler's periodic reconcile detects generation mismatch
5. OrgReconciler loads fresh `MissionConfig`
6. OrgReconciler sends config to MissionInstance
7. MissionInstance forwards slices to children
8. Each child updates its state

```elixir
# In OrgReconciler
defp reload_mission(mission_id) do
  with {:ok, config} <- MissionConfig.load(mission_id),
       :ok <- push_config_to_mission(mission_id, config) do
    :ok
  end
end

defp push_config_to_mission(mission_id, config) do
  case MissionInstance.whereis(mission_id) do
    nil -> {:error, :not_running}
    pid -> send(pid, {:apply_config, config})
  end
  :ok
end
```

### 6.3 MissionInstance Forwards Config to Children

MissionInstance is a Supervisor, but we can convert to Supervisor + GenServer hybrid,
or add a separate ConfigDistributor child that handles config updates:

```elixir
# Option A: MissionInstance as GenServer that supervises
def handle_info({:apply_config, config}, state) do
  # Forward relevant slices to each child
  send_to_child(:pipeline, {:apply_config, %{packet_defs: config.packet_defs}})
  send_to_child(:state_tracker, {:apply_config, %{limit_defs: config.limit_defs}})
  send_to_child(:alarm_manager, {:apply_config, %{alarm_rules: config.alarm_rules}})
  send_to_child(:interface_supervisor, {:apply_config, %{interfaces: config.interfaces}})
  # ...

  {:noreply, %{state | config_generation: config.config_generation}}
end

# Option B: Dedicated ConfigDistributor GenServer as child of MissionInstance
defmodule ConfigDistributor do
  def handle_info({:apply_config, config}, state) do
    # Same distribution logic
  end
end
```

### 6.4 Generation Guards: Reject Stale Config

Config updates can arrive out-of-order if multiple changes happen rapidly. Each component should guard against applying stale configurations by checking the generation number:

```elixir
defp apply_config_if_newer(config, state, apply_fn) do
  if config.config_generation <= state.observed_generation do
    Logger.debug("Ignoring stale config gen=#{config.config_generation}, current=#{state.observed_generation}")
    {:noreply, state}
  else
    apply_fn.()
  end
end
```

This pattern should be applied consistently across all components that handle `{:apply_config, ...}` messages.

### 6.5 Components Handle Their Own Updates

Each component receives new config and reconciles:

```elixir
defmodule Cadence.Runtime.Telemetry.Pipeline do
  # ... existing code ...

  def handle_info({:apply_config, %{packet_defs: new_packet_defs, generation: gen}}, state) do
    if gen <= state.observed_generation do
      {:noreply, state}
    else
      # Simply replace config in state
      # Old config becomes garbage, collected on next GC
      # New config moves to old heap after minor GC
      {:noreply, %{state | packet_defs: new_packet_defs, observed_generation: gen}}
    end
  end
end

defmodule Cadence.Runtime.Telemetry.Limits.StateTracker do
  def handle_info({:apply_config, %{limit_defs: new_limit_defs}}, state) do
    # Update config, preserve runtime state (current limit states)
    {:noreply, %{state | limit_defs: new_limit_defs}}
    # Next telemetry point will use new limits
  end
end

defmodule Cadence.Runtime.Alarms.AlarmManager do
  def handle_info({:apply_config, %{alarm_rules: new_rules}}, state) do
    # Update rules, preserve active alarms
    {:noreply, %{state | alarm_rules: new_rules}}
  end
end
```

### 6.6 Interface Updates: Special Case

Interfaces manage external connections. Some config changes require reconnection:

```elixir
defmodule Cadence.Runtime.Interfaces.InterfaceSupervisor do
  def handle_info({:apply_config, %{interfaces: new_interfaces}}, state) do
    current_ids = get_running_interface_ids(state)
    new_ids = MapSet.new(new_interfaces, & &1.id)

    # Stop removed interfaces
    for id <- MapSet.difference(current_ids, new_ids) do
      stop_interface(id, state)
    end

    # Start added interfaces
    for iface <- new_interfaces, iface.id not in current_ids do
      start_interface(iface, state)
    end

    # Restart interfaces with connection-affecting changes
    for iface <- new_interfaces, iface.id in current_ids do
      if connection_changed?(iface, get_running_config(iface.id, state)) do
        restart_interface(iface, state)
      else
        # Non-connection changes: just update config in interface state
        send_to_interface(iface.id, {:apply_config, iface})
      end
    end

    {:noreply, state}
  end

  defp connection_changed?(new, old) do
    new.host != old.host or new.port != old.port or new.interface_type != old.interface_type
  end
end
```

### 6.7 Config vs Runtime State

Key distinction for each component:

| Component | Config (swapped on update) | Runtime State (preserved) |
|-----------|---------------------------|---------------------------|
| Pipeline | `packet_defs`, `targets` | (none) |
| TargetQueue | `command_defs` | Queued commands |
| StateTracker | `limit_defs` | Current limit states |
| AlarmManager | `alarm_rules` | Active alarms |
| AutomationManager | `automations` | Running instances |
| InterfaceSupervisor | `interfaces` | Running interface PIDs |

### 6.8 Generation Tracking

After config is applied, update observed_generation:

```elixir
# In MissionInstance or ConfigDistributor
def handle_info({:apply_config, config}, state) do
  distribute_config(config)

  # Update generation and report to tracker
  new_state = %{state | observed_generation: config.config_generation}
  MissionTracker.update(state.mission_id, %{observed_generation: config.config_generation})

  {:noreply, new_state}
end
```

### 6.9 No ConfigDiff Module Needed

The original plan had a `ConfigDiff` struct with fields for every type of change.
This is eliminated—each component handles its own diffing internally.

Benefits:
- No central module that must understand all config types
- Adding new config types doesn't require updating ConfigDiff
- Each component's update logic lives with that component
- Simpler testing (test each component's handle_info independently)

---

## Phase 7: Observability & Testing

### 7.1 Add Telemetry Events

Instrument reconciliation:
- `[:cadence, :reconciler, :reconcile, :start]`
- `[:cadence, :reconciler, :reconcile, :stop]`
- `[:cadence, :reconciler, :drift, :detected]`

### 7.2 Add LiveView Dashboard

Show reconciler state in admin UI:
- Desired vs actual state per mission
- Work queue length
- Recent reconciliation events

### 7.3 Testing Strategy

- Unit tests for OrgReconciler reconcile logic
- Unit tests for ReconcilerManager org reconciler management
- Integration tests for full start/stop/reload cycles
- Property tests for generation computation
- Chaos tests for crash recovery (kill OrgReconciler, verify restart and re-reconcile)

---

## Implementation Order & Rollout Strategy

**Approach**: Big bang rollout behind feature flag. Build complete architecture, validate thoroughly, then switch over.

### Build Order

1. **Phase 1** (Foundation) - Generation tracking infrastructure
2. **Phase 2** (Tracker) - Phoenix.Tracker setup
3. **Phase 5** (Config Injection) - Refactor components to accept injected config
4. **Phase 3** (State Reporting) - MissionInstance reports via Tracker
5. **Phase 4** (Reconciler Infrastructure) - Build ReconcilerManager, OrgReconciler, supervision tree
6. **Phase 6** (Hot Reload) - Rolling update logic
7. **Phase 7** (Observability) - Dashboards and telemetry

### Feature Flag Strategy

```elixir
# In config/runtime.exs
config :cadence, :mission_reconciler_enabled, System.get_env("ENABLE_RECONCILER") == "true"

# In MissionOperations.start/2
def start(mission_id, org_id) do
  if Application.get_env(:cadence, :mission_reconciler_enabled) do
    # New path: just update DB, let reconciler handle start
    update_mission_status(mission_id, :active)
  else
    # Legacy path: direct supervisor call
    legacy_start(mission_id, org_id)
  end
end
```

### Validation Before Cutover

1. Run both paths in parallel in staging
2. Compare behavior via telemetry
3. Chaos testing: kill reconciler, verify data plane stability
4. Load testing: many missions, frequent config changes
5. Manual validation of all config change scenarios

### Cutover Checklist

- [ ] All phases implemented and tested
- [ ] Staging validation complete
- [ ] Rollback procedure documented
- [ ] Monitoring dashboards ready
- [ ] On-call team briefed

---

## Key Files to Modify

### New Files
- `lib/cadence/runtime/reconciliation/supervisor.ex` - Reconciler supervision tree
- `lib/cadence/runtime/reconciliation/manager.ex` - Manages OrgReconcilers via periodic reconciliation
- `lib/cadence/runtime/reconciliation/org_reconciler.ex` - Per-org mission reconciler
- `lib/cadence/runtime/missions/mission_tracker.ex` - Phoenix.Tracker for state advertisement
- `lib/cadence/runtime/missions/mission_status.ex` - Status struct with conditions
- `lib/cadence/application/missions/mission_config.ex` - Full config loader
- `priv/repo/migrations/*_add_config_generation_to_missions.exs` - DB migration

### Files to Remove (ETS caches replaced by GenServer state)
- `lib/cadence/runtime/commands/meta_command_cache.ex` - Config now in TargetQueue state
- `lib/cadence/runtime/telemetry/packet_identifier.ex` - Config now in Pipeline state
- `lib/cadence/runtime/telemetry/limits/cache.ex` - Config now in StateTracker state
- `lib/cadence/runtime/telemetry/derived_items/cache.ex` - Config now in processor state
- `lib/cadence/runtime/missions/cache_warmer.ex` - No longer needed, config injected at startup

### Modified Files
- `lib/cadence/application.ex` - Add Reconciliation.Supervisor and MissionTracker
- `lib/cadence/domain/missions/entities/mission.ex` - Add config_generation
- `lib/cadence/missions/mission.ex` - Add config_generation
- `lib/cadence/config/version_registry.ex` - Add mission-level generation
- `lib/cadence/application/missions/mission_operations.ex` - Remove direct supervisor calls
- `lib/cadence/runtime/missions/mission_instance.ex` - Accept MissionConfig, distribute to children, handle {:apply_config}
- `lib/cadence/runtime/missions/mission_supervisor.ex` - Accept MissionConfig
- `lib/cadence/runtime/telemetry/pipeline.ex` - Hold packet_defs in state, handle {:apply_config}
- `lib/cadence/runtime/commands/target_queue.ex` - Hold command_defs in state, handle {:apply_config}
- `lib/cadence/runtime/telemetry/limits/state_tracker.ex` - Hold limit_defs in state, handle {:apply_config}
- `lib/cadence/runtime/alarms/alarm_manager.ex` - Hold alarm_rules in state, handle {:apply_config}
- `lib/cadence/runtime/interfaces/interface_supervisor.ex` - Hold interfaces in state, handle {:apply_config}

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Reconciler becomes bottleneck | Per-org sharding + Task-based parallelism within each org |
| Org reconciler crash affects tenant | DynamicSupervisor restarts individual OrgReconciler; other orgs unaffected |
| New org waits for reconciler | ReconcilerManager periodic reconcile (30s max latency); acceptable for rare org creation |
| Tracker state inconsistency | Periodic full reconcile (every 10s per org) as safety net |
| Large config in GenServer heap | Config moves to old heap after first GC; minimal ongoing impact. For very large configs (100MB+), consider chunking |
| Config update causes GC pause | Old config becomes garbage, triggers GC. But config updates are rare; acceptable tradeoff |
| Message copy on config push | Full config copied when sent to MissionInstance. One-time cost per update; acceptable |
| Breaking existing start/stop UI | Keep facade API, change implementation |
| Components miss config update | Supervisor restarts guarantee fresh config; periodic reconcile catches drift |
| Test complexity | Start with integration tests, add unit tests incrementally |

---

## Success Criteria

1. Missions auto-start on application boot if status is `:active`
2. Missed PubSub events don't leave system in bad state
3. Config changes propagate within reconcile interval
4. Data plane continues running if control plane crashes
5. Clear observability into reconciler state

---

## Future Enhancements

The following concerns have been identified but deferred until after the core reconciliation model is proven. These are hardening and production-readiness improvements.

### Race Conditions & Consistency

**User actions during reconciliation**
If a user toggles mission status while an OrgReconciler is mid-reconcile, the reconciler may act on stale desired state. Consider optimistic locking or re-fetching desired state before executing actions.

**Idempotency of config application**
Verify that `{:apply_config, config}` is fully idempotent. Message duplication (however unlikely) should not cause issues.

### Orphaned Runtime State

**Config deletion with active runtime state**
When new config removes an entity that has active runtime state (e.g., removing a limit with an active alarm, or a target with queued commands), the orphaned state needs cleanup. Each component should reconcile its runtime state against the new config:

```elixir
def handle_info({:apply_config, %{alarm_rules: new_rules}}, state) do
  orphaned_alarms = find_alarms_without_rules(state.active_alarms, new_rules)
  for alarm <- orphaned_alarms, do: clear_alarm(alarm)
  {:noreply, %{state | alarm_rules: new_rules}}
end
```

### Startup & Shutdown

**Thundering herd on node restart**
On application boot, all OrgReconcilers trigger `send(self(), :reconcile)` immediately. With many orgs, this creates simultaneous DB load. Consider staggered startup with jitter:

```elixir
def init(opts) do
  jitter = :rand.uniform(@reconcile_interval)
  Process.send_after(self(), :reconcile, jitter)
  {:ok, state}
end
```

**Cold start performance**
With many active missions, startup requires loading all configs. Consider:
- Parallel loading with controlled concurrency
- Startup priority (critical missions first)
- Progress reporting to observability layer

**Graceful shutdown**
Data plane needs coordinated shutdown for in-flight telemetry, queued commands, and active TCP connections. Consider adding shutdown coordination protocol.

### Failure Resilience

**Database unavailability**
Reconcilers depend on DB reads. If DB is slow or partitioned:
- ReconcilerManager can't list orgs
- OrgReconcilers can't load MissionConfig

Consider caching last-known-good config for resilience, or graceful degradation behavior.

**Config validation before apply**
`MissionConfig.load/1` pulls raw data from DB. Invalid configs could crash components on apply. Consider validation step:

```elixir
def load(mission_id) do
  with {:ok, config} <- load_raw(mission_id),
       :ok <- validate(config) do
    {:ok, config}
  end
end
```

**Task timeout leaving partial state**
`async_stream_nolink` with 30s timeout could leave missions partially reconciled if timeout occurs mid-batch. The next reconcile cycle handles this, but there's a window of inconsistency to consider.

### Distributed System Concerns

**Phoenix.Tracker eventual consistency**
Phoenix.Tracker uses CRDTs—during network hiccups or node joins, reconcilers may see temporarily stale data plane state. A mission might appear "not running" when it actually is on another node, potentially causing duplicate start attempts.

**Multi-node testing**
Testing strategy should eventually cover:
- Network partition scenarios (netsplit between nodes)
- Node join/leave during reconciliation
- Phoenix.Tracker behavior under partition

### Backpressure & Rate Limiting

**Rapid config changes**
No rate limiting if config changes come in rapidly (e.g., bulk import). Consider debouncing or coalescing:

```elixir
def handle_info(:reconcile, state) do
  if state.reconcile_in_progress do
    {:noreply, %{state | needs_re_reconcile: true}}
  else
    do_reconcile(state)
  end
end
```

### Migration & Compatibility

**Migration of existing data**
Existing running missions need their `config_generation` initialized correctly. Document what happens to missions started before this architecture is deployed.

**Generation overflow**
`config_generation` is an integer. While overflow is unlikely in practice, consider using bigint or documenting expected behavior.

---

## References

- [Kubernetes Controllers](https://kubernetes.io/docs/concepts/architecture/controller/)
- [Level Triggering and Reconciliation in Kubernetes](https://medium.com/hackernoon/level-triggering-and-reconciliation-in-kubernetes-1f17fe30333d)
- [Control Plane vs Data Plane - AWS](https://docs.aws.amazon.com/wellarchitected/latest/reducing-scope-of-impact-with-cell-based-architecture/control-plane-and-data-plane.html)
- [Phoenix.Tracker](https://hexdocs.pm/phoenix_pubsub/Phoenix.Tracker.html)
