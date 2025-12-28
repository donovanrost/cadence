# Epsilon3-Like Procedures Data Model

> Clean-slate design for Cadence procedures with Epsilon3-inspired UX

## Design Principles

1. **Blocks are first-class** - Everything is a block, steps contain blocks
2. **Execution is operator-paced by default** - Manual signoff is the norm, automation is opt-in
3. **Rich audit trail** - Every action is a recordable
4. **Single model** - No legacy/normalized split
5. **Target-agnostic procedures** - Procedures are templates; data sources bound at runtime

---

## Data Source Abstraction

### The Problem

Procedures need to work across multiple targets in a constellation. A "Battery Health Check" procedure should work for any spacecraft, not just one hardcoded target.

### Solution: Scoped Telemetry References

Telemetry references in blocks use a **scoped path** that gets resolved at runtime:

```
# In block content (template form)
item: "target.EPS.battery_voltage"     # Resolves via execution's target_id
item: "{{params.vehicle}}.EPS.voltage" # Explicit parameter interpolation
item: "EPS.battery_voltage"            # Unscoped = current target (shorthand)
```

### Resolution Hierarchy

When a procedure executes, telemetry paths are resolved:

1. **Explicit target prefix** - `SC-001.EPS.voltage` → direct CVT lookup
2. **`target.` prefix** - `target.EPS.voltage` → uses `execution.target_id`
3. **Parameter interpolation** - `{{params.vehicle}}.EPS.voltage` → uses runtime parameter
4. **Unscoped (default)** - `EPS.voltage` → uses `execution.target_id` if set, else mission default

### Implementation

```elixir
defmodule Cadence.Procedures.TelemetryResolver do
  @moduledoc """
  Resolves telemetry paths to actual CVT items based on execution context.
  """

  @doc """
  Resolves a telemetry path template to a concrete CVT path.

  ## Examples

      resolve("target.EPS.voltage", execution)
      # => "SC-001.EPS.voltage" (if execution.target_id points to SC-001)

      resolve("{{params.primary}}.EPS.voltage", execution)
      # => "SC-002.EPS.voltage" (if params.primary = "SC-002")

      resolve("EPS.voltage", execution)
      # => "SC-001.EPS.voltage" (uses default target)
  """
  def resolve(path, execution) do
    path
    |> interpolate_params(execution.parameters)
    |> resolve_target_prefix(execution)
    |> apply_default_target(execution)
  end

  defp interpolate_params(path, params) do
    Regex.replace(~r/\{\{params\.(\w+)\}\}/, path, fn _, key ->
      Map.get(params, key, "UNRESOLVED")
    end)
  end

  defp resolve_target_prefix("target." <> rest, execution) do
    case get_target_name(execution.target_id) do
      nil -> {:error, :no_target}
      name -> "#{name}.#{rest}"
    end
  end
  defp resolve_target_prefix(path, _), do: path

  defp apply_default_target(path, execution) do
    # If path has no target prefix and execution has a target, prepend it
    if has_target_prefix?(path) do
      path
    else
      case get_target_name(execution.target_id) do
        nil -> path  # Mission-level telemetry (no target scope)
        name -> "#{name}.#{path}"
      end
    end
  end
end
```

### CVT Implications

The CVT already supports target-scoped keys. The key insight is that **procedures are templates** and **executions bind the template to concrete targets**.

```elixir
# CVT structure (already exists)
%{
  "SC-001.EPS.battery_voltage" => %{value: 25.3, timestamp: ...},
  "SC-002.EPS.battery_voltage" => %{value: 24.8, timestamp: ...},
  "GROUND.POWER.grid_voltage" => %{value: 480.0, timestamp: ...}  # Non-target telemetry
}
```

### Multi-Target Procedures

For procedures that operate on multiple targets simultaneously (e.g., constellation-wide health check), use **target groups** or **iteration**:

```elixir
# Option 1: Multiple target parameters
parameters_schema: %{
  "primary_target" => %{type: "target", required: true},
  "backup_target" => %{type: "target", required: false}
}

# In blocks:
%{item: "{{params.primary_target}}.EPS.voltage"}
%{item: "{{params.backup_target}}.EPS.voltage"}

# Option 2: Target group with iteration (future)
parameters_schema: %{
  "target_group" => %{type: "target_group", required: true}
}
# Procedure iterates over all targets in group
```

### Data Dictionary Support

For organizations with multiple telemetry schemas (different spacecraft types, vendors), support **dictionary selection**:

```elixir
# In ProcedureVersion
field :telemetry_dictionary_id, :binary_id  # Optional: constrain to specific dictionary

# In block content
%{
  item: "target.EPS.battery_voltage",
  dictionary: "cubesat_v2"  # Optional override
}
```

This enables:
- Procedure templates that work across spacecraft families
- Validation that referenced items exist in the dictionary
- Auto-complete in the editor based on dictionary schema

---

## Data Source Architecture

### Why Abstract Data Sources?

Procedures need to read data from various sources:

| Source | Characteristics | Use Case |
|--------|----------------|----------|
| **CVT** | Real-time, in-memory, push-based | Live spacecraft telemetry |
| **TSDB** | Historical, disk-based, query-based | Trends, analysis, playback |
| **External API** | Remote, HTTP, poll-based | Ground equipment, external systems |
| **Manual Entry** | Operator-provided, form-based | Readings, observations |
| **Computed** | Derived from other sources | Aggregates, transformations |
| **Constants** | Static configuration | Limits, thresholds, calibration |

Different blocks may need different sources, and the same procedure might run against different source configurations.

### Data Source Behaviour

