defmodule Cadence.Reads.PointSearch do
  @moduledoc """
  M23 point search (Telemetry explore T1, ⌘K Telemetry): the mission's
  canonical points (active decom fields and governed derived telemetry, the
  same set as the LiveView `CanonicalTelemetryPoints` provider), filtered by a
  substring of id, name or description. With a `spacecraft_id`, each point
  also carries its latest value and limit state for that spacecraft.
  Callers authorize first.
  """

  alias Cadence.Governance
  alias Cadence.Limits.Event
  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.{Limits, Telemetry}

  @max_limit 200
  @text_types [:string, :bytes, :text]

  @spec search(binary(), binary(), map()) :: [map()]
  def search(organization_id, mission_id, %{} = opts) do
    query = opts |> Map.get(:q, "") |> to_string() |> String.trim() |> String.downcase()
    limit = opts |> Map.get(:limit, 50) |> min(@max_limit)

    points =
      (raw(organization_id, mission_id) ++ derived(organization_id, mission_id))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id)
      |> Enum.filter(&matches?(&1, query))
      |> Enum.take(limit)

    case opts[:spacecraft_id] do
      nil -> Enum.map(points, &Map.put(&1, :latest, nil))
      spacecraft_id -> with_latest(organization_id, mission_id, spacecraft_id, points)
    end
  end

  defp raw(organization_id, mission_id) do
    organization_id
    |> PointCatalog.list_points(mission_id)
    |> Enum.map(fn point ->
      %{
        id: point.point_id,
        name: point.field_name || point.point_id,
        description: point.description,
        unit: point.unit,
        subsystem: point.packet_name,
        type: type(point[:data_type])
      }
    end)
  end

  defp derived(organization_id, mission_id) do
    organization_id
    |> Governance.list_derived_definitions(mission_id)
    |> Enum.map(fn definition ->
      %{
        id: definition.point_id,
        name: Map.get(definition, :point_name) || definition.point_id,
        description: Map.get(definition, :description) || "Derived telemetry",
        unit: Map.get(definition, :unit),
        subsystem: "Derived",
        type: "numeric"
      }
    end)
  end

  defp with_latest(organization_id, mission_id, spacecraft_id, points) do
    samples =
      organization_id
      |> Telemetry.latest_values_for_mission(mission_id, spacecraft_id: spacecraft_id)
      |> Map.new(&{&1.point_id, &1})

    limits =
      organization_id
      |> Limits.latest_states_for_mission(mission_id, spacecraft_id: spacecraft_id)
      |> Enum.group_by(& &1.point_id)

    Enum.map(points, fn point ->
      latest =
        case Map.get(samples, point.id) do
          nil ->
            nil

          sample ->
            %{
              value: sample.engineering_value || sample.raw_value,
              received_at: sample.receipt_time,
              limit_state: limit_state(Map.get(limits, point.id, []))
            }
        end

      Map.put(point, :latest, latest)
    end)
  end

  defp limit_state([]), do: :no_data

  defp limit_state(events) do
    cond do
      Enum.any?(events, &match?(%Event{normalized_state: :red}, &1)) -> :critical
      Enum.any?(events, &match?(%Event{normalized_state: :yellow}, &1)) -> :caution
      true -> :nominal
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
