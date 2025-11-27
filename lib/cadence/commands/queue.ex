defmodule Cadence.Commands.Queue do
  @moduledoc """
  Mission-scoped command queue manager.

  Processes queued commands in priority order with support for:
  - Priority-based ordering (0=emergency, 5=background)
  - Scheduled execution (future-dated commands)
  - Automatic retry on transient failures
  - Pause/resume during anomalies
  - Rate limiting

  ## Architecture

  One Queue GenServer per mission, added to MissionInstance supervision tree.
  Works alongside Dispatcher - Queue enqueues, processes, and calls Dispatcher
  to execute each command.

  ## Queue Processing

  Commands are processed in order by:
  1. Priority (lower number = higher priority)
  2. Sequence number (FIFO within same priority)
  3. Scheduled time (only process if scheduled_at <= now)

  ## Example

      # Enqueue a command
      {:ok, entry} = Queue.enqueue(mission_id, "SET_MODE", %{mode: 1},
        target: target_id,
        priority: 2
      )

      # Pause queue during anomaly
      :ok = Queue.pause(mission_id)

      # Resume queue
      :ok = Queue.resume(mission_id)

      # Check queue status
      %{paused: false, pending: 5, executing: 1} = Queue.status(mission_id)
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Commands.{QueueEntry, Dispatcher}
  alias Cadence.Missions

  @process_interval_ms 100
  @retry_delay_ms 1000
  @max_concurrent 1

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :mission,
      paused: false,
      processing: false,
      executing_count: 0,
      sequence_counter: 0,
      process_timer: nil
    ]
  end

  ## Client API

  @doc """
  Starts the queue for a mission.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @doc """
  Returns the via tuple for registry lookup.
  """
  def via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :command_queue}}}
  end

  @doc """
  Returns the PID of a queue by mission_id.
  """
  def whereis(mission_id) do
    case Registry.lookup(Cadence.MissionRegistry, {mission_id, :command_queue}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Enqueues a command for execution.

  ## Options

  - `:target` or `:target_id` - Target ID (required)
  - `:priority` - Priority level 0-5 (default: 3)
  - `:scheduled_at` - Execute at or after this time
  - `:expires_at` - Cancel if not executed by this time
  - `:max_attempts` - Max retry attempts (default: 3)
  - `:user_id` - User performing the action
  - `:immediate` - Skip queue, execute immediately (default: false)

  ## Returns

  - `{:ok, queue_entry}` - Command queued successfully
  - `{:ok, command_log_id}` - Command executed immediately (if :immediate)
  - `{:error, reason}` - Enqueue failed
  """
  def enqueue(mission_id, command_name, params, opts \\ []) do
    if Keyword.get(opts, :immediate, false) do
      # Bypass queue, dispatch immediately
      Dispatcher.dispatch(mission_id, command_name, params, opts)
    else
      GenServer.call(via_tuple(mission_id), {:enqueue, command_name, params, opts})
    end
  end

  @doc """
  Pauses queue processing. Commands can still be enqueued but won't execute.
  """
  def pause(mission_id) do
    GenServer.call(via_tuple(mission_id), :pause)
  end

  @doc """
  Resumes queue processing after a pause.
  """
  def resume(mission_id) do
    GenServer.call(via_tuple(mission_id), :resume)
  end

  @doc """
  Cancels a queued command.
  """
  def cancel(mission_id, entry_id) do
    GenServer.call(via_tuple(mission_id), {:cancel, entry_id})
  end

  @doc """
  Cancels all pending commands for a target.
  """
  def cancel_all_for_target(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id), {:cancel_all_for_target, target_id})
  end

  @doc """
  Clears all pending commands from the queue.
  """
  def clear(mission_id) do
    GenServer.call(via_tuple(mission_id), :clear)
  end

  @doc """
  Gets the current queue status.
  """
  def status(mission_id) do
    GenServer.call(via_tuple(mission_id), :status)
  end

  @doc """
  Lists pending queue entries.
  """
  def list_pending(mission_id, opts \\ []) do
    GenServer.call(via_tuple(mission_id), {:list_pending, opts})
  end

  @doc """
  Moves a command to a different position in the queue.
  """
  def reorder(mission_id, entry_id, new_priority) do
    GenServer.call(via_tuple(mission_id), {:reorder, entry_id, new_priority})
  end

  ## Server Callbacks

  @impl true
  def init(mission_id) do
    Logger.info("Starting CommandQueue for mission_id=#{mission_id}")

    mission = Missions.get_mission!(mission_id)

    # Get the highest sequence number from existing entries
    sequence_counter = get_max_sequence(mission_id) || 0

    state = %State{
      mission_id: mission_id,
      mission: mission,
      sequence_counter: sequence_counter
    }

    # Start processing loop
    {:ok, schedule_process(state)}
  end

  @impl true
  def handle_call({:enqueue, command_name, params, opts}, _from, state) do
    case do_enqueue(command_name, params, opts, state) do
      {:ok, entry, new_state} ->
        {:reply, {:ok, entry}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:pause, _from, state) do
    Logger.info("Pausing command queue for mission_id=#{state.mission_id}")
    {:reply, :ok, %{state | paused: true}}
  end

  def handle_call(:resume, _from, state) do
    Logger.info("Resuming command queue for mission_id=#{state.mission_id}")
    new_state = %{state | paused: false}
    {:reply, :ok, schedule_process(new_state)}
  end

  def handle_call({:cancel, entry_id}, _from, state) do
    case do_cancel(entry_id, state.mission_id) do
      {:ok, entry} -> {:reply, {:ok, entry}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel_all_for_target, target_id}, _from, state) do
    count = do_cancel_all_for_target(target_id, state.mission_id)
    {:reply, {:ok, count}, state}
  end

  def handle_call(:clear, _from, state) do
    count = do_clear(state.mission_id)
    {:reply, {:ok, count}, state}
  end

  def handle_call(:status, _from, state) do
    status = %{
      mission_id: state.mission_id,
      paused: state.paused,
      pending: count_by_status(state.mission_id, :pending),
      executing: state.executing_count,
      failed: count_by_status(state.mission_id, :failed)
    }

    {:reply, status, state}
  end

  def handle_call({:list_pending, opts}, _from, state) do
    entries = do_list_pending(state.mission_id, opts)
    {:reply, entries, state}
  end

  def handle_call({:reorder, entry_id, new_priority}, _from, state) do
    case do_reorder(entry_id, new_priority, state.mission_id) do
      {:ok, entry} -> {:reply, {:ok, entry}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:process_queue, state) do
    new_state = process_queue(state)
    {:noreply, schedule_process(new_state)}
  end

  def handle_info({:command_complete, entry_id, result}, state) do
    new_state = handle_command_complete(entry_id, result, state)
    {:noreply, new_state}
  end

  def handle_info({:retry_command, entry_id}, state) do
    # Re-mark as pending to be picked up by next process cycle
    case Repo.get(QueueEntry, entry_id) do
      nil -> :ok
      entry ->
        entry
        |> QueueEntry.execution_changeset(%{status: :pending})
        |> Repo.update()
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp do_enqueue(command_name, params, opts, state) do
    target_id = Keyword.get(opts, :target) || Keyword.get(opts, :target_id)

    if is_nil(target_id) do
      {:error, :target_required}
    else
      sequence = state.sequence_counter + 1

      attrs = %{
        organization_id: state.mission.organization_id,
        mission_id: state.mission_id,
        target_id: target_id,
        command_name: command_name,
        parameters: params,
        priority: Keyword.get(opts, :priority, 3),
        sequence_number: sequence,
        scheduled_at: Keyword.get(opts, :scheduled_at),
        expires_at: Keyword.get(opts, :expires_at),
        max_attempts: Keyword.get(opts, :max_attempts, 3),
        user_id: Keyword.get(opts, :user_id),
        dispatch_opts: opts_to_map(opts)
      }

      case %QueueEntry{} |> QueueEntry.changeset(attrs) |> Repo.insert() do
        {:ok, entry} ->
          Logger.debug("Enqueued command #{command_name} as entry_id=#{entry.id}")
          {:ok, entry, %{state | sequence_counter: sequence}}

        {:error, changeset} ->
          {:error, {:validation, changeset}}
      end
    end
  end

  defp opts_to_map(opts) do
    opts
    |> Keyword.drop([:priority, :scheduled_at, :expires_at, :max_attempts, :user_id, :immediate])
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp do_cancel(entry_id, mission_id) do
    case Repo.get_by(QueueEntry, id: entry_id, mission_id: mission_id) do
      nil ->
        {:error, :not_found}

      %QueueEntry{status: status} when status in [:completed, :cancelled] ->
        {:error, :already_finished}

      %QueueEntry{status: :executing} ->
        {:error, :currently_executing}

      entry ->
        entry
        |> QueueEntry.cancel_changeset()
        |> Repo.update()
    end
  end

  defp do_cancel_all_for_target(target_id, mission_id) do
    {count, _} =
      from(e in QueueEntry,
        where: e.mission_id == ^mission_id,
        where: e.target_id == ^target_id,
        where: e.status == :pending
      )
      |> Repo.update_all(set: [status: :cancelled, updated_at: DateTime.utc_now()])

    count
  end

  defp do_clear(mission_id) do
    {count, _} =
      from(e in QueueEntry,
        where: e.mission_id == ^mission_id,
        where: e.status == :pending
      )
      |> Repo.update_all(set: [status: :cancelled, updated_at: DateTime.utc_now()])

    count
  end

  defp do_list_pending(mission_id, opts) do
    limit = Keyword.get(opts, :limit, 100)
    target_id = Keyword.get(opts, :target_id)

    query =
      from(e in QueueEntry,
        where: e.mission_id == ^mission_id,
        where: e.status == :pending,
        order_by: [asc: e.priority, asc: e.sequence_number],
        limit: ^limit
      )

    query =
      if target_id do
        from(e in query, where: e.target_id == ^target_id)
      else
        query
      end

    Repo.all(query)
  end

  defp do_reorder(entry_id, new_priority, mission_id) do
    case Repo.get_by(QueueEntry, id: entry_id, mission_id: mission_id, status: :pending) do
      nil ->
        {:error, :not_found}

      entry ->
        entry
        |> Ecto.Changeset.change(priority: new_priority)
        |> Repo.update()
    end
  end

  defp process_queue(%State{paused: true} = state), do: state
  defp process_queue(%State{executing_count: count} = state) when count >= @max_concurrent, do: state

  defp process_queue(state) do
    # Check for expired entries first
    expire_old_entries(state.mission_id)

    # Get next entry to process
    case get_next_entry(state.mission_id) do
      nil ->
        state

      entry ->
        execute_entry(entry, state)
    end
  end

  defp get_next_entry(mission_id) do
    now = DateTime.utc_now()

    from(e in QueueEntry,
      where: e.mission_id == ^mission_id,
      where: e.status == :pending,
      where: is_nil(e.scheduled_at) or e.scheduled_at <= ^now,
      order_by: [asc: e.priority, asc: e.sequence_number],
      limit: 1
    )
    |> Repo.one()
  end

  defp execute_entry(entry, state) do
    # Mark as executing
    {:ok, entry} =
      entry
      |> QueueEntry.execution_changeset(%{
        status: :executing,
        attempts: entry.attempts + 1,
        last_attempt_at: DateTime.utc_now()
      })
      |> Repo.update()

    # Execute asynchronously
    parent = self()

    Task.start(fn ->
      result = execute_command(entry, state.mission_id)
      send(parent, {:command_complete, entry.id, result})
    end)

    %{state | executing_count: state.executing_count + 1}
  end

  defp execute_command(entry, mission_id) do
    # Convert stored opts back to keyword list
    opts =
      entry.dispatch_opts
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Keyword.put(:target, entry.target_id)
      |> Keyword.put(:user_id, entry.user_id)
      |> Keyword.put(:skip_queue, true)

    Dispatcher.dispatch(mission_id, entry.command_name, entry.parameters, opts)
  end

  defp handle_command_complete(entry_id, result, state) do
    case Repo.get(QueueEntry, entry_id) do
      nil ->
        %{state | executing_count: max(0, state.executing_count - 1)}

      entry ->
        case result do
          {:ok, command_log_id} ->
            # Success
            entry
            |> QueueEntry.execution_changeset(%{
              status: :completed,
              command_log_id: command_log_id
            })
            |> Repo.update()

            Logger.debug("Queue entry #{entry_id} completed successfully")

          {:error, :requires_confirmation, _info} ->
            # Hazardous command - mark as failed, don't retry
            entry
            |> QueueEntry.execution_changeset(%{
              status: :failed,
              last_error: "Hazardous command requires confirmation - cannot execute from queue"
            })
            |> Repo.update()

          {:error, reason} ->
            handle_failure(entry, reason, state)

          {:error, reason, _details} ->
            handle_failure(entry, reason, state)
        end

        %{state | executing_count: max(0, state.executing_count - 1)}
    end
  end

  defp handle_failure(entry, reason, state) do
    error_msg = inspect(reason)

    if QueueEntry.retriable?(entry) do
      # Schedule retry
      entry
      |> QueueEntry.execution_changeset(%{
        status: :failed,
        last_error: error_msg
      })
      |> Repo.update()

      Process.send_after(self(), {:retry_command, entry.id}, @retry_delay_ms)
      Logger.warning("Queue entry #{entry.id} failed, will retry: #{error_msg}")
    else
      # Max attempts reached
      entry
      |> QueueEntry.execution_changeset(%{
        status: :failed,
        last_error: "Max attempts reached. Last error: #{error_msg}"
      })
      |> Repo.update()

      Logger.error("Queue entry #{entry.id} failed permanently: #{error_msg}")
    end

    state
  end

  defp expire_old_entries(mission_id) do
    now = DateTime.utc_now()

    from(e in QueueEntry,
      where: e.mission_id == ^mission_id,
      where: e.status == :pending,
      where: not is_nil(e.expires_at),
      where: e.expires_at < ^now
    )
    |> Repo.update_all(set: [status: :expired, updated_at: now])
  end

  defp count_by_status(mission_id, status) do
    from(e in QueueEntry,
      where: e.mission_id == ^mission_id,
      where: e.status == ^status,
      select: count(e.id)
    )
    |> Repo.one()
  end

  defp get_max_sequence(mission_id) do
    from(e in QueueEntry,
      where: e.mission_id == ^mission_id,
      select: max(e.sequence_number)
    )
    |> Repo.one()
  end

  defp schedule_process(%State{paused: true} = state), do: state

  defp schedule_process(state) do
    if state.process_timer do
      Process.cancel_timer(state.process_timer)
    end

    timer = Process.send_after(self(), :process_queue, @process_interval_ms)
    %{state | process_timer: timer}
  end
end
