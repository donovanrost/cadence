defmodule Cadence.Reads.AlarmList do
  @moduledoc """
  The mission's alarms for operators (#794): the live monitoring alarms the runtime keeps in
  `semantic_latest_alarm_states` (#451 T3c; it read the ground limit states before), each with its
  point's name, unit and description and when it entered its current state (`first_crossed_at`).
  Severity uses the console vocabulary: `critical | caution | nominal`, from the alarm level
  (`SemanticRuntime.AlarmLevel`).

  What a live alarm does not carry is `null` on the wire: the sampled `value` (a state is written
  on a transition, not the value that caused it), `condition` and `limit_set_name` (ground-limit
  words), and `thresholds` (a rule is not a red/yellow pair).
  """

  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.{PointInfo, SpacecraftMetadata}
  alias Cadence.SemanticObservations.AlarmPage
  alias Cadence.SemanticRuntime.AlarmLevel
  alias Cadence.SpacecraftStore

  @default_limit 100
  @max_limit 200

  @doc """
  One page of alarms, in the list's order, and the cursor of the next.

  Options: `:spacecraft_id`, `:state` (`"active" | "nominal" | "all"`, default
  `"active"`), `:severity` (`"critical" | "caution"`), `:query`, `:point_id` (exactly that
  point), `:plane` (the spacecraft in that orbital plane, from spacecraft metadata),
  `:exclude_spacecraft_id`, `:limit` (1 to #{@max_limit}, default #{@default_limit}), `:cursor`
  (a previous page's `next_cursor`).

  The filters, the order and the page are SQL (`Cadence.SemanticObservations.AlarmPage`), so a page
  costs the page, not the fleet; the point catalog is read once for the names. `total` counts the
  rows matching the filters, whatever the page; `summary` counts every active alarm of the mission.
  """
  @spec load(binary(), binary(), map()) :: {:ok, map()} | {:error, :invalid_cursor}
  def load(organization_id, mission_id, filters) do
    limit = filters |> Map.get(:limit) |> page_size()

    with {:ok, after_key} <- decode_cursor(filters[:cursor]) do
      points = PointCatalog.list_points(organization_id, mission_id)
      sql_filters = sql_filters(organization_id, mission_id, filters, points)

      {states, more?} =
        case AlarmPage.rows(organization_id, mission_id, sql_filters, after_key, limit) do
          states when length(states) > limit -> {Enum.take(states, limit), true}
          states -> {states, false}
        end

      by_parameter = Map.new(points, &{&1.parameter_id, &1})
      info = if states == [], do: %{}, else: PointInfo.by_id(organization_id, mission_id, points)

      {:ok,
       %{
         observed_at: DateTime.utc_now(),
         summary: AlarmPage.summary(organization_id, mission_id),
         total: AlarmPage.count(organization_id, mission_id, sql_filters),
         next_cursor: if(more?, do: states |> List.last() |> AlarmPage.key() |> encode_cursor()),
         alarms: Enum.map(states, &alarm(&1, by_parameter, info))
       }}
    end
  end

  defp alarm(state, by_parameter, info) do
    point = Map.get(by_parameter, state.parameter_id)
    point_id = (point && point.point_id) || state.parameter_id

    %{
      id: state.transition_id || Integer.to_string(state.id),
      spacecraft_id: state.spacecraft_id,
      point_id: point_id,
      point_name: (point && Map.get(point, :point_name)) || point_id,
      subsystem: subsystem(point_id),
      severity: severity(state.effective_state),
      active?: AlarmLevel.alarming?(state.effective_state),
      limit_state: nil,
      evaluated_value: nil,
      limit_set_name: nil,
      thresholds: nil,
      first_crossed_at: state.receipt_time,
      generation_time: state.generation_time,
      receipt_time: state.receipt_time
    }
    |> Map.merge(Map.get(info, point_id, PointInfo.unknown()))
  end

  defp subsystem(point_id) do
    point_id |> String.split([".", "/", ":"], parts: 2) |> List.first()
  end

  defp severity(state) do
    case AlarmLevel.level(state) do
      :critical -> :critical
      :caution -> :caution
      _other -> :nominal
    end
  end

  defp sql_filters(organization_id, mission_id, filters, points) do
    by_point = Map.new(points, &{&1.point_id, &1.parameter_id})

    %{
      state: filters[:state] || "active",
      severity: filters[:severity],
      spacecraft_id: filters[:spacecraft_id],
      parameter_ids: point_parameters(by_point, filters[:point_id]),
      query: filters[:query],
      query_parameter_ids: matching_parameters(points, filters[:query]),
      exclude_spacecraft_id: filters[:exclude_spacecraft_id],
      spacecraft_ids: plane_spacecraft(organization_id, mission_id, filters[:plane])
    }
  end

  # The parameter of the point asked for (the point itself when the catalog does not map it).
  defp point_parameters(_by_point, value) when value in [nil, "", "all"], do: nil
  defp point_parameters(by_point, point_id), do: [Map.get(by_point, point_id) || point_id]

  # The parameters whose point's id, name or subsystem contains the query.
  defp matching_parameters(_points, value) when value in [nil, ""], do: []

  defp matching_parameters(points, query) do
    needle = String.downcase(query)

    for point <- points,
        is_binary(point.parameter_id),
        Enum.any?([point.point_id, Map.get(point, :point_name)], fn text ->
          is_binary(text) and String.contains?(String.downcase(text), needle)
        end),
        do: point.parameter_id
  end

  defp page_size(limit) when is_integer(limit) and limit in 1..@max_limit, do: limit
  defp page_size(_limit), do: @default_limit

  # The cursor is the sort key of the page's last row: rows that appear or clear between pages
  # neither repeat nor skip a row that stays.
  defp encode_cursor(key),
    do: key |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)

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
end
