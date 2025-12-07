defmodule Cadence.Procedures.Dag.StepExecutor do
  @moduledoc """
  Executes individual steps within a DAG procedure.

  This module adapts the step execution logic for use with the DAG executor,
  handling each step type (check, command, wait, wait_for, log, set, assert).

  ## Variable Scoping

  Variables set by steps are prefixed with the step name:
  - Step "check_a" setting "result" -> stored as "check_a.result"
  - Access via `vars.check_a.result` or `vars.result` if single dependency
  """

  require Logger

  alias Cadence.Commands.Dispatcher, as: CommandDispatcher
  alias Cadence.Procedures.ConditionEvaluator
  alias Cadence.Telemetry.CurrentValueTable, as: CVT

  @type step_name :: String.t()
  @type step_def :: map()
  @type context :: map()
  @type step_result :: {:ok, any()} | {:error, any()} | {:skip, any()}

  @doc """
  Creates a step executor function for use with the DAG executor.

  The returned function has signature `(step_name, step_def, context) -> result`.
  """
  @spec create_executor(map()) :: (step_name(), step_def(), context() -> step_result())
  def create_executor(opts \\ %{}) do
    fn step_name, step_def, context ->
      execute_step(step_name, step_def, context, opts)
    end
  end

  @doc """
  Executes a single step.

  Returns:
  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  - `{:skip, reason}` if step should be skipped
  """
  @spec execute_step(step_name(), step_def(), context(), map()) :: step_result()
  def execute_step(step_name, step_def, context, opts \\ %{})

  def execute_step(step_name, %{"type" => "check"} = step, context, _opts) do
    condition = Map.get(step, "condition", "true")

    case evaluate_condition(condition, context) do
      {:ok, true} ->
        {:ok, %{condition: condition, result: true}}

      {:ok, false} ->
        message = Map.get(step, "message", "Check failed: #{condition}")
        on_fail = Map.get(step, "on_fail", "abort")

        case on_fail do
          "skip" ->
            Logger.info("DAG step '#{step_name}': Check skipped - #{message}")
            {:skip, message}

          "warn" ->
            Logger.warning("DAG step '#{step_name}': Check warning - #{message}")
            {:ok, %{condition: condition, result: false, warning: message}}

          _ ->
            {:error, message}
        end

      {:error, reason} ->
        {:error, "Condition evaluation failed: #{inspect(reason)}"}
    end
  end

  def execute_step(step_name, %{"type" => "command"} = step, context, _opts) do
    name = Map.get(step, "name")
    args = Map.get(step, "args", %{})

    # Resolve template variables in args
    resolved_args = resolve_values(args, context)

    Logger.info("DAG step '#{step_name}': Sending command #{name} with args #{inspect(resolved_args)}")

    case send_command(name, resolved_args, context) do
      {:ok, result} ->
        {:ok, %{command: name, args: resolved_args, result: result}}

      {:error, reason} ->
        {:error, "Command '#{name}' failed: #{inspect(reason)}"}
    end
  end

  def execute_step(step_name, %{"type" => "wait"} = step, context, opts) do
    duration_raw = Map.get(step, "duration", 0)
    duration = resolve_duration(duration_raw, context)
    progress_callback = Map.get(opts, :on_progress)

    Logger.debug("DAG step '#{step_name}': Waiting #{duration}ms")

    # For short waits, just sleep. For longer waits, emit progress updates.
    if duration > 1000 and is_function(progress_callback, 2) do
      wait_with_progress(step_name, duration, progress_callback)
    else
      Process.sleep(duration)
    end

    {:ok, %{waited: duration}}
  end

  def execute_step(step_name, %{"type" => "wait_for"} = step, context, opts) do
    item = Map.get(step, "item")
    operator = Map.get(step, "operator", "==")
    value = resolve_value(Map.get(step, "value"), context)
    timeout = Map.get(step, "timeout", 30_000)
    progress_callback = Map.get(opts, :on_progress)

    Logger.debug("DAG step '#{step_name}': Waiting for #{item} #{operator} #{inspect(value)}")

    case wait_for_condition(step_name, item, operator, value, timeout, context, progress_callback) do
      {:ok, actual_value} ->
        {:ok, %{item: item, expected: value, actual: actual_value}}

      {:error, :timeout} ->
        {:error, "Timeout waiting for #{item} #{operator} #{inspect(value)}"}

      {:error, reason} ->
        {:error, "Wait failed: #{inspect(reason)}"}
    end
  end

  def execute_step(step_name, %{"type" => "log"} = step, context, _opts) do
    level_str = Map.get(step, "level", "info") || "info"
    level = safe_to_atom(level_str)
    message = resolve_template(Map.get(step, "message") || "", context)

    log_message(level, "DAG step '#{step_name}': #{message}")

    {:ok, %{level: level, message: message}}
  end

  defp safe_to_atom(str) when is_binary(str) do
    case str do
      "debug" -> :debug
      "info" -> :info
      "warn" -> :warn
      "warning" -> :warn
      "error" -> :error
      _ -> :info
    end
  end

  defp safe_to_atom(atom) when is_atom(atom), do: atom
  defp safe_to_atom(_), do: :info

  def execute_step(step_name, %{"type" => "set"} = step, context, _opts) do
    var_name = Map.get(step, "name")
    value = resolve_value(Map.get(step, "value"), context)

    # Store with step prefix for scoping
    scoped_name = "#{step_name}.#{var_name}"

    Logger.debug("DAG step '#{step_name}': Setting #{scoped_name} = #{inspect(value)}")

    # Return the variable to be stored in context
    {:ok, %{variable: scoped_name, value: value, set_var: {scoped_name, value}}}
  end

  def execute_step(step_name, %{"type" => "assert"} = step, context, _opts) do
    condition = Map.get(step, "condition", "true")
    message = Map.get(step, "message", "Assertion failed: #{condition}")

    case evaluate_condition(condition, context) do
      {:ok, true} ->
        {:ok, %{condition: condition, result: true}}

      {:ok, false} ->
        Logger.error("DAG step '#{step_name}': ASSERTION FAILED - #{message}")
        {:error, message}

      {:error, reason} ->
        {:error, "Assertion evaluation failed: #{inspect(reason)}"}
    end
  end

  def execute_step(step_name, %{"type" => type}, _context, _opts) do
    Logger.warning("DAG step '#{step_name}': Unknown step type '#{type}'")
    {:error, "Unknown step type: #{type}"}
  end

  def execute_step(step_name, step, _context, _opts) do
    Logger.warning("DAG step '#{step_name}': Invalid step definition: #{inspect(step)}")
    {:error, "Invalid step definition"}
  end

  # ============================================================================
  # Condition Evaluation
  # ============================================================================

  defp evaluate_condition(condition, context) do
    # Delegate to unified condition evaluator
    # This ensures consistent behavior and explicit failure on invalid conditions
    ConditionEvaluator.evaluate(condition, context)
  end

  # ============================================================================
  # Telemetry Access
  # ============================================================================

  defp get_telemetry_value(item, context) do
    mission_id = context[:mission_id]
    target_id = context[:target_id]

    # Item format: "PACKET.item" or "TARGET.PACKET.item"
    parts = String.split(item, ".")

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

  # Wait with periodic progress updates
  defp wait_with_progress(step_name, duration, progress_callback) do
    # Update every 500ms
    update_interval = 500
    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + duration

    do_wait_with_progress(step_name, end_time, update_interval, progress_callback, duration)
  end

  defp do_wait_with_progress(step_name, end_time, update_interval, progress_callback, total_duration) do
    now = System.monotonic_time(:millisecond)
    remaining = max(0, end_time - now)

    if remaining <= 0 do
      :ok
    else
      # Emit progress
      elapsed = total_duration - remaining
      progress_callback.(step_name, %{
        type: :wait,
        total_ms: total_duration,
        elapsed_ms: elapsed,
        remaining_ms: remaining
      })

      # Sleep for update_interval or remaining time, whichever is smaller
      sleep_time = min(update_interval, remaining)
      Process.sleep(sleep_time)

      do_wait_with_progress(step_name, end_time, update_interval, progress_callback, total_duration)
    end
  end

  defp wait_for_condition(step_name, item, operator, expected, timeout, context, progress_callback) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_interval = 100
    # Emit progress every 500ms to avoid flooding
    progress_interval = 500

    do_wait_for(step_name, item, operator, expected, deadline, poll_interval, progress_interval, context, progress_callback, 0)
  end

  defp do_wait_for(step_name, item, operator, expected, deadline, poll_interval, progress_interval, context, progress_callback, last_progress_at) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {:error, :timeout}
    else
      case get_telemetry_value(item, context) do
        {:ok, actual} ->
          if compare_for_wait(actual, operator, expected) do
            {:ok, actual}
          else
            # Emit progress if callback provided and enough time has passed
            last_progress_at =
              if is_function(progress_callback, 2) and (now - last_progress_at) >= progress_interval do
                remaining_ms = max(0, deadline - now)
                progress_callback.(step_name, %{
                  type: :wait_for,
                  item: item,
                  operator: operator,
                  expected: expected,
                  actual: actual,
                  remaining_ms: remaining_ms
                })
                now
              else
                last_progress_at
              end

            Process.sleep(poll_interval)
            do_wait_for(step_name, item, operator, expected, deadline, poll_interval, progress_interval, context, progress_callback, last_progress_at)
          end

        {:error, _} ->
          # Emit progress even when value not available
          last_progress_at =
            if is_function(progress_callback, 2) and (now - last_progress_at) >= progress_interval do
              remaining_ms = max(0, deadline - now)
              progress_callback.(step_name, %{
                type: :wait_for,
                item: item,
                operator: operator,
                expected: expected,
                actual: nil,
                remaining_ms: remaining_ms
              })
              now
            else
              last_progress_at
            end

          Process.sleep(poll_interval)
          do_wait_for(step_name, item, operator, expected, deadline, poll_interval, progress_interval, context, progress_callback, last_progress_at)
      end
    end
  end

  # Simple comparison for wait_for conditions
  defp compare_for_wait(actual, ">=", expected) when is_number(actual) and is_number(expected),
    do: actual >= expected
  defp compare_for_wait(actual, "<=", expected) when is_number(actual) and is_number(expected),
    do: actual <= expected
  defp compare_for_wait(actual, ">", expected) when is_number(actual) and is_number(expected),
    do: actual > expected
  defp compare_for_wait(actual, "<", expected) when is_number(actual) and is_number(expected),
    do: actual < expected
  defp compare_for_wait(actual, "==", expected), do: actual == expected
  defp compare_for_wait(actual, "!=", expected), do: actual != expected
  defp compare_for_wait(_, _, _), do: false

  # ============================================================================
  # Command Execution
  # ============================================================================

  defp send_command(name, args, context) do
    mission_id = context[:mission_id]
    target_id = context[:target_id]
    user_id = context[:user_id]
    allow_hazardous = context[:allow_hazardous_commands] || false

    if allow_hazardous do
      Logger.warning(
        "DAG step executing command #{name} with hazardous bypass enabled",
        execution_id: context[:execution_id],
        command: name
      )
    end

    opts = [target_id: target_id, user_id: user_id, skip_hazardous_check: allow_hazardous]

    case CommandDispatcher.dispatch(mission_id, name, args, opts) do
      {:ok, _command_log_id} -> {:ok, :sent}
      {:error, reason} -> {:error, reason}
      {:error, reason, _details} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ============================================================================
  # Value Resolution
  # ============================================================================

  defp resolve_values(map, context) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, resolve_value(v, context)} end)
  end

  defp resolve_values(list, context) when is_list(list) do
    Enum.map(list, fn v -> resolve_value(v, context) end)
  end

  defp resolve_values(other, _context), do: other

  defp resolve_value(value, context) when is_binary(value) do
    alias Cadence.Procedures.InputReferences

    cond do
      # Handle ${input.name} syntax - interpolate input references first
      InputReferences.has_references?(value) ->
        params = context[:params] || %{}
        case InputReferences.interpolate(value, params) do
          {:ok, interpolated} ->
            # The result may still need further resolution (e.g., if it became a params. reference)
            if interpolated == value, do: value, else: resolve_value(interpolated, context)
          {:error, :missing_input, name} ->
            Logger.warning("Missing input reference: ${input.#{name}}")
            value
        end

      String.starts_with?(value, "params.") ->
        param_name = String.replace_prefix(value, "params.", "")
        get_in(context, [:params, param_name]) || get_in(context, [:params, String.to_atom(param_name)])

      String.starts_with?(value, "trigger.") ->
        path = String.replace_prefix(value, "trigger.", "") |> String.split(".")
        get_nested(context[:trigger] || %{}, path)

      String.starts_with?(value, "vars.") ->
        var_path = String.replace_prefix(value, "vars.", "")
        get_in(context, [:vars, var_path])

      String.starts_with?(value, "telemetry.") ->
        item = String.replace_prefix(value, "telemetry.", "")
        case get_telemetry_value(item, context) do
          {:ok, val} -> val
          _ -> nil
        end

      String.contains?(value, "{{") ->
        resolve_template(value, context)

      true ->
        value
    end
  end

  defp resolve_value(value, _context), do: value

  # Resolve a duration value - handles input references and ensures integer result
  defp resolve_duration(value, _context) when is_integer(value), do: value
  defp resolve_duration(value, context) when is_binary(value) do
    resolved = resolve_value(value, context)
    case resolved do
      v when is_integer(v) -> v
      v when is_binary(v) ->
        case Integer.parse(v) do
          {int, _} -> int
          :error -> 0
        end
      _ -> 0
    end
  end
  defp resolve_duration(_, _), do: 0

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

  defp log_message(:debug, msg), do: Logger.debug(msg)
  defp log_message(:info, msg), do: Logger.info(msg)
  defp log_message(:warn, msg), do: Logger.warning(msg)
  defp log_message(:error, msg), do: Logger.error(msg)
  defp log_message(_, msg), do: Logger.info(msg)
end
