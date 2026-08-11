defmodule Cadence.Applications.SurfaceElements.PacketBindings do
  @moduledoc "Bounded host-owned packet and resource binding interaction document."

  alias Cadence.Applications.PacketInputDefinition
  alias Cadence.Applications.SurfaceElements.PacketBindingGroup

  @type activation_state ::
          :unconfigured | :configured | :active | :outdated | :disabled | :unavailable

  @type source_endpoint :: %{required(:label) => binary(), required(:value) => binary()}

  @type t :: %__MODULE__{
          id: binary(),
          title: binary(),
          description: binary() | nil,
          action_id: binary(),
          submit_label: binary(),
          input_definition: PacketInputDefinition.t(),
          catalog_revision_id: binary() | nil,
          source_endpoint_ref: binary() | nil,
          source_endpoints: [source_endpoint()],
          packet_groups: [PacketBindingGroup.t()],
          configured_version: pos_integer() | nil,
          applied_version: pos_integer() | nil,
          activation_state: activation_state(),
          save_enabled: boolean(),
          empty_title: binary(),
          empty_description: binary() | nil
        }

  @enforce_keys [
    :id,
    :title,
    :action_id,
    :submit_label,
    :input_definition,
    :activation_state,
    :save_enabled,
    :empty_title
  ]

  defstruct [
    :id,
    :title,
    :description,
    :action_id,
    :submit_label,
    :input_definition,
    :catalog_revision_id,
    :source_endpoint_ref,
    :configured_version,
    :applied_version,
    :activation_state,
    :save_enabled,
    :empty_title,
    :empty_description,
    source_endpoints: [],
    packet_groups: []
  ]

  @max_groups 512
  @max_resources 4_096

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_packet_bindings}
  def validate(%__MODULE__{} = bindings) do
    group_ids = Enum.map(bindings.packet_groups, &group_id/1)
    resource_count = Enum.sum(Enum.map(bindings.packet_groups, &length(&1.resources)))

    if valid_identity?(bindings) and valid_input?(bindings) and
         valid_groups?(bindings.packet_groups, group_ids, resource_count) and
         valid_lifecycle?(bindings) and valid_empty_state?(bindings) do
      :ok
    else
      {:error, :invalid_application_surface_packet_bindings}
    end
  end

  def validate(_bindings), do: {:error, :invalid_application_surface_packet_bindings}

  defp valid_identity?(bindings),
    do:
      valid_text?(bindings.id) and valid_text?(bindings.title) and
        optional_text?(bindings.description) and valid_text?(bindings.action_id) and
        valid_text?(bindings.submit_label)

  defp valid_input?(bindings),
    do:
      PacketInputDefinition.validate(bindings.input_definition) == :ok and
        optional_text?(bindings.catalog_revision_id) and
        optional_text?(bindings.source_endpoint_ref) and
        valid_source_endpoints?(bindings.source_endpoints)

  defp valid_groups?(groups, group_ids, resource_count) do
    is_list(groups) and length(groups) <= @max_groups and resource_count <= @max_resources and
      Enum.all?(groups, &(PacketBindingGroup.validate(&1) == :ok)) and
      length(Enum.uniq(group_ids)) == length(group_ids)
  end

  defp valid_lifecycle?(bindings),
    do:
      optional_positive_integer?(bindings.configured_version) and
        optional_positive_integer?(bindings.applied_version) and
        valid_activation_state?(bindings.activation_state) and is_boolean(bindings.save_enabled)

  defp valid_activation_state?(state),
    do: state in [:unconfigured, :configured, :active, :outdated, :disabled, :unavailable]

  defp valid_empty_state?(bindings),
    do: valid_text?(bindings.empty_title) and optional_text?(bindings.empty_description)

  defp group_id(%PacketBindingGroup{id: id}), do: id
  defp group_id(_group), do: nil

  defp valid_source_endpoints?(endpoints) when is_list(endpoints) do
    values = Enum.map(endpoints, &Map.get(&1, :value))

    length(endpoints) <= 128 and
      Enum.all?(endpoints, fn endpoint ->
        is_map(endpoint) and valid_text?(Map.get(endpoint, :label)) and
          valid_text?(Map.get(endpoint, :value)) and
          Enum.all?(Map.keys(endpoint), &(&1 in [:label, :value]))
      end) and length(Enum.uniq(values)) == length(values)
  end

  defp valid_source_endpoints?(_endpoints), do: false
  defp optional_positive_integer?(nil), do: true
  defp optional_positive_integer?(value), do: is_integer(value) and value > 0
  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
