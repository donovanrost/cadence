defmodule Cadence.Procedures.Primitives do
  @moduledoc """
  Shared primitive operations for procedure execution.

  This module provides atomic operations used by both the DAG executor and the V2
  operator-paced executor. These primitives handle:

  - Command execution via the command queue (priority-based)
  - Telemetry access via CVT
  - Condition evaluation via ConditionEvaluator
  - Value resolution (templates, params, vars, telemetry references)
  - Wait operations with progress callbacks

  ## Context

  Most functions require a context map with:

      %{
        mission_id: String.t(),
        target_id: String.t(),
        organization_id: String.t(),   # optional
        params: map(),                  # procedure parameters
        vars: map(),                    # step variables
        trigger: map(),                 # trigger context (optional)
        user_id: String.t(),            # optional, for command audit
        allow_hazardous_commands: boolean()  # optional, default false
      }

  ## Progress Callbacks

  Wait operations accept an optional progress callback:

      fn(name :: String.t(), progress :: map()) -> :ok

  Progress maps vary by operation type but always include `:type`.
  """

  require Logger

  alias Cadence.Commands
  alias Cadence.Procedures.ConditionEvaluator
  alias Cadence.Procedures.InputReferences
  alias Cadence.Runtime.Telemetry.CurrentValueTable, as: CVT

  @typedoc """
  Execution context containing mission, target, and runtime data.

  Required keys:
    - `:mission_id` - Mission identifier
    - `:target_id` - Target identifier

  Optional keys:
    - `:organization_id` - Organization identifier
    - `:params` - Procedure parameters
    - `:vars` - Step variables
    - `:trigger` - Trigger context
    - `:user_id` - User ID for audit
    - `:allow_hazardous_commands` - Bypass hazardous command checks
  """
  @type context :: map()

  @type progress_callback :: (String.t(), map() -> :ok) | nil

  # ============================================================================
  # Command Execution
  # ============================================================================

  @doc """
  Enqueues a command to a target via the command queue.

  Uses `Commands.enqueue/4` to add commands to the priority-based command queue
  instead of dispatching directly. This allows operators to specify command priority
  and enables proper queue management.

  ## Options

    * `:skip_hazardous_check` - bypass hazardous command confirmation (default: from context)
    * `:user_id` - user ID for audit trail (default: from context)
    * `:priority` - command priority 0-5 (default: 3, normal priority)
      - 0: Emergency
      - 1: Critical
      - 2: High
      - 3: Normal (default)
      - 4: Low
      - 5: Background

  ## Returns

    * `{:ok, queue_entry_id}` - command was enqueued successfully
    * `{:error, reason}` - command failed to enqueue

  ## Examples

      iex> send_command("ENABLE_HEATER", %{zone: 1}, context)
      {:ok, "entry-123"}

      iex> send_command("SET_MODE", %{mode: 1}, context, priority: 1)
      {:ok, "entry-456"}

      iex> send_command("INVALID_CMD", %{}, context)
      {:error, :unknown_command}
  """
  @spec send_command(String.t(), map(), context(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_command(name, args, context, opts \\ []) do
    mission_id = context[:mission_id]
    target_id = context[:target_id]
    user_id = opts[:user_id] || context[:user_id]
    priority = opts[:priority] || context[:command_priority] || 3
    allow_hazardous = opts[:skip_hazardous_check] || context[:allow_hazardous_commands] || false

    if allow_hazardous do
      Logger.warning(
        "Executing command #{name} with hazardous bypass enabled",
        mission_id: mission_id,
        target_id: target_id,
        command: name
      )
    end

    enqueue_opts = [
      target: target_id,
      user_id: user_id,
      priority: priority,
      skip_hazardous_check: allow_hazardous
    ]

    case Commands.enqueue(mission_id, name, args, enqueue_opts) do
      {:ok, queue_entry} -> {:ok, queue_entry.id}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, {:noproc, _} ->
      {:error, "Command queue not running. Is the mission started?"}

    :exit, reason ->
      {:error, "Command queue unavailable: #{inspect(reason)}"}
  end

  # ============================================================================
  # Telemetry Access
  # ============================================================================

  @doc """
  Gets a telemetry value from the Current Value Table (CVT).

  ## Item Path Formats

    * `"PACKET.item"` - uses target_id from context
    * `"TARGET.PACKET.item"` - explicit target

  ## Returns

    * `{:ok, value}` - value found
    * `{:error, :not_found}` - item not in CVT
    * `{:error, :invalid_item_format}` - malformed item path

  ## Examples

      iex> get_telemetry("HK.battery_voltage", context)
      {:ok, 28.5}

      iex> get_telemetry("SAT1.HK.battery_voltage", context)
      {:ok, 28.5}
  """
  @spec get_telemetry(String.t(), context(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_telemetry(item_path, context, _opts \\ []) do
    mission_id = context[:mission_id]
    target_id = context[:target_id]

    parts = String.split(item_path, ".")

    {effective_target, packet_name, item_name} =
      case parts do
        [target, packet, item_name] ->
          {target, packet, item_name}

        [packet, item_name] ->
          {target_id, packet, item_name}

        _ ->
          {target_id, nil, nil}
      end

    if packet_name && item_name do
      case CVT.get(mission_id, effective_target, packet_name, item_name) do
        {:ok, value} -> {:ok, value}
        {:error, _} -> {:error, :not_found}
      end
    else
      {:error, :invalid_item_format}
    end
  rescue
    _ -> {:error, :cvt_error}
  end

  # ============================================================================
  # Condition Evaluation
  # ============================================================================

  @doc """
  Evaluates a condition string against the current context.

  Delegates to `Cadence.Procedures.ConditionEvaluator`.

  ## Condition Syntax

    * `"true"` / `"false"` - literals
    * `"telemetry.PACKET.item >= 50"` - telemetry comparison
    * `"params.threshold > 0"` - parameter comparison
    * `"vars.step_name.result == true"` - variable comparison

  ## Returns

    * `{:ok, true}` - condition is true
    * `{:ok, false}` - condition is false
    * `{:error, reason}` - evaluation failed

  ## Examples

      iex> check_condition("telemetry.HK.voltage >= 24", context)
      {:ok, true}

      iex> check_condition("params.mode == 'safe'", context)
      {:ok, false}
  """
  @spec check_condition(String.t(), context()) :: {:ok, boolean()} | {:error, term()}
  def check_condition(condition, context) do
    ConditionEvaluator.evaluate(condition, context)
  end

  # ============================================================================
  # Wait Operations
  # ============================================================================

  @doc """
  Waits for a specified duration with optional progress callbacks.

  ## Options

    * `:on_progress` - callback function `fn(name, progress_map) -> :ok`
    * `:name` - identifier for progress callbacks (default: "wait")
    * `:update_interval` - progress update interval in ms (default: 500)

  Progress callback receives:

      %{
        type: :wait,
        total_ms: integer(),
        elapsed_ms: integer(),
        remaining_ms: integer()
      }

  ## Examples

      iex> wait(5000, on_progress: &IO.inspect/2)
      :ok
  """
  @spec wait(pos_integer(), keyword()) :: :ok
  def wait(duration_ms, opts \\ []) do
    progress_callback = opts[:on_progress]
    name = opts[:name] || "wait"
    update_interval = opts[:update_interval] || 500

    if duration_ms > 1000 and is_function(progress_callback, 2) do
      wait_with_progress(name, duration_ms, progress_callback, update_interval)
    else
      Process.sleep(duration_ms)
    end

    :ok
  end

  @doc """
  Waits for a telemetry condition to be satisfied.

  Polls the CVT at regular intervals until the condition is met or timeout.

  ## Options

    * `:on_progress` - callback for progress updates
    * `:name` - identifier for progress callbacks
    * `:poll_interval` - how often to check condition in ms (default: 100)
    * `:progress_interval` - how often to emit progress in ms (default: 500)

  Progress callback receives:

      %{
        type: :wait_for,
        item: String.t(),
        operator: String.t(),
        expected: term(),
        actual: term() | nil,
        remaining_ms: integer()
      }

  ## Returns

    * `{:ok, actual_value}` - condition was satisfied
    * `{:error, :timeout}` - timed out waiting

  ## Examples

      iex> wait_for("HK.mode", "==", "SAFE", 30_000, context)
      {:ok, "SAFE"}

      iex> wait_for("HK.voltage", ">=", 28, 5_000, context)
      {:error, :timeout}
  """
  @spec wait_for(String.t(), String.t(), term(), pos_integer(), context(), keyword()) ::
          {:ok, term()} | {:error, :timeout}
  def wait_for(item_path, operator, expected, timeout_ms, context, opts \\ []) do
    progress_callback = opts[:on_progress]
    name = opts[:name] || "wait_for"
    poll_interval = opts[:poll_interval] || 100
    progress_interval = opts[:progress_interval] || 500

    deadline = System.monotonic_time(:millisecond) + timeout_ms

    do_wait_for(%{
      name: name,
      item_path: item_path,
      operator: operator,
      expected: expected,
      deadline: deadline,
      poll_interval: poll_interval,
      progress_interval: progress_interval,
      context: context,
      progress_callback: progress_callback,
      last_progress_at: 0
    })
  end

  # ============================================================================
  # Value Resolution
  # ============================================================================

  @doc """
  Resolves a value that may contain references to params, vars, telemetry, or templates.

  ## Reference Types

    * `"params.name"` - parameter value
    * `"vars.step.field"` - variable value
    * `"telemetry.PACKET.item"` - current telemetry value
    * `"trigger.field"` - trigger context value
    * `"${input.name}"` - input reference (for DAG procedures)
    * `"{{expr}}"` - template interpolation

  Non-string values are returned as-is.

  ## Examples

      iex> resolve_value("params.target_temp", %{params: %{"target_temp" => 45}})
      45

      iex> resolve_value("telemetry.HK.voltage", context)
      28.5

      iex> resolve_value(123, context)
      123
  """
  @spec resolve_value(term(), context()) :: term()
  def resolve_value(value, context)

  def resolve_value(value, context) when is_binary(value) do
    if InputReferences.has_references?(value) do
      resolve_input_reference(value, context)
    else
      resolve_prefixed_value(value, context)
    end
  end

  def resolve_value(value, _context), do: value

  defp resolve_input_reference(value, context) do
    params = context[:params] || %{}

    case InputReferences.interpolate(value, params) do
      {:ok, interpolated} ->
        if interpolated == value, do: value, else: resolve_value(interpolated, context)

      {:error, :missing_input, name} ->
        Logger.warning("Missing input reference: ${input.#{name}}")
        value
    end
  end

  @prefix_resolvers [
    {"params.", :params},
    {"trigger.", :trigger},
    {"vars.", :vars},
    {"target.", :target},
    {"telemetry.", :telemetry}
  ]

  defp resolve_prefixed_value(value, context) do
    case find_prefix_resolver(value) do
      {:ok, resolver, rest} -> resolve_by_prefix(resolver, rest, context)
      :template -> resolve_template(value, context)
      :literal -> value
    end
  end

  defp find_prefix_resolver(value) do
    Enum.find_value(@prefix_resolvers, fn {prefix, resolver} ->
      if String.starts_with?(value, prefix) do
        {:ok, resolver, String.replace_prefix(value, prefix, "")}
      end
    end) || if(String.contains?(value, "{{"), do: :template, else: :literal)
  end

  defp resolve_by_prefix(:params, rest, context), do: resolve_params_value(rest, context)
  defp resolve_by_prefix(:trigger, rest, context), do: resolve_trigger_value(rest, context)
  defp resolve_by_prefix(:vars, rest, context), do: resolve_vars_value(rest, context)
  defp resolve_by_prefix(:target, rest, context), do: resolve_target_value(rest, context)
  defp resolve_by_prefix(:telemetry, rest, context), do: resolve_telemetry_value(rest, context)

  defp resolve_params_value(param_name, context) do
    get_in(context, [:params, param_name]) || get_in(context, [:params, String.to_atom(param_name)])
  end

  defp resolve_trigger_value(path, context) do
    get_nested(context[:trigger] || %{}, String.split(path, "."))
  end

  defp resolve_vars_value(var_path, context) do
    get_in(context, [:vars, var_path])
  end

  defp resolve_target_value(param_name, context) do
    get_in(context, [:params, param_name]) || get_in(context, [:params, String.to_atom(param_name)])
  end

  defp resolve_telemetry_value(item, context) do
    case get_telemetry(item, context) do
      {:ok, val} -> val
      _ -> nil
    end
  end

  @doc """
  Resolves all values in a map or list.

  ## Examples

      iex> resolve_values(%{a: "params.x", b: 123}, context)
      %{a: 42, b: 123}
  """
  @spec resolve_values(term(), context()) :: term()
  def resolve_values(map, context) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, resolve_value(v, context)} end)
  end

  def resolve_values(list, context) when is_list(list) do
    Enum.map(list, fn v -> resolve_value(v, context) end)
  end

  def resolve_values(other, _context), do: other

  @doc """
  Resolves a duration value, ensuring an integer result.

  Handles input references and string-to-integer conversion.

  ## Examples

      iex> resolve_duration(5000, context)
      5000

      iex> resolve_duration("params.delay", %{params: %{"delay" => 1000}})
      1000
  """
  @spec resolve_duration(term(), context()) :: non_neg_integer()
  def resolve_duration(value, _context) when is_integer(value), do: value

  def resolve_duration(value, context) when is_binary(value) do
    resolved = resolve_value(value, context)

    case resolved do
      v when is_integer(v) ->
        v

      v when is_binary(v) ->
        case Integer.parse(v) do
          {int, _} -> int
          :error -> 0
        end

      _ ->
        0
    end
  end

  def resolve_duration(_, _), do: 0

  # ============================================================================
  # Comparison Operations
  # ============================================================================

  @doc """
  Compares two values using the specified operator.

  Used by wait_for and condition evaluation.

  ## Supported Operators

    * `"=="` - equal
    * `"!="` - not equal
    * `">="` - greater than or equal (numeric)
    * `"<="` - less than or equal (numeric)
    * `">"` - greater than (numeric)
    * `"<"` - less than (numeric)

  ## Examples

      iex> compare_values(28.5, ">=", 24)
      true

      iex> compare_values("SAFE", "==", "SAFE")
      true
  """
  @spec compare_values(term(), String.t(), term()) :: boolean()
  def compare_values(actual, ">=", expected) when is_number(actual) and is_number(expected),
    do: actual >= expected

  def compare_values(actual, "<=", expected) when is_number(actual) and is_number(expected),
    do: actual <= expected

  def compare_values(actual, ">", expected) when is_number(actual) and is_number(expected),
    do: actual > expected

  def compare_values(actual, "<", expected) when is_number(actual) and is_number(expected),
    do: actual < expected

  def compare_values(actual, "==", expected), do: actual == expected
  def compare_values(actual, "!=", expected), do: actual != expected
  def compare_values(_, _, _), do: false

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp wait_with_progress(name, duration, progress_callback, update_interval) do
    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + duration

    do_wait_with_progress(name, end_time, update_interval, progress_callback, duration)
  end

  defp do_wait_with_progress(name, end_time, update_interval, progress_callback, total_duration) do
    now = System.monotonic_time(:millisecond)
    remaining = max(0, end_time - now)

    if remaining <= 0 do
      :ok
    else
      elapsed = total_duration - remaining

      progress_callback.(name, %{
        type: :wait,
        total_ms: total_duration,
        elapsed_ms: elapsed,
        remaining_ms: remaining
      })

      sleep_time = min(update_interval, remaining)
      Process.sleep(sleep_time)

      do_wait_with_progress(name, end_time, update_interval, progress_callback, total_duration)
    end
  end

  defp do_wait_for(state) do
    now = System.monotonic_time(:millisecond)

    if now >= state.deadline do
      {:error, :timeout}
    else
      case get_telemetry(state.item_path, state.context) do
        {:ok, actual} ->
          handle_wait_for_value(state, actual, now)

        {:error, _} ->
          handle_wait_for_value(state, nil, now)
      end
    end
  end

  defp handle_wait_for_value(state, actual, now) do
    if compare_values(actual, state.operator, state.expected) do
      {:ok, actual}
    else
      state = maybe_emit_wait_for_progress(state, actual, now)
      Process.sleep(state.poll_interval)
      do_wait_for(state)
    end
  end

  defp maybe_emit_wait_for_progress(state, actual, now) do
    if is_function(state.progress_callback, 2) and now - state.last_progress_at >= state.progress_interval do
      remaining_ms = max(0, state.deadline - now)

      state.progress_callback.(state.name, %{
        type: :wait_for,
        item: state.item_path,
        operator: state.operator,
        expected: state.expected,
        actual: actual,
        remaining_ms: remaining_ms
      })

      %{state | last_progress_at: now}
    else
      state
    end
  end

  defp resolve_template(template, context) do
    Regex.replace(~r/\{\{(.+?)\}\}/, template, fn _, expr ->
      value = resolve_value(String.trim(expr), context)
      to_string(value || "")
    end)
  end

  defp get_nested(map, []), do: map
  defp get_nested(nil, _), do: nil

  defp get_nested(map, [key | rest]) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))
    get_nested(value, rest)
  end

  defp get_nested(_, _), do: nil
end
