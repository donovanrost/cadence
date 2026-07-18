defmodule Cadence.Ops.PointCatalog do
  @moduledoc """
  Registry of telemetry points operators can bind dashboard widgets to.

  Points come from the mission's active binding set — the same compiled packet
  definitions the decom runtime extracts samples from — so a widget can only
  bind to a point that actually produces data. Display metadata (descriptions,
  stale timeouts) is enriched from the catalog telemetry snapshots when the
  compiled field still references a catalog point.
  """

  alias Cadence.Activations
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.ApplicationDispatch.CapabilityInstance
  alias Cadence.Catalog
  alias Cadence.Telemetry.PacketDefinition

  @type point_info :: %{
          point_id: binary(),
          packet_name: binary(),
          field_name: binary(),
          unit: binary() | nil,
          stale_timeout_ms: non_neg_integer() | nil,
          description: binary() | nil
        }

  @spec list_points(binary(), binary()) :: [point_info()]
  def list_points(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    case Activations.fetch_active_binding_set(organization_id, mission_id) do
      {:ok, %BindingSet{} = binding_set} ->
        catalog_points = catalog_points_by_id(organization_id, mission_id)

        binding_set.capability_instances
        |> Enum.flat_map(&points_from_instance/1)
        |> Enum.uniq_by(& &1.point_id)
        |> Enum.map(&enrich(&1, catalog_points))
        |> Enum.sort_by(& &1.point_id)

      {:error, _reason} ->
        []
    end
  end

  defp points_from_instance(%CapabilityInstance{
         runtime_configuration: %PacketDefinition{} = packet_definition
       }) do
    Enum.map(packet_definition.fields, fn field ->
      %{
        point_id: packet_definition.packet_name <> "." <> field.name,
        packet_name: packet_definition.packet_name,
        field_name: field.name,
        unit: field.engineering_unit,
        field_id: field.field_id,
        stale_timeout_ms: nil,
        description: nil
      }
    end)
  end

  defp points_from_instance(%CapabilityInstance{}), do: []

  defp enrich(point, catalog_points) do
    {field_id, point} = Map.pop(point, :field_id)

    case Map.get(catalog_points, field_id) do
      nil ->
        point

      catalog_point ->
        %{
          point
          | stale_timeout_ms: catalog_point.stale_timeout_ms,
            description: catalog_point.description || catalog_point.short_description
        }
    end
  end

  # Enrichment only matches snapshots whose compiled point ids appear in the
  # active binding set — in practice the snapshot that was materialized plus
  # maybe a few imported since. Snapshot rows embed every point, so loading
  # the full import history would grow without bound; the newest few cover
  # the active set, and a miss only costs optional display metadata.
  @snapshot_lookback 5

  defp catalog_points_by_id(organization_id, mission_id) do
    # Snapshots list newest-first; put_new keeps the newest definition of a point.
    organization_id
    |> Catalog.list_telemetry_snapshots(mission_id, limit: @snapshot_lookback)
    |> Enum.flat_map(& &1.points)
    |> Enum.reduce(%{}, fn point, acc -> Map.put_new(acc, point.point_id, point) end)
  end
end
