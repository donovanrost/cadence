defmodule Cadence.Procedures.V2.AutomationRunner do
  @moduledoc """
  Executes automated blocks within a V2 procedure step.

  The AutomationRunner is responsible for:
  - Executing a sequence of automated blocks (commands, waits, telemetry checks, scripts)
  - Reporting progress via callbacks
  - Checking for control signals (pause/abort) between blocks
  - Handling block-level failures and retries

  ## Usage

  The runner is typically spawned as a Task by the ExecutionProcess:

      task = Task.async(fn ->
        AutomationRunner.run(blocks, context, opts)
      end)

  ## Options

    * `:on_progress` - `fn(block, status, data) -> :ok` - Called with progress updates
    * `:on_block_complete` - `fn(block, result) -> :ok` - Called when a block completes
    * `:check_signal` - `fn() -> :continue | :pause | :abort` - Called between blocks
    * `:strategy` - The execution strategy module (for confirmation checks)

  ## Results

  Returns one of:
    * `{:ok, results}` - All blocks completed successfully
    * `{:error, block, reason}` - A block failed
    * `{:paused, completed_results, remaining_blocks}` - Execution was paused
    * `{:aborted, completed_results}` - Execution was aborted
  """

  require Logger

  alias Cadence.Procedures.Primitives
  alias Cadence.Procedures.ProcedureBlock
  alias Cadence.Procedures.Runtime.CadenceApi
  alias Cadence.Targets

  @type block :: ProcedureBlock.t() | map()
  @type context :: Primitives.context()
  @type result ::
          {:ok, map()}
          | {:error, block(), term()}
          | {:paused, map(), [block()]}
          | {:aborted, map()}

  @type progress_status :: :starting | :running | :waiting | :completed | :failed
  @type signal :: :continue | :pause | :abort

  @doc """
  Runs a sequence of automated blocks.

  Executes each block in order, checking for control signals between blocks.
  Reports progress via the provided callbacks.

  ## Options

    * `:on_progress` - Progress callback `fn(block, status, data) -> :ok`
    * `:on_block_complete` - Block completion callback `fn(block, result) -> :ok`
    * `:check_signal` - Signal check function `fn() -> :continue | :pause | :abort`
    * `:strategy` - Strategy module for confirmation checks

  ## Returns

    * `{:ok, results}` - Map of block_id => result for all completed blocks
    * `{:error, block, reason}` - The block that failed and why
    * `{:paused, results, remaining}` - Partial results and remaining blocks
    * `{:aborted, results}` - Partial results before abort
  """
  @spec run([block()], context(), keyword()) :: result()
  def run(blocks, context, opts \\ []) do
    on_progress = opts[:on_progress] || fn _, _, _ -> :ok end
    on_block_complete = opts[:on_block_complete] || fn _, _ -> :ok end
    check_signal = opts[:check_signal] || fn -> :continue end

    run_blocks(blocks, context, %{}, on_progress, on_block_complete, check_signal)
  end

  @doc """
  Executes a single block and returns the result.

  This is the core execution logic for each block type.
  """
  @spec execute_block(block(), context(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:skip, term()}
  def execute_block(block, context, opts \\ [])

  def execute_block(%{block_type: :command} = block, context, opts) do
    execute_command_block(block, context, opts)
  end

  def execute_block(%{block_type: :command_sequence} = block, context, opts) do
    execute_command_sequence_block(block, context, opts)
  end

  def execute_block(%{block_type: :telemetry_wait} = block, context, opts) do
    execute_wait_for_block(block, context, opts)
  end

  def execute_block(%{block_type: :wait} = block, context, opts) do
    execute_wait_block(block, context, opts)
  end

  def execute_block(%{block_type: :wait_for} = block, context, opts) do
    execute_wait_for_block(block, context, opts)
  end

  def execute_block(%{block_type: :telemetry_check} = block, context, _opts) do
    execute_telemetry_check_block(block, context)
  end

  def execute_block(%{block_type: :telemetry_value} = block, context, _opts) do
    execute_telemetry_value_block(block, context)
  end

  def execute_block(%{block_type: :script} = block, context, opts) do
    execute_script_block(block, context, opts)
  end

  def execute_block(%{block_type: type} = block, context, opts)
      when type in [
             :text_input,
             :number_input,
             :select_input,
             :checkbox_input,
             :timestamp_input,
             :duration_input,
             :attachment_input,
             :signature_input
           ] do
    execute_input_block(block, context, opts)
  end

  def execute_block(%{block_type: type}, _context, _opts) do
    {:error, "Unknown block type: #{type}"}
  end

  # Handle map-based blocks (for testing or legacy)
  def execute_block(%{} = block, context, opts) when not is_struct(block) do
    block_type = block[:block_type] || block["block_type"]
    execute_block(%{block | block_type: block_type}, context, opts)
  end

  # ============================================================================
  # Block Type Implementations
  # ============================================================================

  defp execute_command_block(block, context, opts) do
    %{
      context: context,
      command_name: command_name,
      arguments: arguments,
      priority: priority,
      content: content
    } =
      command_context(block, context)

    notify_command_progress(opts[:on_progress], block, command_name, arguments)

    case Primitives.send_command(command_name, arguments, context, priority: priority) do
      {:ok, command_id} ->
        result = build_command_result(command_name, arguments, command_id, priority)
        handle_command_verification(result, content, context, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp command_context(block, context) do
    content = block.content || %{}
    command_name = content["command_name"] || content["name"]
    priority = content["priority"] || 3
    target = resolve_target(content["target"], context)
    arguments = Primitives.resolve_values(content["arguments"] || %{}, context)

    %{
      content: content,
      command_name: command_name,
      arguments: arguments,
      priority: priority,
      context: Map.put(context, :target_id, target)
    }
  end

  defp notify_command_progress(nil, _block, _command_name, _arguments), do: :ok

  defp notify_command_progress(on_progress, block, command_name, arguments) do
    on_progress.(block, :running, %{command: command_name, args: arguments})
  end

  defp build_command_result(command_name, arguments, command_id, priority) do
    %{
      command_name: command_name,
      arguments: arguments,
      command_id: command_id,
      priority: priority,
      status: :enqueued,
      enqueued_at: DateTime.utc_now()
    }
  end

  defp handle_command_verification(result, content, context, opts) do
    case content["verify_after"] do
      nil -> {:ok, result}
      verify_config -> verify_command(result, verify_config, context, opts)
    end
  end

  # Resolves target from block content, supporting:
  # - nil -> falls back to context target
  # - "execution_target" -> falls back to context target
  # - Template references like "{{params.target}}" -> resolved via Primitives
  # - Target identifiers (non-UUID strings) -> looked up by identifier
  # - Literal target UUIDs
  defp resolve_target(nil, context), do: ensure_target_id(context[:target_id], context)

  defp resolve_target("execution_target", context),
    do: ensure_target_id(context[:target_id], context)

  defp resolve_target(target_ref, context) when is_binary(target_ref) do
    resolved = Primitives.resolve_value(target_ref, context) || context[:target_id]
    ensure_target_id(resolved, context)
  end

  # Ensures the target value is a UUID. If it's an identifier, look it up.
  defp ensure_target_id(nil, _context), do: nil

  defp ensure_target_id(target_value, context) when is_binary(target_value) do
    if uuid?(target_value) do
      target_value
    else
      # Not a UUID - try to look up by identifier
      mission_id = context[:mission_id]

      Logger.debug(
        "Resolving target identifier: #{inspect(target_value)} for mission: #{inspect(mission_id)}"
      )

      case Targets.get_target_by_identifier(mission_id, target_value) do
        {:ok, target} ->
          Logger.debug("Resolved target #{target_value} to UUID: #{target.id}")
          target.id

        {:error, :not_found} ->
          Logger.warning(
            "Target not found by identifier: #{inspect(target_value)}, mission: #{inspect(mission_id)}"
          )

          target_value
      end
    end
  end

  # Check if a string is a valid UUID format
  defp uuid?(str) when byte_size(str) == 36 do
    case Ecto.UUID.cast(str) do
      {:ok, _} -> true
      :error -> false
    end
  end

  defp uuid?(_), do: false

  defp execute_command_sequence_block(block, context, opts) do
    content = block.content || %{}
    commands = content["commands"] || []

    results =
      Enum.reduce_while(commands, {:ok, []}, fn cmd, {:ok, acc} ->
        cmd_block = %{block_type: :command, content: cmd, id: "#{block.id}-#{length(acc)}"}

        case execute_command_block(cmd_block, context, opts) do
          {:ok, result} -> {:cont, {:ok, [result | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, cmd_results} -> {:ok, %{commands: Enum.reverse(cmd_results)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_wait_block(block, context, opts) do
    content = block.content || %{}

    duration =
      Primitives.resolve_duration(content["duration"] || content["duration_ms"] || 0, context)

    on_progress = opts[:on_progress]

    progress_callback =
      if on_progress do
        fn _name, progress -> on_progress.(block, :waiting, progress) end
      else
        nil
      end

    Primitives.wait(duration, on_progress: progress_callback, name: block.id)

    {:ok, %{waited_ms: duration}}
  end

  defp execute_wait_for_block(block, context, opts) do
    content = block.content || %{}
    item = content["item"]
    operator = content["operator"] || "=="
    expected = Primitives.resolve_value(content["expected"], context)
    timeout = content["timeout"] || content["timeout_ms"] || 30_000

    on_progress = opts[:on_progress]

    progress_callback =
      if on_progress do
        fn _name, progress -> on_progress.(block, :waiting, progress) end
      else
        nil
      end

    case Primitives.wait_for(item, operator, expected, timeout, context,
           on_progress: progress_callback,
           name: block.id
         ) do
      {:ok, actual} ->
        {:ok, %{item: item, operator: operator, expected: expected, actual: actual, passed: true}}

      {:error, :timeout} ->
        {:error, :timeout}
    end
  end

  defp execute_telemetry_check_block(block, context) do
    content = block.content || %{}
    item = content["item"]
    operator = content["operator"] || "=="
    expected = Primitives.resolve_value(content["expected"], context)
    condition = "telemetry.#{item} #{operator} #{expected}"

    with {:ok, actual} <- Primitives.get_telemetry(item, context),
         {:ok, passed} <- Primitives.check_condition(condition, context) do
      if passed == false and content["fail_on_false"] == true do
        {:error, "Telemetry check failed: #{item} #{operator} #{expected}"}
      else
        {:ok,
         %{
           item: item,
           operator: operator,
           expected: expected,
           actual: actual,
           passed: passed
         }}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_telemetry_value_block(block, context) do
    content = block.content || %{}
    item = content["item"]

    case Primitives.get_telemetry(item, context) do
      {:ok, value} ->
        {:ok, %{item: item, value: value, read_at: DateTime.utc_now()}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_script_block(block, context, opts) do
    content = block.content || %{}
    script = content["script"]
    timeout_seconds = content["timeout_seconds"] || 60

    on_progress = opts[:on_progress]
    if on_progress, do: on_progress.(block, :running, %{script_started: true})

    # Run script in a task with timeout
    task =
      Task.async(fn ->
        run_lua_script(script, context)
      end)

    case Task.yield(task, timeout_seconds * 1000) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, %{script_result: result, completed_at: DateTime.utc_now()}}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, :script_timeout}
    end
  end

  defp execute_input_block(block, _context, opts) do
    # For input blocks in automatic mode, use defaults
    strategy = opts[:strategy]

    if strategy do
      case strategy.get_default_value(block) do
        {:ok, value} ->
          {:ok, %{value: value, source: :default}}

        :no_default ->
          {:skip, :requires_user_input}
      end
    else
      {:skip, :requires_user_input}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp run_blocks([], _context, results, _on_progress, _on_block_complete, _check_signal) do
    {:ok, results}
  end

  defp run_blocks(
         [block | remaining],
         context,
         results,
         on_progress,
         on_block_complete,
         check_signal
       ) do
    # Check for control signal before each block
    case check_signal.() do
      :abort ->
        {:aborted, results}

      :pause ->
        {:paused, results, [block | remaining]}

      :continue ->
        # Execute the block
        on_progress.(block, :starting, %{})

        case execute_block(block, context, on_progress: on_progress) do
          {:ok, result} ->
            on_progress.(block, :completed, result)
            on_block_complete.(block, {:ok, result})

            block_id = block.id || block[:id]
            new_results = Map.put(results, block_id, {:ok, result})

            run_blocks(
              remaining,
              context,
              new_results,
              on_progress,
              on_block_complete,
              check_signal
            )

          {:skip, reason} ->
            on_progress.(block, :skipped, %{reason: reason})
            on_block_complete.(block, {:skip, reason})

            block_id = block.id || block[:id]
            new_results = Map.put(results, block_id, {:skip, reason})

            run_blocks(
              remaining,
              context,
              new_results,
              on_progress,
              on_block_complete,
              check_signal
            )

          {:error, reason} ->
            on_progress.(block, :failed, %{reason: reason})
            on_block_complete.(block, {:error, reason})

            {:error, block, reason}
        end
    end
  end

  defp verify_command(result, verify_config, context, opts) do
    item = verify_config["item"]
    expected = Primitives.resolve_value(verify_config["expected"], context)
    timeout = verify_config["timeout_seconds"] || 10
    operator = verify_config["operator"] || "=="

    on_progress = opts[:on_progress]

    progress_callback =
      if on_progress do
        fn _name, progress ->
          # We don't have the block here, but we can emit generic progress
          Logger.debug("Command verification progress: #{inspect(progress)}")
        end
      else
        nil
      end

    case Primitives.wait_for(item, operator, expected, timeout * 1000, context,
           on_progress: progress_callback
         ) do
      {:ok, actual} ->
        {:ok,
         Map.merge(result, %{
           verification: %{
             status: :satisfied,
             item: item,
             expected: expected,
             actual: actual,
             verified_at: DateTime.utc_now()
           }
         })}

      {:error, :timeout} ->
        {:ok,
         Map.merge(result, %{
           verification: %{
             status: :timeout,
             item: item,
             expected: expected,
             timeout_seconds: timeout
           }
         })}
    end
  end

  defp run_lua_script(script, context) do
    # Check if luerl is available
    if Code.ensure_loaded?(:luerl) do
      try do
        lua_state = :luerl.init()

        # Install CadenceApi if available
        lua_state =
          if Code.ensure_loaded?(CadenceApi) do
            CadenceApi.install(lua_state, context)
          else
            lua_state
          end

        case :luerl.do(script, lua_state) do
          {:ok, result, _state} -> {:ok, result}
          {:error, reason, _state} -> {:error, reason}
        end
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, :luerl_not_available}
    end
  end
end
