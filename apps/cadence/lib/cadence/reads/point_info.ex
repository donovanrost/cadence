defmodule Cadence.Reads.PointInfo do
  @moduledoc """
  Display facts for telemetry points (unit, description), keyed by point id.

  Units come from the engineering unit of the decoded packet field in the
  mission's active binding set (`Cadence.Ops.PointCatalog`). Descriptions are
  not carried through catalog import yet, so `description` is always `nil`.
  """

  alias Cadence.Ops.PointCatalog

  @type info :: %{unit: binary() | nil, description: binary() | nil}

  @doc "Unit and description for every point in the mission's active binding set."
  @spec by_id(binary(), binary()) :: %{binary() => info()}
  def by_id(organization_id, mission_id) do
    organization_id
    |> PointCatalog.list_points(mission_id)
    |> Map.new(&{&1.point_id, %{unit: blank_to_nil(&1.unit), description: &1.description}})
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