```elixir
defmodule Cadence.Procedures.DataSource do
  @moduledoc """
  Behaviour for data sources that provide values to procedure blocks.

  Data sources are:
  - Identified by a source_type atom (:cvt, :tsdb, :api, :manual, :computed)
  - Configured per-mission or per-execution
  - Resolved at runtime based on block configuration
  """

  @type item_path :: String.t()
  @type value :: number() | String.t() | boolean() | map() | nil

  @type reading :: %{
    value: value(),
    timestamp: DateTime.t(),
    quality: quality(),
    source: source_metadata()
  }

  @type quality :: :good | :stale | :bad | :unknown | :simulated | :manual

  @type source_metadata :: %{
    source_type: atom(),
    source_id: String.t() | nil,
    raw_path: String.t()
  }

  @type query_opts :: [
    at: DateTime.t(),           # Point-in-time query (for TSDB)
    timeout: pos_integer(),     # Max wait time in ms
    default: value()            # Value if not found
  ]

  @type condition_result :: %{
    result: boolean(),
    evaluated_at: DateTime.t(),
    bindings: %{String.t() => reading()}  # Values used in evaluation
  }

  @type subscription :: %{
    id: String.t(),
    item_path: item_path(),
    source_type: atom(),
    pid: pid()
  }

  # ─────────────────────────────────────────────────────────────
  # Core Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the current value of a data item.

  The path is already resolved (target prefix applied).
  """
  @callback get_value(item_path, context :: map(), opts :: query_opts()) ::
    {:ok, reading()} | {:error, term()}

  @doc """
  Evaluate a condition expression against current data.

  Returns the boolean result plus the bindings used.
  """
  @callback evaluate_condition(expression :: String.t(), context :: map()) ::
    {:ok, condition_result()} | {:error, term()}

  @doc """
  Subscribe to value changes for real-time updates.

  The callback will be invoked with {:data_update, item_path, reading}.
  """
  @callback subscribe(item_path, context :: map(), callback :: pid()) ::
    {:ok, subscription()} | {:error, term()}

  @doc """
  Unsubscribe from value changes.
  """
  @callback unsubscribe(subscription()) :: :ok

  # ─────────────────────────────────────────────────────────────
  # Metadata Operations (for editor/validation)
  # ─────────────────────────────────────────────────────────────

  @doc """
  List available data items for autocomplete/validation.
  """
  @callback list_items(context :: map(), filter :: map()) ::
    {:ok, [item_metadata()]} | {:error, term()}

  @doc """
  Check if an item path is valid (exists in dictionary).
  """
  @callback validate_item(item_path, context :: map()) ::
    :ok | {:error, :not_found | :invalid_format | term()}

  # ─────────────────────────────────────────────────────────────
  # Optional: Historical Queries (TSDB, not CVT)
  # ─────────────────────────────────────────────────────────────

  @doc """
  Query historical values over a time range.

  Only implemented by sources that support history (TSDB).
  """
  @callback get_history(item_path, start_time :: DateTime.t(), end_time :: DateTime.t(),
                        context :: map(), opts :: keyword()) ::
    {:ok, [reading()]} | {:error, :not_supported | term()}

  @optional_callbacks [get_history: 5]
end
```

### Data Source Registry

Multiple sources can be registered and selected per-block:

```elixir
defmodule Cadence.Procedures.DataSourceRegistry do
  @moduledoc """
  Registry of available data sources.

  Sources are registered at startup and selected at runtime
  based on block configuration or defaults.
  """

  use GenServer

  @type source_config :: %{
    module: module(),
    name: String.t(),
    source_type: atom(),
    capabilities: [atom()],  # [:realtime, :history, :subscribe, :write]
    config: map()
  }

  # ─────────────────────────────────────────────────────────────
  # Registration
  # ─────────────────────────────────────────────────────────────

  def register(source_type, module, config \\ %{}) do
    GenServer.call(__MODULE__, {:register, source_type, module, config})
  end

  def unregister(source_type) do
    GenServer.call(__MODULE__, {:unregister, source_type})
  end

  # ─────────────────────────────────────────────────────────────
  # Resolution
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the appropriate data source for a block.

  Resolution order:
  1. Explicit source in block content
  2. Default source for block type
  3. Mission-level default
  4. Global default (CVT)
  """
  def resolve(block, context) do
    source_type =
      block.content[:source] ||
      default_for_block_type(block.block_type) ||
      context[:default_data_source] ||
      :cvt

    get(source_type)
  end

  def get(source_type) do
    GenServer.call(__MODULE__, {:get, source_type})
  end

  def list do
    GenServer.call(__MODULE__, :list)
  end

  # ─────────────────────────────────────────────────────────────
  # Defaults by block type
  # ─────────────────────────────────────────────────────────────

  defp default_for_block_type(:telemetry_value), do: :cvt
  defp default_for_block_type(:telemetry_check), do: :cvt
  defp default_for_block_type(:telemetry_wait), do: :cvt
  defp default_for_block_type(:telemetry_trend), do: :tsdb  # Future
  defp default_for_block_type(_), do: nil
end
```

### CVT Data Source (Primary Implementation)

