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
          parameter_id: binary() | nil,
          qualified_name: binary() | nil,
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
        points(binding_set)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  The point a verifier or constraint subject names, or nil: a point id (`HK.sc_mode`, also as
  `telemetry:HK.sc_mode`), the parameter's semantic id from the mission model
  (`semantic:parameter:…`, stored on the field since #73), or its qualified name. Compose's
  current value and the U2 verifier plot resolve subjects the same way.
  """
  @spec resolve([point_info()], binary()) :: point_info() | nil
  def resolve(points, subject) when is_list(points) and is_binary(subject) do
    ref = subject |> String.trim() |> String.replace_prefix("telemetry:", "")

    Enum.find(points, &(Map.get(&1, :point_id) == ref)) ||
      Enum.find(points, &(Map.get(&1, :parameter_id) == ref)) ||
      Enum.find(points, &(Map.get(&1, :qualified_name) == ref))
  end

  @doc "The points a binding set's packet definitions produce."
  @spec points(BindingSet.t()) :: [point_info()]
  def points(%BindingSet{} = binding_set) do
    binding_set.capability_instances
    |> Enum.flat_map(&points_from_instance/1)
    |> Enum.uniq_by(& &1.point_id)
    |> Enum.sort_by(& &1.point_id)
  end

  defp points_from_instance(%CapabilityInstance{
         runtime_configuration: %PacketDefinition{} = packet_definition
       }) do
    Enum.map(packet_definition.fields, fn field ->
      %{
        point_id: packet_definition.packet_name <> "." <> field.name,
        parameter_id: field.parameter_id,
        qualified_name: field.qualified_name,
        packet_name: packet_definition.packet_name,
        field_name: field.name,
        unit: field.engineering_unit,
        data_type: Map.get(field, :data_type),
        stale_timeout_ms: nil,
        description: nil
      }
    end)
  end

  defp points_from_instance(%CapabilityInstance{}), do: []
end
