defmodule Cadence.Procedures.Dag.Executor do
  @moduledoc """
  Executes DAG-structured procedures with parallel step execution.

  Steps in a DAG can run concurrently when their dependencies are satisfied.
  The executor:

  1. Validates the DAG structure
  2. Finds all steps with no unmet dependencies
  3. Executes ready steps in parallel (using Tasks)
  4. Updates completion status as steps finish
  5. Repeats until all steps complete or failure occurs

  ## Failure Handling

  Steps can specify `on_fail` behavior:
  - `"abort"` (default): Fail the entire DAG, cancel running steps
  - `"continue"`: Mark step as failed, continue independent branches
  - `"pause"`: Pause execution, allow operator to decide

  The DAG-level default can be set via `on_step_failure` in the source.

  ## State Tracking

  The executor maintains:
  - `completed_steps`: Steps that succeeded
  - `failed_steps`: Steps that failed
  - `blocked_steps`: Steps that couldn't run due to failed dependencies
  - `skipped_steps`: Steps skipped due to condition being false
  - `step_results`: Results/metadata from each step
  """

  require Logger

  alias Cadence.Procedures.Dag.CancellationToken
  alias Cadence.Procedures.Dag.Validator

  @type step_name :: String.t()
  @type step_status :: :pending | :running | :completed | :failed | :blocked | :skipped

  defmodule State do
    @moduledoc "Internal state for DAG execution"
    defstruct [
      :steps,
      :dependencies,
      :dependents,
      :default_on_fail,
      :step_executor,
      :context,
      :max_concurrency,
      :default_step_timeout,
      :global_deadline,
      # CancellationToken for lock-free signal propagation (optional, for parent process control)
      :cancellation_token,
      completed: MapSet.new(),
      failed: MapSet.new(),
      blocked: MapSet.new(),
      skipped: MapSet.new(),
      timed_out: MapSet.new(),
      # running: %{step_name => {task, deadline}}
      running: %{},
      step_results: %{},
      control_signal: nil,
      # Flag to prevent repeated timeout warnings
      timeout_warned: false
    ]
  end

  # Default step timeout: 5 minutes
  @default_step_timeout_ms 300_000
  # Default global timeout: 1 hour
  @default_global_timeout_ms 3_600_000
  # Grace period for step shutdown (5 seconds to complete cleanly)
  @step_shutdown_grace_ms 5_000

  @doc """
  Executes a DAG procedure.

  ## Parameters

  - `steps`: Map of step names to step definitions
  - `step_executor`: Function `(step_name, step_def, context) -> {:ok, result} | {:error, reason} | {:skip, reason}`
  - `context`: Execution context passed to step executor
  - `opts`: Options
    - `:max_concurrency` - Maximum parallel steps (default: `:unlimited`)
    - `:on_step_failure` - Default failure mode (`:abort`, `:continue`, `:pause`)
    - `:completed_steps` - Pre-completed steps (for resume)
    - `:failed_steps` - Pre-failed steps (for resume)
    - `:timed_out_steps` - Pre-timed-out steps (for resume)
    - `:skipped_steps` - Pre-skipped steps (for resume)
    - `:blocked_steps` - Pre-blocked steps (for resume)
    - `:step_results` - Pre-existing step results (for resume, used to rebuild vars)
    - `:on_status_change` - Callback for status changes
    - `:step_timeout` - Default timeout for steps in ms (default: 5 minutes)
    - `:global_timeout` - Total execution timeout in ms (default: 1 hour)
    - `:cancellation_token` - Optional `CancellationToken` for lock-free signal propagation

  ## Cancellation Token

  When a `CancellationToken` is provided, the executor checks it atomically before
  starting each step. This eliminates the race condition window that exists with
  message-based signal forwarding. Use it when control signals are sent from
  another process (e.g., ExecutionProcess GenServer).

      token = CancellationToken.new()
      Task.async(fn ->
        Executor.execute(steps, executor, ctx, cancellation_token: token)
      end)

      # Later, from another process:
      CancellationToken.request_pause(token)

  ## Step-level Timeouts

  Individual steps can override the default timeout by setting a `timeout` field (in ms).
  When a step times out, it is killed and marked as `:timed_out`.

  ## Returns

  - `{:ok, result}` where result contains completed/failed/blocked/skipped/timed_out steps
  - `{:error, reason}` on validation failure or execution error
  - `{:error, :global_timeout}` if global timeout exceeded
  - `{:paused, state}` if paused by control signal or step failure
  """
  @spec execute(map(), function(), map(), keyword()) ::
          {:ok, map()} | {:error, term()} | {:paused, map()}
  def execute(steps, step_executor, context, opts \\ []) do
    default_on_fail = Keyword.get(opts, :on_step_failure, :abort)
    pre_completed = Keyword.get(opts, :completed_steps, []) |> MapSet.new()
    pre_failed = Keyword.get(opts, :failed_steps, []) |> MapSet.new()
    pre_timed_out = Keyword.get(opts, :timed_out_steps, []) |> MapSet.new()
    pre_skipped = Keyword.get(opts, :skipped_steps, []) |> MapSet.new()
    pre_blocked = Keyword.get(opts, :blocked_steps, []) |> MapSet.new()
    pre_step_results = Keyword.get(opts, :step_results, %{})
    on_status_change = Keyword.get(opts, :on_status_change)
    max_concurrency = Keyword.get(opts, :max_concurrency, :unlimited)
    step_timeout = Keyword.get(opts, :step_timeout, @default_step_timeout_ms)
    global_timeout = Keyword.get(opts, :global_timeout, @default_global_timeout_ms)
    cancellation_token = Keyword.get(opts, :cancellation_token)

    # Calculate global deadline
    global_deadline = System.monotonic_time(:millisecond) + global_timeout

    # Rebuild vars from pre-existing step results (for resume)
    pre_vars = rebuild_vars_from_results(pre_step_results)
    context_with_vars = Map.update(context, :vars, pre_vars, &Map.merge(&1, pre_vars))

    # Validate DAG structure
    case Validator.validate(steps) do
      :ok ->
        state = %State{
          steps: steps,
          dependencies: Validator.build_dependency_graph(steps),
          dependents: Validator.build_dependents_graph(steps),
          default_on_fail: default_on_fail,
          step_executor: step_executor,
          context: context_with_vars,
          completed: pre_completed,
          failed: pre_failed,
          timed_out: pre_timed_out,
          skipped: pre_skipped,
          blocked: pre_blocked,
          max_concurrency: max_concurrency,
          default_step_timeout: step_timeout,
          global_deadline: global_deadline,
          cancellation_token: cancellation_token,
          step_results: pre_step_results
        }

        run_loop(state, on_status_change)

      {:error, reasons} ->
        {:error, {:validation_failed, reasons}}
    end
  end

  # Rebuild vars map from persisted step_results
  # Each step's result is stored under vars.<step_name>
  defp rebuild_vars_from_results(step_results) when is_map(step_results) do
    step_results
    |> Enum.filter(fn {_name, result} ->
      # Only include completed steps with actual results
      is_map(result) and Map.get(result, :status) == :completed
    end)
    |> Enum.map(fn {name, result} ->
      {name, Map.get(result, :result, %{})}
    end)
    |> Map.new()
  end

  defp rebuild_vars_from_results(_), do: %{}

  @doc """
  Sends a control signal to pause execution.

  This is typically called from another process to request pause.
  """
  def request_pause(executor_pid) do
    send(executor_pid, {:control_signal, :pause})
  end

  @doc """
  Sends a control signal to abort execution.
  """
  def request_abort(executor_pid) do
    send(executor_pid, {:control_signal, :abort})
  end

  # ============================================================================
  # Main Execution Loop
  # ============================================================================

  # Warning threshold before global timeout (30 seconds before)
  @timeout_warning_threshold_ms 30_000

  defp run_loop(state, on_status_change) do
    # Check for global timeout first
    cond do
      global_timeout_exceeded?(state) ->
        Logger.warning("DAG: Global execution timeout exceeded - initiating graceful shutdown")
        # Mark running steps as timed out before cancellation
        state = mark_running_as_timed_out(state, on_status_change)
        cancel_running_steps(state)
        {:error, {:global_timeout, build_result(state)}}

      global_timeout_warning?(state) and not state.timeout_warned ->
        # Log warning when approaching timeout, but only once
        remaining_ms = state.global_deadline - System.monotonic_time(:millisecond)
        Logger.warning("DAG: Approaching global timeout - #{div(remaining_ms, 1000)}s remaining")
        run_loop_inner(%{state | timeout_warned: true}, on_status_change)

      true ->
        run_loop_inner(state, on_status_change)
    end
  end

  defp global_timeout_warning?(state) do
    remaining = state.global_deadline - System.monotonic_time(:millisecond)
    remaining > 0 and remaining <= @timeout_warning_threshold_ms
  end

  defp mark_running_as_timed_out(state, on_status_change) do
    Enum.reduce(state.running, state, fn {name, _task_info}, acc_state ->
      notify_status_change(on_status_change, name, :timed_out, %{reason: :global_timeout})
      %{acc_state | timed_out: MapSet.put(acc_state.timed_out, name)}
    end)
  end

  defp run_loop_inner(state, on_status_change) do
    # Check for control signals
    state = check_control_signals(state)

    case state.control_signal do
      :abort ->
        cancel_running_steps(state)
        {:error, :aborted}

      :pause ->
        # Don't start any new steps, but let running steps complete naturally
        # This gives us the "pausing" state while steps finish
        if map_size(state.running) == 0 do
          # No steps running, pause immediately
          {:paused, build_result(state)}
        else
          # Wait for running steps to complete, then pause
          # Don't start any new steps (skip the ready check)
          wait_for_pause_completion(state, on_status_change)
        end

      nil ->
        # Check for any timed out steps
        state = check_step_timeouts(state, on_status_change)

        # Find steps ready to run
        ready = find_ready_steps(state)

        cond do
          # All done - either completed or all blocked/failed
          ready == [] and map_size(state.running) == 0 ->
            finalize_execution(state)

          # Nothing ready but steps still running - wait for them
          ready == [] ->
            wait_for_step_completion(state, on_status_change)

          # Start ready steps and continue
          true ->
            state = start_steps(state, ready, on_status_change)
            wait_for_step_completion(state, on_status_change)
        end
    end
  end

  defp global_timeout_exceeded?(%{global_deadline: nil}), do: false

  defp global_timeout_exceeded?(%{global_deadline: deadline}) do
    System.monotonic_time(:millisecond) >= deadline
  end

  defp check_step_timeouts(state, on_status_change) do
    now = System.monotonic_time(:millisecond)

    # Find any steps that have exceeded their deadline
    timed_out_steps =
      state.running
      |> Enum.filter(fn {_name, {_task, deadline}} -> now >= deadline end)
      |> Enum.map(fn {name, _} -> name end)

    # Handle each timed out step
    Enum.reduce(timed_out_steps, state, fn step_name, acc ->
      handle_step_timeout(acc, step_name, on_status_change)
    end)
  end

  defp handle_step_timeout(state, step_name, on_status_change) do
    case Map.get(state.running, step_name) do
      nil ->
        state

      {task, _deadline} ->
        Logger.warning("DAG: Step '#{step_name}' timed out, initiating graceful shutdown")

        # Give the task a grace period to complete cleanly
        Task.shutdown(task, @step_shutdown_grace_ms)

        # Remove from running, add to timed_out
        {_, running} = Map.pop(state.running, step_name)
        execution_id = state.context[:execution_id]

        notify_status_change(on_status_change, step_name, :timed_out, %{reason: :timeout})
        emit_step_telemetry(:timeout, step_name, execution_id, %{})

        state = %{
          state
          | running: running,
            timed_out: MapSet.put(state.timed_out, step_name),
            step_results: Map.put(state.step_results, step_name, %{status: :timed_out})
        }

        # Block dependents like we do for failures
        block_dependents(state, step_name, on_status_change)
    end
  end

  # Check for control signals - first from CancellationToken (atomic), then from mailbox
  defp check_control_signals(%{cancellation_token: nil} = state) do
    # No token - fall back to message-based signals
    check_mailbox_signals(state)
  end

  defp check_control_signals(%{cancellation_token: token} = state) do
    # Check token first (atomic, no race condition)
    case CancellationToken.check(token) do
      :abort -> %{state | control_signal: :abort}
      :pause -> %{state | control_signal: :pause}
      :none -> check_mailbox_signals(state)
    end
  end

  defp check_mailbox_signals(state) do
    receive do
      {:control_signal, signal} ->
        %{state | control_signal: signal}
    after
      0 -> state
    end
  end

  defp find_ready_steps(state) do
    ready =
      state.steps
      |> Map.keys()
      |> Enum.filter(fn name ->
        not MapSet.member?(state.completed, name) and
          not MapSet.member?(state.failed, name) and
          not MapSet.member?(state.blocked, name) and
          not MapSet.member?(state.skipped, name) and
          not MapSet.member?(state.timed_out, name) and
          not Map.has_key?(state.running, name) and
          dependencies_satisfied?(state, name)
      end)

    Logger.debug(
      "DAG: Finding ready steps. Completed=#{inspect(MapSet.to_list(state.completed))}, " <>
        "Running=#{inspect(Map.keys(state.running))}, Ready=#{inspect(ready)}"
    )

    ready
  end

  defp dependencies_satisfied?(state, step_name) do
    deps = Map.get(state.dependencies, step_name, [])

    Enum.all?(deps, fn dep ->
      MapSet.member?(state.completed, dep) or MapSet.member?(state.skipped, dep)
    end)
  end

  defp any_dependency_failed?(state, step_name) do
    deps = Map.get(state.dependencies, step_name, [])

    Enum.any?(deps, fn dep ->
      MapSet.member?(state.failed, dep) or
        MapSet.member?(state.blocked, dep) or
        MapSet.member?(state.timed_out, dep)
    end)
  end

  # ============================================================================
  # Step Execution
  # ============================================================================

  defp start_steps(state, step_names, on_status_change) do
    # Respect concurrency limits
    available_slots = available_concurrency_slots(state)
    steps_to_start = Enum.take(step_names, available_slots)

    Enum.reduce(steps_to_start, state, fn name, acc ->
      start_step(acc, name, on_status_change)
    end)
  end

  defp available_concurrency_slots(%{max_concurrency: :unlimited}), do: 1000

  defp available_concurrency_slots(%{max_concurrency: max, running: running}) do
    max(0, max - map_size(running))
  end

  defp start_step(state, step_name, on_status_change) do
    # CRITICAL: Check for cancellation signal BEFORE starting each step
    # This eliminates the race window where a signal arrives after the check
    # in run_loop but before we start the step
    if cancellation_signaled?(state) do
      Logger.debug("DAG: Not starting step '#{step_name}' - cancellation signaled")
      state
    else
      do_start_step(state, step_name, on_status_change)
    end
  end

  # Check if cancellation is signaled (via token or control_signal)
  defp cancellation_signaled?(%{cancellation_token: nil, control_signal: nil}), do: false
  defp cancellation_signaled?(%{control_signal: signal}) when signal != nil, do: true

  defp cancellation_signaled?(%{cancellation_token: token}) do
    token && CancellationToken.signaled?(token)
  end

  defp do_start_step(state, step_name, on_status_change) do
    step = Map.get(state.steps, step_name)
    execution_id = state.context[:execution_id]

    # Check for conditional execution
    if should_skip_step?(step, state) do
      Logger.debug("DAG: Skipping step '#{step_name}' (condition false)")
      notify_status_change(on_status_change, step_name, :skipped, nil)
      emit_step_telemetry(:skip, step_name, execution_id, %{reason: :condition_false})
      %{state | skipped: MapSet.put(state.skipped, step_name)}
    else
      # Check if dependencies failed and this step should be blocked
      if any_dependency_failed?(state, step_name) do
        Logger.debug("DAG: Blocking step '#{step_name}' (dependency failed)")
        notify_status_change(on_status_change, step_name, :blocked, nil)
        emit_step_telemetry(:block, step_name, execution_id, %{reason: :dependency_failed})
        %{state | blocked: MapSet.put(state.blocked, step_name)}
      else
        Logger.debug("DAG: Starting step '#{step_name}'")
        notify_status_change(on_status_change, step_name, :running, nil)
        start_time = System.monotonic_time()
        emit_step_telemetry(:start, step_name, execution_id, %{})

        # Calculate step deadline (step-specific timeout or default)
        step_timeout = get_step_timeout(step, state.default_step_timeout)
        step_deadline = System.monotonic_time(:millisecond) + step_timeout

        # Start async task
        parent = self()

        task =
          Task.async(fn ->
            try do
              result = state.step_executor.(step_name, step, state.context)
              duration = System.monotonic_time() - start_time

              emit_step_telemetry(:stop, step_name, execution_id, %{
                duration: duration,
                result: result_type(result)
              })

              send(parent, {:step_result, step_name, result})
              result
            rescue
              e ->
                duration = System.monotonic_time() - start_time
                result = {:error, Exception.message(e)}

                emit_step_telemetry(:exception, step_name, execution_id, %{
                  duration: duration,
                  exception: e
                })

                send(parent, {:step_result, step_name, result})
                result
            catch
              kind, reason ->
                duration = System.monotonic_time() - start_time
                result = {:error, {kind, reason}}

                emit_step_telemetry(:exception, step_name, execution_id, %{
                  duration: duration,
                  kind: kind
                })

                send(parent, {:step_result, step_name, result})
                result
            end
          end)

        # Store task with its deadline
        %{state | running: Map.put(state.running, step_name, {task, step_deadline})}
      end
    end
  end

  defp get_step_timeout(step, default) do
    case Map.get(step, "timeout") do
      nil -> default
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _ -> default
    end
  end

  defp emit_step_telemetry(event, step_name, execution_id, metadata) do
    :telemetry.execute(
      [:cadence, :dag, :step, event],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{step_name: step_name, execution_id: execution_id})
    )
  end

  defp result_type({:ok, _}), do: :ok
  defp result_type({:error, _}), do: :error
  defp result_type({:skip, _}), do: :skip
  defp result_type(_), do: :unknown

  defp should_skip_step?(step, _state) do
    # TODO: Evaluate condition if present
    # For now, just check if there's a condition field set to false literal
    case Map.get(step, "condition") do
      false -> true
      "false" -> true
      _ -> false
    end
  end

  # ============================================================================
  # Waiting and Result Handling
  # ============================================================================

  defp wait_for_step_completion(state, on_status_change) do
    if map_size(state.running) == 0 do
      # Nothing running, continue loop
      run_loop(state, on_status_change)
    else
      receive do
        {:step_result, step_name, result} ->
          state = handle_step_result(state, step_name, result, on_status_change)
          run_loop(state, on_status_change)

        # Handle Task completion message (from Task.async)
        {ref, _result} when is_reference(ref) ->
          # Flush the DOWN message that Task.async sends
          Process.demonitor(ref, [:flush])
          # The actual result is handled via :step_result message, just continue
          wait_for_step_completion(state, on_status_change)

        # Handle Task crash
        {:DOWN, ref, :process, _pid, reason} when is_reference(ref) ->
          # Find which step this task belonged to
          case find_step_by_ref(state, ref) do
            {:ok, step_name} ->
              Logger.error("DAG: Step '#{step_name}' task crashed: #{inspect(reason)}")

              state =
                handle_step_result(
                  state,
                  step_name,
                  {:error, {:task_crashed, reason}},
                  on_status_change
                )

              run_loop(state, on_status_change)

            :not_found ->
              # Unknown task, continue waiting
              wait_for_step_completion(state, on_status_change)
          end

        {:control_signal, signal} ->
          state = %{state | control_signal: signal}
          run_loop(state, on_status_change)
      after
        # Timeout - check for control signals periodically
        100 ->
          run_loop(state, on_status_change)
      end
    end
  end

  defp find_step_by_ref(state, ref) do
    case Enum.find(state.running, fn {_name, {task, _deadline}} -> task.ref == ref end) do
      {name, _} -> {:ok, name}
      nil -> :not_found
    end
  end

  # Wait for running steps to complete during pause (don't start new steps)
  defp wait_for_pause_completion(state, on_status_change) do
    if map_size(state.running) == 0 do
      # All running steps completed, now we can pause
      {:paused, build_result(state)}
    else
      receive do
        {:step_result, step_name, result} ->
          state = handle_step_result(state, step_name, result, on_status_change)
          # Continue waiting for remaining steps (don't start new ones)
          wait_for_pause_completion(state, on_status_change)

        # Handle Task completion message (from Task.async)
        {ref, _result} when is_reference(ref) ->
          Process.demonitor(ref, [:flush])
          wait_for_pause_completion(state, on_status_change)

        # Handle Task crash
        {:DOWN, ref, :process, _pid, reason} when is_reference(ref) ->
          case find_step_by_ref(state, ref) do
            {:ok, step_name} ->
              Logger.error(
                "DAG: Step '#{step_name}' task crashed during pause: #{inspect(reason)}"
              )

              state =
                handle_step_result(
                  state,
                  step_name,
                  {:error, {:task_crashed, reason}},
                  on_status_change
                )

              wait_for_pause_completion(state, on_status_change)

            :not_found ->
              wait_for_pause_completion(state, on_status_change)
          end

        {:control_signal, :abort} ->
          # Abort takes priority over pause - kill everything
          cancel_running_steps(state)
          {:error, :aborted}

        {:control_signal, _signal} ->
          # Ignore other signals while pausing
          wait_for_pause_completion(state, on_status_change)
      end
    end
  end

  defp handle_step_result(state, step_name, result, on_status_change) do
    Logger.debug("DAG: Handling result for step '#{step_name}': #{inspect(result)}")

    # Remove from running
    {_task, state} = pop_running(state, step_name)

    case result do
      {:ok, step_result} ->
        Logger.debug("DAG: Step '#{step_name}' completed successfully")
        notify_status_change(on_status_change, step_name, :completed, step_result)

        # Update context.vars with the step result so subsequent steps can access it
        # via vars.<step_name>.<field>
        updated_vars = Map.put(state.context[:vars] || %{}, step_name, step_result)
        updated_context = Map.put(state.context, :vars, updated_vars)

        %{
          state
          | completed: MapSet.put(state.completed, step_name),
            step_results:
              Map.put(state.step_results, step_name, %{status: :completed, result: step_result}),
            context: updated_context
        }

      {:skip, reason} ->
        Logger.debug("DAG: Step '#{step_name}' skipped: #{inspect(reason)}")
        notify_status_change(on_status_change, step_name, :skipped, reason)

        %{
          state
          | skipped: MapSet.put(state.skipped, step_name),
            step_results:
              Map.put(state.step_results, step_name, %{status: :skipped, reason: reason})
        }

      {:error, reason} ->
        handle_step_failure(state, step_name, reason, on_status_change)
    end
  end

  defp handle_step_failure(state, step_name, reason, on_status_change) do
    step = Map.get(state.steps, step_name)
    on_fail = get_on_fail(step, state.default_on_fail)

    Logger.warning("DAG: Step '#{step_name}' failed: #{inspect(reason)}, on_fail=#{on_fail}")
    notify_status_change(on_status_change, step_name, :failed, reason)

    state = %{
      state
      | failed: MapSet.put(state.failed, step_name),
        step_results: Map.put(state.step_results, step_name, %{status: :failed, error: reason})
    }

    case on_fail do
      :abort ->
        # Mark all dependents as blocked and signal abort
        state = block_dependents(state, step_name, on_status_change)
        %{state | control_signal: :abort}

      :continue ->
        # Mark direct dependents as blocked, but continue independent branches
        block_dependents(state, step_name, on_status_change)

      :pause ->
        # Pause for operator decision
        %{state | control_signal: :pause}
    end
  end

  defp get_on_fail(step, default) do
    case Map.get(step, "on_fail") do
      "abort" -> :abort
      "continue" -> :continue
      "pause" -> :pause
      _ -> default
    end
  end

  defp block_dependents(state, failed_step, on_status_change) do
    # Find all steps that transitively depend on the failed step
    to_block = find_all_dependents(state, failed_step)

    Enum.reduce(to_block, state, fn step_name, acc ->
      if not MapSet.member?(acc.blocked, step_name) and
           not MapSet.member?(acc.completed, step_name) and
           not MapSet.member?(acc.failed, step_name) do
        Logger.debug("DAG: Blocking step '#{step_name}' (depends on failed step)")

        notify_status_change(
          on_status_change,
          step_name,
          :blocked,
          {:dependency_failed, failed_step}
        )

        %{acc | blocked: MapSet.put(acc.blocked, step_name)}
      else
        acc
      end
    end)
  end

  defp find_all_dependents(state, step_name) do
    # BFS to find all transitive dependents
    do_find_dependents([step_name], MapSet.new(), state.dependents)
  end

  defp do_find_dependents([], found, _dependents), do: MapSet.to_list(found)

  defp do_find_dependents([current | rest], found, dependents) do
    direct = Map.get(dependents, current, [])

    new_deps =
      direct
      |> Enum.reject(fn d -> MapSet.member?(found, d) end)

    found = Enum.reduce(new_deps, found, fn d, acc -> MapSet.put(acc, d) end)
    do_find_dependents(rest ++ new_deps, found, dependents)
  end

  defp pop_running(state, step_name) do
    {task, running} = Map.pop(state.running, step_name)
    {task, %{state | running: running}}
  end

  defp cancel_running_steps(state) do
    Enum.each(state.running, fn {name, {task, _deadline}} ->
      Logger.debug("DAG: Cancelling running step '#{name}'")
      # Give steps a grace period to complete cleanly before forcing shutdown
      # This allows steps like "command" to finish sending to the spacecraft
      # rather than being killed mid-transmission
      case Task.shutdown(task, @step_shutdown_grace_ms) do
        {:ok, _result} ->
          Logger.debug("DAG: Step '#{name}' completed during shutdown grace period")

        {:exit, reason} ->
          Logger.debug("DAG: Step '#{name}' exited with: #{inspect(reason)}")

        nil ->
          # Task was killed after grace period
          Logger.warning("DAG: Step '#{name}' force-killed after grace period")
      end
    end)
  end

  # ============================================================================
  # Finalization
  # ============================================================================

  defp finalize_execution(state) do
    result = build_result(state)

    has_failures = MapSet.size(state.failed) > 0 or MapSet.size(state.timed_out) > 0

    cond do
      has_failures and state.default_on_fail == :abort ->
        {:error, {:steps_failed, result}}

      has_failures ->
        # Some steps failed but we continued
        {:ok, Map.put(result, :status, :completed_with_failures)}

      true ->
        {:ok, Map.put(result, :status, :completed)}
    end
  end

  defp build_result(state) do
    %{
      completed_steps: MapSet.to_list(state.completed),
      failed_steps: MapSet.to_list(state.failed),
      blocked_steps: MapSet.to_list(state.blocked),
      skipped_steps: MapSet.to_list(state.skipped),
      timed_out_steps: MapSet.to_list(state.timed_out),
      step_results: state.step_results
    }
  end

  defp notify_status_change(nil, _step_name, _status, _data), do: :ok

  defp notify_status_change(callback, step_name, status, data) when is_function(callback, 3) do
    callback.(step_name, status, data)
  end

  defp notify_status_change(_callback, _step_name, _status, _data), do: :ok
end