```elixir
defmodule Cadence.Procedures.DataSources.CVT do
  @moduledoc """
  Data source backed by the Current Value Table.

  This is the primary real-time data source for spacecraft telemetry.
  """

  @behaviour Cadence.Procedures.DataSource

  alias Cadence.Telemetry.CVT, as: CvtStore
  alias Cadence.Procedures.TelemetryResolver

  @impl true
  def get_value(item_path, context, opts \\ []) do
    resolved_path = TelemetryResolver.resolve(item_path, context)
    timeout = Keyword.get(opts, :timeout, 5_000)
    default = Keyword.get(opts, :default, nil)

    case CvtStore.get(context.mission_id, resolved_path) do
      nil when not is_nil(default) ->
        {:ok, %{
          value: default,
          timestamp: DateTime.utc_now(),
          quality: :unknown,
          source: %{source_type: :cvt, source_id: nil, raw_path: resolved_path}
        }}

      nil ->
        {:error, :not_found}

      %{value: value, timestamp: ts, stale: stale} ->
        {:ok, %{
          value: value,
          timestamp: ts,
          quality: if(stale, do: :stale, else: :good),
          source: %{source_type: :cvt, source_id: context.mission_id, raw_path: resolved_path}
        }}
    end
  end

  @impl true
  def evaluate_condition(expression, context) do
    # Parse expression to find all telemetry references
    items = extract_telemetry_items(expression)

    # Fetch all values
    bindings =
      items
      |> Enum.map(fn item ->
        case get_value(item, context) do
          {:ok, reading} -> {item, reading}
          {:error, _} -> {item, nil}
        end
      end)
      |> Map.new()

    # Check for missing values
    missing = Enum.filter(bindings, fn {_, v} -> is_nil(v) end)
    if length(missing) > 0 do
      {:error, {:missing_values, Enum.map(missing, &elem(&1, 0))}}
    else
      # Evaluate expression with bindings
      case do_evaluate(expression, bindings) do
        {:ok, result} ->
          {:ok, %{
            result: result,
            evaluated_at: DateTime.utc_now(),
            bindings: bindings
          }}
        {:error, _} = err ->
          err
      end
    end
  end

  @impl true
  def subscribe(item_path, context, callback_pid) do
    resolved_path = TelemetryResolver.resolve(item_path, context)
    topic = "cvt:#{context.mission_id}:#{resolved_path}"

    # Subscribe to PubSub
    Phoenix.PubSub.subscribe(Cadence.PubSub, topic)

    # Return subscription handle
    {:ok, %{
      id: Ecto.UUID.generate(),
      item_path: item_path,
      source_type: :cvt,
      pid: callback_pid,
      topic: topic
    }}
  end

  @impl true
  def unsubscribe(%{topic: topic}) do
    Phoenix.PubSub.unsubscribe(Cadence.PubSub, topic)
    :ok
  end

  @impl true
  def list_items(context, filter \\ %{}) do
    # Delegate to telemetry dictionary
    Cadence.Telemetry.Dictionary.list_items(
      context.mission_id,
      filter
    )
  end

  @impl true
  def validate_item(item_path, context) do
    resolved_path = TelemetryResolver.resolve(item_path, context)

    case Cadence.Telemetry.Dictionary.get_item(context.mission_id, resolved_path) do
      nil -> {:error, :not_found}
      _item -> :ok
    end
  end

  # CVT doesn't support history
  # get_history/5 not implemented - will return {:error, :not_supported}
end
```

### TSDB Data Source (Future Implementation)

```elixir
defmodule Cadence.Procedures.DataSources.TSDB do
  @moduledoc """
  Data source backed by a Time Series Database.

  Provides historical queries and trend analysis.
  """

  @behaviour Cadence.Procedures.DataSource

  # Current value = most recent point
  @impl true
  def get_value(item_path, context, opts) do
    # Query TSDB for latest point
    case query_latest(item_path, context) do
      {:ok, point} ->
        {:ok, %{
          value: point.value,
          timestamp: point.timestamp,
          quality: determine_quality(point, opts),
          source: %{source_type: :tsdb, source_id: context.tsdb_id, raw_path: item_path}
        }}
      {:error, _} = err ->
        err
    end
  end

  # TSDB supports history
  @impl true
  def get_history(item_path, start_time, end_time, context, opts) do
    resolution = Keyword.get(opts, :resolution, :raw)
    limit = Keyword.get(opts, :limit, 10_000)

    query_range(item_path, start_time, end_time, resolution, limit, context)
  end

  @impl true
  def subscribe(item_path, context, callback_pid) do
    # TSDB subscription via polling or change streams
    {:ok, pid} = Cadence.Procedures.DataSources.TSDBPoller.start_link(
      item_path: item_path,
      context: context,
      callback: callback_pid,
      interval_ms: 1_000
    )

    {:ok, %{
      id: Ecto.UUID.generate(),
      item_path: item_path,
      source_type: :tsdb,
      pid: pid
    }}
  end

  # ... other callbacks
end
```

### Block Content with Source Selection

Blocks can specify which data source to use:

```elixir
# Default: uses CVT (most common)
%{
  block_type: :telemetry_value,
  content: %{
    item: "target.EPS.battery_voltage",
    format: "%.2f V"
  }
}

# Explicit CVT
%{
  block_type: :telemetry_value,
  content: %{
    source: :cvt,
    item: "target.EPS.battery_voltage",
    format: "%.2f V"
  }
}

# From TSDB (for historical procedures / playback)
%{
  block_type: :telemetry_value,
  content: %{
    source: :tsdb,
    item: "target.EPS.battery_voltage",
    at: "{{params.playback_time}}",  # Point-in-time query
    format: "%.2f V"
  }
}

# Trend block (TSDB only)
%{
  block_type: :telemetry_trend,  # New block type
  content: %{
    source: :tsdb,
    item: "target.EPS.battery_voltage",
    range: "1h",  # Last hour
    resolution: "1m"  # 1-minute buckets
  }
}

# External API source
%{
  block_type: :telemetry_value,
  content: %{
    source: {:api, "ground_power"},  # Named API source
    item: "GRID.voltage",
    format: "%.1f V"
  }
}

# Manual entry fallback
%{
  block_type: :telemetry_value,
  content: %{
    source: :manual,  # Operator will enter value
    item: "VISUAL.panel_deployment",
    prompt: "Observe panel deployment status"
  }
}
```

### Execution Context with Data Sources

```elixir
defmodule Cadence.Procedures.ExecutionContext do
  @moduledoc """
  Execution context carries data source configuration for a procedure run.
  """

  defstruct [
    :execution_id,
    :mission_id,
    :target_id,
    :organization_id,
    :user_id,
    :parameters,

    # Data source configuration
    :default_data_source,     # :cvt | :tsdb | etc
    :data_source_overrides,   # %{item_pattern => source_type}
    :tsdb_id,                 # TSDB connection if using TSDB
    :api_sources,             # %{name => config} for external APIs

    # Runtime state
    :subscriptions            # Active data subscriptions
  ]

  def build(execution, opts \\ []) do
    %__MODULE__{
      execution_id: execution.id,
      mission_id: execution.mission_id,
      target_id: execution.target_id,
      organization_id: execution.organization_id,
      user_id: opts[:user_id],
      parameters: execution.parameters,
      default_data_source: opts[:data_source] || :cvt,
      data_source_overrides: opts[:source_overrides] || %{},
      tsdb_id: opts[:tsdb_id],
      api_sources: opts[:api_sources] || %{},
      subscriptions: %{}
    }
  end
end
```

