defmodule Cadence.Reads.AlarmList do
  @moduledoc """
  Limit alarms for a mission, enriched for operators: the point's `unit` and `description`, the thresholds of the
  limit definition that produced each state, and when the point first entered
  its current state (`first_crossed_at`).

  Built on `Cadence.Reads.Alarms` (the latest limit-state projection).
  Severity uses the console vocabulary: `critical | caution | nominal`.
  """

  alias Cadence.Limits.Event
  alias Cadence.Reads.Alarms
  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.Reads.{PointInfo, SpacecraftMetadata}
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

  Every row of every page is enriched (unit, description, thresholds, `first_crossed_at`); a page
  is at most `@max_limit` rows, which bounds the per-row history reads. `opts` are test seams:
  `:latest_states` (`Alarms.snapshot/3`'s) and `:first_crossed_at` (a row function). `total` counts the rows
  matching the filters, whatever the page; `summary` counts every active alarm of the mission.
  """
  @spec load(binary(), binary(), map(), keyword()) :: {:ok, map()} | {:error, :invalid_cursor}
  def load(organization_id, mission_id, filters, opts \\ []) do
    limit = filters |> Map.get(:limit) |> page_size()

    with {:ok, after_key} <- decode_cursor(filters[:cursor]) do
      snapshot =
        Alarms.snapshot(organization_id, mission_id,
          latest_states: opts[:latest_states],
          filters: %{
            "spacecraft_id" => filters[:spacecraft_id],
            "state" => filters[:state] || "active",
            "severity" => alarms_severity(filters[:severity]),
            "query" => filters[:query],
            "point_id" => filters[:point_id],
            "spacecraft_ids" => plane_spacecraft(organization_id, mission_id, filters[:plane]),
            "exclude_spacecraft_id" => filters[:exclude_spacecraft_id]
          }
        )

      remaining = after_key |> rows_after(snapshot.rows)
      {page, rest} = Enum.split(remaining, limit)

      crossed =
        Keyword.get(opts, :first_crossed_at, &first_crossed_at(organization_id, mission_id, &1))

      thresholds = thresholds(organization_id, mission_id, page)
      points = if page == [], do: %{}, else: PointInfo.by_id(organization_id, mission_id)

      {:ok,
       %{
         observed_at: snapshot.observed_at,
         summary: summary(snapshot.summary),
         total: length(snapshot.rows),
         next_cursor: if(rest == [], do: nil, else: encode_cursor(List.last(page))),
         alarms:
           Enum.map(page, fn row ->
             row
             |> Map.merge(Map.get(points, row.point_id, PointInfo.unknown()))
             |> Map.put(:severity, severity(row.normalized_state))
             |> Map.put(:thresholds, Map.get(thresholds, definition_key(row)))
             |> Map.put(:first_crossed_at, crossed.(row))
           end)
       }}
    end
  end

  defp page_size(limit) when is_integer(limit) and limit in 1..@max_limit, do: limit
  defp page_size(_limit), do: @default_limit

  defp rows_after(nil, rows), do: rows
  defp rows_after(key, rows), do: Enum.drop_while(rows, &(Alarms.sort_key(&1) <= key))

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

  @doc false
  @spec first_crossed_from_history(atom(), [Event.t()]) :: DateTime.t() | nil
  def first_crossed_from_history(current_state, newest_first) do
    newest_first
    |> Enum.take_while(&(&1.normalized_state == current_state))
    |> List.last()
    |> case do
      nil -> nil
      %Event{} = event -> event.generation_time || event.receipt_time
    end
  end

  defp first_crossed_at(organization_id, mission_id, row) do
    history =
      LimitReads.event_history(organization_id, mission_id, row.point_id,
        spacecraft_id: row.spacecraft_id,
        limit: @history_depth,
        order: :desc
      )

    first_crossed_from_history(row.normalized_state, history)
  end

  defp thresholds(organization_id, mission_id, rows) do
    rows
    |> Enum.map(&definition_key/1)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn
      {id, version} = key, acc when is_binary(id) and is_integer(version) ->
        case Cadence.Limits.fetch_limit_definition(organization_id, mission_id, id, version) do
          {:ok, definition} -> Map.put(acc, key, definition.thresholds)
          {:error, _reason} -> acc
        end

      _key, acc ->
        acc
    end)
  end

  defp definition_key(row), do: {row.limit_definition_id, row.limit_definition_version}

  defp summary(summary) do
    %{
      active: summary.active_count,
      critical: summary.critical_count,
      caution: summary.warning_count,
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
