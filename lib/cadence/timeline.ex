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
  alias Cadence.Commands.QueueEntry
  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Recordings
  alias Cadence.Recordings.Recording
  alias Cadence.Repo
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
    command: "Command",
    alarm: "Alarm",
    procedure: "ProcedureExecution",
    automation: "Automation",
    queue: "QueueEntry"
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
    aggregate_types = Enum.map(types, &Map.get(@type_to_aggregate, &1)) |> Enum.reject(&is_nil/1)

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

    # Convert recordings to timeline events (passing pre-loaded recordable)
    events =
      Enum.map(recordings_with_recordables, fn %{recording: recording, recordable: recordable} ->
        Event.from_recording(recording, recordable: recordable)
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
    now = DateTime.utc_now()
    start_time = DateTime.add(now, -minutes, :minute)
    # Include future events up to 24 hours ahead
    end_time = DateTime.add(now, 24, :hour)

    list_events(mission_id, start_time, end_time, opts)
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
    now = DateTime.utc_now()

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
  def list_events_before(path_prefix, cursor, opts \\ []) do
    types = Keyword.get(opts, :types, [:command, :alarm, :procedure, :automation])
    limit = Keyword.get(opts, :limit, 50)
    organization_id = Keyword.get(opts, :organization_id)

    # Convert types to aggregate types for recordings query
    aggregate_types = Enum.map(types, &Map.get(@type_to_aggregate, &1)) |> Enum.reject(&is_nil/1)

    # Query recordings before cursor using path prefix
    recordings =
      Recordings.list_recordings_before(%{timestamp: cursor, id: nil},
        aggregate_types: aggregate_types,
        path_prefix: path_prefix,
        organization_id: organization_id,
        limit: limit
      )

    # Batch load recordables to avoid N+1 queries
    recordings_with_recordables = Recordings.load_recordables_for_recordings(recordings)

    # Convert recordings to timeline events (passing pre-loaded recordable)
    events =
      Enum.map(recordings_with_recordables, fn %{recording: recording, recordable: recordable} ->
        Event.from_recording(recording, recordable: recordable)
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
end