### Block Executor with Data Source Resolution

```elixir
defmodule Cadence.Procedures.BlockExecutor do
  alias Cadence.Procedures.DataSourceRegistry
  alias Cadence.Procedures.DataSource

  def execute_telemetry_value(block, step_exec, context) do
    # 1. Resolve which data source to use
    {:ok, source} = DataSourceRegistry.resolve(block, context)

    # 2. Resolve the item path (target substitution)
    item_path = block.content.item

    # 3. Get the value
    case source.get_value(item_path, context, build_opts(block)) do
      {:ok, reading} ->
        # 4. Save to block execution
        save_telemetry_reading(step_exec, block, reading)

      {:error, reason} ->
        handle_data_error(step_exec, block, reason)
    end
  end

  def execute_telemetry_check(block, step_exec, context) do
    {:ok, source} = DataSourceRegistry.resolve(block, context)

    case source.get_value(block.content.item, context, []) do
      {:ok, reading} ->
        # Evaluate pass criteria
        passed = evaluate_criteria(reading.value, block.content.pass_criteria)

        # Record result
        save_telemetry_check_result(step_exec, block, reading, passed)

        # Handle failure based on block config
        unless passed do
          handle_check_failure(step_exec, block, reading)
        end

      {:error, reason} ->
        handle_data_error(step_exec, block, reason)
    end
  end

  def execute_telemetry_wait(block, step_exec, context) do
    {:ok, source} = DataSourceRegistry.resolve(block, context)

    condition = block.content.condition
    timeout = block.content.timeout_seconds * 1_000
    poll_interval = (block.content[:poll_interval_seconds] || 5) * 1_000

    wait_for_condition(source, condition, context, timeout, poll_interval)
  end

  defp wait_for_condition(source, condition, context, timeout, poll_interval) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      case source.evaluate_condition(condition, context) do
        {:ok, %{result: true} = result} ->
          {:halt, {:ok, result}}

        {:ok, %{result: false}} ->
          if System.monotonic_time(:millisecond) > deadline do
            {:halt, {:error, :timeout}}
          else
            Process.sleep(poll_interval)
            :continue
          end

        {:error, _} = err ->
          {:halt, err}
      end
    end)
    |> Enum.reduce_while(nil, fn
      :continue, _ -> {:cont, nil}
      {:halt, result}, _ -> {:halt, result}
    end)
  end
end
```

### Data Source Schema (for persistent configuration)

```elixir
defmodule Cadence.Procedures.Schemas.DataSourceConfig do
  @moduledoc """
  Persistent configuration for data sources at the mission level.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "procedure_data_source_configs" do
    field :source_type, Ecto.Enum, values: [:cvt, :tsdb, :api, :manual, :computed]
    field :name, :string           # Human-readable name
    field :is_default, :boolean, default: false
    field :priority, :integer, default: 0  # For fallback ordering

    # Type-specific configuration
    field :config, :map, default: %{}
    # CVT: %{stale_threshold_ms: 30_000}
    # TSDB: %{connection_string: "...", database: "..."}
    # API: %{base_url: "...", auth: %{type: "bearer", token_env: "..."}}

    # Item path patterns this source handles
    field :path_patterns, {:array, :string}, default: ["*"]
    # e.g., ["GROUND.*"] for ground equipment API

    belongs_to :mission, Mission

    timestamps()
  end
end
```

### Reading Quality and Staleness

Unified quality model across sources:

```elixir
defmodule Cadence.Procedures.DataQuality do
  @moduledoc """
  Unified data quality assessment across sources.
  """

  @type quality :: :good | :stale | :bad | :unknown | :simulated | :manual

  @doc """
  Determine quality based on source characteristics.
  """
  def assess(reading, source_type, opts \\ []) do
    stale_threshold = Keyword.get(opts, :stale_threshold_ms, 30_000)

    age_ms = DateTime.diff(DateTime.utc_now(), reading.timestamp, :millisecond)

    cond do
      reading.quality == :bad -> :bad
      reading.quality == :simulated -> :simulated
      reading.quality == :manual -> :manual
      age_ms > stale_threshold -> :stale
      true -> :good
    end
  end

  @doc """
  Check if quality is acceptable for signoff.
  """
  def acceptable_for_signoff?(quality, strict_mode \\ false) do
    case {quality, strict_mode} do
      {:good, _} -> true
      {:stale, false} -> true  # Allow stale in non-strict mode
      {:manual, _} -> true     # Manual entries are always acceptable
      _ -> false
    end
  end
end
```

---

## Core Schema

### 1. Procedure (container - mostly unchanged)

```elixir
defmodule Cadence.Procedures.Procedure do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "procedures" do
    field :name, :string
    field :description, :string
    field :tags, {:array, :string}, default: []

    belongs_to :organization, Organization
    belongs_to :mission, Mission  # nil = org-wide template
    belongs_to :current_version, ProcedureVersion

    timestamps()
  end
end
```

### 2. ProcedureVersion (immutable snapshot)

```elixir
defmodule Cadence.Procedures.ProcedureVersion do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "procedure_versions" do
    field :version_number, :integer
    field :status, Ecto.Enum, values: [:draft, :in_review, :approved, :deprecated]

    # Version-level settings
    field :execution_mode, Ecto.Enum, values: [:manual, :assisted, :automatic], default: :manual
    # manual = operator drives everything
    # assisted = auto-advance through non-signoff steps, pause at signoffs
    # automatic = full DAG execution (current behavior)

    field :allow_hazardous_commands, :boolean, default: false
    field :allow_suggested_edits, :boolean, default: true

    # Parameters (collected at start)
    field :parameters_schema, :map, default: %{}

    # Approval tracking
    field :submitted_by_id, :binary_id
    field :submitted_at, :utc_datetime_usec
    field :approved_by_id, :binary_id
    field :approved_at, :utc_datetime_usec
    field :rejected_by_id, :binary_id
    field :rejected_at, :utc_datetime_usec
    field :rejection_reason, :string

    belongs_to :procedure, Procedure
    has_many :sections, ProcedureSection
    has_many :approvals, ProcedureApproval

    timestamps()
  end
end
```

