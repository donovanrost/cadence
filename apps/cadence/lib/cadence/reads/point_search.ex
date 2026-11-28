defmodule Cadence.Reads.PointSearch do
  @moduledoc """
  M23 point search (Telemetry explore T1, ⌘K Telemetry): the mission's
  operator point catalog (`Cadence.Ops.PointCatalog`: the active binding set's
  packet fields and the active revision's derived points, the algorithm outputs
  of #451 T4b), filtered by a substring of id, name or description. With a
  `spacecraft_id`, each point also carries its latest value and limit state for
  that spacecraft: live from
  the current-value store, or (`source: :history`) the newest stored sample when
  the live store has none since a restart. The limit state comes from the runtime's alarm states and
  the compiled plan either way (`Reads.PointLimitState`; `no_data` when nothing monitors the point
  on that spacecraft).
  Callers authorize first.
  """

  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.{MonitoredParameters, PointLimitState, Telemetry}
  alias Cadence.Telemetry.PointLatest

  @max_limit 200
  @text_types [:string, :bytes, :text]

  @spec search(binary(), binary(), map()) :: [map()]
  def search(organization_id, mission_id, %{} = opts) do
    query = opts |> Map.get(:q, "") |> to_string() |> String.trim() |> String.downcase()
    limit = opts |> Map.get(:limit, 50) |> min(@max_limit)

    catalog =
      PointCatalog.list_points(organization_id, mission_id,
        spacecraft_id: Map.get(opts, :spacecraft_id)
      )

    points =
      catalog
      |> Enum.map(&point/1)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id)
      |> Enum.filter(&matches?(&1, query))
      |> Enum.take(limit)
      |> with_has_limits(organization_id, mission_id, catalog)

    case opts[:spacecraft_id] do
      nil -> Enum.map(points, &Map.put(&1, :latest, nil))
      spacecraft_id -> with_latest(organization_id, mission_id, spacecraft_id, points, catalog)
    end
  end

  # ux T1: whether the point has limits at all (the compiled plan evaluates its parameter on some
  # spacecraft), so 'No limits' (false) reads apart from 'Not checked yet' (true, with limit_state
  # no_data). Point-level: a point's limits exist with or without a sample.
  defp with_has_limits(points, organization_id, mission_id, catalog) do
    limited = MonitoredParameters.anywhere(organization_id, mission_id)
    parameters = Map.new(catalog, &{&1.point_id, &1.parameter_id || &1.point_id})

    Enum.map(points, fn point ->
      parameter = Map.get(parameters, point.id, point.id)
      Map.put(point, :has_limits, MapSet.member?(limited, parameter))
    end)
  end

  defp point(%{source: :derived} = point) do
    %{
      id: point.point_id,
      name: point.name,
      description: point.description,
      unit: point.unit,
      subsystem: "Derived",
      type: type(point.data_type)
    }
  end

  defp point(point) do
    %{
      id: point.point_id,
      name: point.field_name || point.point_id,
      description: point.description,
      unit: point.unit,
      subsystem: point.packet_name,
      type: type(point[:data_type])
    }
  end

  defp with_latest(organization_id, mission_id, spacecraft_id, points, catalog) do
    live =
      organization_id
      |> Telemetry.latest_values_for_mission(mission_id, spacecraft_id: spacecraft_id)
      |> Map.new(&{&1.point_id, {:live, &1}})

    samples = Map.merge(stored(organization_id, mission_id, spacecraft_id, points, live), live)

    limits = PointLimitState.load(organization_id, mission_id, spacecraft_id, catalog)

    Enum.map(points, fn point ->
      latest =
        case Map.get(samples, point.id) do
          nil ->
            nil

          {source, sample} ->
            %{
              value: sample.engineering_value || sample.raw_value,
              received_at: sample.receipt_time,
              limit_state: Map.get(limits, point.id, :no_data),
              source: source
            }
        end

      Map.put(point, :latest, latest)
    end)
  end

  # The live store is empty for a point until its spacecraft sends telemetry after a restart;
  # the history store still has the newest stored sample (`source: :history`).
  defp stored(organization_id, mission_id, spacecraft_id, points, live) do
    missing = for point <- points, not Map.has_key?(live, point.id), do: point.id

    case PointLatest.for_spacecraft(organization_id, mission_id, spacecraft_id, missing) do
      {:ok, samples} -> Map.new(samples, &{&1.point_id, {:history, &1}})
      {:error, _reason} -> %{}
    end
  end

  defp type(data_type) when data_type in @text_types, do: "text"
  defp type(:enum), do: "enum"
  defp type(_numeric), do: "numeric"

  defp matches?(_point, ""), do: true

  defp matches?(point, query) do
    [point.id, point.name, point.description]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&String.contains?(String.downcase(&1), query))
  end
end
