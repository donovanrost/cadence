# Data Plane / Control Plane Migration Plan

## Executive Summary

This plan outlines the remaining work to complete the Data Plane / Control Plane architecture separation for Cadence. Phases 1-2 (Interfaces and Protocol Chain runtime) are complete. This plan covers Phase 3 (Telemetry Pipeline optimization) and beyond.

---

## Current State Assessment

### Completed Work

| Phase | Component | Status |
|-------|-----------|--------|
| Phase 1 | Interface Runtime | Complete |
| Phase 1 | InterfaceSupervisor hot reload | Complete |
| Phase 1 | Status broadcasting via PubSub | Complete |
| Phase 2 | Protocol Chain runtime | Complete |
| Phase 2 | ProtocolChainSupervisor hot reload | Complete |

### Hexagonal Architecture Migration Status

The Data Plane / Control Plane separation depends on hexagonal architecture being in place. Here's the current status:

| Domain | Hexagonal Status | Notes |
|--------|------------------|-------|
| **Interfaces** | ✅ Complete | Full hexagonal + Data Plane ready |
| **Missions** | ✅ Complete | Full hexagonal + runtime separation |
| **Accounts** | ✅ Complete | Full hexagonal implementation |
| **Organizations** | ✅ Complete | Full hexagonal implementation |
| **Settings** | ✅ Complete | Full hexagonal implementation |
| **Procedures** | ⚠️ Partial | Domain entities exist, runtime operational |
| **Alerting** | ⚠️ Partial | Hexagonal layer exists, runtime needs refactoring |
| **Automations** | ⚠️ Partial | Domain entities exist, runtime good |
| **Commanding** | ⚠️ Partial | Domain entities exist, needs complete migration |
| **Targeting** | ⚠️ Partial | Domain entities exist |
| **Schedules** | ⚠️ Partial | Domain entities exist |
| **Dashboard Layouts** | ⚠️ Partial | Domain entities exist |
| **Notifications** | ⚠️ Partial | Domain entities exist |
| **Buckets** | ❌ Legacy | `lib/cadence/buckets/` - not migrated |
| **Outbox** | ❌ Legacy | `lib/cadence/outbox/` - transactional outbox, not hexagonal |
| **Telemetry** | ❌ Legacy | `lib/cadence/telemetry/` - critical Data Plane code, legacy structure |
| **Mission Database** | ❌ Legacy | `lib/cadence/mission_database/` - command/telemetry definitions |
| **Shifts** | ❌ Legacy | `lib/cadence/shifts/` - not migrated |
| **Simulator** | ❌ Legacy | `lib/cadence/simulator/` - testing utility |
| **Timeline** | ❌ Legacy | `lib/cadence/timeline/` - not migrated |
| **Recordings** | ⚠️ Partial | Has adapters, not fully hexagonal |

### Runtime Folder Structure

Currently, only `lib/cadence/runtime/missions/` exists for Data Plane separation. Other runtime components are scattered throughout the codebase. The target structure should consolidate all Data Plane GenServers under `lib/cadence/runtime/`:

**Current State:**
```
lib/cadence/
├── runtime/
│   └── missions/                    # ✅ Clean separation
│       ├── mission_instance.ex
│       └── mission_supervisor.ex
├── interfaces/                      # ❌ Mixed Control/Data Plane
│   ├── interface_supervisor.ex      # Data Plane - should move
│   ├── tcp_client_interface.ex      # Data Plane - should move
│   ├── tcp_server_interface.ex      # Data Plane - should move
│   └── factory.ex                   # Data Plane - should move
├── commands/                        # ❌ Mixed Control/Data Plane
│   ├── target_dispatcher.ex         # Data Plane - should move
│   ├── target_queue.ex              # Data Plane - should move
│   └── target_pipeline_supervisor.ex # Data Plane - should move
├── alarms/
│   └── engine/                      # ❌ Mixed Control/Data Plane
│       ├── alarm_manager.ex         # Data Plane - should move
│       └── rule_cache.ex            # Data Plane - should move
└── telemetry/                       # ❌ Mixed Control/Data Plane
    ├── pipeline.ex                  # Data Plane - should move
    ├── pipeline_v2/                 # Data Plane - should move
    ├── current_value_table.ex       # Data Plane - should move
    └── packet_identifier.ex         # Data Plane - should move
```

**Target State:**
```
lib/cadence/runtime/
├── missions/
│   ├── mission_instance.ex
│   └── mission_supervisor.ex
├── interfaces/
│   ├── interface_supervisor.ex
│   ├── tcp_client_interface.ex
│   ├── tcp_server_interface.ex
│   └── factory.ex
├── commands/
│   ├── target_pipeline_supervisor.ex
│   ├── target_dispatcher.ex
│   ├── target_queue.ex
│   └── meta_command_cache.ex
├── alarms/
│   ├── alarm_manager.ex
│   └── rule_cache.ex
└── telemetry/
    ├── pipeline.ex
    ├── pipeline_v2/
    ├── current_value_table.ex
    ├── packet_identifier.ex
    ├── limits/
    │   └── cache.ex
    └── derived_items/
        └── cache.ex
```

