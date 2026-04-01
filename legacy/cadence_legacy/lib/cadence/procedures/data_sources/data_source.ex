defmodule Cadence.Procedures.DataSources.DataSource do
  @moduledoc """
  Behaviour for data sources that provide values to procedure blocks.

  Data sources abstract how procedure blocks access telemetry, computed values,
  and external data. Each source type implements this behaviour to provide
  a consistent interface for reading and subscribing to data.

  ## Supported Source Types

  - `:cvt` - Current Value Table (real-time telemetry)
  - `:tsdb` - Time Series Database (historical data)
  - `:api` - External HTTP API
  - `:manual` - Operator-provided values
  - `:computed` - Derived values

  ## Core Operations

  - `get_value/3` - Read current value for an item path
  - `evaluate_condition/2` - Evaluate boolean expression against data
  - `subscribe/3` - Subscribe to live value changes
  - `unsubscribe/1` - Cancel subscription
  - `list_items/2` - List available items for autocomplete
  - `validate_item/2` - Check if item path is valid

  ## Optional Operations

  - `get_history/5` - Query historical values (TSDB only)

  ## Context

  All operations receive a context map with execution information:

      %{
        execution_id: "...",
        mission_id: "...",
        target_id: "...",
        organization_id: "...",
        parameters: %{...}
      }

  ## Reading Structure

  Readings returned by `get_value/3` have this structure:

      %{
        value: 25.4,
        timestamp: ~U[2025-12-26 15:30:00Z],
        quality: :good,
        source: %{
          source_type: :cvt,
          source_id: "mission-uuid",
          raw_path: "SC-001.EPS.battery_voltage"
        }
      }

  ## Quality Values

  - `:good` - Fresh, valid data
  - `:stale` - Data older than threshold
  - `:bad` - Invalid or error data
  - `:unknown` - Quality cannot be determined
  - `:simulated` - Simulated/test data
  - `:manual` - Manually entered data
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
          at: DateTime.t(),
          timeout: pos_integer(),
          default: value()
        ]

  @type condition_result :: %{
          result: boolean(),
          evaluated_at: DateTime.t(),
          bindings: %{String.t() => reading()}
        }

  @type subscription :: %{
          id: String.t(),
          item_path: item_path(),
          source_type: atom(),
          pid: pid()
        }

  @type item_metadata :: %{
          path: String.t(),
          name: String.t(),
          type: atom(),
          unit: String.t() | nil,
          description: String.t() | nil
        }

  @type context :: %{
          optional(:execution_id) => String.t(),
          :mission_id => String.t(),
          optional(:target_id) => String.t(),
          optional(:organization_id) => String.t(),
          optional(:parameters) => map()
        }

  # ─────────────────────────────────────────────────────────────
  # Core Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the current value of a data item.

  The path is already resolved (target prefix applied).

  ## Parameters

  - `item_path` - The resolved item path (e.g., "SC-001.EPS.voltage")
  - `context` - Execution context with mission_id, etc.
  - `opts` - Query options:
    - `:at` - Point in time for TSDB queries
    - `:timeout` - Max wait time in milliseconds
    - `:default` - Value to return if not found

  ## Returns

  - `{:ok, reading}` - Successfully retrieved value
  - `{:error, :not_found}` - Item doesn't exist
  - `{:error, reason}` - Other error
  """
  @callback get_value(item_path(), context(), query_opts()) ::
              {:ok, reading()} | {:error, term()}

  @doc """
  Evaluate a condition expression against current data.

  Parses the expression to find telemetry references, fetches all values,
  and evaluates the boolean expression.

  ## Parameters

  - `expression` - Boolean expression (e.g., "EPS.voltage >= 24.0")
  - `context` - Execution context

  ## Returns

  - `{:ok, condition_result}` - Expression evaluated
  - `{:error, {:missing_values, paths}}` - Required values not found
  - `{:error, {:parse_error, message}}` - Invalid expression
  """
  @callback evaluate_condition(expression :: String.t(), context()) ::
              {:ok, condition_result()} | {:error, term()}

  @doc """
  Subscribe to value changes for real-time updates.

  The callback process will receive messages of the form:
  `{:data_update, item_path, reading}`

  ## Parameters

  - `item_path` - The item to subscribe to
  - `context` - Execution context
  - `callback` - PID to receive update messages

  ## Returns

  - `{:ok, subscription}` - Successfully subscribed
  - `{:error, :not_supported}` - Source doesn't support subscriptions
  - `{:error, reason}` - Other error
  """
  @callback subscribe(item_path(), context(), callback :: pid()) ::
              {:ok, subscription()} | {:error, term()}

  @doc """
  Unsubscribe from value changes.
  """
  @callback unsubscribe(subscription()) :: :ok

  # ─────────────────────────────────────────────────────────────
  # Metadata Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  List available data items for autocomplete/validation.

  ## Parameters

  - `context` - Execution context
  - `filter` - Optional filter criteria:
    - `:prefix` - Filter by path prefix
    - `:type` - Filter by item type
    - `:limit` - Max items to return

  ## Returns

  - `{:ok, [item_metadata]}` - List of matching items
  - `{:error, reason}` - Query failed
  """
  @callback list_items(context(), filter :: map()) ::
              {:ok, [item_metadata()]} | {:error, term()}

  @doc """
  Check if an item path is valid (exists in dictionary).

  ## Returns

  - `:ok` - Item exists
  - `{:error, :not_found}` - Item doesn't exist
  - `{:error, :invalid_format}` - Path format is invalid
  """
  @callback validate_item(item_path(), context()) ::
              :ok | {:error, :not_found | :invalid_format | term()}

  # ─────────────────────────────────────────────────────────────
  # Optional: Historical Queries
  # ─────────────────────────────────────────────────────────────

  @doc """
  Query historical values over a time range.

  Only implemented by sources that support history (TSDB).

  ## Parameters

  - `item_path` - The item to query
  - `start_time` - Range start
  - `end_time` - Range end
  - `context` - Execution context
  - `opts` - Query options:
    - `:resolution` - Time bucket size
    - `:limit` - Max points to return
    - `:aggregation` - How to aggregate (avg, min, max, etc.)

  ## Returns

  - `{:ok, [reading]}` - List of historical readings
  - `{:error, :not_supported}` - Source doesn't support history
  """
  @callback get_history(
              item_path(),
              start_time :: DateTime.t(),
              end_time :: DateTime.t(),
              context(),
              opts :: keyword()
            ) ::
              {:ok, [reading()]} | {:error, :not_supported | term()}

  @optional_callbacks [get_history: 5]
end
