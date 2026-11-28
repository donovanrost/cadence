defmodule Cadence.Reads.SpacecraftLive do
  @moduledoc """
  Reads behind the console's live spacecraft topic (M8, Investigate B1):
  the selected points' display facts and their latest samples for one spacecraft.

    * `type` is `numeric | enum | text`: from the catalog type's `base_type` when the active
      revision declares one (`enumerated` and boolean are `enum`), else from the decoded field's
      `data_type`.
    * `limit_state` is the point's alarm level on this spacecraft (`Reads.PointLimitState`):
      `critical`, `caution`, or `nominal`, and `nil` when nothing monitors the point there.
  """

  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.{CatalogDeclarations, PointLimitState, Telemetry}

  @max_points 200

  @doc "The most points one subscription may select."
  @spec max_points() :: pos_integer()
  def max_points, do: @max_points

  @doc "`[%{point_id, unit, type}]` in the order asked; unknown points have nil unit and type."
  @spec points(binary(), binary(), [binary()]) :: [map()]
  def points(_org, _mission, []), do: []

  def points(org, mission, point_ids) do
    catalog = Map.new(PointCatalog.list_points(org, mission), &{&1.point_id, &1})

    declarations =
      CatalogDeclarations.closure(
        org,
        mission,
        CatalogDeclarations.active_revision_id(org, mission),
        catalog
        |> Map.take(point_ids)
        |> Map.values()
        |> Enum.map(& &1.parameter_id)
        |> Enum.reject(&is_nil/1)
      )

    Enum.map(point_ids, fn id ->
      case Map.get(catalog, id) do
        nil ->
          %{point_id: id, unit: nil, type: nil}

        point ->
          %{
            point_id: id,
            unit:
              blank_to_nil(point.unit) ||
                CatalogDeclarations.parameter_unit(declarations, point.parameter_id),
            type:
              type(
                CatalogDeclarations.parameter_base_type(declarations, point.parameter_id),
                Map.get(point, :data_type)
              )
          }
      end
    end)
  end

  @doc """
  Latest sample per selected point for `spacecraft_id`: `%{point_id => %{value_json,
  generation_time, received_at, limit_state}}`. Points without a sample are absent.
  """
  @spec samples(binary(), binary(), binary(), [binary()]) :: %{binary() => map()}
  def samples(_org, _mission, _spacecraft_id, []), do: %{}

  def samples(org, mission, spacecraft_id, point_ids) do
    wanted = MapSet.new(point_ids)

    limits =
      PointLimitState.load(
        org,
        mission,
        spacecraft_id,
        PointCatalog.list_points(org, mission),
        point_ids
      )

    org
    |> Telemetry.latest_values_for_mission(mission, spacecraft_id: spacecraft_id)
    |> Enum.filter(&(&1.spacecraft_id == spacecraft_id and MapSet.member?(wanted, &1.point_id)))
    |> Map.new(fn sample ->
      {sample.point_id,
       %{
         point_id: sample.point_id,
         value_json: Jason.encode!(value(sample)),
         generation_time: sample.generation_time,
         received_at: sample.receipt_time,
         limit_state: limits |> Map.get(sample.point_id) |> limit_state()
       }}
    end)
  end

  defp value(%{engineering_value: nil} = sample), do: sample.raw_value
  defp value(sample), do: sample.engineering_value

  defp type(base_type, _data_type) when base_type in ["enumerated", "boolean"], do: "enum"
  defp type(base_type, _data_type) when base_type in ["integer", "float"], do: "numeric"
  defp type(base_type, _data_type) when base_type in ["string", "binary"], do: "text"
  defp type(_base_type, data_type) when data_type in [:uint, :int, :float], do: "numeric"
  defp type(_base_type, :bool), do: "enum"
  defp type(_base_type, data_type) when data_type in [:string, :binary], do: "text"
  defp type(_base_type, _data_type), do: nil

  defp limit_state(nil), do: nil
  defp limit_state(state), do: Atom.to_string(state)

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