This reorganization clearly separates Control Plane (configuration, CRUD) from Data Plane (runtime processing) code.

### Architecture Health

**Well-Structured (Data Plane Ready):**
- `lib/cadence/runtime/missions/` - Clean data plane separation
- `lib/cadence/telemetry/limits/cache.ex` - ETS-based, O(1) lookups
- `lib/cadence/telemetry/derived_items/cache.ex` - ETS-based with indices
- `lib/cadence/telemetry/packet_identifier.ex` - ETS-cached packet lookup
- `lib/cadence/telemetry/current_value_table.ex` - Pure ETS operations
- `lib/cadence/interfaces/` - GenServers receive domain entities

**Needs Work:**
- `lib/cadence/commands/target_dispatcher.ex` - DB call in hot path (line 974)
- `lib/cadence/commands/target_queue.ex` - Frequent DB operations
- `lib/cadence/alarms/engine/rule_cache.ex` - DB call during rule filtering (line 230)
- Dashboard LiveViews - Not yet using PubSub for real-time status
- Missing: Centralized config cache with versioning
- Missing: Target identifier → UUID cache

**Bugs Found (separate from Data Plane):**
- `lib/cadence/telemetry/conversions.ex` - `apply_db_conversion/2` doesn't handle calibrator-based conversion maps (lines 221-245)

---

## Phase 3: Mission Database Loading Strategy

The Mission Database contains all command and telemetry definitions (DefinitionSets). This is critical infrastructure that must be properly cached for the Data Plane.

### 3.0 Current State Analysis

| Component | Loading Strategy | Cache | Hot Path DB Calls | Status |
|-----------|------------------|-------|-------------------|--------|
| **PacketIdentifier** | Eager at mission start | ETS | None | Good |
| **MetaCommand lookup** | Lazy per dispatch | None | 1 per command | **Needs work** |
| **Limits** | Lazy, 5-min TTL | ETS | First access | OK |
| **Derived Items** | Lazy, 5-min TTL | ETS | First access | OK |
| **TargetDispatcher** | Loads target at init | None | 2 at init | OK (init only) |

### 3.1 MetaCommand Cache (Critical)

**Problem:** Every command dispatch calls `Commands.get_meta_command()` which hits the database.

**File:** `lib/cadence/commands/target_dispatcher.ex` - `get_command/2` function

**Solution:** Create `MetaCommandCache` following the `PacketIdentifier` pattern.

**New file: `lib/cadence/commands/meta_command_cache.ex`**