### 3. ProcedureSection

```elixir
defmodule Cadence.Procedures.ProcedureSection do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "procedure_sections" do
    field :name, :string
    field :description, :string
    field :position, :integer
    field :collapsed_by_default, :boolean, default: false

    belongs_to :procedure_version, ProcedureVersion
    has_many :steps, ProcedureStep

    timestamps()
  end
end
```

### 4. ProcedureStep

```elixir
defmodule Cadence.Procedures.ProcedureStep do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "procedure_steps" do
    field :name, :string           # Unique within version (for dependencies)
    field :title, :string          # Display title
    field :position, :integer

    # Signoff requirements
    field :requires_signoff, :boolean, default: true
    field :required_roles, {:array, :string}, default: []  # Empty = any role
    field :signoff_logic, Ecto.Enum, values: [:any, :all], default: :any

    # Dependencies
    field :depends_on, {:array, :string}, default: []  # Step names
    field :dependency_logic, Ecto.Enum, values: [:all, :any], default: :all

    # Conditional execution
    field :condition, :string  # Expression - skip if false
    field :on_fail, Ecto.Enum, values: [:abort, :continue, :pause], default: :abort

    # Duration estimate (for planning)
    field :estimated_duration_seconds, :integer

    belongs_to :section, ProcedureSection
    has_many :blocks, ProcedureBlock

    timestamps()
  end
end
```

### 5. ProcedureBlock (the heart of the system)

```elixir
defmodule Cadence.Procedures.ProcedureBlock do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  @block_types [
    # Content blocks (display only)
    :text,              # Rich text / markdown
    :note,              # Info callout
    :caution,           # Yellow warning
    :warning,           # Red critical warning
    :reference,         # Link to document/external resource

    # Data blocks (collect input)
    :text_input,        # Free text entry
    :number_input,      # Numeric with validation
    :select_input,      # Dropdown / radio
    :checkbox_input,    # Boolean or multi-select
    :timestamp_input,   # Date/time capture
    :duration_input,    # Time duration
    :attachment_input,  # File upload
    :signature_input,   # Operator signature capture

    # Telemetry blocks (live data)
    :telemetry_value,   # Display current value
    :telemetry_check,   # Auto-validate against criteria
    :telemetry_wait,    # Wait for condition

    # Command blocks
    :command,           # Send a command
    :command_sequence,  # Send multiple commands in order

    # Reference blocks
    :input_reference,   # Display value from earlier input
    :variable_display,  # Display procedure variable

    # Subprocess
    :procedure_call     # Execute child procedure
  ]

  schema "procedure_blocks" do
    field :block_type, Ecto.Enum, values: @block_types
    field :position, :integer
    field :name, :string          # For referencing (input blocks)
    field :label, :string         # Display label
    field :required, :boolean, default: false  # For input blocks

    # Block content (type-specific)
    field :content, :map, default: %{}

    belongs_to :step, ProcedureStep

    timestamps()
  end
end
```

**Block Content Examples:**

```elixir
# :text
%{markdown: "## Safety Precautions\n\nEnsure all personnel are clear..."}

# :caution
%{text: "High voltage present - verify isolation before proceeding"}

# :text_input
%{
  placeholder: "Enter observed value",
  max_length: 500
}

# :number_input
%{
  min: 0,
  max: 100,
  step: 0.1,
  unit: "V",
  pass_criteria: ">= 24.0"  # Optional validation
}

# :select_input
%{
  options: [
    %{value: "nominal", label: "Nominal"},
    %{value: "degraded", label: "Degraded"},
    %{value: "failed", label: "Failed"}
  ],
  allow_other: false
}

# :telemetry_value
# Display live telemetry - path is resolved at runtime
%{
  item: "target.EPS.battery_voltage",   # "target." prefix = execution's target
  format: "%.2f V",
  stale_threshold_seconds: 30
}

# Alternative: explicit parameter binding
%{
  item: "{{params.vehicle}}.EPS.battery_voltage",
  format: "%.2f V"
}

# :telemetry_check
# Validate telemetry against criteria
%{
  item: "target.EPS.battery_voltage",   # Resolved to "SC-001.EPS.battery_voltage"
  pass_criteria: ">= 24.0 and <= 32.0",
  fail_action: :block_signoff,  # :warn, :block_signoff, :abort_procedure
  auto_evaluate: true
}

# :telemetry_wait
# Wait for condition on target's telemetry
%{
  condition: "target.THERMAL.temp_sensor_1 < 45.0",  # Target-scoped
  timeout_seconds: 300,
  poll_interval_seconds: 5
}

# Multi-target comparison
%{
  condition: "{{params.primary}}.THERMAL.temp < {{params.backup}}.THERMAL.temp",
  timeout_seconds: 60
}

# :command
# Commands always specify target (explicit or via execution context)
%{
  command_name: "SET_MODE",
  target: :execution_target,  # Use execution.target_id (most common)
  arguments: %{mode: 1},
  require_confirmation: true,
  verify_after: %{
    item: "target.STATUS.current_mode",  # Verify on same target
    expected: 1,
    timeout_seconds: 10
  }
}

# Alternative: parameter-based target
%{
  command_name: "POWER_ON",
  target: "{{params.secondary_vehicle}}",  # Different target
  arguments: %{}
}

# :procedure_call
# Child procedure inherits target context or gets explicit binding
%{
  procedure_id: "...",
  target: :inherit,  # Use parent's target (default)
  parameters: %{threshold: 25.0},
  wait_for_completion: true
}

# Call same procedure for different target
%{
  procedure_id: "battery_check",
  target: "{{params.backup_vehicle}}",
  parameters: %{},
  wait_for_completion: true
}

# :input_reference
%{
  source_step: "initial_readings",
  source_block: "voltage_reading"
}
```

