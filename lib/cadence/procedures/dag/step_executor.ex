defmodule Cadence.Procedures.Dag.StepExecutor do
  @moduledoc """
  Executes individual steps within a DAG procedure.

  This module adapts the step execution logic for use with the DAG executor,
  handling each step type (check, command, wait, wait_for, log, set, assert).

  Uses shared primitives from `Cadence.Procedures.Primitives` for atomic operations.

  ## Variable Scoping

  Variables set by steps are prefixed with the step name:
  - Step "check_a" setting "result" -> stored as "check_a.result"
  - Access via `vars.check_a.result` or `vars.result` if single dependency
  """

  require Logger

  alias Cadence.Procedures.Primitives

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

    case Primitives.check_condition(condition, context) do
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
    resolved_args = Primitives.resolve_values(args, context)

    Logger.info(
      "DAG step '#{step_name}': Sending command #{name} with args #{inspect(resolved_args)}"
    )

    case Primitives.send_command(name, resolved_args, context) do
      {:ok, command_id} ->
        {:ok, %{command: name, args: resolved_args, result: :sent, command_id: command_id}}

      {:error, reason} ->
        {:error, "Command '#{name}' failed: #{inspect(reason)}"}
    end
  end

  def execute_step(step_name, %{"type" => "wait"} = step, context, opts) do
    duration_raw = Map.get(step, "duration", 0)
    duration = Primitives.resolve_duration(duration_raw, context)
    progress_callback = Map.get(opts, :on_progress)

    Logger.debug("DAG step '#{step_name}': Waiting #{duration}ms")

    Primitives.wait(duration,
      on_progress: progress_callback,
      name: step_name
    )

    {:ok, %{waited: duration}}
  end

  def execute_step(step_name, %{"type" => "wait_for"} = step, context, opts) do
    item = Map.get(step, "item")
    operator = Map.get(step, "operator", "==")
    value = Primitives.resolve_value(Map.get(step, "value"), context)
    timeout = Map.get(step, "timeout", 30_000)
    progress_callback = Map.get(opts, :on_progress)

    Logger.debug("DAG step '#{step_name}': Waiting for #{item} #{operator} #{inspect(value)}")

    case Primitives.wait_for(item, operator, value, timeout, context,
           on_progress: progress_callback,
           name: step_name
         ) do
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
    message_template = Map.get(step, "message") || ""
    message = resolve_template(message_template, context)

    log_message(level, "DAG step '#{step_name}': #{message}")

    {:ok, %{level: level, message: message}}
  end

  def execute_step(step_name, %{"type" => "set"} = step, context, _opts) do
    var_name = Map.get(step, "name")
    value = Primitives.resolve_value(Map.get(step, "value"), context)

    # Store with step prefix for scoping
    scoped_name = "#{step_name}.#{var_name}"

    Logger.debug("DAG step '#{step_name}': Setting #{scoped_name} = #{inspect(value)}")

    # Return the variable to be stored in context
    {:ok, %{variable: scoped_name, value: value, set_var: {scoped_name, value}}}
  end

  def execute_step(step_name, %{"type" => "assert"} = step, context, _opts) do
    condition = Map.get(step, "condition", "true")
    message = Map.get(step, "message", "Assertion failed: #{condition}")

    case Primitives.check_condition(condition, context) do
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
  # Private Helpers
  # ============================================================================

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

  # Resolve {{template}} strings - delegates to Primitives for value resolution
  defp resolve_template(template, context) do
    Regex.replace(~r/\{\{(.+?)\}\}/, template, fn _, expr ->
      value = Primitives.resolve_value(String.trim(expr), context)
      to_string(value || "")
    end)
  end

  defp log_message(:debug, msg), do: Logger.debug(msg)
  defp log_message(:info, msg), do: Logger.info(msg)
  defp log_message(:warn, msg), do: Logger.warning(msg)
  defp log_message(:error, msg), do: Logger.error(msg)
  defp log_message(_, msg), do: Logger.info(msg)
end