```elixir
defmodule Cadence.Commands.MetaCommandCache do
  @moduledoc """
  ETS-based cache for MetaCommand definitions.

  Part of the Data Plane - provides O(1) command lookup during dispatch.
  Scoped by definition_set_id to support constellation missions with
  multiple spacecraft platforms.

  ## Cache Structure

  - Key: `{definition_set_id, command_name}` or `{definition_set_id, :opcode, opcode}`
  - Value: MetaCommand struct with arguments and verifiers preloaded

  ## Lifecycle

  1. Started as child of MissionInstance
  2. Loads all commands for all definition_sets used by mission targets
  3. Subscribes to PubSub for definition_set changes
  4. Hot-reloads on `:definition_set_changed` events
  """

  use GenServer
  require Logger

  alias Cadence.MissionDatabase.MetaCommand
  alias Cadence.Repo

  import Ecto.Query

  @table_prefix :meta_command_cache

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Looks up a command by name for a given definition_set.
  Returns {:ok, command} or {:error, :not_found}.
  O(1) ETS lookup - no database call.
  """
  def get_by_name(mission_id, definition_set_id, command_name) do
    table = table_name(mission_id)
    case :ets.lookup(table, {definition_set_id, command_name}) do
      [{_, command}] -> {:ok, command}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Looks up a command by opcode for a given definition_set.
  """
  def get_by_opcode(mission_id, definition_set_id, opcode) do
    table = table_name(mission_id)
    case :ets.lookup(table, {definition_set_id, :opcode, opcode}) do
      [{_, command}] -> {:ok, command}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all commands for a definition_set.
  """
  def list_for_definition_set(mission_id, definition_set_id) do
    table = table_name(mission_id)
    # Use match spec to find all commands for this definition_set
    :ets.match_object(table, {{definition_set_id, :_}, :_})
    |> Enum.map(fn {_key, command} -> command end)
    |> Enum.uniq_by(& &1.id)
  end

  # GenServer callbacks

  @impl true
  def init(mission_id) do
    table = :ets.new(table_name(mission_id), [
      :named_table, :set, :public, read_concurrency: true
    ])

    # Subscribe to definition_set changes
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:definition_set")
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:targets")

    # Load all commands for mission's definition_sets
    load_all_definition_sets(mission_id, table)

    {:ok, %{mission_id: mission_id, table: table}}
  end

  @impl true
  def handle_info({:definition_set_changed, definition_set_id, _version}, state) do
    Logger.info("Reloading MetaCommandCache for definition_set=#{definition_set_id}")
    load_for_definition_set(definition_set_id, state.table)
    {:noreply, state}
  end

  def handle_info({:target_definition_set_changed, _target_id, definition_set_id}, state) do
    # A target switched to a new definition_set - ensure it's loaded
    load_for_definition_set(definition_set_id, state.table)
    {:noreply, state}
  end

  def handle_info({:target_created, target}, state) do
    # New target added - ensure its definition_set is loaded
    if target.definition_set_id do
      load_for_definition_set(target.definition_set_id, state.table)
    end
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private functions

  defp load_all_definition_sets(mission_id, table) do
    # Get all unique definition_set_ids from targets in this mission
    definition_set_ids = get_mission_definition_set_ids(mission_id)

    Enum.each(definition_set_ids, fn ds_id ->
      load_for_definition_set(ds_id, table)
    end)

    Logger.info(
      "MetaCommandCache loaded #{length(definition_set_ids)} definition_sets " <>
      "for mission=#{mission_id}"
    )
  end

  defp get_mission_definition_set_ids(mission_id) do
    from(t in Cadence.Targets.Target,
      where: t.mission_id == ^mission_id and not is_nil(t.definition_set_id),
      select: t.definition_set_id,
      distinct: true
    )
    |> Repo.all()
  end

  defp load_for_definition_set(definition_set_id, table) do
    commands =
      from(mc in MetaCommand,
        where: mc.definition_set_id == ^definition_set_id and mc.abstract == false,
        preload: [:arguments, :verifiers, :interlocks, :transmission_constraints]
      )
      |> Repo.all()

    Enum.each(commands, fn cmd ->
      # Index by name
      :ets.insert(table, {{definition_set_id, cmd.name}, cmd})

      # Also index by opcode for binary protocol lookup
      if cmd.opcode do
        :ets.insert(table, {{definition_set_id, :opcode, cmd.opcode}, cmd})
      end
    end)

    Logger.debug(
      "Loaded #{length(commands)} commands for definition_set=#{definition_set_id}"
    )
  end

  defp table_name(mission_id), do: :"#{@table_prefix}_#{mission_id}"
  defp via_tuple(mission_id), do: {:via, Registry, {Cadence.MissionRegistry, {:meta_command_cache, mission_id}}}
end
```

**Add to MissionInstance children:**

```elixir
# lib/cadence/runtime/missions/mission_instance.ex
children = [
  {CurrentValueTable, mission_id: mission_id},
  {Cadence.Telemetry.PacketIdentifier, mission_id: mission_id},
  {Cadence.Commands.MetaCommandCache, mission_id: mission_id},  # NEW
  # ... rest of children
]
```

**Update TargetDispatcher to use cache:**

```elixir
# lib/cadence/commands/target_dispatcher.ex
defp get_command(target, command_name) do
  definition_set_id = target.definition_set_id

  # Use cache instead of DB query
  case MetaCommandCache.get_by_name(state.mission_id, definition_set_id, command_name) do
    {:ok, command} -> {:ok, command}
    {:error, :not_found} -> {:error, :unknown_command}
  end
end
```

### 3.2 Eager Loading for Limits and Derived Items

**Current:** Both use lazy loading with 5-minute TTL. First telemetry packet triggers DB query.

**Improvement:** Trigger cache warm-up during MissionInstance startup.

```elixir
# lib/cadence/runtime/missions/mission_instance.ex
defp do_init(mission_id, mission_name, organization_id) do
  # ... existing children setup ...

  # Warm up caches after supervision tree is started
  {:ok, supervisor_pid, {:continue, :warm_caches}}
end

def handle_continue(:warm_caches, state) do
  # Get all targets for this mission
  targets = Targets.list_for_mission(state.mission_id)

  # Warm up limits cache for each target
  Enum.each(targets, fn target ->
    Cadence.Telemetry.Limits.Cache.warm(state.mission_id, target.id)
  end)

  # Warm up derived items cache
  Cadence.Telemetry.DerivedItems.Cache.warm(state.mission_id)

  {:noreply, state}
end
```

### 3.3 Target-to-DefinitionSet Mapping

**Current:** PacketIdentifier caches this, but command dispatch loads target from DB.

**Issue:** `TargetDispatcher.init/1` calls:
- `Missions.get_mission!(mission_id)` - DB call
- `Targets.get_target_with_definition_set!(target_id)` - DB call

**Solution:** TargetDispatcher should receive target entity at startup (like Interface pattern).

