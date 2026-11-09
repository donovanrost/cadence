defmodule Cadence.Reads.PointInfo do
  @moduledoc """
  Display facts for telemetry points (unit, description), keyed by point id.

  Units come from the engineering unit of the decoded packet field in the
  mission's active binding set (`Cadence.Ops.PointCatalog`), falling back to
  the active revision's catalog declarations (`parameter -> type -> unit`)
  when the lowered field has none. Descriptions are not carried through
  catalog import yet, so `description` is always `nil`.
  """

  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.CatalogDeclarations

  @type info :: %{unit: binary() | nil, description: binary() | nil}

  @doc "Unit and description for every point in the mission's active binding set."
  @spec by_id(binary(), binary()) :: %{binary() => info()}
  def by_id(organization_id, mission_id) do
    points = PointCatalog.list_points(organization_id, mission_id)

    declarations =
      if Enum.any?(points, &(blank_to_nil(&1.unit) == nil and is_binary(&1.parameter_id))),
        do: CatalogDeclarations.active(organization_id, mission_id),
        else: %{}

    Map.new(points, fn point ->
      unit =
        blank_to_nil(point.unit) ||
          CatalogDeclarations.parameter_unit(declarations, point.parameter_id)

      {point.point_id, %{unit: unit, description: point.description}}
    end)
  end

  @doc "Unit and description of one point; both `nil` when the point is unknown."
  @spec fetch(binary(), binary(), binary()) :: info()
  def fetch(organization_id, mission_id, point_id) do
    Map.get(by_id(organization_id, mission_id), point_id, unknown())
  end

  @doc "The info for a point the catalog doesn't know."
  @spec unknown() :: info()
  def unknown, do: %{unit: nil, description: nil}

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
