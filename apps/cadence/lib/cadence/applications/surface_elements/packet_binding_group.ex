defmodule Cadence.Applications.SurfaceElements.PacketBindingGroup do
  @moduledoc "One bounded packet group rendered by the Packet Bindings host element."

  alias Cadence.Applications.SurfaceElements.PacketBindingResource

  @type state :: :available | :selected | :invalid | :unavailable

  @type t :: %__MODULE__{
          id: binary(),
          packet_id: binary(),
          packet_name: binary(),
          apid: non_neg_integer(),
          selector_summary: binary(),
          model_label: binary(),
          selected: boolean(),
          expanded: boolean(),
          selectable: boolean(),
          state: state(),
          reason: binary() | nil,
          consumers: [binary()],
          resources: [PacketBindingResource.t()]
        }

  @enforce_keys [
    :id,
    :packet_id,
    :packet_name,
    :apid,
    :selector_summary,
    :model_label,
    :selected,
    :expanded,
    :selectable,
    :state
  ]

  defstruct [
    :id,
    :packet_id,
    :packet_name,
    :apid,
    :selector_summary,
    :model_label,
    :selected,
    :expanded,
    :selectable,
    :state,
    :reason,
    consumers: [],
    resources: []
  ]

  @max_resources 256

  @spec validate(t()) :: :ok | {:error, :invalid_application_surface_packet_binding_group}
  def validate(%__MODULE__{} = group) do
    resource_ids = Enum.map(group.resources, &resource_id/1)

    if valid_identity?(group) and valid_selection_state?(group) and
         valid_consumers?(group.consumers) and valid_resources?(group.resources, resource_ids) do
      :ok
    else
      {:error, :invalid_application_surface_packet_binding_group}
    end
  end

  def validate(_group), do: {:error, :invalid_application_surface_packet_binding_group}

  defp valid_identity?(group),
    do:
      valid_text?(group.id) and valid_text?(group.packet_id) and
        valid_text?(group.packet_name) and valid_apid?(group.apid) and
        valid_text?(group.selector_summary) and valid_text?(group.model_label)

  defp valid_selection_state?(group),
    do:
      is_boolean(group.selected) and is_boolean(group.expanded) and
        is_boolean(group.selectable) and
        group.state in [:available, :selected, :invalid, :unavailable] and
        optional_text?(group.reason)

  defp valid_resources?(resources, resource_ids) do
    is_list(resources) and length(resources) <= @max_resources and
      Enum.all?(resources, &(PacketBindingResource.validate(&1) == :ok)) and
      length(Enum.uniq(resource_ids)) == length(resource_ids)
  end

  defp valid_apid?(apid), do: is_integer(apid) and apid in 0..2_047

  defp resource_id(%PacketBindingResource{id: id}), do: id
  defp resource_id(_resource), do: nil

  defp valid_consumers?(consumers) when is_list(consumers) do
    length(consumers) <= 16 and Enum.all?(consumers, &valid_text?/1) and
      length(Enum.uniq(consumers)) == length(consumers)
  end

  defp valid_consumers?(_consumers), do: false
  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