---

## Execution Schema

### 6. ProcedureExecution

```elixir
defmodule Cadence.Procedures.ProcedureExecution do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "procedure_executions" do
    field :status, Ecto.Enum,
      values: [:pending, :running, :paused, :blocked, :completed, :failed, :cancelled]

    # Trigger info
    field :triggered_by, Ecto.Enum, values: [:manual, :schedule, :event, :procedure]
    field :trigger_context, :map, default: %{}

    # Parameters (validated at start)
    field :parameters, :map, default: %{}

    # Timing
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    # Error tracking
    field :error_message, :string
    field :error_step_id, :binary_id

    belongs_to :procedure, Procedure
    belongs_to :procedure_version, ProcedureVersion
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :target, Target  # Optional
    belongs_to :started_by, User
    belongs_to :parent_execution, ProcedureExecution  # For subprocess calls

    has_many :step_executions, StepExecution
    has_many :comments, ExecutionComment
    has_many :suggested_edits, SuggestedEdit

    timestamps()
  end
end
```

### 7. StepExecution

```elixir
defmodule Cadence.Procedures.StepExecution do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "step_executions" do
    field :status, Ecto.Enum,
      values: [:pending, :active, :awaiting_signoff, :completed, :skipped, :failed, :blocked]

    # Timing
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    # Result
    field :result, Ecto.Enum, values: [:pass, :fail, :skip]
    field :error_message, :string

    # Skip tracking
    field :skipped_reason, :string
    field :skipped_by_id, :binary_id

    belongs_to :procedure_execution, ProcedureExecution
    belongs_to :step, ProcedureStep

    has_many :block_executions, BlockExecution
    has_many :signoffs, StepSignoff
    has_many :comments, ExecutionComment

    timestamps()
  end
end
```

### 8. BlockExecution (captured values/results per block)

```elixir
defmodule Cadence.Procedures.BlockExecution do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "block_executions" do
    field :status, Ecto.Enum,
      values: [:pending, :in_progress, :completed, :failed, :skipped]

    # For input blocks: captured value
    field :value, :map  # Type-specific: %{text: "..."} or %{number: 25.3} etc.

    # For validation blocks: pass/fail
    field :passed, :boolean
    field :validation_message, :string

    # For command blocks: execution result
    field :command_result, :map

    # For telemetry blocks: captured reading
    field :telemetry_reading, :map  # %{value: 25.3, timestamp: ..., stale: false}

    # Timing
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :step_execution, StepExecution
    belongs_to :block, ProcedureBlock
    belongs_to :entered_by, User  # For input blocks

    timestamps()
  end
end
```

### 9. StepSignoff

```elixir
defmodule Cadence.Procedures.StepSignoff do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "step_signoffs" do
    field :role, :string
    field :note, :string

    belongs_to :step_execution, StepExecution
    belongs_to :user, User

    timestamps(updated_at: false)
  end
end
```

### 10. ExecutionComment

```elixir
defmodule Cadence.Procedures.ExecutionComment do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  @comment_types [:note, :issue, :question, :resolution]

  schema "execution_comments" do
    field :content, :string
    field :comment_type, Ecto.Enum, values: @comment_types, default: :note

    belongs_to :procedure_execution, ProcedureExecution
    belongs_to :step_execution, StepExecution  # nil = execution-level
    belongs_to :user, User

    # For threading
    belongs_to :parent_comment, ExecutionComment

    timestamps()
  end
end
```

### 11. SuggestedEdit (Redlines)

```elixir
defmodule Cadence.Procedures.SuggestedEdit do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  @edit_types [:add_step, :modify_step, :delete_step, :add_block, :modify_block, :delete_block]

  schema "suggested_edits" do
    field :edit_type, Ecto.Enum, values: @edit_types
    field :status, Ecto.Enum, values: [:pending, :accepted, :rejected], default: :pending

    # Target
    field :target_section_id, :binary_id
    field :target_step_id, :binary_id
    field :target_block_id, :binary_id
    field :target_position, :integer  # For insertions

    # The change
    field :before_snapshot, :map  # What it looked like before (for modify/delete)
    field :after_snapshot, :map   # What it should look like (for add/modify)
    field :reason, :string

    # Resolution
    field :resolved_at, :utc_datetime_usec
    field :resolution_note, :string

    belongs_to :procedure_execution, ProcedureExecution
    belongs_to :step_execution, StepExecution  # Context where edit was suggested
    belongs_to :suggested_by, User
    belongs_to :resolved_by, User

    timestamps()
  end
end
```

---

## Supporting Entities

### 12. Snippet (reusable content library)

```elixir
defmodule Cadence.Procedures.Snippet do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "procedure_snippets" do
    field :name, :string
    field :description, :string
    field :snippet_type, Ecto.Enum, values: [:step, :section, :block_group]
    field :tags, {:array, :string}, default: []
    field :content, :map  # Serialized step/section/blocks

    belongs_to :organization, Organization
    belongs_to :created_by, User

    timestamps()
  end
end
```

---

## Recordables (Execution Events)

Extend the existing Recordables system:

```elixir
# New recordable types for procedure execution
@new_recordables [
  # Step lifecycle
  StepActivated,      # Step became active (operator can work on it)
  StepSignedOff,      # Signoff captured
  StepCompleted,      # Step finished
  StepSkipped,        # Step skipped (condition or manual)
  StepFailed,         # Step failed

  # Block interactions
  BlockValueEntered,  # Input block filled
  BlockValidated,     # Telemetry check passed/failed
  CommandSent,        # Command block executed (reuse existing)
  CommandVerified,    # Command verification (reuse existing)

  # Collaboration
  CommentAdded,       # Comment posted
  SuggestedEditProposed,  # Redline created
  SuggestedEditResolved,  # Redline accepted/rejected
]
```