```elixir
# Current (target_dispatcher.ex:203-211)
def init({mission_id, target_id}) do
  mission = Missions.get_mission!(mission_id)  # DB call
  target = Targets.get_target_with_definition_set!(target_id)  # DB call
  ...
end

# Target: Receive entities from supervisor
def init(%{mission: mission, target: target}) do
  # No DB calls - entities injected
  ...
end
```

**TargetPipelineSupervisor changes:**

```elixir
defmodule Cadence.Commands.TargetPipelineSupervisor do
  def init(mission_id) do
    # Load all targets with definition_sets at supervisor start
    mission = MissionQueries.get(mission_id)
    targets = TargetQueries.list_for_mission(mission_id, preload: [:definition_set])

    children = Enum.flat_map(targets, fn target ->
      [
        {TargetQueue, %{mission: mission, target: target}},
        {TargetDispatcher, %{mission: mission, target: target}}
      ]
    end)

    # Subscribe to target changes for hot reload
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:targets")

    Supervisor.init(children, strategy: :one_for_one)
  end

  def handle_info({:target_created, target}, state) do
    # Start new queue + dispatcher for target
    start_target_pipeline(target, state.mission)
    {:noreply, state}
  end
end
```

---

### 3.4 Consolidated Data Plane Cache Architecture

After implementing the above, the Data Plane cache architecture looks like:

```
MissionInstance Supervision Tree
├── CurrentValueTable (ETS)
│   └── Latest telemetry values per item
│
├── PacketIdentifier (ETS) ← existing
│   ├── {definition_set_id, :type_byte, packet_type} → PacketDef
│   ├── {definition_set_id, :apid, apid} → PacketDef
│   └── {:target_ds, target_identifier} → definition_set_id
│
├── MetaCommandCache (ETS) ← NEW
│   ├── {definition_set_id, command_name} → MetaCommand
│   └── {definition_set_id, :opcode, opcode} → MetaCommand
│
├── Limits.Cache (ETS) ← existing, add warm()
│   └── {mission_id, target_id} → {limits_map, limit_set, cached_at}
│
├── DerivedItems.Cache (ETS) ← existing, add warm()
│   └── mission_id → {sorted_defs, packet_index, cached_at}
│
├── InterfaceSupervisor
│   └── Holds interface entities for child restart
│
└── TargetPipelineSupervisor ← refactor
    └── Holds target entities for child restart
```

**All caches share these properties:**
1. Loaded at mission startup (eager or warm-on-start)
2. Subscribe to PubSub for hot reload
3. O(1) lookup during runtime
4. No DB calls in hot path

### 3.5 Target Identifier Cache

**Problem:** `RuleCache.resolve_target_id/2` calls `Targets.get_target_by_identifier()` during rule filtering when target_id is a string identifier instead of UUID.

**File:** `lib/cadence/alarms/engine/rule_cache.ex:224-234`

```elixir
# Current: DB call during rule filtering
defp resolve_target_id(mission_id, target_id) when is_binary(target_id) do
  case Ecto.UUID.cast(target_id) do
    {:ok, uuid} -> uuid
    :error ->
      case Targets.get_target_by_identifier(mission_id, target_id) do  # DB CALL!
        {:ok, %{id: uuid}} -> uuid
        {:error, :not_found} -> nil
      end
  end
end
```

**Solution:** Add target identifier mapping to PacketIdentifier's ETS cache (already has target data).

**Option A: Extend PacketIdentifier**

PacketIdentifier already caches `{:target_ds, target_identifier} → definition_set_id`. Extend to also cache `{:target_id, target_identifier} → target_uuid`:

```elixir
# In PacketIdentifier.cache_target_definition_sets/2
defp cache_target_definition_sets(table_name, mission_id) do
  targets = ...

  Enum.each(targets, fn target ->
    # Existing: for definition_set lookup
    :ets.insert(table_name, {{:target_ds, target.identifier}, target.definition_set_id})

    # NEW: for target UUID lookup
    :ets.insert(table_name, {{:target_id, target.identifier}, target.id})
  end)
end

# New public function
def get_target_id(mission_id, identifier) do
  table = table_name(mission_id)
  case :ets.lookup(table, {:target_id, identifier}) do
    [{_, target_id}] -> {:ok, target_id}
    [] -> {:error, :not_found}
  end
end
```

**Option B: Dedicated TargetCache**

Create `lib/cadence/targets/target_cache.ex` for mission-scoped target lookups:

```elixir
defmodule Cadence.Targets.TargetCache do
  @moduledoc """
  ETS cache for target lookups by identifier.
  Eliminates DB calls when resolving target identifiers to UUIDs.
  """

  use GenServer

  def get_target_id(mission_id, identifier) do
    table = table_name(mission_id)
    case :ets.lookup(table, {:by_identifier, identifier}) do
      [{_, target_id}] -> {:ok, target_id}
      [] -> {:error, :not_found}
    end
  end

  def get_target(mission_id, identifier) do
    table = table_name(mission_id)
    case :ets.lookup(table, {:full, identifier}) do
      [{_, target}] -> {:ok, target}
      [] -> {:error, :not_found}
    end
  end
end
```

