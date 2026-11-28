defmodule Cadence.Reads.PointInfo do
  @moduledoc """
  Display facts for telemetry points (unit, description), keyed by point id.

  The points are the operator point catalog's (`Cadence.Ops.PointCatalog`): the
  active binding set's packet fields and the active revision's derived points
  (algorithm outputs, keyed by the output parameter's semantic id, #451 T4b).
  A packet point's unit is its decoded field's engineering unit, falling back to
  the active revision's catalog declarations (`parameter -> type -> unit`) when
  the lowered field has none; a derived point's unit already comes from those
  declarations. Descriptions are not carried through catalog import yet, so
  `description` is always `nil`.
  """

  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.CatalogDeclarations

  @type info :: %{unit: binary() | nil, description: binary() | nil}

  @doc "Unit and description for every point of the mission's operator point catalog."
  @spec by_id(binary(), binary()) :: %{binary() => info()}
  def by_id(organization_id, mission_id) do
    points = PointCatalog.list_points(organization_id, mission_id)

    # A derived point's unit already comes from its declaration; only packet fields fall back.
    missing =
      for %{source: :packet, parameter_id: parameter_id} = point <- points,
          is_binary(parameter_id) and blank_to_nil(point.unit) == nil,
          do: parameter_id

    declarations =
      if missing == [],
        do: %{},
        else:
          CatalogDeclarations.closure(
            organization_id,
            mission_id,
            CatalogDeclarations.active_revision_id(organization_id, mission_id),
            missing
          )

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
