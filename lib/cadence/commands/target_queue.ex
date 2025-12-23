defmodule Cadence.Commands.TargetQueue do
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

  ## Example

      # Enqueue a command
      {:ok, entry} = TargetQueue.enqueue(mission_id, target_id, "SET_MODE", %{mode: 1},
        priority: 2
      )

      # List pending entries
      entries = TargetQueue.list_pending(mission_id, target_id)

      # Cancel a queued command
      {:ok, entry} = TargetQueue.cancel(mission_id, target_id, entry_id)
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Commands.{QueueEntry, TargetDispatcher}
  alias Cadence.{Missions, Targets}
  alias Cadence.Outbox
  alias Cadence.Recordings
  alias Cadence.Recordings.Recordables.{CommandQueued, CommandDequeued}
  alias Ecto.Multi

  # Fallback poll interval - used as safety net for scheduled commands and missed events
  # Primary wakeup is via PubSub from outbox events
  @fallback_poll_interval_ms 10_000
  @retry_delay_ms 1_000
  # Stale executing entries older than this are recovered as failed
  @stale_executing_timeout_ms 120_000

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :target_id,
      :organization_id,
      :target,
      executing: nil,
      sequence_counter: 0,
      process_timer: nil,
      # Cached paused state from dispatcher - updated via cast to avoid deadlocks
      dispatcher_paused: false
    ]
  end

  ## Client API

  @doc """
  Starts the queue for a target.
  """
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    target_id = Keyword.fetch!(opts, :target_id)
    GenServer.start_link(__MODULE__, {mission_id, target_id}, name: via_tuple(mission_id, target_id))
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
  Enqueues a command for execution.

  ## Options

  - `:priority` - Priority level 0-5 (default: 3)
  - `:scheduled_at` - Execute at or after this time
  - `:expires_at` - Cancel if not executed by this time
  - `:max_attempts` - Max retry attempts (default: 3)
  - `:user_id` - User performing the action
  - `:interface_id` - Specific interface to use

  ## Returns

  - `{:ok, queue_entry}` - Command queued successfully
  - `{:error, reason}` - Enqueue failed
  """
  def enqueue(mission_id, target_id, command_name, params, opts \\ []) do
    GenServer.call(via_tuple(mission_id, target_id), {:enqueue, command_name, params, opts})
  end

  @doc """
  Gets the next command ready for dispatch.

  Called by TargetDispatcher when it's ready to send a command.
  Returns nil if no commands are ready (paused, empty, or all scheduled for future).
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
  Reports execution result for a queue entry.

  Called by TargetDispatcher after attempting to send a command.
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

  Called by TargetDispatcher via cast to avoid synchronous dependency.
  """
  def set_dispatcher_paused(mission_id, target_id, paused) do
    GenServer.cast(via_tuple(mission_id, target_id), {:set_dispatcher_paused, paused})
  end

  @doc """
  Manually triggers the dispatcher to check for queued commands.

  Useful for debugging or forcing immediate processing of pending commands.
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
  Moves a command to a different position in the queue.
  """
  def reorder(mission_id, target_id, entry_id, new_priority) do
    GenServer.call(via_tuple(mission_id, target_id), {:reorder, entry_id, new_priority})
  end

  ## Server Callbacks

  @impl true
  def init({mission_id, target_id}) do
    Logger.info(
      "Starting TargetQueue for mission_id=#{mission_id}, target_id=#{target_id}"
    )

    # These are internal GenServer processes - use unscoped as mission context
    # is already verified through the supervision tree
    mission = Missions.get_mission!(mission_id)
    target = Targets.get_target_unscoped!(target_id)

    # Subscribe to outbox events for this target
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:outbox")

    # Get the highest sequence number from existing entries for this target
    sequence_counter = get_max_sequence(target_id) || 0

    state = %State{
      mission_id: mission_id,
      target_id: target_id,
      organization_id: mission.organization_id,
      target: target,
      sequence_counter: sequence_counter
    }

    # Start fallback processing loop
    {:ok, schedule_process(state)}
  end

  @impl true
  def handle_call({:enqueue, command_name, params, opts}, _from, state) do
    case do_enqueue(command_name, params, opts, state) do
      {:ok, entry, new_state} ->
        # Notify dispatcher to wake up
        notify_dispatcher(state.mission_id, state.target_id)
        {:reply, {:ok, entry}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:next, _from, state) do
    # Check cached dispatcher paused state to avoid synchronous call
    if state.dispatcher_paused do
      {:reply, nil, state}
    else
      # Expire old entries first
      expire_old_entries(state.target_id)

      # Get next ready entry
      entry = fetch_next_ready_entry(state.target_id)
      {:reply, entry, state}
    end
  end

  def handle_call({:mark_executing, entry_id}, _from, state) do
    case Repo.get(QueueEntry, entry_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        {:ok, updated} =
          entry
          |> QueueEntry.execution_changeset(%{
            status: :executing,
            attempts: entry.attempts + 1,
            last_attempt_at: DateTime.utc_now()
          })
          |> Repo.update()

        publish_status_changed(updated, :executing, state)
        {:reply, {:ok, updated}, %{state | executing: updated}}
    end
  end

  def handle_call({:cancel, entry_id}, _from, state) do
    case do_cancel(entry_id, state.target_id) do
      {:ok, entry} ->
        # Create CommandDequeued recording for cancellation
        record_command_dequeued(entry, "cancelled", nil, state)
        {:reply, {:ok, entry}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:clear, _from, state) do
    count = do_clear(state.target_id)
    {:reply, {:ok, count}, state}
  end

  def handle_call(:status, _from, state) do
    status = %{
      mission_id: state.mission_id,
      target_id: state.target_id,
      pending: count_by_status(state.target_id, :pending),
      executing: if(state.executing, do: 1, else: 0),
      failed: count_by_status(state.target_id, :failed),
      dispatcher_paused: state.dispatcher_paused
    }

    {:reply, status, state}
  end

  def handle_call(:trigger_check, _from, state) do
    Logger.info("Manual trigger_check for target_id=#{state.target_id}")

    # Check if there are ready entries
    has_entries = has_ready_entries?(state.target_id)
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
    entries = do_list_pending(state.target_id, opts)
    {:reply, entries, state}
  end

  def handle_call({:reorder, entry_id, new_priority}, _from, state) do
    case do_reorder(entry_id, new_priority, state.target_id) do
      {:ok, entry} -> {:reply, {:ok, entry}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:complete, entry_id, result}, state) do
    new_state = handle_command_complete(entry_id, result, state)
    {:noreply, new_state}
  end

  def handle_cast({:set_dispatcher_paused, paused}, state) do
    {:noreply, %{state | dispatcher_paused: paused}}
  end

  @impl true
  def handle_info(:process_queue, state) do
    # Recover any stale executing entries (defense in depth)
    recover_stale_entries(state.target_id)

    # Periodic check - notify dispatcher if there's work
    # Use cached paused state to avoid synchronous call to dispatcher
    if not state.dispatcher_paused do
      if has_ready_entries?(state.target_id) do
        notify_dispatcher(state.mission_id, state.target_id)
      end
    end

    {:noreply, schedule_process(state)}
  end

  def handle_info({:retry_command, entry_id}, state) do
    # Re-mark as pending to be picked up by next process cycle
    case Repo.get(QueueEntry, entry_id) do
      nil ->
        :ok

      entry ->
        entry
        |> QueueEntry.execution_changeset(%{status: :pending})
        |> Repo.update()

        # Notify dispatcher there's work
        notify_dispatcher(state.mission_id, state.target_id)
    end

    {:noreply, state}
  end

  # Handle outbox events - wake up when a command is enqueued for this target
  def handle_info({:outbox_event, %{event_type: "command_enqueued", payload: payload}}, state) do
    # Check if this event is for our target
    target_id = Map.get(payload, "target_id") || Map.get(payload, :target_id)

    if target_id == state.target_id do
      Logger.debug(
        "TargetQueue received command_enqueued event for target_id=#{state.target_id}"
      )

      notify_dispatcher(state.mission_id, state.target_id)
    end

    {:noreply, state}
  end

  def handle_info({:outbox_event, _event}, state) do
    # Ignore other outbox event types
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp do_enqueue(command_name, params, opts, state) do
    sequence = state.sequence_counter + 1
    user_id = Keyword.get(opts, :user_id)
    priority = Keyword.get(opts, :priority, 3)
    scheduled_at = Keyword.get(opts, :scheduled_at)
    expires_at = Keyword.get(opts, :expires_at)
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    dispatch_opts = opts_to_map(opts)

    entry_attrs = %{
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      target_id: state.target_id,
      command_name: command_name,
      parameters: params,
      priority: priority,
      sequence_number: sequence,
      scheduled_at: scheduled_at,
      expires_at: expires_at,
      max_attempts: max_attempts,
      user_id: user_id,
      dispatch_opts: dispatch_opts
    }

    # Recordable attrs for CommandQueued (computed before Multi since values are known)
    queued_attrs = %{
      command_name: command_name,
      parameters: params,
      target_id: state.target_id,
      priority: priority,
      scheduled_at: scheduled_at,
      expires_at: expires_at,
      max_attempts: max_attempts,
      dispatch_opts: dispatch_opts
    }

    result =
      Multi.new()
      |> Multi.insert(:entry, QueueEntry.changeset(%QueueEntry{}, entry_attrs))
      |> Outbox.append(:outbox, fn %{entry: entry} ->
        %{
          organization_id: state.organization_id,
          mission_id: state.mission_id,
          event_type: "command_enqueued",
          aggregate_type: "command_queue_entry",
          aggregate_id: entry.id,
          actor_id: user_id,
          actor_type: if(user_id, do: "user", else: "system"),
          payload: %{
            command_name: command_name,
            target_id: state.target_id,
            priority: priority,
            scheduled_at: scheduled_at
          }
        }
      end)
      |> Recordings.append(:queued, CommandQueued, queued_attrs, fn %{entry: entry} ->
        %{
          organization_id: state.organization_id,
          mission_id: state.mission_id,
          bucket_id: state.target.bucket_id,
          aggregate_type: "QueueEntry",
          aggregate_id: entry.id,
          actor_id: user_id,
          actor_type: if(user_id, do: "user", else: "system"),
          timestamp: DateTime.utc_now()
        }
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{entry: entry}} ->
        Logger.debug(
          "Enqueued command #{command_name} for target_id=#{state.target_id} as entry_id=#{entry.id}"
        )

        {:ok, entry, %{state | sequence_counter: sequence}}

      {:error, :entry, changeset, _changes} ->
        {:error, {:validation, changeset}}

      {:error, :outbox, changeset, _changes} ->
        Logger.error("Failed to create outbox event: #{inspect(changeset.errors)}")
        {:error, {:outbox_failed, changeset}}

      {:error, :queued_recordable, changeset, _changes} ->
        Logger.error("Failed to create CommandQueued recordable: #{inspect(changeset.errors)}")
        {:error, {:recording_failed, changeset}}

      {:error, :queued_recording, changeset, _changes} ->
        Logger.error("Failed to create recording: #{inspect(changeset.errors)}")
        {:error, {:recording_failed, changeset}}
    end
  end

  defp opts_to_map(opts) do
    opts
    |> Keyword.drop([:priority, :scheduled_at, :expires_at, :max_attempts, :user_id])
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp do_cancel(entry_id, target_id) do
    case Repo.get_by(QueueEntry, id: entry_id, target_id: target_id) do
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

  defp do_clear(target_id) do
    {count, _} =
      from(e in QueueEntry,
        where: e.target_id == ^target_id,
        where: e.status == :pending
      )
      |> Repo.update_all(set: [status: :cancelled, updated_at: DateTime.utc_now()])

    count
  end

  defp do_list_pending(target_id, opts) do
    limit = Keyword.get(opts, :limit, 100)

    from(e in QueueEntry,
      where: e.target_id == ^target_id,
      where: e.status == :pending,
      order_by: [asc: e.priority, asc: e.sequence_number],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp do_reorder(entry_id, new_priority, target_id) do
    case Repo.get_by(QueueEntry, id: entry_id, target_id: target_id, status: :pending) do
      nil ->
        {:error, :not_found}

      entry ->
        entry
        |> Ecto.Changeset.change(priority: new_priority)
        |> Repo.update()
    end
  end

  defp fetch_next_ready_entry(target_id) do
    now = DateTime.utc_now()

    from(e in QueueEntry,
      where: e.target_id == ^target_id,
      where: e.status == :pending,
      where: is_nil(e.scheduled_at) or e.scheduled_at <= ^now,
      order_by: [asc: e.priority, asc: e.sequence_number],
      limit: 1
    )
    |> Repo.one()
  end

  defp has_ready_entries?(target_id) do
    now = DateTime.utc_now()

    from(e in QueueEntry,
      where: e.target_id == ^target_id,
      where: e.status == :pending,
      where: is_nil(e.scheduled_at) or e.scheduled_at <= ^now,
      limit: 1,
      select: 1
    )
    |> Repo.one() != nil
  end

  defp handle_command_complete(entry_id, result, state) do
    case Repo.get(QueueEntry, entry_id) do
      nil ->
        %{state | executing: nil}

      entry ->
        case result do
          {:ok, %{aggregate_id: aggregate_id, recording_id: recording_id}} ->
            # Success
            {:ok, updated_entry} =
              entry
              |> QueueEntry.execution_changeset(%{
                status: :completed,
                command_log_id: aggregate_id
              })
              |> Repo.update()

            # Create CommandDequeued recording for successful execution
            record_command_dequeued(entry, "executed", aggregate_id, state)

            publish_status_changed(updated_entry, :completed, recording_id, state)
            Logger.debug("Queue entry #{entry_id} completed successfully")

          {:error, :paused} ->
            # Dispatcher was paused - put back in queue
            {:ok, updated_entry} =
              entry
              |> QueueEntry.execution_changeset(%{status: :pending})
              |> Repo.update()

            publish_status_changed(updated_entry, :pending, state)
            Logger.debug("Queue entry #{entry_id} returned to pending (dispatcher paused)")

          {:error, :requires_confirmation, _info} ->
            # Hazardous command - mark as failed, don't retry
            {:ok, updated_entry} =
              entry
              |> QueueEntry.execution_changeset(%{
                status: :failed,
                last_error: "Hazardous command requires confirmation - cannot execute from queue"
              })
              |> Repo.update()

            publish_status_changed(updated_entry, :failed, state)

          {:error, :send_failed, :no_clients_connected} ->
            # Interface has no connected clients - return to pending, don't count as failure
            {:ok, updated_entry} =
              entry
              |> QueueEntry.execution_changeset(%{status: :pending})
              |> Repo.update()

            publish_status_changed(updated_entry, :pending, state)
            Logger.info("Queue entry #{entry_id} returned to pending (no clients connected)")

          {:error, :interface_not_running} ->
            # Interface not running - return to pending, don't count as failure
            {:ok, updated_entry} =
              entry
              |> QueueEntry.execution_changeset(%{status: :pending})
              |> Repo.update()

            publish_status_changed(updated_entry, :pending, state)
            Logger.info("Queue entry #{entry_id} returned to pending (interface not running)")

          {:error, reason} ->
            handle_failure(entry, reason, state)

          {:error, reason, _details} ->
            handle_failure(entry, reason, state)
        end

        %{state | executing: nil}
    end
  end

  defp handle_failure(entry, reason, state) do
    error_msg = inspect(reason)

    if QueueEntry.retriable?(entry) do
      # Schedule retry
      {:ok, updated_entry} =
        entry
        |> QueueEntry.execution_changeset(%{
          status: :failed,
          last_error: error_msg
        })
        |> Repo.update()

      publish_status_changed(updated_entry, :failed, state)
      Process.send_after(self(), {:retry_command, entry.id}, @retry_delay_ms)
      Logger.warning("Queue entry #{entry.id} failed, will retry: #{error_msg}")
    else
      # Max attempts reached
      {:ok, updated_entry} =
        entry
        |> QueueEntry.execution_changeset(%{
          status: :failed,
          last_error: "Max attempts reached. Last error: #{error_msg}"
        })
        |> Repo.update()

      publish_status_changed(updated_entry, :failed, state)
      Logger.error("Queue entry #{entry.id} failed permanently: #{error_msg}")
    end
  end

  defp publish_status_changed(entry, new_status, state) do
    publish_status_changed(entry, new_status, nil, state)
  end

  defp publish_status_changed(entry, new_status, recording_id, state) do
    # Insert to outbox for persistence and audit trail
    {:ok, event} =
      Outbox.insert(%{
        organization_id: state.organization_id,
        mission_id: state.mission_id,
        recording_id: recording_id,
        event_type: "command_status_changed",
        aggregate_type: "command_queue_entry",
        aggregate_id: entry.id,
        actor_type: "system",
        payload: %{
          command_name: entry.command_name,
          target_id: state.target_id,
          status: to_string(new_status),
          command_log_id: entry.command_log_id,
          last_error: entry.last_error
        }
      })

    # Broadcast immediately for real-time UI updates
    # (Processor will also broadcast, but this ensures instant feedback)
    Outbox.broadcast(event)
  end

  defp expire_old_entries(target_id) do
    now = DateTime.utc_now()

    from(e in QueueEntry,
      where: e.target_id == ^target_id,
      where: e.status == :pending,
      where: not is_nil(e.expires_at),
      where: e.expires_at < ^now
    )
    |> Repo.update_all(set: [status: :expired, updated_at: now])
  end

  defp count_by_status(target_id, status) do
    from(e in QueueEntry,
      where: e.target_id == ^target_id,
      where: e.status == ^status,
      select: count(e.id)
    )
    |> Repo.one()
  end

  defp get_max_sequence(target_id) do
    from(e in QueueEntry,
      where: e.target_id == ^target_id,
      select: max(e.sequence_number)
    )
    |> Repo.one()
  end

  defp schedule_process(state) do
    if state.process_timer do
      Process.cancel_timer(state.process_timer)
    end

    timer = Process.send_after(self(), :process_queue, @fallback_poll_interval_ms)
    %{state | process_timer: timer}
  end

  defp notify_dispatcher(mission_id, target_id) do
    # Send message to dispatcher to check for work
    case TargetDispatcher.whereis(mission_id, target_id) do
      nil -> :ok
      pid -> send(pid, :check_queue)
    end
  end

  defp recover_stale_entries(target_id) do
    # Find entries stuck in :executing status for longer than the stale timeout
    # This is a defense-in-depth mechanism - normally Task supervision handles this
    stale_threshold = DateTime.add(DateTime.utc_now(), -@stale_executing_timeout_ms, :millisecond)

    {count, _} =
      from(e in QueueEntry,
        where: e.target_id == ^target_id,
        where: e.status == :executing,
        where: e.last_attempt_at < ^stale_threshold
      )
      |> Repo.update_all(
        set: [
          status: :failed,
          last_error: "Stale entry recovery - execution timed out after #{@stale_executing_timeout_ms}ms",
          updated_at: DateTime.utc_now()
        ]
      )

    if count > 0 do
      Logger.warning(
        "Recovered #{count} stale executing entries for target_id=#{target_id}"
      )
    end

    count
  end

  # Creates a CommandDequeued recording for queue entry state transitions
  defp record_command_dequeued(entry, reason, command_aggregate_id, state) do
    dequeued_attrs = %{
      reason: reason,
      command_aggregate_id: command_aggregate_id,
      attempts: entry.attempts,
      last_error: entry.last_error
    }

    recording_attrs = %{
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      bucket_id: state.target.bucket_id,
      aggregate_type: "QueueEntry",
      aggregate_id: entry.id,
      actor_type: "system",
      timestamp: DateTime.utc_now()
    }

    case Recordings.create(CommandDequeued, dequeued_attrs, recording_attrs) do
      {:ok, _} ->
        :ok

      {:error, step, changeset, _} ->
        Logger.error(
          "Failed to create CommandDequeued recording (#{step}): #{inspect(changeset.errors)}"
        )
    end
  end
end
