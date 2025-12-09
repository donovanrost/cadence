defmodule Cadence.Procedures.Runtime.CadenceApi do
  @moduledoc """
  The Cadence API exposed to Lua procedures.

  This module provides the bridge between Lua scripts and Cadence functionality.
  Functions are registered in the Luerl VM under the `cadence` namespace.

  ## Available Functions

  ### Telemetry
  - `cadence.telemetry.get(item_name)` - Get current value of a telemetry item
  - `cadence.telemetry.wait_for(item_name, operator, value, timeout_ms)` - Wait for condition

  ### Commands
  - `cadence.command.send(name, args)` - Send a command
  - `cadence.command.send_and_verify(name, args, timeout_ms)` - Send and wait for verification

  ### Flow Control
  - `cadence.wait(milliseconds)` - Wait for a duration
  - `cadence.log(message)` - Log a message
  - `cadence.log(level, message)` - Log with specific level
  - `cadence.checkpoint(name)` - Mark a checkpoint for resume

  ### Context
  - `cadence.params` - Table of runtime parameters
  - `cadence.mission_id` - Current mission ID
  - `cadence.target_id` - Current target ID (if target-scoped)
  """

  require Logger

  alias Cadence.Commands.Dispatcher, as: CommandDispatcher
  alias Cadence.Telemetry.CurrentValueTable

  @type context :: %{
          mission_id: String.t(),
          organization_id: String.t(),
          target_id: String.t() | nil,
          execution_id: String.t(),
          execution_pid: pid(),
          params: map()
        }

  @doc """
  Installs the Cadence API into a Luerl state.

  Returns the updated Luerl state with `cadence.*` functions available.
  """
  @spec install(term(), context()) :: term()
  def install(lua_state, context) do
    lua_state
    |> create_cadence_namespace()
    |> install_telemetry_api(context)
    |> install_command_api(context)
    |> install_flow_api(context)
    |> install_context(context)
  end

  # Create the cadence namespace table and sub-tables
  defp create_cadence_namespace(lua_state) do
    # Create nested table structure: cadence.telemetry, cadence.command
    lua_code = """
    cadence = {
      telemetry = {},
      command = {},
      params = {}
    }
    """

    case :luerl.do(lua_code, lua_state) do
      {:ok, _, new_state} -> new_state
      {:error, reason, _state} -> raise "Failed to create cadence namespace: #{inspect(reason)}"
    end
  end

  # ============================================================================
  # Telemetry API
  # ============================================================================

  defp install_telemetry_api(lua_state, context) do
    get_fn = fn [item_name], state ->
      result = telemetry_get(context, to_string(item_name))
      {[result], state}
    end

    wait_for_fn = fn args, state ->
      [item_name, operator, value, timeout_ms] = normalize_args(args, 4)

      result =
        telemetry_wait_for(
          context,
          to_string(item_name),
          to_string(operator),
          value,
          trunc(timeout_ms || 30000)
        )

      {[result], state}
    end

    lua_state
    |> set_table_keys([:cadence, :telemetry, :get], get_fn)
    |> set_table_keys([:cadence, :telemetry, :wait_for], wait_for_fn)
  end

  defp telemetry_get(context, item_name) do
    # Item name format: "PACKET.item" or just "item"
    {packet_name, item} = parse_item_name(item_name)

    case CurrentValueTable.get(context.mission_id, context.target_id, packet_name, item) do
      {:ok, %{value: value}} -> value
      {:error, :not_found} -> nil
    end
  end

  defp telemetry_wait_for(context, item_name, operator, expected_value, timeout_ms) do
    # Notify execution process we're waiting
    send(context.execution_pid, {:waiting_for_telemetry, item_name, operator, expected_value})

    deadline = System.monotonic_time(:millisecond) + timeout_ms

    wait_loop(context, item_name, operator, expected_value, deadline)
  end

  defp wait_loop(context, item_name, operator, expected_value, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      false
    else
      current_value = telemetry_get(context, item_name)

      if evaluate_condition(current_value, operator, expected_value) do
        true
      else
        # Poll interval - check every 100ms
        Process.sleep(min(100, remaining))
        wait_loop(context, item_name, operator, expected_value, deadline)
      end
    end
  end

  defp evaluate_condition(nil, _operator, _expected), do: false

  defp evaluate_condition(actual, "<", expected) when is_number(actual) and is_number(expected),
    do: actual < expected

  defp evaluate_condition(actual, "<=", expected) when is_number(actual) and is_number(expected),
    do: actual <= expected

  defp evaluate_condition(actual, ">", expected) when is_number(actual) and is_number(expected),
    do: actual > expected

  defp evaluate_condition(actual, ">=", expected) when is_number(actual) and is_number(expected),
    do: actual >= expected

  defp evaluate_condition(actual, "==", expected), do: actual == expected
  defp evaluate_condition(actual, "!=", expected), do: actual != expected
  defp evaluate_condition(_actual, _operator, _expected), do: false

  # ============================================================================
  # Command API
  # ============================================================================

  defp install_command_api(lua_state, context) do
    send_fn = fn args, state ->
      [name, lua_args] = normalize_args(args, 2)
      args_map = lua_table_to_map(lua_args)
      result = command_send(context, to_string(name), args_map)
      {[result], state}
    end

    send_and_verify_fn = fn args, state ->
      [name, lua_args, timeout_ms] = normalize_args(args, 3)
      args_map = lua_table_to_map(lua_args)

      result =
        command_send_and_verify(context, to_string(name), args_map, trunc(timeout_ms || 5000))

      {[result], state}
    end

    lua_state
    |> set_table_keys([:cadence, :command, :send], send_fn)
    |> set_table_keys([:cadence, :command, :send_and_verify], send_and_verify_fn)
  end

  defp command_send(context, command_name, args) do
    allow_hazardous = Map.get(context, :allow_hazardous_commands, false)

    if allow_hazardous do
      Logger.warning(
        "Procedure #{context.execution_id} executing command #{command_name} with hazardous bypass enabled"
      )
    end

    opts = [
      target: context.target_id,
      skip_hazardous_check: allow_hazardous
    ]

    case CommandDispatcher.dispatch(context.mission_id, command_name, args, opts) do
      {:ok, command_log_id} ->
        send(context.execution_pid, {:command_sent, command_name, command_log_id})
        true

      {:error, reason} ->
        send(context.execution_pid, {:command_failed, command_name, reason})
        false

      {:error, reason, details} ->
        send(context.execution_pid, {:command_failed, command_name, {reason, details}})
        false
    end
  end

  defp command_send_and_verify(context, command_name, args, timeout_ms) do
    # For now, just send and wait - verification is handled by the Dispatcher
    case command_send(context, command_name, args) do
      true ->
        # Simple wait for verification
        # TODO: Integrate with Dispatcher's verification tracking
        Process.sleep(timeout_ms)
        true

      false ->
        false
    end
  end

  # ============================================================================
  # Flow Control API
  # ============================================================================

  defp install_flow_api(lua_state, context) do
    wait_fn = fn [milliseconds], state ->
      flow_wait(context, trunc(milliseconds))
      {[], state}
    end

    log_fn = fn args, state ->
      case args do
        [level, message] ->
          flow_log(context, to_string(level), to_string(message))

        [message] ->
          flow_log(context, "info", to_string(message))

        _ ->
          :ok
      end

      {[], state}
    end

    checkpoint_fn = fn [name], state ->
      flow_checkpoint(context, to_string(name))
      {[], state}
    end

    abort_fn = fn args, state ->
      message = if args == [], do: "Procedure aborted", else: to_string(hd(args))
      flow_abort(context, message)
      # This should interrupt execution
      {[], state}
    end

    lua_state
    |> set_table_keys([:cadence, :wait], wait_fn)
    |> set_table_keys([:cadence, :log], log_fn)
    |> set_table_keys([:cadence, :checkpoint], checkpoint_fn)
    |> set_table_keys([:cadence, :abort], abort_fn)
  end

  defp flow_wait(context, milliseconds) do
    send(context.execution_pid, {:waiting, milliseconds})

    # Break into smaller chunks to allow for pause/abort checks
    chunk_size = 100
    chunks = div(milliseconds, chunk_size)
    remainder = rem(milliseconds, chunk_size)

    # Use reduce_while instead of throw for control flow
    aborted =
      Enum.reduce_while(1..max(chunks, 1), false, fn _, _acc ->
        Process.sleep(chunk_size)
        # Check for abort signal
        receive do
          :abort -> {:halt, true}
        after
          0 -> {:cont, false}
        end
      end)

    # Only sleep remainder if not aborted
    if not aborted and remainder > 0, do: Process.sleep(remainder)

    # Return whether we were aborted (caller can check if needed)
    not aborted
  end

  defp flow_log(context, level, message) do
    send(context.execution_pid, {:log, String.to_atom(level), message})
  end

  defp flow_checkpoint(context, name) do
    send(context.execution_pid, {:checkpoint, name})
  end

  defp flow_abort(context, message) do
    # Signal the execution process that abort was requested
    # The execution process will handle the actual abort logic
    send(context.execution_pid, {:abort_requested, message})

    # Return a marker value that indicates abort was requested
    # The Lua code can check this if needed, but typically the
    # execution process will terminate the Lua VM externally
    :aborted
  end

  # ============================================================================
  # Context Installation
  # ============================================================================

  defp install_context(lua_state, context) do
    params_table = map_to_lua_table(context.params)

    lua_state
    |> set_table_keys([:cadence, :params], params_table)
    |> set_table_keys([:cadence, :mission_id], context.mission_id)
    |> set_table_keys([:cadence, :target_id], context.target_id)
    |> set_table_keys([:cadence, :execution_id], context.execution_id)
  end

  # ============================================================================
  # Luerl Helpers
  # ============================================================================

  # Wrapper for luerl's set_table_keys_dec which automatically encodes values
  # This properly handles Elixir functions by wrapping them in #erl_func{}
  # Signature: set_table_keys_dec(DecodedKeys, DecodedVal, State) -> {ok, State} | {lua_error, ...}
  defp set_table_keys(lua_state, keys, value) do
    case :luerl.set_table_keys_dec(keys, value, lua_state) do
      {:ok, new_state} -> new_state
      {:lua_error, error, _state} -> raise "Luerl error: #{inspect(error)}"
    end
  end

  # ============================================================================
  # Data Conversion Helpers
  # ============================================================================

  defp parse_item_name(item_name) do
    case String.split(item_name, ".", parts: 2) do
      [packet, item] -> {packet, item}
      [item] -> {"", item}
    end
  end

  defp normalize_args(args, expected_count) do
    padded = args ++ List.duplicate(nil, expected_count)
    Enum.take(padded, expected_count)
  end

  defp lua_table_to_map(nil), do: %{}

  defp lua_table_to_map(table) when is_list(table) do
    table
    |> Enum.filter(fn {k, _v} -> is_binary(k) or is_atom(k) end)
    |> Enum.map(fn {k, v} -> {to_string(k), lua_value_to_elixir(v)} end)
    |> Map.new()
  end

  defp lua_table_to_map(_), do: %{}

  defp lua_value_to_elixir(value) when is_list(value), do: lua_table_to_map(value)
  defp lua_value_to_elixir(value), do: value

  defp map_to_lua_table(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {to_string(k), elixir_to_lua_value(v)} end)
  end

  defp map_to_lua_table(_), do: []

  defp elixir_to_lua_value(value) when is_map(value), do: map_to_lua_table(value)
  defp elixir_to_lua_value(value) when is_list(value), do: Enum.map(value, &elixir_to_lua_value/1)
  defp elixir_to_lua_value(value), do: value
end