**Update RuleCache:**

```elixir
# After: Use cached lookup
defp resolve_target_id(mission_id, target_id) when is_binary(target_id) do
  case Ecto.UUID.cast(target_id) do
    {:ok, uuid} -> uuid
    :error ->
      case PacketIdentifier.get_target_id(mission_id, target_id) do
        {:ok, uuid} -> uuid
        {:error, :not_found} -> nil
      end
  end
end
```

---

## Phase 4: Alarms, Automations & Procedures Runtime

### 4.0 Data Plane Audit Results

| Component | Init DB Calls | Hot Path DB Calls | Cache Strategy | Status |
|-----------|---------------|-------------------|----------------|--------|
| **AlarmManager** | None | None | ETS (no TTL) | Good |
| **RuleCache** | `list_rules()` on miss | `get_target_by_identifier()` | ETS, 5-min refresh | **Fix target lookup** |
| **AutomationManager** | `list_automations()` | None | ETS (no TTL) | Good |
| **ActionExecutor** | None | `get_alarm()` on action | None | OK (not per-packet) |
| **ExecutionCoordinator** | `list_executions()` | None | In-memory map | Good |
| **ExecutionProcess** | `get_execution!()` + preload | None | Lua state | Good |
| **ExecutionPersistence** | None | Transaction on state change | Outbox pattern | OK (not per-packet) |

### 4.1 Alarms Runtime - RuleCache Fix

Already covered in 3.5 above. The key change is to use PacketIdentifier's cached target data instead of DB lookups.

### 4.2 Automations Runtime - Already Good

AutomationManager properly:
- Loads automations at init into ETS
- Subscribes to PubSub for updates (`mission:{id}:automations`)
- Processes events without DB calls
- Only hits DB when reloading a single automation on update event

**No changes needed.**

### 4.3 Procedures Runtime - Already Good

ExecutionCoordinator and ExecutionProcess properly:
- Load execution data at process init (acceptable, not per-packet)
- Use in-memory state for execution control
- Persist via ExecutionPersistence only on state changes
- Use outbox pattern for event sourcing

**No changes needed.**

### 4.4 Telemetry Pipeline Stages - Already Good

All pipeline stages use cached data:

| Stage | Data Source | Cache |
|-------|-------------|-------|
| IdentifyStage | PacketIdentifier | ETS |
| DecommutationStage | packet_def.field_specs | Pre-compiled in ETS |
| ConversionStage | packet_def.items_by_name | Pre-loaded in ETS |
| DeriveStage | DerivedItems.Cache | ETS with TTL |
| LimitsStage | StateTracker + Limits.Cache | ETS with TTL |

**No changes needed** (but see bug note about `apply_db_conversion`).

---

## Phase 5: Command Queue Optimization

### 5.1 Command Queue Local State

**Problem:** `target_queue.ex` has multiple `Repo.get()` and `Repo.all()` calls for queue management.

**Analysis:** These are not per-telemetry-packet but are frequent operations. The queue is inherently stateful and persistent (commands must survive restarts).

**Recommendation:** Hybrid approach - keep persistence but add local state caching.

| Operation | Current | Target |
|-----------|---------|--------|
| `fetch_next_ready_entry` | DB query | Local queue + DB persistence |
| `mark_executing` | DB update | Local state + async DB write |
| `count_by_status` | DB count | Local counter |

**Implementation Strategy:**

1. **Local queue state in GenServer**: Keep in-memory list of pending commands
2. **Async persistence**: Write to DB asynchronously via `Task.async` or Oban
3. **Recovery on restart**: Load from DB on init, mark orphaned entries as failed

```elixir
# In TargetQueue GenServer state
defmodule State do
  defstruct [
    :target_id,
    :mission_id,
    pending_queue: :queue.new(),  # In-memory queue
    executing: nil,                # Currently executing command
    counts: %{pending: 0, executing: 0, completed: 0, failed: 0}
  ]
end
```

---

## Phase 6: Remaining Domain Migrations

### 4.1 Commanding Domain (Hexagonal Migration)

**Current State:** Mixed - some hexagonal, some legacy schema-based.

**Files to Create:**

| Component | Location |
|-----------|----------|
| Entities | `lib/cadence/domain/commanding/entities/` |
| Value Objects | `lib/cadence/domain/commanding/value_objects/` |
| Repository Port | `lib/cadence/ports/repository/commanding/` |
| Ecto Adapter | `lib/cadence/adapters/persistence/ecto/commanding/` |
| Application Services | `lib/cadence/application/commanding/` (exists, enhance) |

