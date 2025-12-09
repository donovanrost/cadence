defmodule Cadence.Procedures.Engine.ExecutionProcess do
  @moduledoc """
  GenServer that manages a single procedure execution.

  Each execution runs in its own process with an isolated Luerl VM.
  The process:

  1. Compiles/loads the procedure source into Lua
  2. Installs the Cadence API
  3. Executes step by step, checking for control signals
  4. Persists checkpoints to database
  5. Broadcasts status changes via PubSub

  ## Architecture: ExecutionProcess <-> DAG Executor Interaction

  For DAG-type procedures, the execution runs in a separate `Task` to avoid
  blocking the GenServer. This allows the GenServer to respond to status
  queries and control signals during execution.

  ```
  ExecutionProcess (GenServer)              DAG Executor (Task)
         │                                        │
         │ Task.async(Executor.execute)           │
         │────────────────────────────────────────>│
         │                                        │
         │ {:control_signal, :pause}              │
         │ ────> (sends to Task mailbox)          │
         │       OR via CancellationToken ────────>│ (atomic check)
         │                                        │
         │ handle_info({ref, result})             │
         │<────────────────────────────────────────│ Task completes
         │                                        │
  ```

  ### Signal Propagation

  Control signals (pause/abort) can be propagated in two ways:

  1. **Message-based** (legacy): `send(task_pid, {:control_signal, signal})`
     - Has a race window between signal send and next check
     - The executor checks signals via `receive after 0` in its event loop

  2. **CancellationToken** (preferred): Atomic signal via `:atomics`
     - No race condition - signal is immediately visible
     - Executor checks token before starting each step
     - See `Cadence.Procedures.Dag.CancellationToken` for details

  ### Task Monitoring

  The ExecutionProcess monitors the DAG Task and handles:
  - Normal completion: `handle_info({ref, result}, state)`
  - Task crash: `handle_info({:DOWN, ref, :process, pid, reason}, state)`

  ## Control Signals

  Send messages to control execution:

  - `:pause` - Pause at next checkpoint
  - `:abort` - Stop execution immediately
  - `:resume` - Resume from paused state
  - `{:skip_step, step_index}` - Skip a step (escape hatch)

  ## Events Broadcast

  On topic `procedure:<execution_id>`:

  - `{:status_changed, status, execution}` - Status changed
  - `{:step_started, step_index, step}` - Starting a step
  - `{:step_completed, step_index, step}` - Step finished
  - `{:log, level, message}` - Log message from procedure
  - `{:checkpoint, name}` - Checkpoint reached
  """

  use GenServer, restart: :temporary
  require Logger

  alias Cadence.Procedures
  alias Cadence.Procedures.Dag.{Executor, StepExecutor}
  alias Cadence.Procedures.Engine.ExecutionPersistence
  alias Cadence.Procedures.Events.ProcedureExecutionEvent
  alias Cadence.Procedures.Events.StepEvent
  alias Cadence.Procedures.ProcedureLog
  alias Cadence.Procedures.Runtime.CadenceApi
  alias Cadence.Repo

  @type control_signal :: :pause | :abort | :resume | {:skip_step, integer()}

  defmodule State do
    @moduledoc false
    defstruct [
      :execution_id,
      :execution,
      :procedure,
      :version,
      :lua_state,
      :context,
      :current_step_index,
      # Task struct for DAG executor (for monitoring and control signals)
      :dag_task,
      control_signal: nil,
      status: :pending
    ]
  end

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    execution_id = Keyword.fetch!(opts, :execution_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(execution_id))
  end

  @doc """
  Returns the PID of an execution process.
  """
  def whereis(execution_id) do
    case Registry.lookup(Cadence.ProcedureRegistry, execution_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Sends a control signal to the execution.
  """
  @spec send_signal(String.t(), control_signal()) :: :ok | {:error, :not_found}
  def send_signal(execution_id, signal) do
    case whereis(execution_id) do
      nil -> {:error, :not_found}
      pid -> GenServer.cast(pid, {:control_signal, signal})
    end
  end

  @doc """
  Pauses the execution at the next safe point.
  """
  def pause(execution_id), do: send_signal(execution_id, :pause)

  @doc """
  Aborts the execution.
  """
  def abort(execution_id), do: send_signal(execution_id, :abort)

  @doc """
  Resumes a paused execution.
  """
  def resume(execution_id), do: send_signal(execution_id, :resume)

  @doc """
  Gets the current state of an execution.
  """
  def get_state(execution_id) do
    case whereis(execution_id) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_state)
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    execution_id = Keyword.fetch!(opts, :execution_id)

    Logger.info("Starting ExecutionProcess for execution_id=#{execution_id}")

    # Load execution with associations
    execution = Procedures.get_execution!(execution_id)
    procedure = Repo.preload(execution.procedure, [])
    version = Repo.preload(execution.procedure_version, [])

    # Build context for Cadence API
    context = %{
      mission_id: execution.mission_id,
      organization_id: execution.organization_id,
      target_id: execution.target_id,
      execution_id: execution_id,
      execution_pid: self(),
      params: execution.parameters || %{},
      allow_hazardous_commands: version.allow_hazardous_commands || false
    }

    # Initialize Luerl state
    lua_state = :luerl.init()
    lua_state = CadenceApi.install(lua_state, context)

    state = %State{
      execution_id: execution_id,
      execution: execution,
      procedure: procedure,
      version: version,
      lua_state: lua_state,
      context: context,
      current_step_index: execution.current_step_index || 0,
      status: execution.status
    }

    # Start execution asynchronously
    # Note: Late-joining clients derive state from outbox events (source of truth),
    # so there's no need for artificial delays. The ExecutionChannel handles this
    # via derive_step_state_from_events on join.
    if execution.status == :pending do
      send(self(), :start_execution)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    reply = %{
      execution_id: state.execution_id,
      status: state.status,
      current_step_index: state.current_step_index,
      control_signal: state.control_signal
    }

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:control_signal, signal}, state) do
    Logger.info("Received control signal #{inspect(signal)} for execution #{state.execution_id}")

    case signal do
      :pause when state.status in [:running, :pausing] ->
        # The coordinator may have already transitioned to :pausing optimistically.
        # If not, do it now. Either way, set the control signal.
        state =
          if state.status == :running do
            new_state = update_status(state, :pausing)

            persist_log(
              new_state,
              :info,
              "Pause requested, waiting for current step to complete..."
            )

            new_state
          else
            # Already in :pausing, just log
            persist_log(state, :info, "Pause requested, waiting for current step to complete...")
            state
          end

        # Forward pause signal to DAG executor if running
        forward_signal_to_dag_executor(state, :pause)

        {:noreply, %{state | control_signal: :pause}}

      :abort ->
        # Forward abort signal to DAG executor if running
        forward_signal_to_dag_executor(state, :abort)
        handle_abort(state)

      :resume when state.status == :paused ->
        # Update status in DB and broadcast before continuing
        state = update_status(state, :running)
        persist_log(state, :info, "Execution resumed")
        send(self(), :continue_execution)
        {:noreply, %{state | control_signal: nil}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:start_execution, state) do
    state = update_status(state, :running, %{started_at: DateTime.utc_now()})
    send(self(), :continue_execution)
    {:noreply, state}
  end

  def handle_info(:continue_execution, state) do
    case check_control_signal(state) do
      {:pause, state} ->
        state = update_status(state, :paused)
        persist_log(state, :info, "Execution paused")
        {:noreply, %{state | control_signal: nil}}

      {:abort, state} ->
        handle_abort(state)

      {:continue, state} ->
        execute_next(state)
    end
  end

  # Handle DAG Task completion via Task.async ref pattern
  def handle_info({ref, result}, %{dag_task: %Task{ref: ref}} = state) do
    # Task completed normally - demonitor and flush any remaining :DOWN message
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, dag_result} ->
        handle_dag_completion(state, dag_result)

      {:error, {:validation_failed, reasons}} ->
        handle_failure(state, 0, "DAG validation failed: #{Enum.join(reasons, "; ")}")

      {:error, {:steps_failed, dag_result}} ->
        handle_dag_failure(state, dag_result)

      {:error, :aborted} ->
        handle_abort(state)

      {:paused, dag_result} ->
        handle_dag_pause(state, dag_result)
    end
  end

  # Handle DAG Task crash via :DOWN message
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{dag_task: %Task{ref: ref}} = state) do
    Logger.error("DAG executor crashed: #{inspect(reason)}")
    handle_failure(state, 0, "DAG executor crashed: #{inspect(reason)}")
  end

  # Messages from Cadence API callbacks
  def handle_info({:log, level, message}, state) do
    # persist_log also broadcasts for real-time UI updates
    persist_log(state, level, message)
    {:noreply, state}
  end

  def handle_info({:checkpoint, name}, state) do
    Logger.debug("Checkpoint reached: #{name} at step #{state.current_step_index}")
    persist_checkpoint(state)
    broadcast(state, {:checkpoint, name})
    {:noreply, state}
  end

  def handle_info({:command_sent, name, log_id}, state) do
    persist_log(state, :info, "Command sent: #{name} (log_id: #{log_id})")
    {:noreply, state}
  end

  def handle_info({:command_failed, name, reason}, state) do
    persist_log(state, :error, "Command failed: #{name} - #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({:waiting, milliseconds}, state) do
    persist_log(state, :debug, "Waiting #{milliseconds}ms")
    {:noreply, state}
  end

  def handle_info({:waiting_for_telemetry, item, op, value}, state) do
    persist_log(state, :debug, "Waiting for #{item} #{op} #{inspect(value)}")
    {:noreply, state}
  end

  def handle_info({:abort_requested, message}, state) do
    persist_log(state, :warn, "Abort requested: #{message}")
    {:noreply, %{state | control_signal: :abort}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "ExecutionProcess terminating: execution_id=#{state.execution_id}, reason=#{inspect(reason)}"
    )

    :ok
  end

  # ============================================================================
  # Execution Logic
  # ============================================================================

  defp execute_next(%{status: status} = state) when status in [:running, :pausing] do
    # Note: We allow :pausing status here because the coordinator may have
    # optimistically set it before the execution process received the signal.
    # The actual pause happens in handle_info(:continue_execution, ...) after
    # the current step completes.
    source = state.version.source

    Logger.info("execute_next: procedure.type=#{inspect(state.procedure.type)}")

    case state.procedure.type do
      :script ->
        execute_script(state, source)

      :dag ->
        execute_dag_sequence(state, source)
    end
  end

  defp execute_next(state) do
    {:noreply, state}
  end

  defp execute_script(state, %{"code" => code}) do
    step_info = %{type: "script"}
    broadcast_step_event(state, 0, step_info, :step_started)

    case :luerl.do(code, state.lua_state) do
      {:ok, _result, new_lua_state} ->
        state = %{state | lua_state: new_lua_state, current_step_index: 1}
        broadcast_step_event(state, 0, step_info, :step_completed)
        handle_completion(state)

      {:error, reason, _lua_state} ->
        handle_failure(state, 0, reason)
    end
  catch
    {:procedure_abort, message} ->
      handle_abort_with_message(state, message)
  end

  defp execute_script(state, _invalid_source) do
    handle_failure(state, 0, "Invalid script source: missing 'code' key")
  end

  # DAG mode: execute steps in parallel based on dependencies
  # We spawn the DAG executor in a separate Task to avoid blocking the GenServer.
  # This allows the GenServer to respond to get_state calls while execution runs.
  defp execute_dag_sequence(state, %{"steps" => steps}) when is_map(steps) do
    Logger.info("Executing DAG sequence with #{map_size(steps)} steps")

    # Build execution context
    dag_context = %{
      mission_id: state.context.mission_id,
      organization_id: state.context.organization_id,
      target_id: state.context.target_id,
      execution_id: state.execution_id,
      params: state.context.params,
      trigger: state.execution.trigger_context,
      vars: %{},
      user_id: state.execution.triggered_by_user_id,
      allow_hazardous_commands: state.context.allow_hazardous_commands
    }

    # Get DAG options from source
    default_on_fail =
      case Map.get(state.version.source, "on_step_failure", "abort") do
        "continue" -> :continue
        "pause" -> :pause
        _ -> :abort
      end

    # Progress callback - broadcasts progress events for wait/wait_for steps
    # This is lightweight (no DB writes) to avoid performance issues with frequent updates
    on_progress = fn step_name, progress_data ->
      topic = "procedure:#{state.execution_id}"

      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        topic,
        {:dag_step_progress, step_name, progress_data}
      )
    end

    # Create step executor with progress callback
    step_executor = StepExecutor.create_executor(%{on_progress: on_progress})

    # Status change callback - uses ExecutionPersistence for atomic writes
    # The outbox event is the authoritative record; PubSub is for real-time updates
    execution = state.execution

    on_status_change = fn step_name, status, data ->
      # Delegate to ExecutionPersistence for atomic transaction handling
      # This ensures step event + log entries are persisted atomically
      # and broadcasts happen only after commit
      ExecutionPersistence.persist_step_event(execution, step_name, status, data)
    end

    # Get pre-completed steps and their results for resume support
    # Derive from outbox events (source of truth) rather than execution record
    step_state = StepEvent.list_for_execution(state.execution_id) |> StepEvent.derive_state()

    # For resume, we need to mark ALL finished steps (not just completed) so they don't re-run
    # This includes: completed, failed, timed_out, skipped, blocked
    pre_completed = step_state.completed
    pre_failed = step_state.failed
    pre_timed_out = step_state.timed_out
    pre_skipped = step_state.skipped
    pre_blocked = step_state.blocked

    # Get pre-existing step results from execution record (persisted on pause/completion)
    # This is used to rebuild context.vars for resumed executions
    pre_step_results = state.execution.step_results || %{}

    # Execute the DAG in a separate Task to avoid blocking the GenServer
    # This allows the GenServer to respond to get_state calls during execution
    # Using Task.async provides automatic monitoring - if the task crashes,
    # we receive a :DOWN message and can handle it gracefully
    opts = [
      on_step_failure: default_on_fail,
      completed_steps: pre_completed,
      failed_steps: pre_failed,
      timed_out_steps: pre_timed_out,
      skipped_steps: pre_skipped,
      blocked_steps: pre_blocked,
      step_results: pre_step_results,
      on_status_change: on_status_change
    ]

    task =
      Task.async(fn ->
        Executor.execute(steps, step_executor, dag_context, opts)
      end)

    # Return immediately - result will be handled in handle_info via Task ref pattern
    # Store the Task struct so we can match on ref and forward control signals
    {:noreply, %{state | status: :running, dag_task: task}}
  end

  defp execute_dag_sequence(state, _invalid_source) do
    handle_failure(state, 0, "Invalid DAG source: 'steps' must be a map")
  end

  defp handle_dag_completion(state, result) do
    Logger.info(
      "DAG execution completed: #{length(result.completed_steps)} completed, #{length(result.skipped_steps)} skipped"
    )

    # Use ExecutionPersistence for atomic update + outbox event
    case ExecutionPersistence.persist_dag_result(state.execution, :completed, result) do
      {:ok, execution} ->
        state = %{state | execution: execution, status: :completed}
        persist_log(state, :info, "DAG execution completed successfully")
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error("Failed to update DAG execution: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  defp handle_dag_failure(state, result) do
    failed_names = Enum.join(result.failed_steps || [], ", ")
    Logger.error("DAG execution failed: steps failed: #{failed_names}")

    # Use ExecutionPersistence for atomic update + outbox event
    case ExecutionPersistence.persist_dag_result(state.execution, :failed, result) do
      {:ok, execution} ->
        state = %{state | execution: execution, status: :failed}
        persist_log(state, :error, "DAG execution failed: #{failed_names}")
        {:stop, :normal, state}

      {:error, _reason} ->
        Logger.error("Failed to update DAG execution status")
        {:stop, :normal, state}
    end
  end

  defp handle_dag_pause(state, result) do
    Logger.info("DAG execution paused: #{length(result.completed_steps)} completed so far")

    # Use ExecutionPersistence for atomic update + outbox event
    case ExecutionPersistence.persist_dag_result(state.execution, :paused, result) do
      {:ok, execution} ->
        state = %{state | execution: execution, status: :paused, control_signal: nil}
        persist_log(state, :info, "DAG execution paused")
        {:noreply, state}

      {:error, _reason} ->
        Logger.error("Failed to update DAG execution status")
        {:noreply, %{state | control_signal: nil}}
    end
  end

  # ============================================================================
  # Control Signal Handling
  # ============================================================================

  defp check_control_signal(%{control_signal: :pause} = state) do
    {:pause, state}
  end

  defp check_control_signal(%{control_signal: :abort} = state) do
    {:abort, state}
  end

  defp check_control_signal(state) do
    {:continue, state}
  end

  # Forward control signals to the DAG executor Task if it's running
  defp forward_signal_to_dag_executor(%{dag_task: %Task{pid: pid}}, signal) when is_pid(pid) do
    if Process.alive?(pid) do
      send(pid, {:control_signal, signal})
      Logger.debug("Forwarded #{signal} signal to DAG executor #{inspect(pid)}")
    end
  end

  defp forward_signal_to_dag_executor(_state, _signal), do: :ok

  defp handle_abort(state) do
    state = update_status(state, :cancelled)
    persist_log(state, :warn, "Execution cancelled")
    # Note: update_status already broadcasts {:status_changed, ...}
    {:stop, :normal, state}
  end

  defp handle_abort_with_message(state, message) do
    state =
      update_status(state, :failed, %{
        error_message: message,
        error_step_index: state.current_step_index
      })

    persist_log(state, :error, "Execution aborted: #{message}")
    # Note: update_status already broadcasts {:status_changed, ...}
    {:stop, :normal, state}
  end

  defp handle_completion(state) do
    state = update_status(state, :completed, %{completed_at: DateTime.utc_now()})
    persist_log(state, :info, "Execution completed successfully")
    # Note: update_status already broadcasts {:status_changed, ...}
    {:stop, :normal, state}
  end

  defp handle_failure(state, step_index, reason) do
    error_message = format_error_reason(reason)

    state =
      update_status(state, :failed, %{
        error_message: error_message,
        error_step_index: step_index
      })

    persist_log(state, :error, "Step #{step_index} failed: #{error_message}")
    # Note: update_status already broadcasts {:status_changed, ...}
    {:stop, :normal, state}
  end

  # ============================================================================
  # Persistence
  # ============================================================================

  defp update_status(state, new_status, extra_attrs \\ %{}) do
    attrs = Map.merge(%{status: new_status}, extra_attrs)

    case Procedures.update_execution_status(state.execution, attrs) do
      {:ok, execution} ->
        broadcast(state, {:status_changed, new_status, execution})
        %{state | execution: execution, status: new_status}

      {:error, _changeset} ->
        Logger.error("Failed to update execution status to #{new_status}")
        %{state | status: new_status}
    end
  end

  defp persist_checkpoint(state) do
    # Serialize Luerl state for resume
    # Note: Full Luerl state serialization is complex - for now just save step index
    attrs = %{
      current_step_index: state.current_step_index
      # checkpoint_state: :erlang.term_to_binary(state.lua_state)
    }

    case Procedures.update_execution_status(state.execution, attrs) do
      {:ok, execution} ->
        %{state | execution: execution}

      {:error, _} ->
        state
    end
  end

  defp persist_log(state, level, message) do
    attrs = %{
      execution_id: state.execution_id,
      timestamp: DateTime.utc_now(),
      level: level,
      message: message,
      step_index: state.current_step_index
    }

    %ProcedureLog{}
    |> ProcedureLog.changeset(attrs)
    |> Repo.insert()

    # Also broadcast for real-time UI updates
    broadcast(state, {:log, level, message})
  end

  # ============================================================================
  # Broadcasting
  # ============================================================================

  defp broadcast(state, message) do
    topic = "procedure:#{state.execution_id}"
    Phoenix.PubSub.broadcast(Cadence.PubSub, topic, message)
  end

  defp broadcast_step_event(state, step_index, step_info, event_type) do
    event =
      case event_type do
        :step_started ->
          ProcedureExecutionEvent.step_started(state.execution, step_index, step_info)

        :step_completed ->
          ProcedureExecutionEvent.step_completed(state.execution, step_index, step_info)
      end

    # Broadcast to mission topic for automations/other subscribers
    mission_topic = "mission:#{state.execution.mission_id}:procedures"
    Phoenix.PubSub.broadcast(Cadence.PubSub, mission_topic, {:procedure_event, event})

    # Also broadcast legacy format to execution-specific topic for UI subscribers
    broadcast(state, {event_type, step_index, step_info})
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp via_tuple(execution_id) do
    {:via, Registry, {Cadence.ProcedureRegistry, execution_id}}
  end

  # Format error reasons for storage - handles various error types including Luerl parse errors
  defp format_error_reason(reason) when is_binary(reason), do: reason
  defp format_error_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error_reason(reason) when is_list(reason), do: inspect(reason)
  defp format_error_reason({:lua_error, error, _stacktrace}), do: "Lua error: #{inspect(error)}"
  defp format_error_reason(reason), do: inspect(reason)
end
