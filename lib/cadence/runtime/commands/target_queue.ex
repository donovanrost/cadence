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

  alias Cadence.Commands.QueueEntry
  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.Outbox
  alias Cadence.Recordings
  alias Cadence.Recordings.Recordables.{CommandDequeued, CommandQueued}
  alias Cadence.Repo
  alias Cadence.Runtime.Commands.TargetDispatcher
  alias Ecto.Multi

  # Fallback poll interval - used as safety net for scheduled commands and missed events
  # Primary wakeup is via PubSub from outbox events
  @fallback_poll_interval_ms 10_000
  @retry_delay_ms 1_000
  # Stale executing entries older than this are recovered as failed
  @stale_executing_timeout_ms 120_000

  defmodule State do
    @moduledoc """
    In-memory queue state for O(1) operations.

    ## Data Plane Optimization

    The queue maintains local state to avoid DB queries in the hot path:
    - `pending_entries` - Sorted list of pending entries (by priority, sequence)
    - `entries_by_id` - Map for O(1) lookup by entry_id
    - `counts` - Local counters for status queries

    DB persistence happens asynchronously after local state is updated.
    On restart, state is recovered from DB.
    """
    defstruct [
      :mission_id,
      :target_id,
      :organization_id,
      :target,
      # In-memory queue: list of entries sorted by {priority, sequence_number}
      pending_entries: [],
      # Map of entry_id -> entry for O(1) lookup
      entries_by_id: %{},
      # Currently executing entry (or nil)
      executing: nil,
      # Local counters - updated synchronously with local state
      counts: %{pending: 0, executing: 0, completed: 0, failed: 0},
      # Sequence counter for ordering
      sequence_counter: 0,
      process_timer: nil,
      # Cached paused state from dispatcher - updated via cast to avoid deadlocks
      dispatcher_paused: false
    ]
  end

  ## Client API

  @doc """
  Starts the queue for a target.

  Accepts either:
  - Entity-based: `mission: mission_entity, target: target_entity` (preferred, no DB calls)
  - ID-based: `mission_id: id, target_id: id` (legacy, makes DB calls)
  """
  def start_link(opts) do
    {mission, target} = extract_mission_and_target(opts)
    GenServer.start_link(__MODULE__, {mission, target}, name: via_tuple(mission.id, target.id))
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
  def init({%Mission{} = mission, %Target{} = target}) do
    Logger.info(
      "Starting TargetQueue for mission_id=#{mission.id}, target=#{target.identifier} (#{target.id})"
    )

    # Subscribe to outbox events for this target
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:outbox")

    # Load existing entries into memory for O(1) operations
    # This DB call is necessary for crash recovery - entries persist across restarts
    {pending_entries, entries_by_id, counts, sequence_counter} =
      load_entries_from_db(target.id)

    state = %State{
      mission_id: mission.id,
      target_id: target.id,
      organization_id: mission.organization_id,
      target: target,
      pending_entries: pending_entries,
      entries_by_id: entries_by_id,
      counts: counts,
      sequence_counter: sequence_counter
    }

    Logger.info(
      "TargetQueue loaded #{counts.pending} pending entries for target=#{target.identifier} (#{target.id})"
    )

    # Start fallback processing loop
    {:ok, schedule_process(state)}
  end

  # Load all entries from DB into memory state on startup
  # This is only called once at init - all subsequent operations use local state
  defp load_entries_from_db(target_id) do
    # Get all pending/executing entries for this target
    entries =
      from(e in QueueEntry,
        where: e.target_id == ^target_id,
        where: e.status in [:pending, :executing],
        order_by: [asc: e.priority, asc: e.sequence_number]
      )
      |> Repo.all()

    # Recover any stale executing entries as failed
    {entries, recovered_count} = recover_stale_on_load(entries)

    if recovered_count > 0 do
      Logger.warning(
        "Recovered #{recovered_count} stale executing entries on startup for target_id=#{target_id}"
      )
    end

    # Separate pending entries (sorted) from executing
    pending_entries =
      entries
      |> Enum.filter(&(&1.status == :pending))
      |> Enum.sort_by(&{&1.priority, &1.sequence_number})

    # Build lookup map
    entries_by_id = Map.new(entries, &{&1.id, &1})

    # Count statuses
    counts = %{
      pending: length(pending_entries),
      executing: Enum.count(entries, &(&1.status == :executing)),
      completed: 0,
      failed: 0
    }

    # Get max sequence
    sequence_counter =
      case Enum.max_by(entries, & &1.sequence_number, fn -> nil end) do
        nil -> get_max_sequence(target_id) || 0
        entry -> entry.sequence_number
      end

    {pending_entries, entries_by_id, counts, sequence_counter}
  end

  # Recover stale executing entries on startup (crash recovery)
  defp recover_stale_on_load(entries) do
    now = DateTime.utc_now()
    stale_threshold = DateTime.add(now, -@stale_executing_timeout_ms, :millisecond)

    {recovered, normal} =
      Enum.split_with(entries, fn entry ->
        entry.status == :executing &&
          entry.last_attempt_at &&
          DateTime.compare(entry.last_attempt_at, stale_threshold) == :lt
      end)

    # Mark stale entries as failed in DB (async)
    Enum.each(recovered, fn entry ->
      Task.start(fn ->
        entry
        |> QueueEntry.execution_changeset(%{
          status: :failed,
          last_error: "Stale entry recovery on startup - execution timed out"
        })
        |> Repo.update()
      end)
    end)

    {normal, length(recovered)}
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
      # Expire old entries first (updates local state)
      state = expire_old_entries_local(state)

      # Get next ready entry from local queue (O(1))
      case fetch_next_ready_local(state) do
        nil ->
          {:reply, nil, state}

        entry ->
          {:reply, entry, state}
      end
    end
  end

  def handle_call({:mark_executing, entry_id}, _from, state) do
    # Use local state for lookup (O(1))
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      entry ->
        now = DateTime.utc_now()

        # Update local state first
        updated_entry = %{
          entry
          | status: :executing,
            attempts: entry.attempts + 1,
            last_attempt_at: now
        }

        # Remove from pending, add to executing
        new_pending = Enum.reject(state.pending_entries, &(&1.id == entry_id))
        new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)
        new_counts = %{state.counts | pending: state.counts.pending - 1, executing: 1}

        new_state = %{
          state
          | pending_entries: new_pending,
            entries_by_id: new_entries_by_id,
            executing: updated_entry,
            counts: new_counts
        }

        # Persist async - fire and forget
        persist_async(fn ->
          entry
          |> QueueEntry.execution_changeset(%{
            status: :executing,
            attempts: entry.attempts + 1,
            last_attempt_at: now
          })
          |> Repo.update()
        end)

        publish_status_changed(updated_entry, :executing, new_state)
        {:reply, {:ok, updated_entry}, new_state}
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
    # Use local counters (O(1)) instead of DB queries
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

    # Check if there are ready entries (O(1) local check)
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
    # Use local state (O(1)) instead of DB query
    limit = Keyword.get(opts, :limit, 100)
    entries = Enum.take(state.pending_entries, limit)
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
    # Expire old entries (updates local state)
    state = expire_old_entries_local(state)

    # Periodic check - notify dispatcher if there's work
    # Use local state to check (O(1))
    if not state.dispatcher_paused do
      if has_ready_entries_local?(state) do
        notify_dispatcher(state.mission_id, state.target_id)
      end
    end

    {:noreply, schedule_process(state)}
  end

  def handle_info({:retry_command, entry_id}, state) do
    # Re-mark as pending using local state
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        {:noreply, state}

      entry ->
        # Update local state
        updated_entry = %{entry | status: :pending}
        new_pending = insert_sorted(state.pending_entries, updated_entry)
        new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)

        new_counts = %{
          state.counts
          | pending: state.counts.pending + 1,
            failed: max(0, state.counts.failed - 1)
        }

        new_state = %{
          state
          | pending_entries: new_pending,
            entries_by_id: new_entries_by_id,
            counts: new_counts
        }

        # Persist async
        persist_async(fn ->
          case Repo.get(QueueEntry, entry_id) do
            nil ->
              :ok

            db_entry ->
              db_entry
              |> QueueEntry.execution_changeset(%{status: :pending})
              |> Repo.update()
          end
        end)

        # Notify dispatcher there's work
        notify_dispatcher(state.mission_id, state.target_id)
        {:noreply, new_state}
    end
  end

  # Handle outbox events - wake up when a command is enqueued for this target
  def handle_info({:outbox_event, %{event_type: "command_enqueued", payload: payload}}, state) do
    # Check if this event is for our target
    target_id = Map.get(payload, "target_id") || Map.get(payload, :target_id)

    if target_id == state.target_id do
      Logger.debug("TargetQueue received command_enqueued event for target_id=#{state.target_id}")

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

        # Add to local state for O(1) operations
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
    # Use local state for lookup (O(1))
    case Map.get(state.entries_by_id, entry_id) do
      nil ->
        %{state | executing: nil, counts: %{state.counts | executing: 0}}

      entry ->
        new_state =
          case result do
            {:ok, %{aggregate_id: aggregate_id, recording_id: recording_id}} ->
              # Success - remove from local state, persist async
              updated_entry = %{entry | status: :completed, command_log_id: aggregate_id}
              new_entries_by_id = Map.delete(state.entries_by_id, entry_id)
              new_counts = %{state.counts | executing: 0, completed: state.counts.completed + 1}

              persist_async(fn ->
                case Repo.get(QueueEntry, entry_id) do
                  nil ->
                    :ok

                  db_entry ->
                    db_entry
                    |> QueueEntry.execution_changeset(%{
                      status: :completed,
                      command_log_id: aggregate_id
                    })
                    |> Repo.update()
                end
              end)

              # Create CommandDequeued recording for successful execution
              record_command_dequeued(entry, "executed", aggregate_id, state)
              publish_status_changed(updated_entry, :completed, recording_id, state)
              Logger.debug("Queue entry #{entry_id} completed successfully")

              %{state | entries_by_id: new_entries_by_id, executing: nil, counts: new_counts}

            {:error, :paused} ->
              # Dispatcher was paused - put back in queue
              updated_entry = %{entry | status: :pending}
              new_pending = insert_sorted(state.pending_entries, updated_entry)
              new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)
              new_counts = %{state.counts | executing: 0, pending: state.counts.pending + 1}

              persist_async(fn ->
                case Repo.get(QueueEntry, entry_id) do
                  nil ->
                    :ok

                  db_entry ->
                    db_entry
                    |> QueueEntry.execution_changeset(%{status: :pending})
                    |> Repo.update()
                end
              end)

              publish_status_changed(updated_entry, :pending, state)
              Logger.debug("Queue entry #{entry_id} returned to pending (dispatcher paused)")

              %{
                state
                | pending_entries: new_pending,
                  entries_by_id: new_entries_by_id,
                  executing: nil,
                  counts: new_counts
              }

            {:error, :requires_confirmation, _info} ->
              # Hazardous command - mark as failed, don't retry
              updated_entry = %{
                entry
                | status: :failed,
                  last_error:
                    "Hazardous command requires confirmation - cannot execute from queue"
              }

              new_entries_by_id = Map.delete(state.entries_by_id, entry_id)
              new_counts = %{state.counts | executing: 0, failed: state.counts.failed + 1}

              persist_async(fn ->
                case Repo.get(QueueEntry, entry_id) do
                  nil ->
                    :ok

                  db_entry ->
                    db_entry
                    |> QueueEntry.execution_changeset(%{
                      status: :failed,
                      last_error:
                        "Hazardous command requires confirmation - cannot execute from queue"
                    })
                    |> Repo.update()
                end
              end)

              publish_status_changed(updated_entry, :failed, state)

              %{state | entries_by_id: new_entries_by_id, executing: nil, counts: new_counts}

            {:error, :send_failed, :no_clients_connected} ->
              # Interface has no connected clients - return to pending
              return_to_pending_local(entry, entry_id, "no clients connected", state)

            {:error, :interface_not_running} ->
              # Interface not running - return to pending
              return_to_pending_local(entry, entry_id, "interface not running", state)

            {:error, reason} ->
              handle_failure_local(entry, entry_id, reason, state)

            {:error, reason, _details} ->
              handle_failure_local(entry, entry_id, reason, state)
          end

        new_state
    end
  end

  # Return entry to pending queue (local state version)
  defp return_to_pending_local(entry, entry_id, reason, state) do
    updated_entry = %{entry | status: :pending}
    new_pending = insert_sorted(state.pending_entries, updated_entry)
    new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)
    new_counts = %{state.counts | executing: 0, pending: state.counts.pending + 1}

    persist_async(fn ->
      case Repo.get(QueueEntry, entry_id) do
        nil ->
          :ok

        db_entry ->
          db_entry
          |> QueueEntry.execution_changeset(%{status: :pending})
          |> Repo.update()
      end
    end)

    publish_status_changed(updated_entry, :pending, state)
    Logger.info("Queue entry #{entry_id} returned to pending (#{reason})")

    %{
      state
      | pending_entries: new_pending,
        entries_by_id: new_entries_by_id,
        executing: nil,
        counts: new_counts
    }
  end

  # Handle failure with local state
  defp handle_failure_local(entry, entry_id, reason, state) do
    error_msg = inspect(reason)

    if QueueEntry.retriable?(entry) do
      # Schedule retry - mark as failed temporarily
      updated_entry = %{entry | status: :failed, last_error: error_msg}
      new_entries_by_id = Map.put(state.entries_by_id, entry_id, updated_entry)
      new_counts = %{state.counts | executing: 0, failed: state.counts.failed + 1}

      persist_async(fn ->
        case Repo.get(QueueEntry, entry_id) do
          nil ->
            :ok

          db_entry ->
            db_entry
            |> QueueEntry.execution_changeset(%{status: :failed, last_error: error_msg})
            |> Repo.update()
        end
      end)

      publish_status_changed(updated_entry, :failed, state)
      Process.send_after(self(), {:retry_command, entry_id}, @retry_delay_ms)
      Logger.warning("Queue entry #{entry_id} failed, will retry: #{error_msg}")

      %{state | entries_by_id: new_entries_by_id, executing: nil, counts: new_counts}
    else
      # Max attempts reached - remove from tracking
      updated_entry = %{
        entry
        | status: :failed,
          last_error: "Max attempts reached. Last error: #{error_msg}"
      }

      new_entries_by_id = Map.delete(state.entries_by_id, entry_id)
      new_counts = %{state.counts | executing: 0, failed: state.counts.failed + 1}

      persist_async(fn ->
        case Repo.get(QueueEntry, entry_id) do
          nil ->
            :ok

          db_entry ->
            db_entry
            |> QueueEntry.execution_changeset(%{
              status: :failed,
              last_error: "Max attempts reached. Last error: #{error_msg}"
            })
            |> Repo.update()
        end
      end)

      publish_status_changed(updated_entry, :failed, state)
      Logger.error("Queue entry #{entry_id} failed permanently: #{error_msg}")

      %{state | entries_by_id: new_entries_by_id, executing: nil, counts: new_counts}
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
          last_error:
            "Stale entry recovery - execution timed out after #{@stale_executing_timeout_ms}ms",
          updated_at: DateTime.utc_now()
        ]
      )

    if count > 0 do
      Logger.warning("Recovered #{count} stale executing entries for target_id=#{target_id}")
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

  # ============================================================================
  # Local State Helpers (Data Plane Optimization)
  # ============================================================================

  # Fetch next ready entry from local queue (O(1) for head of sorted list)
  defp fetch_next_ready_local(%{pending_entries: []}), do: nil

  defp fetch_next_ready_local(%{pending_entries: entries}) do
    now = DateTime.utc_now()

    Enum.find(entries, fn entry ->
      is_nil(entry.scheduled_at) or DateTime.compare(entry.scheduled_at, now) != :gt
    end)
  end

  # Check if there are ready entries (O(1))
  defp has_ready_entries_local?(%{pending_entries: []}), do: false

  defp has_ready_entries_local?(%{pending_entries: entries}) do
    now = DateTime.utc_now()

    Enum.any?(entries, fn entry ->
      is_nil(entry.scheduled_at) or DateTime.compare(entry.scheduled_at, now) != :gt
    end)
  end

  # Expire old entries and update local state
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
      # Update local state
      expired_ids = Enum.map(expired, & &1.id)
      new_entries_by_id = Map.drop(state.entries_by_id, expired_ids)

      # Persist async (batch update)
      persist_async(fn ->
        from(e in QueueEntry,
          where: e.id in ^expired_ids
        )
        |> Repo.update_all(set: [status: :expired, updated_at: now])
      end)

      %{
        state
        | pending_entries: remaining,
          entries_by_id: new_entries_by_id,
          counts: %{state.counts | pending: length(remaining)}
      }
    end
  end

  # Insert entry into sorted list maintaining {priority, sequence_number} order
  defp insert_sorted(entries, entry) do
    {before, after_list} =
      Enum.split_while(entries, fn e ->
        {e.priority, e.sequence_number} < {entry.priority, entry.sequence_number}
      end)

    before ++ [entry | after_list]
  end

  # Async persistence - fire and forget
  # Used for non-critical updates where local state is source of truth
  defp persist_async(fun) do
    Task.start(fn ->
      try do
        fun.()
      rescue
        e ->
          Logger.error("Async persistence failed: #{inspect(e)}")
      end
    end)
  end

  # Extract mission and target from opts, supporting both entity and ID-based startup
  defp extract_mission_and_target(opts) do
    case {Keyword.get(opts, :mission), Keyword.get(opts, :target)} do
      {%Mission{} = mission, %Target{} = target} ->
        # Entity-based startup (preferred) - no DB calls for mission/target
        {mission, target}

      {nil, nil} ->
        # Legacy ID-based startup - makes DB calls
        mission_id = Keyword.fetch!(opts, :mission_id)
        target_id = Keyword.fetch!(opts, :target_id)

        Logger.warning(
          "TargetQueue started with IDs instead of entities. " <>
            "Consider passing entities to avoid DB calls."
        )

        mission = Cadence.Missions.get_mission!(mission_id)
        target = Cadence.Targets.get_target_unscoped!(target_id)

        {mission, target}

      _ ->
        raise ArgumentError,
              "TargetQueue requires either (mission: entity, target: entity) or (mission_id: id, target_id: id)"
    end
  end
end