**Entities to Define:**

```elixir
# lib/cadence/domain/commanding/entities/queued_command.ex
defmodule Cadence.Domain.Commanding.Entities.QueuedCommand do
  @type t :: %__MODULE__{
    id: String.t(),
    organization_id: String.t(),
    mission_id: String.t(),
    target_id: String.t(),
    command_name: String.t(),
    parameters: map(),
    status: QueueStatus.t(),
    sequence_number: non_neg_integer(),
    priority: non_neg_integer(),
    queued_at: DateTime.t(),
    executed_at: DateTime.t() | nil,
    completed_at: DateTime.t() | nil
  }
end

# lib/cadence/domain/commanding/value_objects/queue_status.ex
defmodule Cadence.Domain.Commanding.ValueObjects.QueueStatus do
  @type t :: :pending | :executing | :completed | :failed | :cancelled
end
```

### 4.2 Alarms Domain (Hexagonal Enhancement)

**Current State:** Partially migrated. Has domain entities but runtime still mixed.

**Focus Areas:**

1. **AlarmManager** - Move to `lib/cadence/runtime/alarms/`
2. **RuleCache** - Already ETS-based, verify no DB calls in evaluation path
3. **Event broadcasting** - Ensure alarm status uses PubSub, not DB writes

### 4.3 Procedures Domain

**Current State:** Has domain entities, application services. Runtime engine exists.

**Focus Areas:**

1. **ExecutionCoordinator** - Verify entity injection pattern
2. **Procedure definitions** - Cache in ETS for runtime access
3. **Step execution** - No DB calls during execution hot path

---

## Phase 7: Dashboard LiveView Integration

### 5.1 Real-Time Status via PubSub

**Current:** Dashboard may poll database for status updates.

**Target:** Subscribe to PubSub topics for real-time updates.

**Topics to Subscribe:**

| Topic | Events |
|-------|--------|
| `interface:{id}:status` | `:connected`, `:disconnected`, `:error` |
| `mission:{id}:telemetry` | Telemetry updates (for CVT display) |
| `mission:{id}:commands` | Command status changes |
| `mission:{id}:alarms` | Alarm triggers, acknowledgments |
| `mission:{id}:procedures` | Procedure execution status |

**LiveView Pattern:**

```elixir
defmodule CadenceWeb.MissionDashboardLive do
  use CadenceWeb, :live_view

  def mount(%{"mission_id" => mission_id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to all relevant topics
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:interface_status")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:commands")
    end

    # Initial load from database (Control Plane)
    interfaces = InterfaceQueries.list_for_mission(mission_id)

    {:ok, assign(socket, interfaces: interfaces, mission_id: mission_id)}
  end

  # Real-time updates via PubSub (Data Plane events)
  def handle_info({:interface_status_changed, interface_id, status}, socket) do
    # Update local state, no DB call
    interfaces = update_interface_status(socket.assigns.interfaces, interface_id, status)
    {:noreply, assign(socket, interfaces: interfaces)}
  end
end
```

---

## Phase 8: Config Versioning & Cache Invalidation

### 6.1 Problem Statement

From Open Questions in architecture doc:
> How do we handle stale config in ETS when DB is updated directly (migration, manual fix)?

### 6.2 Solution: Config Version Registry

**Concept:** Each config type has a version number stored in ETS. When config is updated, version increments. Consumers check version before using cached data.

```elixir
defmodule Cadence.Config.VersionRegistry do
  @moduledoc """
  Tracks configuration versions for cache invalidation.
  """

  @table :config_versions

  def init do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
  end

  def get_version(config_type, scope_id) do
    case :ets.lookup(@table, {config_type, scope_id}) do
      [{_, version}] -> version
      [] -> 0
    end
  end

  def increment_version(config_type, scope_id) do
    :ets.update_counter(@table, {config_type, scope_id}, 1, {{config_type, scope_id}, 0})
  end

  # Called from application services after any config write
  def invalidate(config_type, scope_id) do
    new_version = increment_version(config_type, scope_id)

    # Broadcast invalidation event
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "config:#{config_type}:#{scope_id}",
      {:config_invalidated, config_type, scope_id, new_version}
    )
  end
end
```

### 6.3 Cache Consumer Pattern

```elixir
defmodule Cadence.Commands.CommandCache do
  # Store version with cached data
  def init(mission_id) do
    version = VersionRegistry.get_version(:commands, mission_id)
    # ... load data ...
    {:ok, %{version: version, ...}}
  end

  def handle_info({:config_invalidated, :commands, mission_id, new_version}, state) do
    if new_version > state.version do
      # Reload from database
      reload_cache(state)
    else
      {:noreply, state}
    end
  end
end
```

---

## Phase 9: Multi-Node Considerations

### 7.1 Problem Statement

> How does config propagation work in a clustered deployment?

