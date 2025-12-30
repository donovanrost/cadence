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

  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Ports.Persistence.Procedures.ExecutionPersistence, as: ExecutionPersistencePort
  alias Cadence.Ports.Repository.Procedures.ExecutionOperations
  alias Cadence.Procedures.Dag.{Executor, StepExecutor}
  alias Cadence.Procedures.Engine.ExecutionCore
  alias Cadence.Procedures.Events.ProcedureExecutionEvent
  alias Cadence.Procedures.Events.StepEvent
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
      :execution_ops,
      :persistence,
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
  Starts execution for a pending execution process.
  """
  def start_execution(execution_id) do
    case whereis(execution_id) do
      nil ->
        {:error, :not_found}

      pid ->
        send(pid, :start_execution)
        :ok
    end
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
    execution_ops = ExecutionOperations.impl()
    persistence = Keyword.get(opts, :persistence, ExecutionPersistencePort.impl())

    Logger.info(ExecutionCore.execution_starting_message(execution_id))

    # Load execution with associations
    execution =
      case execution_ops.find_execution(execution_id) do
        {:ok, execution} -> normalize_execution(execution)
        {:error, :not_found} -> raise "Execution not found: #{execution_id}"
      end

    {procedure, version} = load_procedure_and_version(execution)

    # Build context for Cadence API
    context = ExecutionCore.build_api_context(execution, version, execution_id, self())

    # Initialize Luerl state
    lua_state = :luerl.init()
    lua_state = CadenceApi.install(lua_state, context)

    state = %State{
      execution_id: execution_id,
      execution: execution,
      procedure: procedure,
      version: version,
      execution_ops: execution_ops,
      persistence: persistence,
      lua_state: lua_state,
      context: context,
      current_step_index: execution.current_step_index || 0,
      status: execution.status
    }

    # Start execution asynchronously
    # Note: Late-joining clients derive state from outbox events (source of truth),
    # so there's no need for artificial delays. The ExecutionChannel handles this
    # via derive_step_state_from_events on join.
    if execution.status == :pending and autostart_pending?() do
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
    Logger.info(ExecutionCore.control_signal_received(signal, state.execution_id))

    case signal do
      :pause when state.status in [:running, :pausing] ->
        # The coordinator may have already transitioned to :pausing optimistically.
        # If not, do it now. Either way, set the control signal.
        state =
          if state.status == :running do
            new_state = update_status(state, :pausing)

            persist_log(new_state, :info, ExecutionCore.pause_requested_message())

            new_state
          else
            # Already in :pausing, just log
            persist_log(state, :info, ExecutionCore.pause_requested_message())
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
        transition = ExecutionCore.resume_transition()
        state = update_status(state, transition.status, transition.attrs)
        persist_log(state, transition.log_level, transition.log_message)
        send(self(), :continue_execution)
        {:noreply, %{state | control_signal: nil}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:start_execution, state) do
    start_attrs = ExecutionCore.start_attrs(DateTime.utc_now())
    state = update_status(state, start_attrs.status, start_attrs.attrs)
    send(self(), :continue_execution)
    {:noreply, state}
  end

  def handle_info(:continue_execution, state) do
    case ExecutionCore.control_action(state) do
      {:pause, state} ->
        transition = ExecutionCore.pause_transition()
        state = update_status(state, transition.status, transition.attrs)
        persist_log(state, transition.log_level, transition.log_message)
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
    Logger.error(ExecutionCore.dag_executor_crashed_message(reason))
    handle_failure(state, 0, ExecutionCore.dag_executor_failure_reason(reason))
  end

  # Messages from Cadence API callbacks
  def handle_info({:log, level, message}, state) do
    # persist_log also broadcasts for real-time UI updates
    persist_log(state, level, message)
    {:noreply, state}
  end

  def handle_info({:checkpoint, name}, state) do
    Logger.debug(ExecutionCore.checkpoint_message(name, state.current_step_index))
    persist_checkpoint(state)
    broadcast(state, {:checkpoint, name})
    {:noreply, state}
  end

  def handle_info({:command_sent, name, log_id}, state) do
    persist_log(state, :info, ExecutionCore.command_sent_message(name, log_id))
    {:noreply, state}
  end

  def handle_info({:command_failed, name, reason}, state) do
    persist_log(state, :error, ExecutionCore.command_failed_message(name, reason))
    {:noreply, state}
  end

  def handle_info({:waiting, milliseconds}, state) do
    persist_log(state, :debug, ExecutionCore.wait_message(milliseconds))
    {:noreply, state}
  end

  def handle_info({:waiting_for_telemetry, item, op, value}, state) do
    persist_log(state, :debug, ExecutionCore.wait_for_message(item, op, value))
    {:noreply, state}
  end

  def handle_info({:abort_requested, message}, state) do
    persist_log(state, :warn, ExecutionCore.abort_requested_message(message))
    {:noreply, %{state | control_signal: :abort}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(ExecutionCore.execution_terminating_message(state.execution_id, reason))

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

    Logger.info(ExecutionCore.execute_next_message(state.procedure.type))

    case ExecutionCore.execution_mode(state.procedure.type) do
      {:ok, :script} ->
        execute_script(state, source)

      {:ok, :dag} ->
        execute_dag_sequence(state, source)

      {:error, reason} ->
        handle_failure(state, 0, reason)
    end
  end

  defp execute_next(state) do
    {:noreply, state}
  end

  defp execute_script(state, source) do
    case ExecutionCore.script_source(source) do
      {:ok, code} ->
        step_info = %{type: "script"}
        broadcast_step_event(state, 0, step_info, :step_started)

        try do
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

      {:error, reason} ->
        handle_failure(state, 0, reason)
    end
  end

  # DAG mode: execute steps in parallel based on dependencies
  # We spawn the DAG executor in a separate Task to avoid blocking the GenServer.
  # This allows the GenServer to respond to get_state calls while execution runs.
  defp execute_dag_sequence(state, source) do
    case ExecutionCore.dag_source(source) do
      {:ok, %{"steps" => steps}} ->
        Logger.info(ExecutionCore.dag_start_message(map_size(steps)))

        # Build execution context
        dag_context = ExecutionCore.build_dag_context(state)

        # Get DAG options from source
        default_on_fail = ExecutionCore.on_step_failure(state.version.source)

        # Progress callback - broadcasts progress events for wait/wait_for steps
        # This is lightweight (no DB writes) to avoid performance issues with frequent updates
        on_progress = fn step_name, progress_data ->
          topic = "procedure:#{state.execution_id}"
          EventPublisher.impl().publish(topic, {:dag_step_progress, step_name, progress_data})
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
          state.persistence.persist_step_event(execution, step_name, status, data)
        end

        # Get pre-completed steps and their results for resume support
        # Derive from outbox events (source of truth) rather than execution record
        step_state =
          state.persistence.list_step_events(state.execution_id)
          |> StepEvent.derive_state()

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

      {:error, reason} ->
        handle_failure(state, 0, reason)
    end
  end

  defp autostart_pending? do
    Application.get_env(:cadence, __MODULE__, [])
    |> Keyword.get(:autostart_pending?, true)
  end

  defp handle_dag_completion(state, result) do
    Logger.info(
      ExecutionCore.dag_completion_summary(
        length(result.completed_steps),
        length(result.skipped_steps)
      )
    )

    # Use ExecutionPersistence for atomic update + outbox event
    case state.persistence.persist_dag_result(state.execution, :completed, result) do
      {:ok, execution} ->
        execution = normalize_execution(execution)
        state = %{state | execution: execution, status: :completed}
        persist_log(state, :info, ExecutionCore.dag_completed_message())
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error(ExecutionCore.dag_update_failure_message(reason))
        {:stop, :normal, state}
    end
  end

  defp handle_dag_failure(state, result) do
    Logger.error(ExecutionCore.dag_failed_message(result.failed_steps))

    # Use ExecutionPersistence for atomic update + outbox event
    case state.persistence.persist_dag_result(state.execution, :failed, result) do
      {:ok, execution} ->
        execution = normalize_execution(execution)
        state = %{state | execution: execution, status: :failed}
        persist_log(state, :error, ExecutionCore.dag_failed_message(result.failed_steps))
        {:stop, :normal, state}

      {:error, _reason} ->
        Logger.error(ExecutionCore.dag_persist_failure_message())
        {:stop, :normal, state}
    end
  end

  defp handle_dag_pause(state, result) do
    Logger.info(ExecutionCore.dag_paused_summary(length(result.completed_steps)))

    # Use ExecutionPersistence for atomic update + outbox event
    case state.persistence.persist_dag_result(state.execution, :paused, result) do
      {:ok, execution} ->
        execution = normalize_execution(execution)
        state = %{state | execution: execution, status: :paused, control_signal: nil}
        persist_log(state, :info, ExecutionCore.dag_paused_message())
        {:noreply, state}

      {:error, _reason} ->
        Logger.error(ExecutionCore.dag_persist_failure_message())
        {:noreply, %{state | control_signal: nil}}
    end
  end

  # ============================================================================
  # Control Signal Handling
  # ============================================================================

  # Forward control signals to the DAG executor Task if it's running
  defp forward_signal_to_dag_executor(%{dag_task: %Task{pid: pid}}, signal) when is_pid(pid) do
    if Process.alive?(pid) do
      send(pid, {:control_signal, signal})
      Logger.debug(ExecutionCore.forward_signal_message(signal, pid))
    end
  end

  defp forward_signal_to_dag_executor(_state, _signal), do: :ok

  defp handle_abort(state) do
    transition = ExecutionCore.abort_transition(state.current_step_index)
    state = update_status(state, transition.status, transition.attrs)
    persist_log(state, transition.log_level, transition.log_message)
    # Note: update_status already broadcasts {:status_changed, ...}
    {:stop, :normal, state}
  end

  defp handle_abort_with_message(state, message) do
    transition = ExecutionCore.abort_transition(state.current_step_index, message)
    state = update_status(state, transition.status, transition.attrs)
    persist_log(state, transition.log_level, transition.log_message)
    # Note: update_status already broadcasts {:status_changed, ...}
    {:stop, :normal, state}
  end

  defp handle_completion(state) do
    transition = ExecutionCore.completion_transition(DateTime.utc_now())
    state = update_status(state, transition.status, transition.attrs)
    persist_log(state, transition.log_level, transition.log_message)
    # Note: update_status already broadcasts {:status_changed, ...}
    {:stop, :normal, state}
  end

  defp handle_failure(state, step_index, reason) do
    transition = ExecutionCore.failure_transition(step_index, reason)
    state = update_status(state, transition.status, transition.attrs)
    persist_log(state, transition.log_level, transition.log_message)
    # Note: update_status already broadcasts {:status_changed, ...}
    {:stop, :normal, state}
  end

  # ============================================================================
  # Persistence
  # ============================================================================

  defp update_status(state, new_status, extra_attrs \\ %{}) do
    attrs = Map.merge(%{status: new_status}, extra_attrs)

    case state.execution_ops.update_execution(state.execution.id, attrs) do
      {:ok, execution} ->
        execution = normalize_execution(execution)
        broadcast(state, {:status_changed, new_status, execution})
        %{state | execution: execution, status: new_status}

      {:error, _reason} ->
        Logger.error(ExecutionCore.status_update_failure_message(new_status))
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

    case state.execution_ops.update_execution(state.execution.id, attrs) do
      {:ok, execution} ->
        execution = normalize_execution(execution)
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

    _ = state.execution_ops.create_log(attrs)

    # Also broadcast for real-time UI updates
    broadcast(state, {:log, level, message})
  end

  defp load_procedure_and_version(execution) do
    procedure = Map.get(execution, :procedure)
    version = Map.get(execution, :procedure_version)

    cond do
      assoc_loaded?(procedure) and assoc_loaded?(version) ->
        {procedure, version}

      is_struct(execution, Cadence.Procedures.ProcedureExecution) ->
        execution = Repo.preload(execution, [:procedure, :procedure_version])
        {execution.procedure, execution.procedure_version}

      true ->
        raise "Execution is missing procedure associations"
    end
  end

  defp assoc_loaded?(%Ecto.Association.NotLoaded{}), do: false
  defp assoc_loaded?(nil), do: false
  defp assoc_loaded?(_), do: true

  defp normalize_execution(%Cadence.Procedures.ProcedureExecution{} = execution), do: execution

  defp normalize_execution(execution),
    do: struct(Cadence.Procedures.ProcedureExecution, execution)

  # ============================================================================
  # Broadcasting
  # ============================================================================

  defp event_publisher, do: EventPublisher.impl()

  defp broadcast(state, message) do
    topic = "procedure:#{state.execution_id}"
    event_publisher().publish(topic, message)
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
    event_publisher().publish(mission_topic, {:procedure_event, event})

    # Also broadcast legacy format to execution-specific topic for UI subscribers
    broadcast(state, {event_type, step_index, step_info})
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp via_tuple(execution_id) do
    {:via, Registry, {Cadence.ProcedureRegistry, execution_id}}
  end
end
