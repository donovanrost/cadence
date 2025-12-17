defmodule Cadence.Timeline do
  @moduledoc """
  Timeline context for unified mission event queries.

  Provides a single interface to query and stream events from multiple sources:
  - Command logs
  - Alarm events
  - Procedure executions
  - Automation executions
  - Scheduled future events

  Events are normalized into `Cadence.Timeline.Event` structs for consistent
  display in the Timeline Mode UI.
  """

  import Ecto.Query
  alias Cadence.Repo
  alias Cadence.Timeline.Event
  alias Cadence.Commands.CommandLog
  alias Cadence.Commands.QueueEntry
  alias Cadence.Alarms.AlarmEvent
  alias Cadence.Alarms.Alarm

  @type event_type :: :command | :alarm | :procedure | :automation | :system
  @type list_opts :: [
          types: [event_type()],
          target_ids: [binary()],
          limit: pos_integer(),
          include_future: boolean(),
          cursor: DateTime.t() | nil
        ]

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
  def list_events(mission_id, start_time, end_time, opts \\ []) do
    types = Keyword.get(opts, :types, [:command, :alarm, :procedure, :automation])
    target_ids = Keyword.get(opts, :target_ids, [])
    limit = Keyword.get(opts, :limit, 100)
    include_future = Keyword.get(opts, :include_future, true)

    events = []

    # Collect events from each source based on requested types
    events =
      if :command in types do
        command_events = list_command_events(mission_id, start_time, end_time, target_ids, limit)
        events ++ command_events
      else
        events
      end

    # Add scheduled future commands if requested
    events =
      if include_future and :command in types do
        scheduled = list_scheduled_commands(mission_id, end_time, target_ids, limit)
        events ++ scheduled
      else
        events
      end

    # Add alarm events
    events =
      if :alarm in types do
        alarm_events = list_alarm_events(mission_id, start_time, end_time, target_ids, limit)
        events ++ alarm_events
      else
        events
      end

    # TODO: Add procedure events when expanding beyond vertical slice
    # TODO: Add automation events when expanding beyond vertical slice

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
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")

    # Subscribe to procedure events
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:procedures")

    # Subscribe to automation events
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:automations")

    :ok
  end

  @doc """
  Unsubscribe from timeline events for a mission.
  """
  @spec unsubscribe(binary()) :: :ok
  def unsubscribe(mission_id) do
    Phoenix.PubSub.unsubscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
    Phoenix.PubSub.unsubscribe(Cadence.PubSub, "mission:#{mission_id}:procedures")
    Phoenix.PubSub.unsubscribe(Cadence.PubSub, "mission:#{mission_id}:automations")
    :ok
  end

  @doc """
  Convert a raw event from PubSub into a Timeline.Event.

  Used by LiveView handlers to transform incoming events.
  """
  @spec event_from_pubsub(atom(), map()) :: Event.t() | nil
  def event_from_pubsub(:command_log_updated, %CommandLog{} = log) do
    Event.from_command_log(log)
  end

  def event_from_pubsub(:alarm_triggered, _alarm) do
    # TODO: Implement when expanding beyond vertical slice
    nil
  end

  def event_from_pubsub(:alarm_updated, _alarm) do
    # TODO: Implement when expanding beyond vertical slice
    nil
  end

  def event_from_pubsub(:procedure_event, _execution) do
    # TODO: Implement when expanding beyond vertical slice
    nil
  end

  def event_from_pubsub(_, _), do: nil

  # Private functions

  defp list_command_events(mission_id, start_time, end_time, target_ids, limit) do
    query =
      from(cl in CommandLog,
        where: cl.mission_id == ^mission_id,
        where: cl.sent_at >= ^start_time and cl.sent_at <= ^end_time,
        order_by: [desc: cl.sent_at],
        limit: ^limit,
        preload: [:target]
      )

    query =
      if target_ids != [] do
        from(cl in query, where: cl.target_id in ^target_ids)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn log ->
      Event.from_command_log(log, target: log.target)
    end)
  end

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

  defp list_alarm_events(mission_id, start_time, end_time, target_ids, limit) do
    query =
      from(ae in AlarmEvent,
        join: a in Alarm, on: ae.alarm_id == a.id,
        where: a.mission_id == ^mission_id,
        where: ae.inserted_at >= ^start_time and ae.inserted_at <= ^end_time,
        order_by: [desc: ae.inserted_at],
        limit: ^limit,
        preload: [alarm: :target]
      )

    query =
      if target_ids != [] do
        from([ae, a] in query, where: a.target_id in ^target_ids)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn event ->
      Event.from_alarm_event(event, alarm: event.alarm, target: event.alarm && event.alarm.target)
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
    target_ids = Keyword.get(opts, :target_ids, [])
    limit = Keyword.get(opts, :limit, 50)

    events = []

    # Collect events from each source before the cursor
    events =
      if :command in types do
        command_events = list_command_events_before(mission_id, cursor, target_ids, limit)
        events ++ command_events
      else
        events
      end

    events =
      if :alarm in types do
        alarm_events = list_alarm_events_before(mission_id, cursor, target_ids, limit)
        events ++ alarm_events
      else
        events
      end

    # TODO: Add procedure events when expanding beyond vertical slice
    # TODO: Add automation events when expanding beyond vertical slice

    # Sort all events by timestamp descending and apply limit
    events
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(limit)
  end

  defp list_command_events_before(mission_id, cursor, target_ids, limit) do
    query =
      from(cl in CommandLog,
        where: cl.mission_id == ^mission_id,
        where: cl.sent_at < ^cursor,
        order_by: [desc: cl.sent_at],
        limit: ^limit,
        preload: [:target]
      )

    query =
      if target_ids != [] do
        from(cl in query, where: cl.target_id in ^target_ids)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn log ->
      Event.from_command_log(log, target: log.target)
    end)
  end

  defp list_alarm_events_before(mission_id, cursor, target_ids, limit) do
    query =
      from(ae in AlarmEvent,
        join: a in Alarm, on: ae.alarm_id == a.id,
        where: a.mission_id == ^mission_id,
        where: ae.inserted_at < ^cursor,
        order_by: [desc: ae.inserted_at],
        limit: ^limit,
        preload: [alarm: :target]
      )

    query =
      if target_ids != [] do
        from([ae, a] in query, where: a.target_id in ^target_ids)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn event ->
      Event.from_alarm_event(event, alarm: event.alarm, target: event.alarm && event.alarm.target)
    end)
  end

  @doc """
  Get a single event by its composite ID.

  Event IDs are prefixed with their source type (e.g., "cmd-uuid", "alm-uuid").
  """
  @spec get_event(binary()) :: Event.t() | nil
  def get_event("cmd-" <> id) do
    case Repo.get(CommandLog, id) |> Repo.preload(:target) do
      nil -> nil
      log -> Event.from_command_log(log, target: log.target)
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