### 7.2 Solution: Distributed PubSub

Phoenix.PubSub already supports distributed nodes via `Phoenix.PubSub.PG2` adapter. Ensure:

1. **All nodes in cluster** - Use libcluster or DNS-based clustering
2. **PubSub adapter** - Configure for distribution:

```elixir
# config/runtime.exs
config :cadence, Cadence.PubSub,
  name: Cadence.PubSub,
  adapter: Phoenix.PubSub.PG2  # Distributed by default
```

3. **ETS is local** - Each node maintains its own ETS cache
4. **Config updates broadcast cluster-wide** - PubSub handles this automatically

### 7.3 Considerations

- **Eventual consistency** - Brief window where nodes have different config versions
- **Startup ordering** - New nodes should load from DB, not rely on PubSub catchup
- **Node partition** - Nodes should continue operating with local cache during partition

---

## Phase 10: Recovery Patterns

### 8.1 Problem Statement

> When a GenServer crashes and restarts, where does it get config from?

### 8.2 Solution: Supervisor-Injected Config

**Pattern:** Supervisors hold config, inject into children on restart.

```elixir
defmodule Cadence.Interfaces.InterfaceSupervisor do
  use GenServer

  # Supervisor holds the config
  defstruct [:mission_id, :interfaces]

  def init(mission_id) do
    # Load once at supervisor start
    interfaces = InterfaceQueries.list_for_mission(mission_id, preload_protocols: true)

    # Start children with config
    children = Enum.map(interfaces, &child_spec/1)

    # Subscribe to config changes
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:interface_config")

    {:ok, %__MODULE__{mission_id: mission_id, interfaces: interfaces},
     {:continue, {:start_children, children}}}
  end

  # When child crashes, supervisor still has config
  def handle_info({:EXIT, pid, _reason}, state) do
    # Find which interface this was
    interface = find_interface_for_pid(pid, state)

    # Restart with same config (no DB call)
    restart_interface(interface)

    {:noreply, state}
  end

  # Config updates refresh supervisor's cache
  def handle_info({:interface_updated, interface}, state) do
    interfaces = update_interface(state.interfaces, interface)

    # Restart child with new config
    restart_interface(interface)

    {:noreply, %{state | interfaces: interfaces}}
  end
end
```

### 8.3 Alternative: ETS-Based Config Store

For very frequent restarts, read from shared ETS instead of supervisor state:

```elixir
defmodule Cadence.Config.InterfaceConfigStore do
  @table :interface_configs

  def get(interface_id) do
    case :ets.lookup(@table, interface_id) do
      [{^interface_id, config}] -> {:ok, config}
      [] -> {:error, :not_found}
    end
  end

  def put(interface_id, config) do
    :ets.insert(@table, {interface_id, config})
  end
end

# GenServer reads from ETS on restart
def init(interface_id) do
  {:ok, config} = InterfaceConfigStore.get(interface_id)
  # ... continue with config
end
```

---

## Additional Architectural Patterns

### Form Schema Pattern (Embedded Schemas for LiveView)

LiveView forms should use `embedded_schema` instead of Ecto schemas to decouple the web layer from the database. This is part of the hexagonal architecture - the web layer should not depend on persistence details.

**Pattern:** `lib/cadence_web/schemas/{domain}_form.ex`

**Example:** `CadenceWeb.Schemas.MissionForm`

```elixir
defmodule CadenceWeb.Schemas.MissionForm do
  @moduledoc """
  Embedded schema for mission creation/editing forms.
  Decouples LiveView forms from Ecto persistence layer.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:active, :inactive]
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:name, :description, :status])
    |> validate_required([:name])
  end

  def to_domain_params(%__MODULE__{} = form) do
    Map.from_struct(form)
  end
end
```

**Benefits:**
- LiveView forms don't depend on Ecto schemas
- Validation logic can differ from persistence constraints
- Forms can have UI-specific fields (confirmations, multi-step wizard state)
- Testable without database

**Domains needing form schemas:**
| Domain | Current | Target |
|--------|---------|--------|
| Missions | ✅ `MissionForm` exists | Done |
| Interfaces | ❌ Uses Ecto schema | Create `InterfaceForm` |
| Targets | ❌ Uses Ecto schema | Create `TargetForm` |
| Procedures | ❌ Uses Ecto schema | Create `ProcedureForm` |
| Alarms | ❌ Uses Ecto schema | Create `AlarmRuleForm` |
| Commands | ❌ Uses Ecto schema | Create `CommandForm` |

---

## Technical Debt & Code Quality

### Credo Violations

The codebase has accumulated technical debt that should be addressed incrementally. Per `CLAUDE.md`, each session should aim to clean up at least one violation.

**Current Status (from `mix credo --strict`):**

| Category | Count | Priority |
|----------|-------|----------|
| TODO comments | ~16 | Low - track separately |
| Nested modules could be aliased | ~41 | Medium - readability |
| Large numbers without underscores | ~3 | Low - style |
| **Total** | ~60 | |