**Example Recordable:**

```elixir
defmodule Cadence.Recordings.Recordables.StepSignedOff do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "step_signed_offs" do
    field :step_name, :string
    field :step_title, :string
    field :role, :string
    field :signoff_count, :integer     # e.g., "2 of 3 required"
    field :signoffs_required, :integer
    field :step_result, :string        # pass/fail/skip

    timestamps(updated_at: false)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.StepSignedOff do
  def recording_type(_), do: "StepSignedOff"
  def aggregate_type(_), do: "ProcedureExecution"
  def title(r), do: "Signed off: #{r.step_title}"
  def status(_), do: "signed_off"
  def severity(_), do: nil
end
```

---

## Execution Engine

Replace the current DAG-centric executor with a step-centric one:

```elixir
defmodule Cadence.Procedures.Executor do
  @moduledoc """
  Executes procedures step-by-step with operator interaction.
  """

  # Start execution
  def start(procedure_version, params, opts) do
    with {:ok, execution} <- create_execution(procedure_version, params, opts),
         {:ok, execution} <- activate_initial_steps(execution) do
      broadcast_started(execution)
      {:ok, execution}
    end
  end

  # Activate steps whose dependencies are satisfied
  def activate_initial_steps(execution) do
    ready_steps = find_ready_steps(execution)

    Enum.each(ready_steps, fn step ->
      {:ok, step_exec} = create_step_execution(execution, step, :active)
      broadcast_step_activated(execution, step_exec)
      record_event(StepActivated, execution, step_exec)
    end)

    {:ok, reload(execution)}
  end

  # Handle block value entry
  def enter_block_value(execution, step_execution, block, value, user) do
    with :ok <- validate_step_active(step_execution),
         :ok <- validate_block_editable(block),
         {:ok, validated_value} <- validate_value(block, value),
         {:ok, block_exec} <- save_block_value(step_execution, block, validated_value, user) do

      record_event(BlockValueEntered, execution, %{
        step_name: step_execution.step.name,
        block_name: block.name,
        value_type: block.block_type
      })

      maybe_auto_evaluate_step(execution, step_execution)
      {:ok, block_exec}
    end
  end

  # Handle signoff
  def sign_off_step(execution, step_execution, user, role, note \\ nil) do
    with :ok <- validate_can_sign_off(step_execution, user, role),
         :ok <- validate_required_inputs_complete(step_execution),
         :ok <- validate_checks_passed(step_execution),
         {:ok, signoff} <- create_signoff(step_execution, user, role, note) do

      record_event(StepSignedOff, execution, %{
        step_name: step_execution.step.name,
        step_title: step_execution.step.title,
        role: role
      })

      if signoff_requirements_met?(step_execution) do
        complete_step(execution, step_execution)
      else
        {:ok, signoff}
      end
    end
  end

  # Complete step and advance
  def complete_step(execution, step_execution) do
    with {:ok, step_execution} <- mark_completed(step_execution),
         {:ok, execution} <- activate_next_steps(execution, step_execution) do

      record_event(StepCompleted, execution, %{
        step_name: step_execution.step.name,
        result: step_execution.result
      })

      if all_steps_complete?(execution) do
        complete_execution(execution)
      else
        {:ok, execution}
      end
    end
  end

  # Skip step (with authorization)
  def skip_step(execution, step_execution, user, reason) do
    with :ok <- validate_can_skip(step_execution, user) do
      {:ok, step_execution} = mark_skipped(step_execution, user, reason)

      record_event(StepSkipped, execution, %{
        step_name: step_execution.step.name,
        reason: reason
      })

      activate_next_steps(execution, step_execution)
    end
  end

  # Execute command block
  def execute_command(execution, step_execution, block, user) do
    with :ok <- validate_step_active(step_execution),
         :ok <- validate_command_authorized(execution, block, user),
         {:ok, result} <- dispatch_command(execution, block) do

      save_block_result(step_execution, block, result)
      # Command recordables already handled by commanding subsystem
      {:ok, result}
    end
  end

  # Assisted mode: auto-advance through non-signoff steps
  def run_assisted(execution) do
    case find_auto_executable_steps(execution) do
      [] ->
        {:ok, execution}  # Nothing to auto-execute

      steps ->
        Enum.reduce_while(steps, {:ok, execution}, fn step, {:ok, exec} ->
          case auto_execute_step(exec, step) do
            {:ok, exec} -> {:cont, {:ok, exec}}
            {:error, _} = err -> {:halt, err}
          end
        end)
    end
  end
end
```

---

## Migration

Single clean migration:

```elixir
defmodule Cadence.Repo.Migrations.CreateProceduresV2 do
  use Ecto.Migration

  def change do
    # Sections
    create table(:procedure_sections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :procedure_version_id, references(:procedure_versions, type: :binary_id), null: false
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, null: false
      add :collapsed_by_default, :boolean, default: false
      timestamps()
    end

    create index(:procedure_sections, [:procedure_version_id, :position])

    # Steps
    create table(:procedure_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :section_id, references(:procedure_sections, type: :binary_id), null: false
      add :name, :string, null: false
      add :title, :string
      add :position, :integer, null: false
      add :requires_signoff, :boolean, default: true
      add :required_roles, {:array, :string}, default: []
      add :signoff_logic, :string, default: "any"
      add :depends_on, {:array, :string}, default: []
      add :dependency_logic, :string, default: "all"
      add :condition, :string
      add :on_fail, :string, default: "abort"
      add :estimated_duration_seconds, :integer
      timestamps()
    end

    create unique_index(:procedure_steps, [:section_id, :name])
    create index(:procedure_steps, [:section_id, :position])

    # Blocks
    create table(:procedure_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_id, references(:procedure_steps, type: :binary_id), null: false
      add :block_type, :string, null: false
      add :position, :integer, null: false
      add :name, :string
      add :label, :string
      add :required, :boolean, default: false
      add :content, :map, default: %{}
      timestamps()
    end

    create index(:procedure_blocks, [:step_id, :position])

    # Step Executions
    create table(:step_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :procedure_execution_id, references(:procedure_executions, type: :binary_id), null: false
      add :step_id, references(:procedure_steps, type: :binary_id), null: false
      add :status, :string, default: "pending"
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :result, :string
      add :error_message, :text
      add :skipped_reason, :string
      add :skipped_by_id, references(:users, type: :binary_id)
      timestamps()
    end

    create index(:step_executions, [:procedure_execution_id])
    create unique_index(:step_executions, [:procedure_execution_id, :step_id])

    # Block Executions
    create table(:block_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_execution_id, references(:step_executions, type: :binary_id), null: false
      add :block_id, references(:procedure_blocks, type: :binary_id), null: false
      add :status, :string, default: "pending"
      add :value, :map
      add :passed, :boolean
      add :validation_message, :string
      add :command_result, :map
      add :telemetry_reading, :map
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :entered_by_id, references(:users, type: :binary_id)
      timestamps()
    end

    create index(:block_executions, [:step_execution_id])

    # Step Signoffs
    create table(:step_signoffs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_execution_id, references(:step_executions, type: :binary_id), null: false
      add :user_id, references(:users, type: :binary_id), null: false
      add :role, :string, null: false
      add :note, :text
      timestamps(updated_at: false)
    end

    create index(:step_signoffs, [:step_execution_id])
    create unique_index(:step_signoffs, [:step_execution_id, :user_id])

    # Execution Comments
    create table(:execution_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :procedure_execution_id, references(:procedure_executions, type: :binary_id), null: false
      add :step_execution_id, references(:step_executions, type: :binary_id)
      add :user_id, references(:users, type: :binary_id), null: false
      add :parent_comment_id, references(:execution_comments, type: :binary_id)
      add :content, :text, null: false
      add :comment_type, :string, default: "note"
      timestamps()
    end

    create index(:execution_comments, [:procedure_execution_id])
    create index(:execution_comments, [:step_execution_id])

    # Suggested Edits
    create table(:suggested_edits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :procedure_execution_id, references(:procedure_executions, type: :binary_id), null: false
      add :step_execution_id, references(:step_executions, type: :binary_id)
      add :suggested_by_id, references(:users, type: :binary_id), null: false
      add :resolved_by_id, references(:users, type: :binary_id)
      add :edit_type, :string, null: false
      add :status, :string, default: "pending"
      add :target_section_id, :binary_id
      add :target_step_id, :binary_id
      add :target_block_id, :binary_id
      add :target_position, :integer
      add :before_snapshot, :map
      add :after_snapshot, :map
      add :reason, :text
      add :resolved_at, :utc_datetime_usec
      add :resolution_note, :text
      timestamps()
    end

    create index(:suggested_edits, [:procedure_execution_id, :status])

    # Snippets
    create table(:procedure_snippets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :created_by_id, references(:users, type: :binary_id), null: false
      add :name, :string, null: false
      add :description, :text
      add :snippet_type, :string, null: false
      add :tags, {:array, :string}, default: []
      add :content, :map, null: false
      timestamps()
    end

    create index(:procedure_snippets, [:organization_id])

    # Update procedure_versions
    alter table(:procedure_versions) do
      add :execution_mode, :string, default: "manual"
      add :allow_suggested_edits, :boolean, default: true
    end

    # Update procedure_executions
    alter table(:procedure_executions) do
      add :parent_execution_id, references(:procedure_executions, type: :binary_id)
    end

    # New Recordables
    create table(:step_activated, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string, null: false
      add :step_title, :string
      timestamps(updated_at: false)
    end

    create table(:step_signed_offs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string, null: false
      add :step_title, :string
      add :role, :string, null: false
      add :signoff_count, :integer
      add :signoffs_required, :integer
      add :step_result, :string
      timestamps(updated_at: false)
    end

    create table(:block_value_entereds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string, null: false
      add :block_name, :string, null: false
      add :block_type, :string
      add :value_summary, :string  # Human-readable summary
      add :passed_validation, :boolean
      timestamps(updated_at: false)
    end

    create table(:comment_addeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :step_name, :string
      add :comment_type, :string
      add :content_preview, :string  # First 100 chars
      timestamps(updated_at: false)
    end

    create table(:suggested_edit_proposeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :edit_type, :string, null: false
      add :target_step_name, :string
      add :summary, :string
      timestamps(updated_at: false)
    end

    create table(:suggested_edit_resolveds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :edit_type, :string, null: false
      add :resolution, :string, null: false  # accepted/rejected
      add :target_step_name, :string
      timestamps(updated_at: false)
    end
  end
end
```

---

## Cleanup: Remove Legacy

Since this is greenfield, we can drop the old JSON-based fields:

```elixir
defmodule Cadence.Repo.Migrations.RemoveLegacyProcedureFields do
  use Ecto.Migration

  def change do
    alter table(:procedure_versions) do
      remove :source  # No more JSON DAG blob
    end

    alter table(:procedure_executions) do
      remove :completed_steps
      remove :skipped_steps
      remove :failed_steps
      remove :blocked_steps
      remove :step_results
      remove :current_step_index
      remove :checkpoint_state
      remove :error_step_index
    end
  end
end
```

---

## Summary

Without legacy concerns, the model is cleaner:

| Aspect | Before | After |
|--------|--------|-------|
| Step definition | JSON blob in `source` | Normalized `ProcedureStep` + `ProcedureBlock` |
| Step execution | Arrays of step names | `StepExecution` records |
| Input collection | Not supported | `BlockExecution.value` |
| Signoffs | Not supported | `StepSignoff` records |
| Comments | Not supported | `ExecutionComment` records |
| Redlines | Not supported | `SuggestedEdit` records |
| Execution mode | Always automatic | Manual/Assisted/Automatic |

The execution engine shifts from "run DAG automatically" to "orchestrate operator-driven steps with optional automation."
