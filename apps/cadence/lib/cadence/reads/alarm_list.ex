defmodule Cadence.Reads.AlarmList do
  @moduledoc """
  Limit alarms for a mission, enriched for operators: the point's `unit` and `description`, the thresholds of the
  limit definition that produced each state, and when the point first entered
  its current state (`first_crossed_at`).

  Built on `Cadence.Reads.Alarms` (the latest limit-state projection).
  Severity uses the console vocabulary: `critical | caution | nominal`.
  """

  alias Cadence.Limits.Store.AlarmPage
  alias Cadence.Reads.{Alarms, PointInfo, SpacecraftMetadata}
  alias Cadence.SpacecraftStore

  @history_depth 200
  @default_limit 100
  @max_limit 200

  @doc """
  One page of alarms, in the list's order, and the cursor of the next.

  Options: `:spacecraft_id`, `:state` (`"active" | "nominal" | "all"`, default
  `"active"`), `:severity` (`"critical" | "caution"`), `:query`, `:point_id` (exactly that
  point), `:plane` (the spacecraft in that orbital plane, from spacecraft metadata),
  `:exclude_spacecraft_id`, `:limit` (1 to #{@max_limit}, default #{@default_limit}), `:cursor`
  (a previous page's `next_cursor`).

  The filters, the order and the page are SQL (`Cadence.Limits.Store.AlarmPage`), so a page costs the
  page, not the fleet. Every row of every page is enriched (unit, description, thresholds,
  `first_crossed_at`) with a fixed number of queries however many rows the page holds. `total`
  counts the rows matching the filters, whatever the page; `summary` counts every active alarm of
  the mission. `first_crossed_at` looks back over the newest #{@history_depth} evaluations of the
  point on that spacecraft.
  """
  @spec load(binary(), binary(), map()) :: {:ok, map()} | {:error, :invalid_cursor}
  def load(organization_id, mission_id, filters) do
    limit = filters |> Map.get(:limit) |> page_size()

    with {:ok, after_key} <- decode_cursor(filters[:cursor]) do
      sql_filters = sql_filters(organization_id, mission_id, filters)

      {events, more?} =
        case AlarmPage.rows(organization_id, mission_id, sql_filters, after_key, limit) do
          events when length(events) > limit -> {Enum.take(events, limit), true}
          events -> {events, false}
        end

      rows = Enum.map(events, &Alarms.row/1)
      crossed = crossed_at(mission_id, events)
      thresholds = thresholds(organization_id, mission_id, rows)
      points = if rows == [], do: %{}, else: PointInfo.by_id(organization_id, mission_id)

      {:ok,
       %{
         observed_at: DateTime.utc_now(),
         summary: summary(AlarmPage.summary(organization_id, mission_id)),
         total: AlarmPage.count(organization_id, mission_id, sql_filters),
         next_cursor: if(more?, do: encode_cursor(List.last(rows))),
         alarms:
           Enum.map(rows, fn row ->
             row
             |> Map.merge(Map.get(points, row.point_id, PointInfo.unknown()))
             |> Map.put(:severity, severity(row.normalized_state))
             |> Map.put(:thresholds, Map.get(thresholds, definition_key(row)))
             |> Map.put(:first_crossed_at, Map.get(crossed, {row.spacecraft_id, row.point_id}))
           end)
       }}
    end
  end

  defp sql_filters(organization_id, mission_id, filters) do
    %{
      state: filters[:state] || "active",
      severity: alarms_severity(filters[:severity]),
      spacecraft_id: filters[:spacecraft_id],
      point_id: filters[:point_id],
      query: filters[:query],
      exclude_spacecraft_id: filters[:exclude_spacecraft_id],
      spacecraft_ids: plane_spacecraft(organization_id, mission_id, filters[:plane])
    }
  end

  defp crossed_at(mission_id, events) do
    AlarmPage.crossed_at(
      mission_id,
      Enum.map(events, &{&1.spacecraft_id, &1.point_id, Atom.to_string(&1.normalized_state)})
    )
  end

  defp page_size(limit) when is_integer(limit) and limit in 1..@max_limit, do: limit
  defp page_size(_limit), do: @default_limit

  # The cursor is the sort key of the page's last row: rows that appear or clear between pages
  # neither repeat nor skip a row that stays.
  defp encode_cursor(row),
    do: row |> Alarms.sort_key() |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) and byte_size(cursor) <= 1_024 do
    with {:ok, binary} <- Base.url_decode64(cursor, padding: false),
         {:ok, key} <- safe_term(binary),
         {severity, received, spacecraft, point}
         when is_integer(severity) and is_integer(received) and is_binary(spacecraft) and
                is_binary(point) <- key do
      {:ok, key}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp decode_cursor(_cursor), do: {:error, :invalid_cursor}

  defp safe_term(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> :error
  end

  # A plane is its spacecraft (an empty plane matches nothing); no plane is no restriction.
  defp plane_spacecraft(_organization_id, _mission_id, nil), do: nil

  defp plane_spacecraft(organization_id, mission_id, plane) when is_integer(plane) do
    for craft <- SpacecraftStore.list_spacecraft(organization_id, mission_id),
        SpacecraftMetadata.integer(craft.metadata || %{}, "plane") == plane,
        do: craft.spacecraft_id
  end

  defp thresholds(organization_id, mission_id, rows) do
    keys = rows |> Enum.map(&definition_key/1) |> Enum.uniq()

    organization_id
    |> Cadence.Limits.fetch_limit_definitions(mission_id, keys)
    |> Map.new(fn {key, definition} -> {key, definition.thresholds} end)
  end

  defp definition_key(row), do: {row.limit_definition_id, row.limit_definition_version}

  defp summary(summary) do
    %{
      active: summary.active,
      critical: summary.critical,
      caution: summary.warning,
      latest_transition_at: summary.latest_transition_at
    }
  end

  defp severity(:red), do: :critical
  defp severity(:yellow), do: :caution
  defp severity(_other), do: :nominal

  defp alarms_severity("critical"), do: "critical"
  defp alarms_severity("caution"), do: "warning"
  defp alarms_severity(_other), do: nil
end