**Key Technical Debt Items:**

1. **`lib/cadence/telemetry/conversions.ex`** (lines 221-245)
   - `apply_db_conversion/2` doesn't handle calibrator-based conversion maps
   - This is a bug, not just technical debt

2. **`lib/cadence/commands/verification_runner.ex`**
   - TODO: Implement full MatchCriteria support

3. **Nested module aliases** (41 occurrences)
   - Example: `Cadence.Domain.Interfaces.Entities.Interface` should be aliased
   - Fix opportunistically when touching related code

**Burndown Strategy:**
- Address 1-2 violations per PR when touching related code
- Don't create PRs solely for credo fixes (avoid churn)
- Track progress in this section

---

## Implementation Priority

### Immediate (Phase 3 - Mission Database & Target Caching)

1. **Create `MetaCommandCache`** (Phase 3.1)
   - New file: `lib/cadence/commands/meta_command_cache.ex`
   - ETS cache for MetaCommand with arguments, verifiers, interlocks preloaded
   - Add to MissionInstance children
   - Eliminates DB call per command dispatch

2. **Update `TargetDispatcher`** (Phase 3.1)
   - Use `MetaCommandCache.get_by_name()` instead of `Commands.get_meta_command()`
   - Remove `Repo.preload(command, :verifiers)` at line 974

3. **Add target identifier → UUID cache** (Phase 3.5)
   - Extend PacketIdentifier to cache `{:target_id, identifier} → uuid`
   - Add `PacketIdentifier.get_target_id/2` function
   - Update RuleCache to use cached lookup instead of DB call

4. **Refactor `TargetPipelineSupervisor`** (Phase 3.3)
   - Load targets with definition_sets at supervisor start
   - Inject entities into TargetDispatcher and TargetQueue
   - Subscribe to target changes for hot reload

5. **Add cache warming** (Phase 3.2)
   - Add `warm/2` functions to Limits.Cache and DerivedItems.Cache
   - Call from MissionInstance after children start

### Short-Term (Phase 5-7)

6. **Command queue optimization** (Phase 5)
   - Local queue state in GenServer
   - Async DB persistence
   - Immediate dispatch from memory

7. **Dashboard PubSub integration** (Phase 7)
   - LiveViews subscribe to status topics
   - Real-time updates without polling

8. **Config versioning** (Phase 8)
   - VersionRegistry for cache invalidation
   - Direct DB update detection

### Medium-Term (Phase 9-10)

9. **Multi-node testing** (Phase 9)
   - Verify PubSub distribution works
   - Test cache consistency across nodes

10. **Recovery testing** (Phase 10)
    - Verify supervisor-injected config pattern
    - Test GenServer crash/restart scenarios

### Long-Term

11. **Metrics and observability** - Track cache hit rates, DB call counts
12. **Performance benchmarking** - Measure latency improvements
13. **Remaining hexagonal migrations** - Commanding, Alarms cleanup
14. **Fix `apply_db_conversion`** - Handle calibrator-based conversion maps (bug)

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| DB calls per telemetry packet | 0 (already cached) | 0 |
| DB calls per command dispatch | 2+ (command + verifier) | 0 |
| DB calls per alarm rule filter | 1 (target lookup) | 0 |
| DB calls at mission start | Many (lazy loading) | Consolidated (eager) |
| Dashboard refresh method | Polling / Page load | PubSub real-time |
| Config update latency | Manual restart | < 100ms (PubSub) |
| Recovery time after crash | DB load (100-500ms) | ETS/Supervisor (< 10ms) |

---

## Changelog

| Date | Change |
|------|--------|
| 2024-12-22 | Initial migration plan created |
| 2024-12-22 | Added Phase 3: Mission Database Loading Strategy |
| 2024-12-22 | Added MetaCommandCache design for O(1) command lookup |
| 2024-12-22 | Added consolidated Data Plane cache architecture diagram |
| 2024-12-22 | Added TargetPipelineSupervisor entity injection pattern |
| 2024-12-22 | Added cache warming strategy for Limits and DerivedItems |
| 2024-12-22 | Added Phase 4: Alarms, Automations & Procedures Runtime audit |
| 2024-12-22 | Added Phase 3.5: Target Identifier Cache for RuleCache fix |
| 2024-12-22 | Documented `apply_db_conversion` bug (calibrator maps not handled) |
| 2024-12-22 | Renumbered phases to accommodate new sections |
| 2024-12-23 | Added Hexagonal Architecture Migration Status table |
| 2024-12-23 | Added Runtime Folder Structure section (current vs target state) |
| 2024-12-23 | Added Form Schema Pattern documentation (embedded_schema for LiveView) |
| 2024-12-23 | Added Technical Debt & Code Quality section (Credo violations tracking) |
