defmodule Cadence.Ops.PointCatalog do
  @moduledoc """
  Registry of telemetry points operators can bind dashboard widgets to.

  Points come from the mission's active binding set — the same Mission Model
  packet definitions the decom runtime extracts samples from — so a widget can
  only bind to a point that actually produces data.
  """

  alias Cadence.Activations
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.ApplicationDispatch.CapabilityInstance
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
        binding_set.capability_instances
        |> Enum.flat_map(&points_from_instance/1)
        |> Enum.uniq_by(& &1.point_id)
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
        stale_timeout_ms: nil,
        description: nil
      }
    end)
  end

  defp points_from_instance(%CapabilityInstance{}), do: []
end
