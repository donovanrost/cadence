defmodule Cadence.Runtime.Commands.TargetQueue do
  @moduledoc """
  Target-scoped command queue manager.

  Processes queued commands for a single target in priority order with support for:
  - Priority-based ordering (0=emergency, 5=background)
  - Scheduled execution (future-dated commands)
  - Automatic retry on transient failures
  - Expiration handling

  ## Architecture

  One TargetQueue GenServer per target, managed by TargetPipeline supervisor.
  Works alongside TargetDispatcher - Queue manages "what's next", Dispatcher
  handles "how to send".

  ## Queue Processing

  Commands are processed in order by:
  1. Priority (lower number = higher priority)
  2. Sequence number (FIFO within same priority)
  3. Scheduled time (only process if scheduled_at <= now)
  """

  use GenServer
  require Logger

  alias Cadence.Application.Commanding.QueuePersistence
  alias Cadence.Application.Commanding.QueueSnapshot
  alias Cadence.Domain.Commanding.Entities.QueuedCommand
  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.Runtime.Commands.TargetDispatcher

  # Fallback poll interval - used as safety net for scheduled commands and missed events
  @fallback_poll_interval_ms 10_000
  @retry_delay_ms 1_000

  defmodule State do
    @moduledoc """
    In-memory queue state for O(1) operations.

    The queue maintains local state to avoid DB queries in the hot path:
    - `pending_entries` - Sorted list of pending entries (by priority, sequence)
    - `entries_by_id` - Map for O(1) lookup by entry_id
    - `counts` - Local counters for status queries
    """

    defstruct [
      :mission_id,
      :target_id,
      :organization_id,
      :target,
      pending_entries: [],
      entries_by_id: %{},
      executing: nil,
      counts: %{pending: 0, executing: 0, completed: 0, failed: 0},
      sequence_counter: 0,
      process_timer: nil,
      dispatcher_paused: false
    ]
  end

  ## Client API

  @doc """
  Starts the queue for a target.

  Requires:
  - `mission: mission_entity`
  - `target: target_entity`

  Optional:
  - `queue_snapshot: %QueueSnapshot{}`
  """
  def start_link(opts) do
    {mission, target, snapshot} = extract_mission_target_snapshot(opts)

    GenServer.start_link(__MODULE__, {mission, target, snapshot},
      name: via_tuple(mission.id, target.id)
    )
  end

  @doc """
  Returns the via tuple for registry lookup.
  """
  def via_tuple(mission_id, target_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:target_queue, mission_id, target_id}}}
  end

  @doc """
  Returns the PID of a queue by mission_id and target_id.
  """
  def whereis(mission_id, target_id) do
    case Registry.lookup(Cadence.MissionRegistry, {:target_queue, mission_id, target_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Enqueues a command for execution (in-memory). Control plane persistence is
  notified asynchronously.
  """
  def enqueue(mission_id, target_id, command_name, params, opts \\ []) do
    GenServer.call(via_tuple(mission_id, target_id), {:enqueue, command_name, params, opts})
  end

  @doc """
  Gets the next command ready for dispatch.
  """
  def next(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id, target_id), :next)
  end

  @doc """
  Marks an entry as executing.
  """
  def mark_executing(mission_id, target_id, entry_id) do
    GenServer.call(via_tuple(mission_id, target_id), {:mark_executing, entry_id})
  end

  @doc """
  Attaches a command aggregate ID to an executing entry.
  """
  def attach_command_aggregate_id(mission_id, target_id, entry_id, command_aggregate_id) do
    GenServer.cast(
      via_tuple(mission_id, target_id),
      {:attach_command_aggregate_id, entry_id, command_aggregate_id}
    )
  end

  @doc """
  Reports execution result for a queue entry.
  """
  def complete(mission_id, target_id, entry_id, result) do
    GenServer.cast(via_tuple(mission_id, target_id), {:complete, entry_id, result})
  end

  @doc """
  Cancels a queued command.
  """
  def cancel(mission_id, target_id, entry_id) do
    GenServer.call(via_tuple(mission_id, target_id), {:cancel, entry_id})
  end

  @doc """
  Clears all pending commands for this target.
  """
  def clear(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id, target_id), :clear)
  end

  @doc """
  Gets the current queue status.
  """
  def status(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id, target_id), :status)
  end

  @doc """
  Updates the cached dispatcher paused state.
  """
  def set_dispatcher_paused(mission_id, target_id, paused) do
    GenServer.cast(via_tuple(mission_id, target_id), {:set_dispatcher_paused, paused})
  end

  @doc """
  Manually triggers the dispatcher to check for queued commands.
  """
  def trigger_check(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id, target_id), :trigger_check)
  end

  @doc """
  Lists pending queue entries.
  """
  def list_pending(mission_id, target_id, opts \\ []) do
    GenServer.call(via_tuple(mission_id, target_id), {:list_pending, opts})
  end

  @doc """
  Moves a command to a different position in the queue (priority change).
  """
  def reorder(mission_id, target_id, entry_id, new_priority) do
    GenServer.call(via_tuple(mission_id, target_id), {:reorder, entry_id, new_priority})
  end

  ## Server Callbacks

  @impl true
  def init({%Mission{} = mission, %Target{} = target, snapshot}) do
    Logger.info(
      "Starting TargetQueue for mission_id=#{mission.id}, target=#{target.identifier} (#{target.id})"
    )

    Phoenix.PubSub.subscribe(Cadence.PubSub, "target:#{target.id}:queue")

    state = build_state_from_snapshot(mission, target, snapshot)

    {:ok, schedule_process(state)}
  end

  @impl true
  def handle_call({:enqueue, command_name, params, opts}, _from, state) do
    case do_enqueue(command_name, params, opts, state) do
      {:ok, entry, new_state} ->
        notify_dispatcher(state.mission_id, state.target_id)
        QueuePersistence.notify({:enqueue, entry})
        {:reply, {:ok, entry}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:next, _from, state) do
    if state.dispatcher_paused do
      {:reply, nil, state}
    else
      state = expire_old_entries_local(state)

      case fetch_next_ready_local(state) do
        nil -> {:reply, nil, state}
        entry -> {:reply, entry, state}
      end
    end
  end

  def handle_call({:mark_executing, entry_id}, _from, state) do
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        now = DateTime.utc_now()

        updated_entry = %{
          entry
          | status: :executing,
            attempts: entry.attempts + 1,
            last_attempt_at: now
        }

        new_pending = Enum.reject(state.pending_entries, &(&1.id == entry_id))
        new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)

        new_state = %{
          state
          | pending_entries: new_pending,
            entries_by_id: new_entries_by_id,
            executing: updated_entry
        }

        QueuePersistence.notify({:mark_executing, entry_id, updated_entry.attempts, now})
        {:reply, {:ok, updated_entry}, refresh_counts(new_state)}
    end
  end

  def handle_call({:cancel, entry_id}, _from, state) do
    case do_cancel(entry_id, state) do
      {:ok, entry, new_state} ->
        QueuePersistence.notify({:cancel, entry_id})
        {:reply, {:ok, entry}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:clear, _from, state) do
    {count, new_state} = do_clear(state)
    QueuePersistence.notify({:clear_pending, state.target_id})
    {:reply, {:ok, count}, new_state}
  end

  def handle_call(:status, _from, state) do
    status = %{
      mission_id: state.mission_id,
      target_id: state.target_id,
      pending: state.counts.pending,
      executing: state.counts.executing,
      failed: state.counts.failed,
      dispatcher_paused: state.dispatcher_paused
    }

    {:reply, status, state}
  end

  def handle_call(:trigger_check, _from, state) do
    Logger.info("Manual trigger_check for target_id=#{state.target_id}")

    has_entries = has_ready_entries_local?(state)
    Logger.info("  has_ready_entries? = #{has_entries}")
    Logger.info("  dispatcher_paused = #{state.dispatcher_paused}")

    result =
      if not state.dispatcher_paused and has_entries do
        case TargetDispatcher.whereis(state.mission_id, state.target_id) do
          nil ->
            Logger.warning("  Dispatcher not found!")
            {:error, :dispatcher_not_found}

          pid ->
            Logger.info("  Sending :check_queue to dispatcher pid=#{inspect(pid)}")
            send(pid, :check_queue)
            :ok
        end
      else
        if state.dispatcher_paused do
          {:error, :dispatcher_paused}
        else
          {:error, :no_ready_entries}
        end
      end

    {:reply, result, state}
  end

  def handle_call({:list_pending, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    entries = Enum.take(state.pending_entries, limit)
    {:reply, entries, state}
  end

  def handle_call({:reorder, entry_id, new_priority}, _from, state) do
    case do_reorder(entry_id, new_priority, state) do
      {:ok, entry, new_state} ->
        QueuePersistence.notify({:priority_changed, entry_id, new_priority})
        {:reply, {:ok, entry}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:complete, entry_id, result}, state) do
    new_state = handle_command_complete(entry_id, result, state)
    {:noreply, new_state}
  end

  def handle_cast({:attach_command_aggregate_id, entry_id, command_aggregate_id}, state) do
    {new_state, updated} =
      update_entry_local(state, entry_id, %{command_aggregate_id: command_aggregate_id})

    if updated do
      QueuePersistence.notify({:attach_command_aggregate_id, entry_id, command_aggregate_id})
    end

    {:noreply, new_state}
  end

  def handle_cast({:set_dispatcher_paused, paused}, state) do
    {:noreply, %{state | dispatcher_paused: paused}}
  end

  @impl true
  def handle_info(:process_queue, state) do
    state = expire_old_entries_local(state)

    if not state.dispatcher_paused do
      if has_ready_entries_local?(state) do
        notify_dispatcher(state.mission_id, state.target_id)
      end
    end

    {:noreply, schedule_process(state)}
  end

  def handle_info({:retry_command, entry_id}, state) do
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        {:noreply, state}

      entry ->
        updated_entry = %{entry | status: :pending}
        new_pending = insert_sorted(state.pending_entries, updated_entry)
        new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)

        new_state = %{
          state
          | pending_entries: new_pending,
            entries_by_id: new_entries_by_id
        }

        QueuePersistence.notify({:return_to_pending, entry_id, entry.last_error})
        notify_dispatcher(state.mission_id, state.target_id)
        {:noreply, refresh_counts(new_state)}
    end
  end

  def handle_info({:command_enqueued, %QueuedCommand{} = entry}, state) do
    if entry.target_id == state.target_id do
      new_state = add_entry_local(state, entry)
      notify_dispatcher(state.mission_id, state.target_id)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:command_cancelled, %QueuedCommand{} = entry}, state) do
    {:noreply, remove_entry_local(state, entry.id)}
  end

  def handle_info({:command_completed, %QueuedCommand{} = entry}, state) do
    {:noreply, remove_entry_local(state, entry.id)}
  end

  def handle_info({:command_failed, %QueuedCommand{} = entry}, state) do
    {:noreply, update_failed_local(state, entry)}
  end

  def handle_info({:command_retried, %QueuedCommand{} = entry}, state) do
    {:noreply, add_entry_local(state, %{entry | status: :pending})}
  end

  def handle_info({:command_reordered, %QueuedCommand{} = entry}, state) do
    {new_state, _} = update_entry_local(state, entry.id, %{priority: entry.priority})
    {:noreply, new_state}
  end

  def handle_info({:commands_cleared, target_id}, state) do
    if target_id == state.target_id do
      {_count, new_state} = do_clear(state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:command_claimed, %QueuedCommand{} = entry}, state) do
    {:noreply, update_claimed_local(state, entry)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp build_state_from_snapshot(
         %Mission{} = mission,
         %Target{} = target,
         %QueueSnapshot{} = snapshot
       ) do
    pending_entries = snapshot.pending_entries || []
    entries_by_id = Map.new(pending_entries, &{&1.id, &1})

    %State{
      mission_id: mission.id,
      target_id: target.id,
      organization_id: mission.organization_id,
      target: target,
      pending_entries: Enum.sort_by(pending_entries, &{&1.priority, &1.sequence_number}),
      entries_by_id: entries_by_id,
      counts: %{pending: length(pending_entries), executing: 0, completed: 0, failed: 0},
      sequence_counter: snapshot.sequence_counter
    }
  end

  defp build_state_from_snapshot(%Mission{} = mission, %Target{} = target, nil) do
    %State{
      mission_id: mission.id,
      target_id: target.id,
      organization_id: mission.organization_id,
      target: target
    }
  end

  defp do_enqueue(command_name, params, opts, state) do
    sequence = state.sequence_counter + 1
    user_id = Keyword.get(opts, :user_id)
    priority = Keyword.get(opts, :priority, 3)
    scheduled_at = Keyword.get(opts, :scheduled_at)
    expires_at = Keyword.get(opts, :expires_at)
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    dispatch_opts = opts_to_map(opts)

    entry_attrs = %{
      id: Ecto.UUID.generate(),
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      target_id: state.target_id,
      user_id: user_id,
      command_name: command_name,
      parameters: params,
      priority: priority,
      sequence_number: sequence,
      scheduled_at: scheduled_at,
      expires_at: expires_at,
      max_attempts: max_attempts,
      dispatch_opts: dispatch_opts
    }

    case QueuedCommand.new(entry_attrs) do
      {:ok, entry} ->
        new_pending = insert_sorted(state.pending_entries, entry)
        new_entries_by_id = Map.put(state.entries_by_id, entry.id, entry)
        new_counts = %{state.counts | pending: state.counts.pending + 1}

        new_state = %{
          state
          | sequence_counter: sequence,
            pending_entries: new_pending,
            entries_by_id: new_entries_by_id,
            counts: new_counts
        }

        {:ok, entry, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp opts_to_map(opts) do
    opts
    |> Keyword.take([:interface_id, :skip_verification, :skip_hazardous_check])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp do_cancel(entry_id, state) do
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        {:error, :not_found}

      %QueuedCommand{status: status} when status in [:completed, :cancelled] ->
        {:error, :already_finished}

      %QueuedCommand{status: :executing} ->
        {:error, :currently_executing}

      entry ->
        updated_entry = %{entry | status: :cancelled}
        new_state = remove_entry_local(state, entry_id)
        {:ok, updated_entry, new_state}
    end
  end

  defp do_clear(state) do
    count = length(state.pending_entries)
    entry_ids = Enum.map(state.pending_entries, & &1.id)

    new_state = %{
      state
      | pending_entries: [],
        entries_by_id: Map.drop(state.entries_by_id, entry_ids),
        counts: %{state.counts | pending: 0}
    }

    {count, refresh_counts(new_state)}
  end

  defp do_reorder(entry_id, new_priority, state) do
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        {:error, :not_found}

      %QueuedCommand{status: :pending} = entry ->
        updated_entry = %{entry | priority: new_priority}

        new_pending =
          state.pending_entries
          |> Enum.reject(&(&1.id == entry_id))
          |> insert_sorted(updated_entry)

        new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)

        new_state = %{
          state
          | pending_entries: new_pending,
            entries_by_id: new_entries_by_id
        }

        {:ok, updated_entry, new_state}

      _ ->
        {:error, :not_pending}
    end
  end

  defp handle_command_complete(entry_id, result, state) do
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        %{state | executing: nil, counts: %{state.counts | executing: 0}}

      entry ->
        apply_completion_result(entry, entry_id, result, state)
    end
  end

  defp apply_completion_result(_entry, entry_id, {:ok, %{aggregate_id: aggregate_id}}, state) do
    new_state = remove_entry_local(state, entry_id)
    QueuePersistence.notify({:complete, entry_id, aggregate_id})
    %{new_state | executing: nil}
  end

  defp apply_completion_result(entry, entry_id, {:error, :paused}, state) do
    return_to_pending_local(entry, entry_id, "dispatcher paused", state)
  end

  defp apply_completion_result(entry, entry_id, {:error, :requires_confirmation, _info}, state) do
    updated_entry = %{
      entry
      | status: :failed,
        last_error: "Hazardous command requires confirmation - cannot execute from queue"
    }

    new_state = remove_entry_local(state, entry_id)
    QueuePersistence.notify({:failed, entry_id, updated_entry.last_error})
    %{new_state | executing: nil}
  end

  defp apply_completion_result(
         entry,
         entry_id,
         {:error, :send_failed, :no_clients_connected},
         state
       ) do
    return_to_pending_local(entry, entry_id, "no clients connected", state)
  end

  defp apply_completion_result(entry, entry_id, {:error, :interface_not_running}, state) do
    return_to_pending_local(entry, entry_id, "interface not running", state)
  end

  defp apply_completion_result(entry, entry_id, {:error, reason}, state) do
    handle_failure_local(entry, entry_id, reason, state)
  end

  defp apply_completion_result(entry, entry_id, {:error, reason, details}, state) do
    handle_failure_local(entry, entry_id, {reason, details}, state)
  end

  defp return_to_pending_local(entry, entry_id, reason, state) do
    updated_entry = %{entry | status: :pending, last_error: reason}
    new_pending = insert_sorted(state.pending_entries, updated_entry)
    new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)

    new_state = %{
      state
      | pending_entries: new_pending,
        entries_by_id: new_entries_by_id,
        executing: nil
    }

    QueuePersistence.notify({:return_to_pending, entry_id, reason})
    notify_dispatcher(state.mission_id, state.target_id)
    refresh_counts(new_state)
  end

  defp handle_failure_local(entry, entry_id, reason, state) do
    error_msg = inspect(reason)

    failed_entry = %{entry | status: :failed, last_error: error_msg}

    if QueuedCommand.retriable?(failed_entry) do
      new_entries_by_id = Map.put(state.entries_by_id, entry_id, failed_entry)
      QueuePersistence.notify({:failed, entry_id, error_msg})
      Process.send_after(self(), {:retry_command, entry_id}, @retry_delay_ms)

      %{state | entries_by_id: new_entries_by_id, executing: nil}
      |> refresh_counts()
    else
      final_error_msg = "Max attempts reached. Last error: #{error_msg}"
      new_state = remove_entry_local(state, entry_id)
      QueuePersistence.notify({:failed, entry_id, final_error_msg})
      %{new_state | executing: nil}
    end
  end

  defp notify_dispatcher(mission_id, target_id) do
    case TargetDispatcher.whereis(mission_id, target_id) do
      nil -> :ok
      pid -> send(pid, :check_queue)
    end
  end

  defp expire_old_entries_local(%{pending_entries: []} = state), do: state

  defp expire_old_entries_local(state) do
    now = DateTime.utc_now()

    {expired, remaining} =
      Enum.split_with(state.pending_entries, fn entry ->
        entry.expires_at && DateTime.compare(entry.expires_at, now) == :lt
      end)

    if expired == [] do
      state
    else
      expired_ids = Enum.map(expired, & &1.id)

      QueuePersistence.notify({:expire_entries, expired_ids})

      %{
        state
        | pending_entries: remaining,
          entries_by_id: Map.drop(state.entries_by_id, expired_ids)
      }
      |> refresh_counts()
    end
  end

  defp fetch_next_ready_local(%{pending_entries: []}), do: nil

  defp fetch_next_ready_local(%{pending_entries: entries}) do
    now = DateTime.utc_now()

    Enum.find(entries, fn entry ->
      is_nil(entry.scheduled_at) or DateTime.compare(entry.scheduled_at, now) != :gt
    end)
  end

  defp has_ready_entries_local?(%{pending_entries: []}), do: false

  defp has_ready_entries_local?(%{pending_entries: entries}) do
    now = DateTime.utc_now()

    Enum.any?(entries, fn entry ->
      is_nil(entry.scheduled_at) or DateTime.compare(entry.scheduled_at, now) != :gt
    end)
  end

  defp insert_sorted(entries, entry) do
    {before, after_list} =
      Enum.split_while(entries, fn e ->
        {e.priority, e.sequence_number} < {entry.priority, entry.sequence_number}
      end)

    before ++ [entry | after_list]
  end

  defp add_entry_local(state, %QueuedCommand{} = entry) do
    if Map.has_key?(state.entries_by_id, entry.id) do
      state
    else
      new_pending =
        if entry.status == :pending do
          insert_sorted(state.pending_entries, entry)
        else
          state.pending_entries
        end

      new_entries_by_id = Map.put(state.entries_by_id, entry.id, entry)

      new_sequence =
        case entry.sequence_number do
          nil -> state.sequence_counter
          sequence_number -> max(state.sequence_counter, sequence_number)
        end

      %{
        state
        | pending_entries: new_pending,
          entries_by_id: new_entries_by_id,
          sequence_counter: new_sequence
      }
      |> refresh_counts()
    end
  end

  defp remove_entry_local(state, entry_id) do
    new_pending = Enum.reject(state.pending_entries, &(&1.id == entry_id))
    new_entries_by_id = Map.delete(state.entries_by_id, entry_id)

    new_executing =
      if(state.executing && state.executing.id == entry_id, do: nil, else: state.executing)

    %{
      state
      | pending_entries: new_pending,
        entries_by_id: new_entries_by_id,
        executing: new_executing
    }
    |> refresh_counts()
  end

  defp update_failed_local(state, %QueuedCommand{} = entry) do
    new_entries_by_id = Map.put(state.entries_by_id, entry.id, entry)
    new_pending = Enum.reject(state.pending_entries, &(&1.id == entry.id))

    new_executing =
      if(state.executing && state.executing.id == entry.id, do: nil, else: state.executing)

    %{
      state
      | pending_entries: new_pending,
        entries_by_id: new_entries_by_id,
        executing: new_executing
    }
    |> refresh_counts()
  end

  defp update_claimed_local(state, %QueuedCommand{} = entry) do
    new_pending = Enum.reject(state.pending_entries, &(&1.id == entry.id))
    new_entries_by_id = Map.put(state.entries_by_id, entry.id, entry)

    %{state | pending_entries: new_pending, entries_by_id: new_entries_by_id, executing: entry}
    |> refresh_counts()
  end

  defp update_entry_local(state, entry_id, attrs) do
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        {state, false}

      entry ->
        updated_entry = struct(entry, attrs)
        new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)

        new_pending =
          if entry.status == :pending do
            state.pending_entries
            |> Enum.reject(&(&1.id == entry_id))
            |> insert_sorted(updated_entry)
          else
            state.pending_entries
          end

        new_state = %{
          state
          | pending_entries: new_pending,
            entries_by_id: new_entries_by_id,
            executing:
              if(state.executing && state.executing.id == entry_id,
                do: updated_entry,
                else: state.executing
              )
        }

        {refresh_counts(new_state), true}
    end
  end

  defp schedule_process(state) do
    if state.process_timer do
      Process.cancel_timer(state.process_timer)
    end

    timer = Process.send_after(self(), :process_queue, @fallback_poll_interval_ms)
    %{state | process_timer: timer}
  end

  defp refresh_counts(state) do
    pending = length(state.pending_entries)

    failed =
      state.entries_by_id
      |> Map.values()
      |> Enum.count(&(&1.status == :failed))

    %{
      state
      | counts: %{
          pending: pending,
          executing: if(state.executing, do: 1, else: 0),
          completed: state.counts.completed,
          failed: failed
        }
    }
  end

  defp extract_mission_target_snapshot(opts) do
    case {Keyword.get(opts, :mission), Keyword.get(opts, :target)} do
      {%Mission{} = mission, %Target{} = target} ->
        snapshot = Keyword.get(opts, :queue_snapshot)
        {mission, target, snapshot}

      _ ->
        raise ArgumentError,
              "TargetQueue requires (mission: entity, target: entity)"
    end
  end
end
