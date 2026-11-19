defmodule Cadence.Alarms.Queries do
  @moduledoc """
  Episode reads in their raw form. `Cadence.Reads.AlarmEpisodes` adds spacecraft, threshold
  and other cross-context detail for the console.

  Active episodes are ordered for the action queue: critical before caution, New before
  acknowledged, then the most recently opened first. Cleared episodes come newest-cleared first.
  """

  import Ecto.Query

  alias Cadence.Alarms.{EpisodeCursor, EpisodeEventRow, EpisodeRow}
  alias Cadence.Repo

  @max_limit 200
  @sources %{"catalog_monitoring" => :catalog_monitoring, "ground_limit" => :ground_limit}
  @event_kinds Map.new(EpisodeEventRow.kinds(), &{&1, String.to_atom(&1)})

  @type filters :: %{
          optional(:state) => String.t(),
          optional(:severity) => String.t(),
          optional(:spacecraft_id) => String.t(),
          optional(:source) => String.t(),
          optional(:assignee_id) => String.t(),
          optional(:limit) => pos_integer()
        }

  @human_kinds ~w(acknowledged assigned unassigned note handed_off)

  @doc """
  People's actions on the mission's alarm episodes in `[from, to)` (acknowledge, assign,
  hand off, note), newest first, for the audit log. Raises, escalations and clears are the
  system's, so they're left out.
  """
  @spec list_actions(String.t(), DateTime.t(), DateTime.t(), pos_integer()) :: [map()]
  def list_actions(mission_id, from, to, limit \\ 500) do
    EpisodeEventRow
    |> join(:inner, [event], episode in EpisodeRow, on: episode.episode_id == event.episode_id)
    |> where(
      [event],
      event.mission_id == ^mission_id and event.kind in ^@human_kinds and event.at >= ^from and
        event.at < ^to
    )
    |> order_by([event], desc: event.at, desc: event.event_id)
    |> limit(^min(limit, 1_000))
    |> select([event, episode], %{
      kind: event.kind,
      actor: event.actor,
      at: event.at,
      episode_id: event.episode_id,
      point_name: episode.point_name,
      spacecraft_id: episode.spacecraft_id,
      payload: event.payload
    })
    |> Repo.all()
  end

  @spec list(String.t(), filters()) :: [map()]
  def list(mission_id, filters \\ %{}), do: page(mission_id, filters).episodes

  @doc """
  U69 A6d: one page in the list's order and the key after its last row (`nil` when it's the
  last page). `filters[:after]` is a key from a previous page (`Alarms.EpisodeCursor`).
  """
  @spec page(String.t(), filters()) :: %{episodes: [map()], next: EpisodeCursor.key() | nil}
  def page(mission_id, filters \\ %{}) do
    state = Map.get(filters, :state, "active")
    limit = filters |> Map.get(:limit, 50) |> min(@max_limit) |> max(1)

    rows =
      EpisodeRow
      |> where([e], e.mission_id == ^mission_id)
      |> state_filter(state)
      |> field_filter(:severity, Map.get(filters, :severity))
      |> field_filter(:spacecraft_id, Map.get(filters, :spacecraft_id))
      |> field_filter(:source, Map.get(filters, :source))
      |> assignee_filter(Map.get(filters, :assignee_id))
      |> EpisodeCursor.after_key(state, Map.get(filters, :after))
      |> ordered(state)
      |> limit(^(limit + 1))
      |> Repo.all()

    shown = Enum.take(rows, limit)

    next =
      if length(rows) > limit, do: EpisodeCursor.key(List.last(shown), state)

    %{episodes: Enum.map(shown, &view/1), next: next}
  end

  @spec get(String.t(), String.t()) :: {:ok, map()} | {:error, :episode_not_found}
  def get(mission_id, episode_id) do
    case Repo.get_by(EpisodeRow, mission_id: mission_id, episode_id: episode_id) do
      nil ->
        {:error, :episode_not_found}

      episode ->
        events =
          EpisodeEventRow
          |> where([event], event.episode_id == ^episode_id)
          |> order_by([event], asc: event.at, asc: event.event_id)
          |> Repo.all()
          |> Enum.map(&event_view/1)

        {:ok, episode |> view() |> Map.put(:events, events)}
    end
  end

  @doc "A point's raised ground-limit alarms: the limit_definition change-set HOLD (#77, U43)."
  @spec active_limit_alarms(String.t(), String.t()) :: [
          %{episode_id: String.t(), severity: String.t()}
        ]
  def active_limit_alarms(mission_id, point_id) do
    EpisodeRow
    |> where(
      [e],
      e.mission_id == ^mission_id and e.source == "ground_limit" and e.parameter_ref == ^point_id and
        e.state == "active"
    )
    |> select([e], %{episode_id: e.episode_id, severity: e.severity})
    |> Repo.all()
  end

  @doc "Active episode counts by severity and status."
  @spec summary(String.t()) :: map()
  def summary(mission_id) do
    counts =
      EpisodeRow
      |> where([e], e.mission_id == ^mission_id and e.state == "active")
      |> group_by([e], [e.severity, is_nil(e.acknowledged_at)])
      |> select([e], {e.severity, is_nil(e.acknowledged_at), count(e.episode_id)})
      |> Repo.all()

    count = fn severity, new? ->
      Enum.reduce(counts, 0, fn
        {^severity, ^new?, n}, acc -> acc + n
        _row, acc -> acc
      end)
    end

    %{
      active: Enum.reduce(counts, 0, fn {_s, _n, n}, acc -> acc + n end),
      critical: %{new: count.("critical", true), acknowledged: count.("critical", false)},
      caution: %{new: count.("caution", true), acknowledged: count.("caution", false)},
      latest_change: latest_change(mission_id)
    }
  end

  @changes ~w(raised escalated deescalated cleared)

  # U69 A6: the mission's newest state change, whichever episode (partial index
  # alarm_episode_events_latest_change_idx). People's actions aren't changes.
  defp latest_change(mission_id) do
    from(ev in EpisodeEventRow,
      join: ep in EpisodeRow,
      on: ep.episode_id == ev.episode_id,
      where: ev.mission_id == ^mission_id and ev.kind in @changes,
      order_by: [desc: ev.at, desc: ev.event_id],
      limit: 1,
      select: %{
        at: ev.at,
        kind: ev.kind,
        spacecraft_id: ep.spacecraft_id,
        episode_id: ep.episode_id
      }
    )
    |> Repo.one()
  end

  @spec view(EpisodeRow.t()) :: map()
  def view(%EpisodeRow{} = episode) do
    %{
      id: episode.episode_id,
      source: Map.fetch!(@sources, episode.source),
      status: status(episode),
      cleared_unacknowledged: episode.cleared_unacknowledged,
      severity: severity(episode.severity),
      peak_severity: severity(episode.peak_severity),
      source_state: episode.source_state,
      spacecraft_id: episode.spacecraft_id,
      point: %{id: episode.parameter_ref, name: episode.point_name},
      context: episode.context,
      # The source record that opened it (a ground limit event id, a catalog transition id).
      opened_by_ref: episode.opened_by_ref,
      opened_at: episode.opened_at,
      cleared_at: episode.cleared_at,
      first_value: unwrap(episode.first_value),
      last_value: unwrap(episode.last_value),
      last_observed_at: episode.last_observed_at,
      last_evaluated_at: episode.last_evaluated_at,
      acknowledged_at: episode.acknowledged_at,
      acknowledged_by: actor(episode.acknowledged_by),
      assignee: assignee(episode.assignee),
      assigned_at: episode.assigned_at
    }
  end

  defp event_view(event) do
    %{
      id: event.event_id,
      kind: Map.fetch!(@event_kinds, event.kind),
      actor: actor(event.actor),
      at: event.at,
      payload: event.payload,
      source_ref: event.source_ref
    }
  end

  defp status(%EpisodeRow{state: "cleared"}), do: :cleared
  defp status(%EpisodeRow{acknowledged_at: nil}), do: :new
  defp status(%EpisodeRow{}), do: :acknowledged

  defp severity("critical"), do: :critical
  defp severity("caution"), do: :caution

  defp state_filter(query, "all"), do: query
  defp state_filter(query, "cleared"), do: where(query, [e], e.state == "cleared")
  defp state_filter(query, _active), do: where(query, [e], e.state == "active")

  defp field_filter(query, _field, nil), do: query
  defp field_filter(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  defp assignee_filter(query, nil), do: query

  defp assignee_filter(query, user_id),
    do: where(query, [e], fragment("?->>'id' = ?", e.assignee, ^user_id))

  defp ordered(query, "cleared"),
    do: order_by(query, [e], desc: e.cleared_at, asc: e.episode_id)

  defp ordered(query, _state) do
    order_by(query, [e],
      asc: fragment("CASE ? WHEN 'critical' THEN 0 ELSE 1 END", e.severity),
      desc: is_nil(e.acknowledged_at),
      desc: e.opened_at,
      asc: e.episode_id
    )
  end

  defp unwrap(%{"value" => value}), do: value
  defp unwrap(_value), do: nil

  defp actor(nil), do: nil
  defp actor(%{"kind" => kind, "id" => id} = doc), do: %{kind: kind, id: id, name: doc["name"]}

  defp assignee(nil), do: nil
  defp assignee(%{"id" => id} = doc), do: %{id: id, name: doc["name"]}
end
