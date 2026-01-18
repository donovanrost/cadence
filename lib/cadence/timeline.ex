defmodule Cadence.Timeline do
  @moduledoc """
  Timeline context for unified mission event queries.

  Provides a single interface to query and stream events from the recordings system:
  - Command recordings (dispatched, sent, verified, etc.)
  - Alarm recordings (triggered, acknowledged, cleared, etc.)
  - Procedure recordings
  - Automation recordings
  - Scheduled future events (from queue)

  Events are normalized into `Cadence.Timeline.Event` structs for consistent
  display in the Timeline Mode UI.
  """

  import Ecto.Query
  alias Cadence.Alarms.Alarm
  alias Cadence.Buckets
  alias Cadence.Buckets.Bucket
  alias Cadence.Commands.QueueEntry
  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Recordings
  alias Cadence.Recordings.Recording
  alias Cadence.Repo
  alias Cadence.Targets.Target
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Timeline.Event

  # Event publisher accessor
  defp event_publisher, do: EventPublisher.impl()

  @type event_type :: :command | :alarm | :procedure | :automation | :system
  @type list_opts :: [
          types: [event_type()],
          target_ids: [binary()],
          limit: pos_integer(),
          include_future: boolean(),
          cursor: DateTime.t() | nil
        ]

  # Map event types to aggregate types in recordings
  @type_to_aggregate %{
    command: ["Command", "QueueEntry"],
    alarm: ["Alarm"],
    procedure: ["ProcedureExecution"],
    automation: ["Automation"]
  }

  @doc """
  List timeline events for a mission within a time range.

  Returns events sorted by timestamp descending (most recent first for past events).

  ## Options

    * `:types` - List of event types to include (default: all)
    * `:target_ids` - Filter to specific targets
    * `:limit` - Maximum events to return (default: 100)
    * `:include_future` - Include scheduled future events (default: true)
    * `:cursor` - For pagination, fetch events before this timestamp

  ## Examples

      iex> Timeline.list_events(mission_id, ~U[2024-01-01 00:00:00Z], ~U[2024-01-02 00:00:00Z])
      [%Event{}, ...]

      iex> Timeline.list_events(mission_id, start, end, types: [:command, :alarm], limit: 50)
      [%Event{}, ...]
  """
  @spec list_events(binary(), DateTime.t(), DateTime.t(), list_opts()) :: [Event.t()]
  def list_events(path_prefix, start_time, end_time, opts \\ []) do
    types = Keyword.get(opts, :types, [:command, :alarm, :procedure, :automation])
    limit = Keyword.get(opts, :limit, 100)
    include_future = Keyword.get(opts, :include_future, true)
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)

    # Convert types to aggregate types for recordings query
    aggregate_types = aggregate_types_for(types)

    # Query recordings using path prefix
    recordings =
      Recordings.list_recordings(start_time, end_time,
        aggregate_types: aggregate_types,
        path_prefix: path_prefix,
        organization_id: organization_id,
        limit: limit
      )

    # Batch load recordables to avoid N+1 queries
    recordings_with_recordables = Recordings.load_recordables_for_recordings(recordings)

    # Batch load target_ids for all recordings
    target_id_map = load_target_ids_for_recordings(recordings)

    # Batch load targets for display names
    target_name_map = load_target_names(Map.values(target_id_map))

    # Convert recordings to timeline events (passing pre-loaded recordable and target_id)
    events =
      Enum.map(recordings_with_recordables, fn %{recording: recording, recordable: recordable} ->
        target_id = Map.get(target_id_map, recording.id)
        target_name = Map.get(target_name_map, target_id)

        Event.from_recording(recording,
          recordable: recordable,
          target_id: target_id,
          target: if(is_binary(target_name), do: %{name: target_name}, else: nil)
        )
      end)

    # Add scheduled future commands if requested
    events =
      if include_future and :command in types and mission_id do
        scheduled = list_scheduled_commands(mission_id, end_time, [], limit)
        events ++ scheduled
      else
        events
      end

    # Sort all events by timestamp and apply limit
    events
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  List recent timeline events for a mission (convenience function).

  Fetches events from the last `minutes` minutes up to now, plus scheduled future events.
  """
  @spec list_recent_events(binary(), pos_integer(), list_opts()) :: [Event.t()]
  def list_recent_events(mission_id, minutes \\ 60, opts \\ []) do
    now = CadenceTime.now()
    start_time = DateTime.add(now, -minutes, :minute)
    # Include future events up to 24 hours ahead
    end_time = DateTime.add(now, 24, :hour)

    # Get the mission's bucket to use its path for filtering recordings
    bucket_path = get_mission_bucket_path(mission_id)

    # Pass mission_id in opts for scheduled commands query
    opts = Keyword.put(opts, :mission_id, mission_id)

    list_events(bucket_path, start_time, end_time, opts)
  end

  @doc """
  List timeline events for a mission within a time range.

  This is a convenience wrapper around `list_events/4` that handles
  looking up the mission's bucket path automatically.
  """
  @spec list_events_for_mission(binary(), DateTime.t(), DateTime.t(), list_opts()) :: [Event.t()]
  def list_events_for_mission(mission_id, start_time, end_time, opts \\ []) do
    bucket_path = get_mission_bucket_path(mission_id)
    opts = Keyword.put(opts, :mission_id, mission_id)
    list_events(bucket_path, start_time, end_time, opts)
  end

  @doc """
  Subscribe to real-time timeline events for a mission.

  This subscribes to all relevant PubSub topics for live updates.
  """
  @spec subscribe(binary()) :: :ok
  def subscribe(mission_id) do
    # Subscribe to command-related events via outbox
    Cadence.Outbox.subscribe_mission(mission_id)

    # Subscribe to alarm events
    event_publisher().subscribe("mission:#{mission_id}:alarms")

    # Subscribe to procedure events
    event_publisher().subscribe("mission:#{mission_id}:procedures")

    # Subscribe to automation events
    event_publisher().subscribe("mission:#{mission_id}:automations")

    :ok
  end

  @doc """
  Unsubscribe from timeline events for a mission.
  """
  @spec unsubscribe(binary()) :: :ok
  def unsubscribe(mission_id) do
    event_publisher().unsubscribe("mission:#{mission_id}:alarms")
    event_publisher().unsubscribe("mission:#{mission_id}:procedures")
    event_publisher().unsubscribe("mission:#{mission_id}:automations")
    :ok
  end

  @doc """
  Convert a raw event from PubSub into a Timeline.Event.

  Used by LiveView handlers to transform incoming events.
  """
  @spec event_from_pubsub(atom(), map()) :: Event.t() | nil
  def event_from_pubsub(:recording_created, %Recording{} = recording) do
    Event.from_recording(recording)
  end

  def event_from_pubsub(:alarm_triggered, _alarm) do
    # Alarms now go through recordings
    nil
  end

  def event_from_pubsub(:alarm_updated, _alarm) do
    # Alarms now go through recordings
    nil
  end

  def event_from_pubsub(:procedure_event, _execution) do
    # Procedures now go through recordings
    nil
  end

  def event_from_pubsub(_, _), do: nil

  # Private functions

  defp list_scheduled_commands(mission_id, after_time, target_ids, limit) do
    now = CadenceTime.now()

    query =
      from(qe in QueueEntry,
        where: qe.mission_id == ^mission_id,
        where: qe.status == :pending,
        where: not is_nil(qe.scheduled_at),
        where: qe.scheduled_at > ^now,
        where: qe.scheduled_at <= ^after_time,
        order_by: [asc: qe.scheduled_at],
        limit: ^limit,
        preload: [:target]
      )

    query =
      if target_ids != [] do
        from(qe in query, where: qe.target_id in ^target_ids)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn entry ->
      Event.from_scheduled_command(entry, target: entry.target)
    end)
  end

  @doc """
  Load older timeline events before a cursor timestamp.

  Used for infinite scroll pagination. Returns events older than the cursor,
  sorted by timestamp descending.

  ## Options

    * `:types` - List of event types to include (default: all)
    * `:target_ids` - Filter to specific targets
    * `:limit` - Maximum events to return (default: 50)
  """
  @spec list_events_before(binary(), DateTime.t(), list_opts()) :: [Event.t()]
  def list_events_before(mission_id, cursor, opts \\ []) do
    types = Keyword.get(opts, :types, [:command, :alarm, :procedure, :automation])
    limit = Keyword.get(opts, :limit, 50)
    organization_id = Keyword.get(opts, :organization_id)

    # Get the mission's bucket path for filtering recordings
    bucket_path = get_mission_bucket_path(mission_id)

    # Convert types to aggregate types for recordings query
    aggregate_types = aggregate_types_for(types)

    # Query recordings before cursor using path prefix
    recordings =
      Recordings.list_recordings_before(%{timestamp: cursor, id: nil},
        aggregate_types: aggregate_types,
        path_prefix: bucket_path,
        organization_id: organization_id,
        limit: limit
      )

    # Batch load recordables to avoid N+1 queries
    recordings_with_recordables = Recordings.load_recordables_for_recordings(recordings)

    # Batch load target_ids for all recordings
    target_id_map = load_target_ids_for_recordings(recordings)

    # Batch load targets for display names
    target_name_map = load_target_names(Map.values(target_id_map))

    # Convert recordings to timeline events (passing pre-loaded recordable and target_id)
    events =
      Enum.map(recordings_with_recordables, fn %{recording: recording, recordable: recordable} ->
        target_id = Map.get(target_id_map, recording.id)
        target_name = Map.get(target_name_map, target_id)

        Event.from_recording(recording,
          recordable: recordable,
          target_id: target_id,
          target: if(is_binary(target_name), do: %{name: target_name}, else: nil)
        )
      end)

    # Sort all events by timestamp descending and apply limit
    events
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Get a single event by its composite ID.

  Event IDs are prefixed with their source type (e.g., "rec-uuid" for recordings,
  "sched-cmd-uuid" for scheduled commands).
  """
  @spec get_event(binary()) :: Event.t() | nil
  def get_event("rec-" <> id) do
    # Unscoped because event IDs are internal references, authorization happens at the caller level
    case Recordings.get_recording_unscoped(id) do
      nil -> nil
      recording -> Event.from_recording(recording)
    end
  end

  def get_event("sched-cmd-" <> id) do
    case Repo.get(QueueEntry, id) |> Repo.preload(:target) do
      nil -> nil
      entry -> Event.from_scheduled_command(entry, target: entry.target)
    end
  end

  def get_event(_), do: nil

  @doc """
  Get the full state change history for an event.

  Returns all recordings for the same aggregate, ordered by timestamp ascending.
  This shows the progression of state changes (e.g., CommandDispatched → CommandSent → CommandVerified).

  Returns an empty list if the event has no aggregate metadata or if no history is found.
  """
  @spec get_event_state_history(Event.t()) :: [Event.t()]
  def get_event_state_history(%Event{metadata: metadata}) when is_map(metadata) do
    aggregate_type = Map.get(metadata, :aggregate_type)
    aggregate_id = Map.get(metadata, :aggregate_id)

    if aggregate_type && aggregate_id do
      Recordings.get_aggregate_history_with_recordables(aggregate_type, aggregate_id)
      |> Enum.map(fn %{recording: recording, recordable: recordable} ->
        Event.from_recording(recording, recordable: recordable)
      end)
    else
      []
    end
  end

  def get_event_state_history(_), do: []

  # Private helpers

  defp get_mission_bucket_path(mission_id) do
    case Buckets.get_bucket_by_bucketable("Mission", mission_id) do
      nil -> nil
      bucket -> bucket.path
    end
  end

  defp aggregate_types_for(types) when is_list(types) do
    types
    |> Enum.flat_map(fn type -> Map.get(@type_to_aggregate, type, []) end)
    |> Enum.uniq()
  end

  @doc false
  # Batch load target_ids for recordings.
  # Prefer deriving from target buckets (recording.bucket_id -> bucketable_id),
  # then fall back to aggregate-specific lookups where needed.
  # Returns a map of recording.id -> target_id
  defp load_target_ids_for_recordings(recordings) do
    target_ids_by_bucket = load_target_ids_for_buckets(recordings)

    initial =
      Enum.reduce(recordings, %{}, fn recording, acc ->
        with bucket_id when is_binary(bucket_id) <- recording.bucket_id,
             target_id when is_binary(target_id) <- Map.get(target_ids_by_bucket, bucket_id) do
          Map.put(acc, recording.id, target_id)
        else
          _ -> acc
        end
      end)

    recordings
    |> Enum.reject(&Map.has_key?(initial, &1.id))
    |> Enum.group_by(& &1.aggregate_type)
    |> Enum.reduce(initial, &merge_target_ids_for_type/2)
  end

  defp merge_target_ids_for_type({aggregate_type, recs}, acc) do
    aggregate_ids = Enum.map(recs, & &1.aggregate_id) |> Enum.uniq()
    target_ids = load_target_ids_by_type(aggregate_type, aggregate_ids)
    map_recordings_to_target_ids(recs, target_ids, acc)
  end

  defp load_target_ids_for_buckets(recordings) do
    bucket_ids =
      recordings
      |> Enum.map(& &1.bucket_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if bucket_ids == [] do
      %{}
    else
      Bucket
      |> where([b], b.id in ^bucket_ids)
      |> where([b], b.bucket_type == "target" or b.bucketable_type in ["Target", "target"])
      |> select([b], {b.id, b.bucketable_id})
      |> Repo.all()
      |> Map.new()
    end
  end

  defp load_target_ids_by_type("QueueEntry", aggregate_ids) do
    QueueEntry
    |> where([q], q.id in ^aggregate_ids)
    |> select([q], {q.id, q.target_id})
    |> Repo.all()
    |> Map.new()
  end

  defp load_target_ids_by_type("Command", aggregate_ids) do
    QueueEntry
    |> where([q], q.command_aggregate_id in ^aggregate_ids)
    |> select([q], {q.command_aggregate_id, q.target_id})
    |> Repo.all()
    |> Map.new()
  end

  defp load_target_ids_by_type("Alarm", aggregate_ids) do
    Alarm
    |> where([a], a.id in ^aggregate_ids)
    |> select([a], {a.id, a.target_id})
    |> Repo.all()
    |> Map.new()
  end

  # Procedures and automations may not have target_id directly
  defp load_target_ids_by_type(_aggregate_type, _aggregate_ids), do: %{}

  defp load_target_names(target_ids) when is_list(target_ids) do
    ids = target_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      Target
      |> where([t], t.id in ^ids)
      |> select([t], {t.id, t.name})
      |> Repo.all()
      |> Map.new()
    end
  end

  defp map_recordings_to_target_ids(recs, target_ids, acc) do
    Enum.reduce(recs, acc, fn rec, inner_acc ->
      case Map.get(target_ids, rec.aggregate_id) do
        nil -> inner_acc
        target_id -> Map.put(inner_acc, rec.id, target_id)
      end
    end)
  end
end
