defmodule Cadence.Ops.PointCatalog do
  @moduledoc """
  Registry of telemetry points operators can bind dashboard widgets to.

  Two sources, both from what the mission's active activation runs (`source`):

    * `:packet`: the fields of the active binding set's packet definitions, the same Mission
      Model packet definitions the decom runtime extracts samples from (`point_id` is
      `PACKET.field`);
    * `:derived`: the outputs of the active revision's algorithms (#451 T4b,
      `Cadence.Reads.DerivedPoints`): `point_id` is the output parameter's semantic id, as the
      partition persists the computed samples, with the type and unit its declaration gives.

  So a widget can only bind to a point that actually produces data. A read is the activation, the
  binding set and one cache lookup per revision, whatever the fleet size.
  """

  alias Cadence.Activations
  alias Cadence.Activations.BindingSetActivation
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.ApplicationDispatch.CapabilityInstance
  alias Cadence.Governance
  alias Cadence.Reads.{DerivedPoints, RevisionsInUse}
  alias Cadence.Telemetry.PacketDefinition

  @type point_info :: %{
          required(:point_id) => binary(),
          required(:parameter_id) => binary() | nil,
          required(:qualified_name) => binary() | nil,
          required(:name) => binary(),
          required(:packet_name) => binary() | nil,
          required(:field_name) => binary() | nil,
          required(:unit) => binary() | nil,
          required(:data_type) => atom() | nil,
          required(:source) => :packet | :derived,
          required(:stale_timeout_ms) => non_neg_integer() | nil,
          required(:description) => binary() | nil,
          optional(:base_type) => binary() | nil,
          optional(:space_system_id) => binary() | nil
        }

  @doc """
  The active activation's packet points (sorted by id), then its derived points.

  Each craft runs the head revision of its composition, so a mission can run several revisions
  (`RevisionsInUse`). With `spacecraft_id:` the derived points are that craft's revision's; without
  it they are every revision in use's, a point once (its id is the output parameter's semantic id,
  the same across revisions that keep it). The statements do not depend on the number of
  spacecraft or points.
  """
  @spec list_points(binary(), binary(), keyword()) :: [point_info()]
  def list_points(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    case Activations.fetch_active_activation(organization_id, mission_id) do
      {:ok, %BindingSetActivation{} = activation} ->
        packets = packet_points(organization_id, activation)
        packet_ids = MapSet.new(packets, & &1.point_id)

        derived =
          organization_id
          |> derived_revisions(mission_id, activation, opts)
          |> Enum.flat_map(&DerivedPoints.list(organization_id, mission_id, &1))
          |> Enum.uniq_by(& &1.point_id)
          |> Enum.sort_by(&{&1.qualified_name, &1.point_id})
          |> Enum.reject(&MapSet.member?(packet_ids, &1.point_id))

        packets ++ derived

      {:error, _reason} ->
        []
    end
  end

  defp packet_points(organization_id, activation) do
    case Governance.fetch_binding_set(
           organization_id,
           activation.mission_id,
           activation.binding_set_id,
           activation.binding_set_version
         ) do
      {:ok, %BindingSet{} = binding_set} -> points(binding_set)
      {:error, _reason} -> []
    end
  end

  defp derived_revisions(organization_id, mission_id, activation, opts) do
    case Keyword.get(opts, :spacecraft_id) do
      craft when is_binary(craft) ->
        [RevisionsInUse.of_spacecraft(organization_id, mission_id, craft)]

      nil ->
        case organization_id |> RevisionsInUse.all(mission_id) |> Map.keys() do
          [] -> [revision_id(activation)]
          revisions -> revisions
        end
    end
  end

  defp revision_id(%BindingSetActivation{metadata: %{} = metadata}),
    do: get_in(metadata, ["mission_model", "revision_id"])

  defp revision_id(%BindingSetActivation{}), do: nil

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

  @doc "The points a binding set's packet definitions produce (`source: :packet`)."
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
        name: field.name,
        packet_name: packet_definition.packet_name,
        field_name: field.name,
        unit: field.engineering_unit,
        data_type: Map.get(field, :data_type),
        source: :packet,
        stale_timeout_ms: nil,
        description: nil
      }
    end)
  end

  defp points_from_instance(%CapabilityInstance{}), do: []
end
