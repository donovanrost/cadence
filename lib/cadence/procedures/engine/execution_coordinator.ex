defmodule Cadence.Procedures.Engine.ExecutionCoordinator do
  @moduledoc """
  Per-mission coordinator for procedure executions.

  The ExecutionCoordinator manages all procedure executions for a mission:

  1. **Tracking** - Maintains a registry of active executions
  2. **Concurrency** - Enforces limits on simultaneous executions
  3. **Control** - Routes pause/abort/resume signals to execution processes
  4. **Broadcasting** - Notifies subscribers of execution status changes

  ## PubSub Topics

  Publishes to:
  - `mission:<mission_id>:procedures` - Execution status changes

  ## Broadcast Messages

  All execution lifecycle events are broadcast as:

      {:procedure_event, %ProcedureExecutionEvent{}}

  Event types include:
  - `:started` - Execution began
  - `:completed` - Execution finished successfully
  - `:failed` - Execution encountered error
  - `:paused` - Execution paused
  - `:cancelled` - Execution cancelled

  See `Cadence.Procedures.Events.ProcedureExecutionEvent` for details.

  ## Usage

      # Start as part of mission supervision tree
      {ExecutionCoordinator, mission_id: mission.id, organization_id: org.id}

      # Start an execution
      {:ok, execution} = ExecutionCoordinator.start_execution(mission_id, procedure_id, opts)

      # Control an execution
      :ok = ExecutionCoordinator.pause(mission_id, execution_id)
      :ok = ExecutionCoordinator.resume(mission_id, execution_id)
      :ok = ExecutionCoordinator.abort(mission_id, execution_id)
  """

  use GenServer
  require Logger

  alias Cadence.Procedures
  alias Cadence.Procedures.Engine.ExecutionProcess
  alias Cadence.Procedures.Events.ProcedureExecutionEvent

  @default_max_concurrent 10

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :organization_id,
      :pubsub_topic,
      active_executions: %{},
      max_concurrent: 10
    ]
  end

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(mission_id))
  end

  @doc """
  Returns the PID of the coordinator for a mission.
  """
  def whereis(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, {mission_id, :procedure_coordinator}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Starts a new procedure execution.

  ## Options

  - `:version_id` - Specific version to run (defaults to current approved)
  - `:target_id` - Target for target-scoped procedures
  - `:parameters` - Runtime parameters
  - `:user_id` - User initiating the execution
  - `:triggered_by` - Trigger type (:manual, :schedule, :event)
  - `:resume_from_execution_id` - Copy completed step events from a previous execution for retry

  ## Returns

  - `{:ok, %ProcedureExecution{}}` - Execution started
  - `{:error, :at_concurrency_limit}` - Too many concurrent executions
  - `{:error, :procedure_not_found}` - Procedure doesn't exist
  - `{:error, :no_approved_version}` - No approved version available
  """
  def start_execution(mission_id, procedure_id, opts \\ []) do
    GenServer.call(via_tuple(mission_id), {:start_execution, procedure_id, opts})
  end

  @doc """
  Pauses an execution at the next safe point.
  """
  def pause(mission_id, execution_id) do
    GenServer.call(via_tuple(mission_id), {:control, execution_id, :pause})
  end

  @doc """
  Resumes a paused execution.
  """
  def resume(mission_id, execution_id) do
    GenServer.call(via_tuple(mission_id), {:control, execution_id, :resume})
  end

  @doc """
  Aborts an execution.
  """
  def abort(mission_id, execution_id) do
    GenServer.call(via_tuple(mission_id), {:control, execution_id, :abort})
  end

  @doc """
  Gets the list of active executions for the mission.
  """
  def list_active(mission_id) do
    GenServer.call(via_tuple(mission_id), :list_active)
  end

  @doc """
  Gets execution counts by status.
  """
  def get_counts(mission_id) do
    GenServer.call(via_tuple(mission_id), :get_counts)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    organization_id = Keyword.fetch!(opts, :organization_id)
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    Logger.info("Starting ExecutionCoordinator for mission #{mission_id}")

    state = %State{
      mission_id: mission_id,
      organization_id: organization_id,
      pubsub_topic: "mission:#{mission_id}:procedures",
      max_concurrent: max_concurrent
    }

    # Load any running executions from database (recovery after restart)
    state = recover_active_executions(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:start_execution, procedure_id, opts}, _from, state) do
    case do_start_execution(procedure_id, opts, state) do
      {:ok, execution, new_state} ->
        {:reply, {:ok, execution}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:control, execution_id, signal}, _from, state) do
    result = do_control(execution_id, signal, state)
    {:reply, result, state}
  end

  def handle_call(:list_active, _from, state) do
    executions =
      state.active_executions
      |> Map.values()
      |> Enum.map(& &1.execution)

    {:reply, executions, state}
  end

  def handle_call(:get_counts, _from, state) do
    counts =
      state.active_executions
      |> Map.values()
      |> Enum.reduce(%{running: 0, paused: 0, pending: 0}, fn entry, acc ->
        status = entry.execution.status
        Map.update(acc, status, 1, &(&1 + 1))
      end)

    {:reply, counts, state}
  end

  @impl true
  def handle_info({:status_changed, new_status, execution}, state) do
    # Only handle executions for this mission
    if execution.mission_id == state.mission_id do
      state = handle_status_change(new_status, execution, state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Handle execution process crash
    case find_execution_by_ref(state, ref) do
      nil ->
        {:noreply, state}

      {execution_id, _entry} ->
        Logger.warning(
          "Execution process crashed: execution_id=#{execution_id}, reason=#{inspect(reason)}"
        )

        state = remove_execution(state, execution_id)
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_start_execution(procedure_id, opts, state) do
    # Check concurrency limit
    if map_size(state.active_executions) >= state.max_concurrent do
      {:error, :at_concurrency_limit}
    else
      case Procedures.get_procedure(procedure_id) do
        nil ->
          {:error, :procedure_not_found}

        procedure ->
          # Determine which version to use
          version_id = opts[:version_id] || procedure.current_version_id

          if is_nil(version_id) do
            {:error, :no_approved_version}
          else
            start_execution_process(procedure, version_id, opts, state)
          end
      end
    end
  end

  defp start_execution_process(procedure, version_id, opts, state) do
    alias Cadence.Procedures.Events.StepEvent

    # Create execution record
    execution_attrs = %{
      procedure_id: procedure.id,
      procedure_version_id: version_id,
      organization_id: procedure.organization_id,
      mission_id: procedure.mission_id || state.mission_id,
      target_id: opts[:target_id],
      parameters: opts[:parameters] || %{},
      triggered_by: opts[:triggered_by] || :manual,
      triggered_by_user_id: opts[:user_id]
    }

    with {:ok, execution} <- Procedures.create_execution(execution_attrs),
         :ok <- maybe_copy_step_events(execution, opts[:resume_from_execution_id]),
         {:ok, pid} <- start_process(execution.id) do
      # Monitor the execution process
      ref = Process.monitor(pid)

      # Subscribe to this execution's status updates
      Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution.id}")

      # Track in state
      entry = %{
        execution: execution,
        pid: pid,
        ref: ref,
        started_at: DateTime.utc_now()
      }

      new_state = %{
        state
        | active_executions: Map.put(state.active_executions, execution.id, entry)
      }

      # Broadcast formal event
      event = ProcedureExecutionEvent.started(execution)
      broadcast(state, {:procedure_event, event})

      {:ok, execution, new_state}
    end
  end

  defp start_process(execution_id) do
    DynamicSupervisor.start_child(
      Cadence.Procedures.ExecutionSupervisor,
      {ExecutionProcess, execution_id: execution_id}
    )
  end

  defp do_control(execution_id, signal, state) do
    case Map.get(state.active_executions, execution_id) do
      nil ->
        {:error, :not_found}

      %{execution: execution} = entry ->
        case signal do
          :pause ->
            # Optimistically update to :pausing immediately so the UI updates
            # even if the execution process is blocked in a long-running step.
            # The execution process will later transition to :paused when it
            # actually pauses at the next checkpoint.
            if execution.status == :running do
              case Procedures.update_execution_status(execution, %{status: :pausing}) do
                {:ok, updated_execution} ->
                  # Update our local cache
                  updated_entry = %{entry | execution: updated_execution}

                  new_active =
                    Map.put(state.active_executions, execution_id, updated_entry)

                  # Broadcast the status change for immediate UI update
                  event = ProcedureExecutionEvent.pausing(updated_execution)
                  broadcast(%{state | active_executions: new_active}, {:procedure_event, event})

                  # Also broadcast on the execution-specific topic
                  Phoenix.PubSub.broadcast(
                    Cadence.PubSub,
                    "procedure:#{execution_id}",
                    {:status_changed, :pausing, updated_execution}
                  )

                {:error, _} ->
                  :ok
              end
            end

            # Send the pause signal to the execution process
            ExecutionProcess.pause(execution_id)

          :resume ->
            ExecutionProcess.resume(execution_id)

          :abort ->
            ExecutionProcess.abort(execution_id)
        end
    end
  end

  defp handle_status_change(new_status, execution, state) do
    case new_status do
      :completed ->
        event = ProcedureExecutionEvent.completed(execution)
        broadcast(state, {:procedure_event, event})
        remove_execution(state, execution.id)

      :failed ->
        event = ProcedureExecutionEvent.failed(execution)
        broadcast(state, {:procedure_event, event})
        remove_execution(state, execution.id)

      :cancelled ->
        event = ProcedureExecutionEvent.cancelled(execution)
        broadcast(state, {:procedure_event, event})
        remove_execution(state, execution.id)

      :pausing ->
        event = ProcedureExecutionEvent.pausing(execution)
        broadcast(state, {:procedure_event, event})
        update_execution(state, execution)

      :paused ->
        event = ProcedureExecutionEvent.paused(execution)
        broadcast(state, {:procedure_event, event})
        update_execution(state, execution)

      :running ->
        # Check if this is a resume (was previously paused)
        previous_status = get_previous_status(state, execution.id)

        if previous_status == :paused do
          event = ProcedureExecutionEvent.resumed(execution)
          broadcast(state, {:procedure_event, event})
        end

        update_execution(state, execution)

      _ ->
        state
    end
  end

  defp get_previous_status(state, execution_id) do
    case Map.get(state.active_executions, execution_id) do
      nil -> nil
      %{execution: prev_execution} -> prev_execution.status
    end
  end

  defp update_execution(state, execution) do
    case Map.get(state.active_executions, execution.id) do
      nil ->
        state

      entry ->
        updated_entry = %{entry | execution: execution}

        %{
          state
          | active_executions: Map.put(state.active_executions, execution.id, updated_entry)
        }
    end
  end

  defp remove_execution(state, execution_id) do
    case Map.get(state.active_executions, execution_id) do
      nil ->
        state

      %{ref: ref} ->
        Process.demonitor(ref, [:flush])
        # Unsubscribe from this execution's topic
        Phoenix.PubSub.unsubscribe(Cadence.PubSub, "procedure:#{execution_id}")
        %{state | active_executions: Map.delete(state.active_executions, execution_id)}
    end
  end

  defp find_execution_by_ref(state, ref) do
    Enum.find(state.active_executions, fn {_id, entry} -> entry.ref == ref end)
  end

  defp recover_active_executions(state) do
    # On startup, we log any executions that were in non-terminal states
    # The OrphanedExecutionCleanupWorker handles actual cleanup asynchronously,
    # which gives time for ExecutionProcesses to potentially restart and reclaim them.
    #
    # For :paused executions, they remain valid and can be resumed by users.
    # For :running and :pausing, they'll be cleaned up by the worker if orphaned.

    running_count =
      Procedures.list_executions(mission_id: state.mission_id, status: :running)
      |> length()

    pausing_count =
      Procedures.list_executions(mission_id: state.mission_id, status: :pausing)
      |> length()

    paused_count =
      Procedures.list_executions(mission_id: state.mission_id, status: :paused)
      |> length()

    if running_count > 0 or pausing_count > 0 do
      Logger.info(
        "ExecutionCoordinator startup: Found #{running_count} running, " <>
          "#{pausing_count} pausing, #{paused_count} paused executions. " <>
          "Orphaned executions will be cleaned up by background worker."
      )
    end

    state
  end

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(Cadence.PubSub, state.pubsub_topic, message)
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :procedure_coordinator}}}
  end

  # Copy completed step events from a previous execution for retry functionality
  defp maybe_copy_step_events(_execution, nil), do: :ok

  defp maybe_copy_step_events(new_execution, resume_from_execution_id) do
    alias Cadence.Procedures.Events.StepEvent

    Logger.info(
      "Copying completed step events from execution #{resume_from_execution_id} to #{new_execution.id}"
    )

    # Get all step events from the old execution
    events = StepEvent.list_for_execution(resume_from_execution_id)

    # Only copy "completed" events (not failed, blocked, etc.)
    # The event_type is a string like "procedure_step_completed"
    completed_events =
      events
      |> Enum.filter(fn event -> event.event_type == "procedure_step_completed" end)

    # Insert them for the new execution
    Enum.each(completed_events, fn event ->
      step_name = event.payload["step_name"]
      data = event.payload["data"]
      StepEvent.insert!(new_execution, step_name, :completed, data)
    end)

    Logger.info("Copied #{length(completed_events)} completed step events for retry")

    :ok
  rescue
    e ->
      Logger.error("Failed to copy step events: #{Exception.message(e)}")
      :ok
  end
end
